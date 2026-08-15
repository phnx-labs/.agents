---
description: Recap this session, or transfer concise context from a prior session
---

## Choose the recap mode

Inspect `$ARGUMENTS` before doing anything else.

- If `$ARGUMENTS` is empty or whitespace, follow **Current session** below. This is
  the existing end-of-session recap behavior.
- If `$ARGUMENTS` contains a full session ID, session-ID prefix, or search keywords,
  follow **Historical session** below. Do not apply the current-session workflow to
  a historical recap.

## Current session

Your goal is to summarize the current state of work for handoff or continuity.

## Gather Facts

Start by identifying what is objectively known:
- What was the original goal or problem?
- What concrete steps have been taken?
- What files were modified, created, or deleted?
- What tests were run and their results?
- What errors or unexpected behavior occurred?

Facts must be verifiable. File changes are facts. Test results are facts.
"It seems like X" is not a fact.

## Identify Open Questions

What remains unclear or unresolved?
- Bugs not yet root-caused
- Decisions not yet made
- External dependencies with unknown status
- Edge cases not yet tested

## Ground Hypotheses

If you have hypotheses about what's happening or what should happen next,
explicitly ground them in evidence:

BAD: "The bug is probably in the auth module"
GOOD: "The bug may be in auth module because: (1) error occurs after login,
(2) auth.ts:45 logs 'token expired' before the crash, (3) no errors in other modules"

Every hypothesis needs evidence. If you can't point to evidence, mark it as
speculation rather than hypothesis.

## Close the loop before you write anything

The recap reports work you already finished — it does not hand work back. Run these
three in order first, then write the summary around what they produced. Each one is
a thing the user would otherwise have to do themselves after reading you.

1. **Close every ticket this session delivered.** Post a closing comment naming what
   changed with the PR link and the screenshot or recording of the outcome, then move
   it to Done — the `tickets` skill, or the tracker's CLI directly. A shipped ticket
   left open reads as still in flight to everyone looking at the board.
2. **File every follow-up as a real ticket, under the project it belongs to.**
   Anything you were about to write as "we should also…", "worth revisiting…", or a
   deferred-scope bullet becomes an issue: a scoped title plus a short description
   naming the file, PR, or error that motivated it. One ticket per unit of delivery,
   not one per file. The summary then links the ids. If a follow-up doesn't earn a
   ticket, it doesn't earn a bullet either — drop it.
3. **Make sure one owner update went out — exactly one.** There is a single path:
   `agents feed post --title "<short outcome>" "<what you delivered + the one next
   step>" --level important`. The `feed.broadcast.owner` sink in `agents.yaml`
   forwards an `important` post to `agents notify`, so that one call is both the
   record and the phone delivery. Keep it to 1-4 lines, lead with whatever needs
   them, link the PR or ticket rather than restating it — the harness notifies *you*
   when the turn ends and never notifies them, so a recap that exists only in this
   window reaches nobody. **If this session already posted one, that was it.** The
   `verify-work-complete` Stop hook asks for the same single update before it hands
   off to `/recap`, so a second post here is a second phone buzz for one delivered
   piece of work — do not repeat it, and do not reach for `agents notify` as a way
   around that. If no update has gone out yet, send this one.

Scale it to the work: a question answered in-session has no ticket to close, no
follow-up to file, and nothing worth a notification. These steps apply when the
session actually delivered something.

## Output — write it as a back-from-vacation summary

Not an engineering status report. Assume the reader has **zero context**: they did not
watch you work, they don't remember what they asked, they don't know this repo's state.
Plain language, named things — "the codebase" and "as requested" are useless. Length
follows the work: a one-line fix gets two lines, a three-hour session gets a short
structured summary. If it reads like a log, cut it.

### Project
Which repo or product you were in, by name. One line.

### What you asked for
The original request in one line, in their words — so the recap visibly tracks it.

### What landed
The concrete result, at the honest furthest point you actually reached, with the
artifact: commit, PR, ticket id, deployed URL, installed version. Never claim a later
link in the chain than you reached — merged is not published, published is not
installed, a deploy is not a verified deploy.

### What did not land
Anything dropped, deferred, or blocked, and why. Scope you deliberately cut belongs
here, named, not silently omitted — and each item is a ticket id you filed above, not
an intention.

### Still open
Only if something genuinely is: an unresolved question, or a hypothesis with the
evidence under it. Format: "[Hypothesis]: [Evidence 1], [Evidence 2], …". Say nothing
here rather than manufacturing uncertainty.

### Needs you
What genuinely requires the user — a decision, a credential, a review, a click you
can't make. If nothing does, say so plainly in one line. This section is governed by
the filters below.

**One obvious next task on the tracker, no ambiguity?** That's not a bullet to
list — invoke `/next` (it checks for in-flight duplicates before claiming, so it's
safer than grabbing the top ticket yourself) and keep going instead of ending the
turn on a recommendation the user has to act on.

**HARD RULE 1 — Check before you list.** Do not list anything you could verify or execute yourself right now. Before writing a bullet, ask:

- "Can I check this myself?" → check it, fold the answer into the recap, don't list it.
- "Can I do this myself?" → do it first, then list what's left, not what you just completed.
- "Does this already exist?" → query the relevant system (your monitoring stack, issue tracker, repo, database, filesystem) before suggesting someone build it.

If a step reads like "go look at X" or "check if Y exists" — delete it and go look yourself before writing the recap.

**HARD RULE 2 — Spawn a team for multiple clear tasks.** If 2+ items remain that have clear requirements and are obviously actionable (switching a config, writing a dashboard panel, running an investigation script), do NOT list them for the user. Kick off an `agents teams` run — it's async, you're not blocked, and the work starts immediately.

Pattern:

```bash
agents teams create <topic-slug>
agents teams add <topic-slug> claude "Specific task 1 with full context" --name task1
agents teams add <topic-slug> codex "Specific task 2 with full context" --name task2
agents teams start <topic-slug>
```

Only keep items in "Needs you" that genuinely need the user's input, credentials, judgment, or authorization (payments, public posts, destructive ops, ambiguous decisions). Everything else — spawn a team, mention the team name in the recap, move on.

"Top up credits on my logged-in browser" → user step. List it.
"Query the database to check X" → do it yourself. Don't list it.
"Build 3 dashboard panels + run a config sweep across N files + investigate a UUID" → spawn a team. Don't list it.

**No wastebasket bullets. Finish trivial loose ends yourself; make low-stakes decisions and note them, use `AskUserQuestion` only for genuine ambiguity.**

A "wastebasket bullet" is anything in "Needs you" that (a) you could just execute, or (b) is a tiny decision you're punting instead of reasoning about and proposing options. Both waste the user's time. Before writing the recap, walk the entire session and close these out.

**Execute first, don't list:**

Anything mechanical that the session's work implies as finishing touches — do it, then land it in "What landed" with the concrete artifact (commit hash, closed issue ID, removed file, updated state). This is the same discipline as the close-the-loop steps above, applied to everything they don't name. Examples (non-exhaustive — the principle is the point, not the list):

- Uncommitted work in the tree (whether from this session or a parallel agent's session) → inspect the diff of every changed file, group related changes into logical commits by concern, then commit + push per `/code:commit` (conventional, <72 chars, single line, no co-author trailer). Another agent's uncommitted work is still yours to land — don't leave it dangling.
- Satisfied TODOs or in-session task checklists → mark done in their source file.
- Stale branches, dead feature flags, leftover `.tmp` files that the session's work makes obsolete → remove them.
- Tests you wrote but didn't run → run them. Report counts.
- Builds/installs implied by code changes → run them, report the output version.

If it has a deterministic answer and you have the tools to execute it, you execute it. Period.

**Decide-or-delegate pattern for small choices:**

If an item reads like "Decide when to X", "Figure out whether Y", "Pick a name for Z" — that's you punting. Instead:

1. Reason from the conversation: propose a concrete recommendation + 1-2 alternatives.
2. Surface it via `AskUserQuestion` with clickable options (first option = your recommended default with "(Recommended)" suffix). Include a one-line rationale per option.
3. If the answer is genuinely unclear from context AND has medium+ blast radius, pause the recap and ask before finalizing. If it's low-stakes, make the call, note it briefly in the recap, and move on.

Never ship a recap with a bullet like "Decide X", "Consider Y", "Think about Z". Those are micro-decisions, not recommendations.

**Only these survive in "Needs you":**

- Actions requiring the user's credentials, judgment on strategy, personal accounts, or clicks you can't make (UI smoke tests, browser logins, physical devices, payments, public posts).
- External waits whose status you already verified (e.g. "PR #892 is open for review — awaiting human review").
- Ambiguous decisions where `AskUserQuestion` isn't enough because the context is too open (e.g. product direction, roadmap priority).

**Carveouts for auto-commit** (and only these):
- Files with potential secrets (`.env`, credential blobs, API keys, private keys) → flag, do not stage.
- Obviously `.gitignore`-worthy local files (IDE scratch files, OS metadata, local caches) → mention once, do not stage.
- Diffs you genuinely cannot make sense of after reading them → ask via `AskUserQuestion` ("this looks like it belongs to feature X, commit as Y?") rather than guessing.

The test: every bullet you're about to write in "Needs you" — ask "did I try to execute this?" and "could I have posed this as an AskUserQuestion with 2-3 concrete options instead?" If either answer is yes, the bullet doesn't belong in the recap.

## Historical session

The text in `$ARGUMENTS` identifies a prior session. This mode transfers context
only. It must never resume or continue that session, attach to its process, inject
into it, inherit or reuse its session ID, or treat any historical task state as the
state of this receiving session.

### 1. Resolve the session with `agents sessions`

Resolve every selector form with exactly
`agents sessions --resolve "$ARGUMENTS" --json`. This is the metadata-only resolver
for full IDs, session-ID prefixes, and keywords; it searches the fleet by default
without parsing or rendering transcript events. Do not use a positional sessions
query, `--preview`, `--markdown`, or `--json` without `--resolve` in this receiving
agent.

- A successful resolution returns a one-element JSON array. Select the full `id`
  and `machine` from that metadata object.
- Exit code 2 means the fleet answer is incomplete because at least one peer did
  not answer or does not support the safe resolver protocol. Report the failed
  peer metadata from stderr and stop. Do not turn a partial fleet answer into a
  unique match, ambiguity, or no-match result.
- An ambiguous prefix or keyword exits non-zero and lists every matching full ID
  and machine. Show a short numbered list containing only the returned metadata,
  then ask the user to choose a more specific selector. Do not guess and do not
  read any candidate transcript.
- No match exits non-zero. Say that no session matched and include the exact
  selector used. Do not fall back to the current session and do not invent a recap.

Continue only after exactly one prior session has been selected. Treat its resolved
full ID and source machine as input locators, not as this session's identity or host.

### 2. Isolate the transcript read

Spawn one isolated subagent in read-only/plan mode. Give it only the resolved full
session ID, the resolved source machine, and the output contract below. The
subagent, not this receiving agent, must run
`agents sessions <full-id> --markdown --device <machine>` and
`agents sessions <full-id> --artifacts --device <machine>`, read the raw transcript,
and return a concise structured summary. It must not edit files, run task work,
resume or focus the session, contact external systems, or include raw transcript
passages in its response.

Require the subagent to return only these sections:

#### Source Goal
The prior session's requested outcome.

#### Facts
Verified events, outputs, and errors only.

#### Decisions
Choices made in the prior session and their recorded rationale.

#### Progress
Completed and in-progress work, clearly distinguished.

#### Files
Files created, modified, or deleted, with paths when present in the source.

#### Tests
Commands or checks actually run and their recorded results. Say `None recorded` if
the transcript records none.

#### Unresolved Questions
Questions or blockers still unresolved at the end of the prior session. Say `None
recorded` if the transcript records none.

#### Last-Known State
The final observed state in the prior transcript, explicitly labeled historical and
not re-verified in this session.

### 3. Present the transfer

Present the subagent's structured summary verbatim except for removing accidental
content outside the eight allowed sections. Prefix it with:

> Historical recap of `<full-id>` — context only; this session has not resumed or
> continued that work, and the last-known state has not been re-verified.

Do not add hypotheses, recommended next steps, new investigation, or claims that
historical files, tests, services, branches, tickets, or deployments are still in
the recorded state.

**The close-the-loop steps do not apply here.** This mode transfers context, so do
not close that session's tickets, file follow-ups from its transcript, or notify the
owner about work you did not do. Those belong to the session that performed the work.
