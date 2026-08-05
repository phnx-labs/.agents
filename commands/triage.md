---
description: Triage the issue tracker end-to-end — ground in real product goals, then force every open item to a real decision (schedule into the current cycle and drive it, or cancel it). Never park in Backlog.
---

You're being asked to triage the issue tracker: $ARGUMENTS

(If `$ARGUMENTS` is empty, default to "the whole board for this repo's project.")

**The point of triage is fewer open items, not reshuffled ones.** Success is the total
open count and the per-cycle count going **down** across runs — not tickets moved between
states. If a pass ends with the same count it started with, it didn't triage anything.

## Step 0: Ground in the real product goals first

You cannot tell "genuinely urgent" from "just labeled urgent" without knowing what the
product is actually trying to do right now. Before judging a single ticket:

- **Linear** — read the goal spine: Initiative → Project (one-liner/metric/goal-now) →
  Milestones (target date + done-condition). `linear milestones` / `linear projects` for
  the live state. The **current goal is the incomplete milestone with the soonest target
  date** — a query, not a guess. Check for a milestone/goal-spine memory for this project
  before re-deriving it from scratch.
- **GitHub** — check `ROADMAP.md`, pinned issues, the repo's milestone list
  (`gh api repos/{owner}/{repo}/milestones`), and any product doc (`PRODUCT.md`,
  `MASTER_PLAN.md`) for a stated near-term goal.
- **Neither exists?** Ask once, briefly, then proceed — don't triage against a goal you
  invented.

## Step 1: Find the tracker

Same detection order as `/tickets` Step 1 — don't re-derive it: skill-level integration →
installed CLI (`linear`, `gh`, `jira`, `glab`) → repo-level signal → ask once. Reuse the
skill's exact commands if one is loaded.

## Step 2: Pull the board

Full open-item list scoped to `$ARGUMENTS` (a project, a label, or the whole team/repo).
Read priority, status, cycle/milestone, assignee, and age for every item — you need all of
it to make the calls below, not just a title list.

## Step 3: Force exactly one of two outcomes per item — no third hedge state

For every open item, decide. There is no "leave it for now":

- **KEEP & SCHEDULE.** It's real work worth doing → put it in the **current cycle**
  (active cycle / this week's milestone), status Todo or further, never `--cycle none` and
  never Backlog. If it's small and fully scoped, don't just schedule it — build it now in
  the same pass (F1: a filed-and-parked ticket isn't progress).
- **CANCEL.** Not worth doing (dead code path, speculative "no test for X" nit, superseded,
  a someday-idea) → cancel it outright with a one-line reason on the ticket. Do **not**
  downgrade it to Low priority or Backlog instead of canceling — that's a slower cancel
  that keeps cluttering the count exactly the same as leaving it Urgent would.

**Explicitly banned as a landing state for anything you touch this pass:** `Backlog`
status, `--cycle none`, and "Low priority, revisit someday." These are hedges, not
decisions — they let a ticket rot instead of forcing the keep/cancel call. (On a tracker
with no cycle concept, e.g. bare GitHub Issues, the same rule maps to: open+milestoned-now
vs closed.)

**One narrow exception:** an item genuinely blocked on a human decision or an external
dependency stays in its current state — but it must carry a comment naming exactly what
it's waiting on and who, so it doesn't just sit there unlabeled.

## Step 4: Decide, don't ask

Re-leveling a priority, canceling a stale ticket, moving something into the active cycle —
these are yours to decide and state in one line, not `AskUserQuestion` material (F1). Only
ask for a genuine strategy/scope call the user hasn't already made — e.g. "is this
initiative still company-priority," not "should I re-level this" or "should I cancel this
zombie." If you're torn between keep and cancel, make the call anyway and say why in one
line; the user will redirect if you're wrong. Never let indecision default to Backlog/Low.

## Step 5: Always link, never bare IDs

Every time you name a ticket in your report, include its full URL
(`linear tasks <id> | grep URL:`, or the tracker's issue-view link) — not just `RUSH-2021`.
A bare identifier means the user can't click through.

## Step 6: Report the delta, compactly

- Counts, before → after: total open, per-cycle/current, Backlog (should trend toward 0),
  Canceled this pass.
- The actual keep/cancel decisions made, each with its link and one-line reason.
- Anything left for the user (the narrow Step 3 exception only) — named, with what it's
  waiting on.

## Anti-patterns

- **Filing a ticket and immediately parking it in Backlog "to be honest about state."**
  Honest state is keep-and-schedule or cancel — Backlog is neither, it's a graveyard with
  a status label. If it's real, this cycle. If it's not, gone.
- **Hedging a priority to Low instead of actually deciding.** A Low ticket nobody will ever
  work just rots at a different altitude — it's the same clutter, slower.
- **Asking `AskUserQuestion` for a call you can make and defend in one line.**
- **Referencing a ticket by bare ID.** Always the link.
- **Ending a pass with the same open count you started with.** That's not triage.
