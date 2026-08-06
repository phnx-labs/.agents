---
description: Confirm the current task is actually done, then surface (and if clear, claim) the next related task and keep working in this session. Reads whatever board state is already in context, never hardcodes Linear; hands non-coding or hand-off-elsewhere work to /work:dispatch instead of dispatching it inline.
---

You just finished something, or are about to move on. Context: $ARGUMENTS

`/next` is the continuity command an agent runs at the boundary between two tasks:
verify what you just did is really done, recall what project you're in, then find
what to work on next — related work first, everything else after — using whichever
tracker this project actually has. It never hardcodes Linear — a prior version of
this command did exactly that and was removed for it; don't reintroduce that.

**Chains from `/continue`.** If you just ran `/continue` and its Step 3 confirmed
the resumed task is done, don't re-derive project context here — you already have
it. Skip straight to Step 3 below.

**Continue-here vs. hand-off-elsewhere.** `/next` is for continuing THIS session on
the next task yourself. If the next unit of work should go to a different
executor instead — a fresh dispatched agent, a different machine, or non-coding
work (content, design, a browser task) — that's `/work:dispatch`, not `/next`.
The two share the same resolution logic (find the target, dedupe against
in-flight work); `/next` picks up where that resolution lands and keeps working
in-session, `/work:dispatch` hands it off. Don't run both on the same target.

## Step 1: Confirm the current task is actually done

Before moving on, make it true — this mirrors `/done`'s Step 0, scoped to just the
task in front of you (not a full session wrap):

- **Code.** Read what you changed. No TODOs, no half-finished branch, nothing
  stubbed. `git diff` / `git status` clean or intentionally staged.
- **Tests.** Run whatever covers the critical path you touched. "It compiles" is
  not "it's tested."
- **Tracker.** If a ticket was open for this, close it via `/tickets` **with
  proof** (PR link, commit, screenshot, metric) — not just a status flip.

If any of this isn't true, finish it first. `/next` assumes done; it does not
verify-and-abandon.

## Step 2: Recall — what project, what you just did

One or two lines, not a full recap (`/recap` is for that):

- **Project.** Repo name, `git remote get-url origin`, and a glance at
  `AGENTS.md`/`README.md` if you haven't grounded in it this session.
- **What just shipped.** The concrete thing — a PR, a fix, a ticket closed. Name
  it; "made progress" doesn't count.

This context is what makes "similar tasks" in Step 3 mean something — a related
next task is one that touches the same surface, component, or ticket cluster as
what you just finished, not just anything open.

## Step 3: Pull the board — tracker-agnostic

**Check what's already in your context first.** Most tracker integrations
auto-inject board state at session start (this repo's Linear hook is one — team
tasks, project milestones, the active cycle, all delivered before you type
anything). Read that before running any discovery command; it's usually already
answered.

Only when nothing's injected, or the project uses a tracker this session hasn't
surfaced yet, fall back to `/tickets` Step 1 (tracker detection: skill → CLI →
repo signal → ask). Do not assume Linear, GitHub, or Jira — detect, every time.
`/tickets` is the right primitive for **actions** (claim, close, comment) even
when discovery came from injected context, not from `/tickets` itself.

Once you have the board, prefer in this order:

1. **Related to what you just shipped** — same component/surface, a follow-up
   noted on the ticket you just closed, a sibling in the same epic/cluster.
2. **Highest priority in Todo** (not already In Progress) that's clearly scoped.
3. Nothing clear? Surface the top few candidates and stop — don't guess at intent
   (see Step 5).

**No ticket assigned to you specifically is not a reason to stop.** Look at
whatever's unclaimed and clearly scoped — you don't need an explicit assignment to
pick up clean, ready work. Stalling with "what should I work on?" when the board
has obvious unclaimed work is the failure this command exists to prevent.

## Step 4: Rule out duplicate work — check what's already in flight

This is the step that actually justifies `/next` existing instead of you just
grabbing the top ticket. Skipping it means you may spend a full task rebuilding
something a sibling agent already shipped.

- **Open PRs:** `gh pr list --state open --limit 30` — scan titles/branches for a
  match to the ticket you're about to claim.
- **Active sessions:** `agents sessions --active` — a ticket can look unclaimed on
  the board while a live session (yours or another agent's) is already building it.
- **Recent commits:** `git log --oneline --since="24 hours ago"` — the fix may
  already be on `main`; if so, close the ticket instead of re-implementing.
- **In-flight context auto-injected at session start** (this repo's convention) —
  read it, don't ignore it.

If you find a match, **do not claim that ticket.** Skip to the next candidate, or
go review the in-flight PR instead.

**Scope this to the 1-3 candidates you're actually choosing between** — this is
not a license to audit the whole backlog. A prior session turned this exact check
into a 230-turn, 14-hour full-board triage by not bounding it; that's `/triage`'s
job, not this step's. Check the candidate, decide, move.

## Step 5: Pick up (or surface, don't guess)

- **Clear winner:** claim it via `/tickets` ("pick up X" — moves to In Progress,
  assigns to you), announce what you picked up and why, then start: read the
  relevant code, plan briefly, execute.
- **Not clear** (several plausible candidates, or the top item needs a
  scope/priority call that isn't yours to make): list the top 2-3 candidates with
  one line each on why, and use `AskUserQuestion` — don't silently pick one.
  Cancel/reprioritize decisions belong to `/triage`, not to `/next` guessing.

**Never park an unclear item in Backlog as an implicit non-decision.** This is the
single most-corrected behavior around task selection: either something is clear
enough to pick up now, or it's not and belongs in the `AskUserQuestion` surface (or
`/triage`'s keep/cancel call) — never a quiet deferral. If it's not worth doing,
say so and let `/triage` cancel it; don't let it rot in a graveyard status.

## Step 6 (optional): Surface related work and improvement opportunities

Once Step 1 confirms the task is done, and only when what you just shipped is
substantial enough to be worth a second look (skip this for a one-line fix):
spin up **one** subagent — not a `/quality`-style sweep — to scan for:

- **Related tracker items** beyond what Step 3 already surfaced — the same
  epic/cluster, a follow-up someone noted on the ticket you just closed.
- **Bounded, concrete opportunities** in what you just shipped — a missing test on
  the critical path you touched, a doc that's now stale, a simplification you
  noticed mid-task but didn't stop to make.

The subagent does the digging so your own context stays clean; it reports back a
short list, not a report. Present findings as **options** — a few bullets, or
`AskUserQuestion` if there's a real choice to make — never auto-execute beyond a
genuine one-line fix, and never let this balloon into a full audit. This is the
"blend recap with suggestions" pattern: recall what happened, then offer what's
worth doing about it, without doing the deep analysis in the main thread.

## Anti-patterns

- **Hardcoding a tracker.** Check injected context first, fall back to `/tickets`
  detection, never assume Linear specifically — this is the exact reason the
  original `/next` was removed.
- **Reimplementing `/work:dispatch`'s resolution logic.** If the pick belongs to a
  different executor (non-coding, or should run on another machine/agent), hand it
  to `/work:dispatch` instead of dispatching it inline from here.
- **Skipping Step 4.** Claiming a ticket without checking for an open PR or a live
  session on it is how duplicate work happens — a session in this very repo did
  this today and had to close a duplicate PR after discovering a sibling had
  already shipped the fix.
- **Turning Step 4 into a full-board audit.** Bound it to the candidates in front
  of you; a whole-backlog sweep is `/triage`'s job, not a side effect of picking
  one ticket.
- **Guessing at an ambiguous pick.** Several plausible next tasks or a
  scope/priority call → surface it, don't auto-decide.
- **Deferring to Backlog instead of deciding.** Not a real choice — either it's
  clear enough to pick up, or it's a `/triage` cancel/surface call.
- **Stalling when nothing's explicitly assigned to you.** Unclaimed, clearly
  scoped work is fair game — pick it up.
- **Turning Step 6 into a full quality sweep.** One bounded subagent, a short
  offer list — not a `/quality`-style audit every time you finish a task.
- **Treating `/next` as a full recap.** It's a lightweight boundary check, not a
  handoff summary — use `/recap` when you need the fuller version.
