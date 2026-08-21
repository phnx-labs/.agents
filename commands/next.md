---
description: Drive the current task to fully delivered — verify end-to-end, docs, commit, PR, release checklist, close the ticket — then surface (and if clear, claim) the next related task and keep working in this session. Never stops at a recap, blocker, or partial handoff; never hardcodes a tracker.
---

You just finished something, or are about to move on. Context: $ARGUMENTS

`/next` is the command an agent runs at the boundary between two tasks. It does two things,
in order: **first drive the current task all the way to delivered** — refusing to stop at a
recap, a blocker, or a partial handoff — **then find what to work on next** (related work
first, everything else after) using whichever tracker this project actually has, and keep
going in this session.

> **Folds in the old `/finish`.** The drive-to-delivered ship checklist that used to be a separate
> `/finish` command now lives in **Part A** below — there is no `/finish`, run `/next`. For
> draining a whole *queue* of tickets/branches to merged, that's `/code:loop`. To *recap and
> exit* the session, that's `/recap` then `/self:close`.

**Chains from `/continue`.** If you just ran `/continue` and its Step 3 already drove the
resumed task to delivered, don't repeat Part A — say so with evidence and skip to Part B.

**Continue-here vs. hand-off-elsewhere.** `/next` continues THIS session on the next task
yourself. If the next unit of work should go to a different executor instead — a fresh
dispatched agent, another machine, or non-coding work (content, design, a browser task) —
that's `/work:dispatch`, not `/next`. They share the same resolution logic (find the target,
dedupe against in-flight work); `/next` keeps working in-session, `/work:dispatch` hands it
off. Don't run both on the same target.

Never hardcode Linear — a prior version of this command did exactly that and was removed for
it. Detect the tracker every time.

---

## Part A — Drive the current task to delivered

This is not a recap. It is an execution contract: recover the goal, finish what remains, verify
the real flow, and ship — before you look at what's next. If the current task is genuinely
already delivered (e.g. `/continue` just did this), say so **with evidence** and jump to
Part B.

### A1 — Recover the contract

Re-read the conversation from the start and write a short checklist:

- **Original ask** — what the user asked you to deliver.
- **Scope changes** — follow-up requests or constraints added later.
- **Commitments** — actions you said you would take.
- **Current state** — what is done, in progress, or not started.

Every item gets a verdict: DONE, IN FLIGHT, NOT STARTED, or BLOCKED. Do not trust memory —
back each DONE or BLOCKED with fresh evidence: file:line, command output, test result,
PR/deploy URL, HTTP response, ticket state, or the exact error. If you can't quote it, it is
not DONE.

### A2 — Convert status into the next action

For every IN FLIGHT / NOT STARTED / BLOCKED item, pick the next executable action. Before
you call anything blocked, make three distinct attempts and quote each result: the direct
path; the project's canonical script / CLI / browser automation / remote box / API; then
reduce scope to verify the critical path manually. Two or more independent workstreams →
start parallel work with `agents teams` (boundary contracts, file:line evidence required),
not one-by-one queueing.

### A3 — Take the next action now

Pick the smallest remaining item that advances delivery and execute it immediately. Do not
ask the user to choose between continuing and stopping, and do not hand back a command for
the user to run when you can run it, drive it in a browser, use a remote box, call an API, or
request the exact permission needed. Reserve `AskUserQuestion` for a true fork that needs
human judgment, credentials, payment, public posting, or destructive/production approval —
with forward-moving options only (never a "stop" option), the recommended one first.

### A4 — Verify end-to-end

"Done" requires real output from the real path. Match the verification to the task:

- Code change → run the relevant tests and exercise the affected flow.
- Bug fix → reproduce the original failure (or nearest case), then show it fixed.
- CLI/script → run the command, quote the output.
- API → call the endpoint, quote the response.
- UI → open the real screen and confirm behavior.
- Deploy/release → run the canonical deploy/release, then health-check or fetch the deployed
  artifact. Script completion alone is not proof.

If unrelated pre-existing failures block a full suite, prove they're unrelated with a
baseline run + touched-path tests + file/commit evidence, then use the project's narrower
documented verification. Don't hide behind a full-suite failure outside the task's blast
radius.

### A5 — Ship the finished work

Run the closing ship checklist; if a sub-step genuinely doesn't apply, say so in the report.

**Docs.** Walk every changed file: did it change anything a human would look up? Update only
the surface that applies — don't write new docs unless asked:

- **`AGENTS.md` / `CLAUDE.md` / `GEMINI.md`** (root or affected subdir) — new module,
  top-level area, gotcha, or file-locations pointer. Maps, not territory; the harness copies
  are usually symlinks — edit the real file.
- **`README.md`** — user-facing setup/usage/install/quickstart changes (new flag, env var,
  command).
- **`CHANGELOG.md`** (if present) — a line for the user-visible change under the next version.
- **Help text / `--help`, in-code descriptions** — if a flag, argument, config key, or tool
  parameter changed, update the string AND any examples.
- No docs needed for: bug fixes, internal refactors with no behavior change, test-only
  changes, self-evident renames — say which.

**Commit & PR.** Check `git status`, inspect every changed file in the diff. Commit completed
work if the project expects agent commits; never commit broken or incomplete work. On a
feature branch with a PR delivery path, push and open/update the PR. For a **private** repo
only, attach a **redacted** session transcript as a **secret** gist for audit — never a
public gist, never on a public repo (link `<host>:<path>` instead).

**Release (if applicable).** If the work touches a publishable package, `release-to-fleet` is
the authority and takes precedence — and it has exactly two end states: you were asked to
ship (you own the whole chain, `merged → published → tagged → fleet-upgraded →
installed-version-verified`), or the user explicitly scoped you away from releasing (you name
who owns it). There is no release train, and "merged + a changelog fragment" is never where
/next ends: if the registry is behind the default branch, driving or verifiably watching the
release **is the next task** — the lease (`release-lease.sh`) serializes concurrent
releasers, so start it and let the lease refuse you if another *verified-live* releaser
holds it. Verify the result landed in the registry (not just that the script exited 0). Do
not `AskUserQuestion` to confirm a release the session's goal already authorizes — that
re-ask is the banned stop.

**Tracker.** Update the issue tracker only with proof (commit, PR, deploy URL, test output,
health-check response). For a deliberately deferred slice (with a complete shippable slice
already delivered), file a follow-up ticket via the `tickets` skill with a clear title,
context, and acceptance criteria — don't silently drop it.

### A6 — No stalling

Every turn in Part A ends with an action, not a question handed back. Forbidden endings — the
stalls this rule exists to interrupt:

- "Want me to continue?" / "Should I do X next?"
- "Pick one and I'll continue."
- "Let me know if (or when) you want me to proceed."
- "The remaining sequence is mechanical." / "I can stop here."
- Any trailing question that hands the steering wheel back, or a status-only recap that does
  not take the next action first.

Required instead: `Next: [doing X]` with the tool call in the **same turn** as the sentence
announcing it. For a genuine fork only (human judgment, credentials, payment, public posting,
destructive/production approval): `AskUserQuestion` with two **forward-moving** options, never
a "stop" option.

The current task is delivered only when Remaining is **None**, or what remains is one of: a
proven external blocker with three quoted attempts; a user-only action (payment, credentials,
destructive/production approval, public posting, strategic judgment); or a deliberately
created follow-up ticket whose current shippable slice is already delivered.

---

## Part B — Move to the next task

Only once Part A has the current task delivered. This is the continuity half: recall what
project you're in, then find what to work on next — related work first, everything else after.

### B1 — Recall: what project, what you just did

One or two lines, not a full recap (`/recap` is for that):

- **Project.** Repo name, `git remote get-url origin`, and a glance at `AGENTS.md`/`README.md`
  if you haven't grounded in it this session.
- **What just shipped.** The concrete thing — a PR, a fix, a ticket closed. Name it; "made
  progress" doesn't count.

This context is what makes "related tasks" in B2 mean something — a related next task touches
the same surface, component, or ticket cluster as what you just finished, not just anything
open.

### B2 — Pull the board — tracker-agnostic

**Check what's already in your context first.** Most tracker integrations auto-inject board
state at session start (this repo's Linear hook is one — team tasks, project milestones, the
active cycle, all delivered before you type anything). Read that before running any discovery
command; it's usually already answered.

Only when nothing's injected, or the project uses a tracker this session hasn't surfaced yet,
fall back to the `tickets` skill (Step 1 tracker detection: skill → CLI → repo signal → ask).
Do not assume Linear, GitHub, or Jira — detect, every time. The `tickets` skill is the right
primitive for **actions** (claim, close, comment) even when discovery came from injected
context.

Once you have the board, prefer in this order:

1. **Related to what you just shipped** — same component/surface, a follow-up noted on the
   ticket you just closed, a sibling in the same epic/cluster.
2. **Highest priority in Todo** (not already In Progress) that's clearly scoped.
3. Nothing clear? Surface the top few candidates and stop — don't guess at intent (see B4).

**No ticket assigned to you specifically is not a reason to stop.** Look at whatever's
unclaimed and clearly scoped — you don't need an explicit assignment to pick up clean, ready
work. Stalling with "what should I work on?" when the board has obvious unclaimed work is the
failure this command exists to prevent.

### B3 — Rule out duplicate work — check what's already in flight

This is the step that justifies `/next` existing instead of you just grabbing the top ticket.
Skipping it means you may spend a full task rebuilding something a sibling agent already shipped.

- **Open PRs:** `gh pr list --state open --limit 30` — scan titles/branches for a match to the
  ticket you're about to claim.
- **Active sessions:** `agents sessions --active` — a ticket can look unclaimed on the board
  while a live session (yours or another agent's) is already building it.
- **Recent commits:** `git log --oneline --since="24 hours ago"` — the fix may already be on
  `main`; if so, close the ticket instead of re-implementing.
- **In-flight context auto-injected at session start** (this repo's convention) — read it.

If you find a match, **do not claim that ticket.** Skip to the next candidate, or go review
the in-flight PR instead.

**Scope this to the 1-3 candidates you're actually choosing between** — not a license to audit
the whole backlog. A prior session turned this exact check into a 230-turn, 14-hour full-board
triage by not bounding it; that's `/triage`'s job. Check the candidate, decide, move.

### B4 — Pick up (or surface, don't guess)

- **Clear winner:** claim it via the `tickets` skill ("pick up X" — moves to In Progress,
  assigns to you), announce what you picked up and why, then start: read the relevant code,
  plan briefly, execute.
- **Not clear** (several plausible candidates, or the top item needs a scope/priority call
  that isn't yours to make): list the top 2-3 candidates with one line each on why, and use
  `AskUserQuestion` — don't silently pick one. Cancel/reprioritize decisions belong to
  `/triage`, not to `/next` guessing.

**Never park an unclear item in Backlog as an implicit non-decision.** Either something is
clear enough to pick up now, or it's not and belongs in the `AskUserQuestion` surface (or
`/triage`'s keep/cancel call) — never a quiet deferral. If it's not worth doing, say so and
let `/triage` cancel it; don't let it rot in a graveyard status.

### B5 (optional) — Surface related work and improvement opportunities

Once the task is delivered, and only when what you just shipped is substantial enough to be
worth a second look (skip for a one-line fix): spin up **one** subagent — not a
`/code:review repo`-style sweep — to scan for:

- **Related tracker items** beyond what B2 surfaced — the same epic/cluster, a follow-up
  someone noted on the ticket you just closed.
- **Bounded, concrete opportunities** in what you just shipped — a missing test on the
  critical path you touched, a doc that's now stale, a simplification you noticed mid-task.

The subagent does the digging so your own context stays clean; it reports back a short list,
not a report. Present findings as **options** — a few bullets, or `AskUserQuestion` if there's
a real choice — never auto-execute beyond a genuine one-line fix, and never let this balloon
into a full audit.

## Anti-patterns

- **Stopping at a recap.** Part A is a ship checklist, not a status summary — drive to delivered
  first (see A6's forbidden endings), then move on.
- **Hardcoding a tracker.** Check injected context first, fall back to the `tickets` skill for
  detection, never assume Linear — the exact reason the original `/next` was removed.
- **Reimplementing `/work:dispatch`'s resolution logic.** If the pick belongs to a different
  executor (non-coding, or another machine/agent), hand it to `/work:dispatch`.
- **Skipping B3.** Claiming a ticket without checking for an open PR or a live session on it is
  how duplicate work happens.
- **Turning B3 into a full-board audit.** Bound it to the candidates in front of you; a
  whole-backlog sweep is `/triage`'s job.
- **Guessing at an ambiguous pick.** Several plausible next tasks or a scope/priority call →
  surface it, don't auto-decide.
- **Deferring to Backlog instead of deciding.** Either it's clear enough to pick up, or it's a
  `/triage` cancel/surface call.
- **Stalling when nothing's explicitly assigned to you.** Unclaimed, clearly scoped work is
  fair game — pick it up.
- **Turning B5 into a full quality sweep.** One bounded subagent, a short offer list — not a
  `/code:review repo`-style audit every time you finish a task.
