---
name: learn
description: "Post-session reflection that writes durable improvements forward. Two modes. Default: reflect on the session you just finished — recall what was used, distill only the lessons that generalize, route each to its right home (skill / rule / memory / nothing). Target mode (`/learn <skill|plugin|command|workflow>`): audit every past session that used that target, surface the recurring problems as an HTML triage report (each framed expectation → what happened → why, anchored to the session that surfaced it), then apply only the fixes you approve. Built to NOT downgrade existing workflows and NOT overfit to one session. Triggers on: 'learn from this', 'reflect and improve', 'update your skills', 'what did we learn', 'audit my rush:design skill', 'where does <skill> keep going wrong', 'retro', 'post-mortem this session'."
argument-hint: "[empty = current session | session-id | topic | <skill|plugin|command|workflow> to audit across sessions]"
allowed-tools: Bash(agents *), Bash(git *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Bash(bun *), Bash(mkdir *), Bash(open *), Bash(xdg-open *), Bash(chmod *), Read(*), Write(*), Edit(*), Task(*)
user-invocable: true
---

# learn

You just finished real work. Some of it taught you something — a tool that behaved differently than you assumed, a step you had to rediscover, a correction the user made twice. This skill turns that into a durable improvement to your own skills, rules, or memory, so the next agent (or you, next week) starts ahead of where you started.

It is the opposite failure mode that makes this hard. The lazy output is to encode nothing. The eager output is to encode everything — to overfit a permanent rule to one session's fluke, or to rewrite a battle-tested skill around a single bad afternoon. Both degrade the system. Your job is the narrow middle: the few lessons that are real, general, and durable — and the discipline to ship them without breaking what already works.

**Not `reflect`.** `reflect` is mid-conversation: it recalls the user's feedback before your next attempt and writes nothing. `learn` is post-session: it writes durable lessons forward into the skill library. Different jobs — don't conflate them.

## Two modes — pick by the argument

- **No argument, a session id, or a free topic → reflection mode.** Reflect on the session you just finished (or the one named) and write its lessons forward. This is everything from **Phase 0** down — the default.
- **The argument names an installed skill, plugin, command, or a workflow → target-audit mode.** The user wants to know where *that one thing* keeps going wrong across all the times they've used it, and fix it. Run **Target audit** below instead, then return to Phase 4 to apply the approved fixes.

Decide which the argument is before doing anything: `agents inspect user --json` and `agents inspect system --json` list the installed skills/commands/plugins. If `$ARGUMENTS` matches one of those names (e.g. `rush:design`, `code:loop`, `/code:commit`), or is clearly the name of a recurring workflow the user runs, it's a **target** — go to Target audit. If it's a hex session id or a loose theme to reflect across, it's reflection mode.

## Target audit — `/learn <target>`

The user runs many skills and plugins every day. This mode answers: *"Where does `<target>` keep failing me, exactly — and what will you change so it stops?"* It mines every past session that actually used the target, frames each recurring problem the way it really happened, and hands you an HTML report to triage before anything is edited.

The audit scripts ship next to this skill. Resolve them once:

```bash
AUDIT="$HOME/.agents/.system/skills/learn/audit"   # canonical source, present wherever agents-cli is set up
RUN="$(mktemp -d)/learn-audit"; mkdir -p "$RUN"
```

### Step 1 — Find every session that used the target

`find-sessions.sh` enumerates the sessions and classifies *how* each used the target (a real `Skill`/tool/command invocation vs. an incidental prose mention), newest first.

```bash
# Named target (skill / plugin / command / tool) — keep only real invocations:
bash "$AUDIT/find-sessions.sh" "<target>" --all --structured-only > "$RUN/sessions.jsonl"
# A loose workflow phrase (no single invocation token) — drop --structured-only so
# conversation-text matches are kept:
# bash "$AUDIT/find-sessions.sh" "<phrase>" --all > "$RUN/sessions.jsonl"
```

Each line carries `id`, `shortId`, `topic`, `ts`, `file` (the transcript), `cwd`, `hits`, `structuredHits`, `firstLine`/`lastLine` (the JSONL line numbers where the use occurred — the moments to quote), and `kind`. Drop `--all` to scope to the current project only.

### Step 2 — Read the sessions, recency-weighted

Read the matched transcripts (`file` field) and find the friction: a result the user rejected, a step the agent rediscovered live, a correction given more than once, a flag/path that had to be guessed, an error that recurred. **Weight by recency** — the newer a session, the more fully you read it, because old friction may already have been fixed:

- A problem seen in **recent** sessions is live. Surface it.
- A problem seen **only in old** sessions, absent from recent ones, is likely already addressed → set `maybe_already_fixed: true` and check: does the target's current text (or `git log` on its file) already cover it? If yes, drop it or mark it resolved. Don't re-propose a fix that already landed.
- The **same** problem across several sessions is the highest-value finding — record every session it appears in and set `recurrence_count`.

For each problem, capture it **exactly as it happened**, grounded in the transcript (cite the session + line; quote the real moment — the user's actual words or the actual error). This is `research-discipline` (no unverified claims): a problem you can't quote, you don't claim.

### Step 3 — Build the findings and render the report

Write `findings.json` (array) and `meta.json` matching the schema in `audit/report.ts`. Every finding is framed **expectation → what happened → why → proposed fix**:

```jsonc
// findings.json — one object per problem
{
  "severity": "high|medium|low",
  "title": "one-line problem name",
  "expectation": "what the user/agent expected (the 'before')",
  "what_happened": "what actually happened (the 'after')",
  "why": "root cause, if known",                  // optional
  "quote": "the real moment — user's words or the error text",
  "session_id": "…", "session_short": "…", "session_topic": "…",
  "session_ts": "ISO8601", "transcript_line": 47,  // from firstLine/lastLine
  "recurrence_count": 2, "recurrence_sessions": ["a1b2c3d4","9f8e7d6c"],
  "maybe_already_fixed": false,
  "proposed_fix": "1–2 lines: exactly what you'll change",
  "fix_target": "skills/<x>/SKILL.md | rules/subrules/<x>.md | memory"
}
```

```bash
bun "$AUDIT/report.ts" "$RUN/findings.json" "$RUN/meta.json" > "$RUN/report.html"
open "$RUN/report.html" 2>/dev/null || xdg-open "$RUN/report.html"
```

Then tell the user the report is open and give a 2–3 line spoken summary (the top recurring problem, the count, the headline fix). The report is the review surface: it groups by severity, sorts newest-first, flags `maybe fixed`, and lets the user tick the fixes they approve and **Copy approved fixes → /learn apply**.

### Step 4 — Apply only what's approved

Wait for the user's call. They either paste back the `/learn apply …` brief from the report or tell you which to take. Then apply **only the approved fixes** — and apply them through the rest of this skill: each fix still passes the **four gates** (Phase 3), routes to its home (Phase 4), edits **without downgrading** (Phase 5), and **verifies + ships** via worktree + PR (Phase 6). The audit changes *what you fix* (problems mined from real sessions, not this conversation); it does not relax *how* you fix it.

---

> The phases below are reflection mode (the default). Target-audit mode borrows Phases 3–6 to filter and ship the fixes it surfaced.

## Phase 0 — Anchor to the user's goals and delivery

A lesson is only worth encoding if it moves the user toward what they are actually
trying to ship. Before you reflect on *friction*, load the two lenses that tell you
whether a lesson has **leverage** — whether it helps the user move faster and beat
their milestones, not just tidy a tool. Reflection with no goal in view optimizes the
agent's comfort; reflection anchored here optimizes the user's outcome.

Pull both cheaply (most is already on hand — the SessionStart Linear hook injects the
project/milestone summary, and this session likely already ran or can run `agents
output`):

- **Goals — the Linear ladder.** The user works to **projects → milestones → cycles →
  tasks**, and the question that matters is *how many are being met*. Read the injected
  Linear context, or query fresh: `linear tasks --project "<name>" --by-milestone`
  (milestone %, what's Todo/Doing/Done), the active cycle's burn-down, and which
  milestones are **slipping** (past or near their target date with low completion).
  Name the one or two goals currently most at risk — those are where leverage is highest.
- **Delivery — the output signal.** `agents output --since <window>` is the shipped-work
  rollup: PRs opened/merged, commits, token burn, cost-per-PR, output-per-$. It tells you
  whether the bottleneck is *throughput* (little shipping), *cost* (lots of burn per
  merged PR), or *rework* (PRs opened but not merged). A lesson that raises the weak
  metric outranks one that doesn't move any.

Hold both as the lens for the whole pass. You are not filing lessons for a library; you
are removing whatever is between the user and their next met milestone.

## Phase 1 — Recall, grounded

Reconstruct what actually happened, from evidence, not impression.

- **What did the session use?** The skills, commands, plugins, and tools you invoked. Name them.
- **Where was the friction?** Retries, dead-ends, manual workarounds, a five-call detour that should have been one, a thing you had to rediscover live, a correction the user gave you. Each friction point is a candidate lesson — cite the concrete moment (a quoted user line, a tool-call sequence, a file:line).
- **What's the improvable surface?** `agents inspect <user|system|project> --json` lists the skills/commands/rules/plugins you could touch. **Read** the specific skills the session leaned on before proposing any change — you cannot improve, or avoid downgrading, what you have not read.

If `$ARGUMENTS` names a session id or a topic, pull it with `agents sessions` and reflect across that instead of the current conversation.

## Phase 2 — Check the plugins for their own learning guidance

Before you decide how to encode anything, see whether the plugins this session used ship their own reflection guidance — a skill named `learn`, `develop`, `improve`, or similar inside the plugin. For each plugin you used:

```bash
fd -t f 'SKILL.md' ~/.agents/.system/plugins/<plugin>/skills ~/.agents/plugins/<plugin>/skills 2>/dev/null \
  | xargs grep -l -iE 'name: (learn|develop|improve|reflect)' 2>/dev/null
```

If a plugin has one (e.g. `code:learn`), **read it and follow its domain-specific routing** — it knows where lessons about *that* plugin's features belong, what its skills already cover, and what its conventions are. This is how `learn` stays smart about specialized surfaces without hard-coding every plugin's internals. If a plugin has none, the general method below still applies — you don't need permission to reflect on a plugin that hasn't documented how.

## Phase 3 — Distill, then filter hard

Write each candidate lesson as one line. Then put every candidate through four gates. A candidate must pass **all four** to earn a durable edit:

1. **Generalization.** Name 2-3 *different future* situations where this lesson would help. If the only situation you can name is the one that just happened, it's an incident, not a pattern.
2. **Recurrence.** Has this bitten before, or is it likely to bite again? A service that was down, a one-time flake, a typo — transient and environmental one-offs don't earn permanent edits.
3. **Root cause.** Is this the actual cause, or a surface symptom? Encode the cause.
4. **Durability.** Will it still be true in six months, or is it pinned to a version/repo state that will change? Volatile facts go to dated memory, not a skill.

Then, **in reflection mode, rank the survivors by outcome leverage** (the Phase 0 lens;
target-audit mode has no Phase 0 and ranks by the report's own severity instead). Among
lessons that clear all four gates, the ones that unblock or accelerate a **slipping
milestone**, or that lift the weak delivery metric (throughput / cost-per-PR / merge
rate), come first and earn the most care and prominence. An equally-general lesson on a
surface tied to no active goal is real but lower-leverage — still encode it, just later
and more briefly. Leverage sets ordering and effort only: a lesson that cleared the four
gates is never dropped for low leverage, and leverage never lets a lesson skip the gates.

**Show your rejects.** List the candidates you dropped and which gate they failed. A learn pass that encodes every candidate isn't thorough — it's overfitting. The rejects are proof the filter ran.

## Phase 4 — Route each survivor to its home

| The lesson is… | It goes to… |
|---|---|
| A principle that should constrain every session | a rule: `~/.agents/rules/subrules/<name>.md` (a new name unions into the `default` preset) |
| A reusable capability or procedure | a new skill, or a new **section** in the most relevant existing skill |
| A gotcha about one tool | that tool's skill |
| A user preference / recurring behavior | a named memory: `~/.claude/memory/<slug>.md` (+ an index line in `MEMORY.md`) |
| A one-off machine/context fix | dated memory: `~/.agents/memory/<YYYY-MM-DD>.md` |
| Real but not generalizable | **nothing** — drop it |

"Drop it" is a valid, common outcome. Most sessions yield zero to two durable lessons.

## Phase 5 — Edit without downgrading

- **Read the target fully first**, and understand why it's shaped the way it is. Guidance you don't understand, you can't safely change.
- **Prefer additive.** A new section or a new skill beats rewriting prose that already works. Battle-tested wording earned its shape.
- **If you change existing guidance, quote the old text** and state why the change doesn't break the cases it currently serves.
- **Minimal, scoped diff.** No drive-by refactors, renames, or reorganizations. Touch only what the lesson requires.

## Phase 6 — Verify, then ship

- **Verify.** If the lesson touched an executable artifact (a script, a command), run it end-to-end — that's how you catch the bug in your own fix. For prose edits, re-read them in context to be sure they don't contradict the guidance around them.
- **Ship, for repo-backed config.** Changes to `~/.agents` or `~/.agents/.system` are real releases: work in a worktree, bump the version + `CHANGELOG`, commit, push, open a PR, and tag on merge (`/git:tag-release` handles the tag). **Present the proposed lessons and diffs to the user before committing** — a human saying "that one's overfit" is the cheapest, best filter you have.

## Evidence

Every lesson you claim cites the moment that earned it — a quoted correction, a tool-call trace, a file:line. A lesson you can't ground is a hunch; drop it. When you hand any part of this to a sub-agent, end the brief with: `Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.`
