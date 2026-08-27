---
name: search
description: "Pull ALL relevant prior-session context on a topic — fast, ranked, snippet-level, without loading full transcripts. `agents sessions \"<q>\"` alone misses assistant answers (not indexed) and returns whole-session refs, not snippets. This skill layers CLI discovery with a bundled fallback script that recovers what the index misses. Triggers on: /sessions:search, /recall, 'find what I said about X before', 'did we already solve this', 'pull context from a past session', 'search my sessions for'."
argument-hint: "<topic, ticket id, filename, symbol, or keywords>"
allowed-tools: Bash(agents sessions*), Bash(python3 *), Read(*)
user-invocable: true
---

# sessions:search

Recall is not "run one CLI query and paste the result." The index that backs
`agents sessions "<q>"` only covers **user turns + title/topic/project**
(`session_text`, bm25) and, separately, **tool activity**
(`tool_call_text`, trigram, needs `--include tools --query`). **Assistant
answers are never indexed.** A session can be 665 messages long with only a
43-character title in the index — the actual answer the user wants is buried
in an assistant turn the index cannot see. Follow this procedure in order;
do not skip straight to guessing an answer from memory.

## 1. Derive search terms from the user's ask

Pull out, in this priority order, every one of these that appears in the ask:

- **Ticket/issue IDs** — `PHNX-\d+`, `RUSH-\d+`, `#\d+`, or any tracker key shape.
- **Filenames / paths** — anything with a `/` or a file extension.
- **Symbols** — function/class/variable names, CLI flag names, config keys.
- **Distinctive keywords** — 2-4 words that would be rare together (skip
  generic verbs like "fix", "add", "look at").

Keep 2-5 terms. Too many terms narrows an FTS query to zero; too few floods it.
If the ask is vague ("what did we decide about the recall design"), use the
closest concrete nouns ("recall design") — do not ask the user to rephrase
before trying at least one layer below.

## 2. Layered discovery — try each in order, stop at the first that returns real hits

**Layer 1 — user turns + titles (fastest, whole-session refs):**

```bash
agents sessions "<terms>" --all --json
```

Read `topic`/`label` per hit to judge relevance before going further. This
layer alone is often enough for "did I already touch this file/ticket."

**Layer 2 — tool activity (commands run, files touched, diffs, errors):**

```bash
agents sessions --include tools --query 'input:<term>' --all --json
# or, to require several distinct calls in the same session:
agents sessions --include tools --query 'program:git input:<term>' --query 'program:gh output:<term2>' --all --json
```

Use this when the ask is about *what ran* (a command, a test, an error
string) rather than what was *said*.

**Layer 3 — fall back to the bundled script** when:

- either CLI call errors, times out, or hangs (the CLI fans out over SSH to
  every registered device and can stall on an unreachable box), OR
- the results are thin — zero hits, or hits that are whole-session refs with
  no way to tell which part of a long session is relevant, OR
- the ask needs an assistant answer specifically ("what did you conclude",
  "what was the fix", "what did you tell me about X") — the index cannot
  contain this by construction, only the transcript file can.

```bash
SKILL_DIR="$HOME/.agents/plugins/sessions/skills/search"
[ -d "$SKILL_DIR" ] || SKILL_DIR="$HOME/.agents/.system/plugins/sessions/skills/search"
python3 "$SKILL_DIR/recall.py" <terms> --limit 8 --json
```

`recall.py` is self-contained (stdlib only, no install step). It:

1. Ranks candidate sessions from the local index (the same two tables as
   layers 1-2, fused by rank so neither dominates).
2. Opens **only those top-K candidates'** own transcript file and greps
   **every role** — user, assistant, tool — for the same terms. This is the
   step that recovers assistant answers the index never stored.
3. Extracts capped ±3-line snippets around each match (never a full
   transcript dump) and caps total snippets per session.
4. Emits one digest entry per hit: `shortId`, `date`, `project`, `why`
   (user/assistant/tool — which role matched), up to 3 snippets, and a
   `resume <shortId>` hint.

Useful flags: `--project <name>`, `--since 7d`, `--limit N` (default 8),
`--snippets N` (default 3 per session), `--context N` (default ±3 lines).

If `recall.py` also returns nothing, say so plainly — do not fabricate a
plausible-sounding memory. A true zero across all three layers means the
topic was never discussed in an indexed local session, or lives on a device
you have not searched (`--device <host>` on the CLI reaches a specific peer;
`recall.py` is local-only by design, since it must open files directly).

A session the FIND phase matched via the index never silently disappears,
even when RECOVER cannot fully parse its transcript — it comes back as an
index-only hit with a `note` instead ("matched via index only", or "transcript
format not recognized"), so a real zero is never confused with "found it, but
couldn't grep it." Transcript recovery is strongest for Claude Code, Codex,
and Droid (full user/assistant/tool extraction) and Grok (reads the sibling
`chat_history.jsonl` next to the indexed `summary.json`); Kimi's transcript is
split across several per-agent files recall.py does not open yet, so Kimi
hits are index-only until that lands. This never affects layers 1-2 or the
FIND phase — only how much of a hit's *content* RECOVER can show.

## 3. Synthesize a compact digest — do not paste full sessions

Your final answer to the user is a **ranked digest**, not raw tool output:

- Lead with the most relevant 1-3 hits, each as: what session, when, why it
  matched, the 1-3 line answer/snippet, and the resume hint.
- If a hit clearly needs deeper reading (the snippet is ambiguous), offer —
  don't auto-run — `agents sessions --markdown <id> --include assistant` or
  `agents sessions resume <id>` to actually pick the work back up.
- Never read a full transcript file yourself as a substitute for this
  procedure; that is exactly the "loading the whole session to answer one
  question" cost this skill exists to avoid.

## Notes

- `recall.py` reads `~/.agents/.history/sessions/sessions.db` directly (SQLite,
  read-only) and the transcript files it points to. It never writes.
- The DB is fleet-shared per machine, not merged across devices — like layers
  1-2 without `--device`, this only sees sessions local to the box you run it
  on.
- Command-name markers in a transcript look like
  `<command-name>NAME</command-name>`; a match inside one of those is a
  legitimate hit on "which command did this" — don't discard it as noise.
