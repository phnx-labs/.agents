---
description: Confirm the current task is actually done, then surface (and if clear, claim) the next related task from the project's tracker. Tracker-agnostic — composes with /tickets, never hardcodes Linear.
---

You just finished something, or are about to move on. Context: $ARGUMENTS

`/next` is the continuity command an agent runs at the boundary between two tasks:
verify what you just did is really done, recall what project you're in, then find
what to work on next — related work first, everything else after — using whichever
tracker this project actually has. It **composes with `/tickets`** (tracker
detection, claim/close primitives) rather than reimplementing a Linear-specific
flow — a prior version of this command hardcoded Linear and was removed for it;
don't reintroduce that.

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

Invoke `/tickets` Step 1 (tracker detection: skill → CLI → repo signal → ask) to
find whatever this project actually uses. Do not assume Linear, GitHub, or Jira —
detect, every time.

Once you have the tracker, prefer in this order:

1. **Related to what you just shipped** — same component/surface, a follow-up
   noted on the ticket you just closed, a sibling in the same epic/cluster.
2. **Highest priority in Todo** (not already In Progress) that's clearly scoped.
3. Nothing clear? Surface the top few candidates and stop — don't guess at intent
   (see Step 5).

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

## Step 5: Pick up (or surface, don't guess)

- **Clear winner:** claim it via `/tickets` ("pick up X" — moves to In Progress,
  assigns to you), announce what you picked up and why, then start: read the
  relevant code, plan briefly, execute.
- **Not clear** (several plausible candidates, or the top item needs a
  scope/priority call that isn't yours to make): list the top 2-3 candidates with
  one line each on why, and use `AskUserQuestion` — don't silently pick one.
  Cancel/reprioritize decisions belong to `/triage`, not to `/next` guessing.

## Anti-patterns

- **Hardcoding a tracker.** Always route through `/tickets` detection — this is
  the exact reason the original `/next` was removed.
- **Skipping Step 4.** Claiming a ticket without checking for an open PR or a live
  session on it is how duplicate work happens — a session in this very repo did
  this today and had to close a duplicate PR after discovering a sibling had
  already shipped the fix.
- **Guessing at an ambiguous pick.** Several plausible next tasks or a
  scope/priority call → surface it, don't auto-decide.
- **Treating `/next` as a full recap.** It's a lightweight boundary check, not a
  handoff summary — use `/recap` when you need the fuller version.
