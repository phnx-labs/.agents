---
description: Take a task in this project from idea to a working agent — understand the repo once, spec fast without re-deriving what's already known, root-cause bugs with the debug skill, show a quick plan, file the ticket, then dispatch an agent to build it.
---

You're being asked to dispatch work in this project: $ARGUMENTS

(If `$ARGUMENTS` is empty, ask what task/issue/directory this run is about — this command
needs a concrete target, unlike `/triage` which defaults to the whole board.)

This is the single-task counterpart to `/triage` (which sweeps the whole board). Use this
when the target is one task, bug, or directory you're about to hand to an agent.

## Step 1: Understand the repo — once per sitting

Before speccing anything, ground yourself in what this project already is and has recently
shipped:

- Read the repo's `AGENTS.md`/`CLAUDE.md`/`README.md` for architecture and conventions.
- Skim the `CHANGELOG.md` (or recent `git log`) for what's already been delivered — you
  need this to avoid re-speccing something that shipped last week, or missing that a task
  depends on a feature that doesn't exist yet.

Do this **once** per sitting, not once per `/dispatch` call — if you already grounded
yourself this session, don't re-read the same files for the next task.

## Step 2: Spec the task fast

- **Feature/task:** write a tight spec — what, why, acceptance criteria — using what
  Step 1 already established. Don't re-explain the architecture or re-justify context
  you've already grounded; spec only what's new about *this* task.
- **Bug:** don't hand-wave a root cause into the spec. Route through the `swarm:debug`
  skill (`/debug`) — trace the data path, form a hypothesis, get it confirmed by
  independent agents — or spin up 2-3 parallel investigation subagents yourself. The spec
  for a bug fix is the *confirmed* root cause, not a guess.

## Step 3: Show a quick plan

A few bullets, not a full artifact: approach, files/surfaces touched, risk, rough size.
If the task turns out to be big or architectural once you look at it (cross-cutting,
several independent surfaces, a real design decision), escalate to the full `/plan`
command instead of forcing it through this shortcut — don't under-plan a big task just
because you started with `/dispatch`.

## Step 4: File the ticket

Route through `/tickets` Step 1 (tracker detection) and its "create" mapping — title +
the Step 2 spec as the description, linked to any related tickets. File it **before**
dispatching so the work is tracked and has an owner of record, even though you're about
to dispatch it yourself.

## Step 5: Dispatch

Hand it to an agent to build, scaled to the task:

| Scope | Use |
|---|---|
| One ticket, one agent | `agents run` (see the `run` skill) — headless or interactive, your call |
| A ticket needing independent verification or parallel surfaces | `agents teams` (see the `teams` skill) |
| A queue of several tickets | the `code:loop` skill — drains one ticket or many |

Reference the ticket filed in Step 4 in the agent's brief so it updates the same ticket,
not a duplicate.

## Step 6: Don't stop at "filed and dispatched"

Per the `parallel-teams` completion contract: the task is done when the PR merges, or
you've handed it off by naming who/what now owns it. If you're waiting on the dispatched
agent, keep watching (background watch + finish-echo) — don't stop the turn on "dispatched"
alone.

## Anti-patterns

- **Re-reading the same repo docs for every task in one sitting.** Ground once, reuse.
- **Guessing a bug's root cause instead of routing through `/debug`.** A spec built on an
  unconfirmed hypothesis wastes the dispatched agent's run on the wrong fix.
- **Skipping Step 4 and dispatching untracked work.** Even solo, file it — that's what
  makes `/triage` later able to see it.
- **Treating "ticket filed + agent dispatched" as done.** It's in flight, not shipped.
