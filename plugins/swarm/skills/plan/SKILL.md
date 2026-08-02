---
name: plan
description: "Plan a feature with swarm verification — research hard, draft an OpenSpec-grade change proposal, then have independent agents plan the same thing blind and reconcile. Use before building anything non-trivial when you want the plan stress-tested, not just written. Triggers on: 'swarm plan', 'plan with verification', 'spec this out', 'change proposal', 'plan and check the approach'."
argument-hint: "[feature or change to plan]"
allowed-tools: Bash(agents teams*), Bash(agents run*), Bash(rg*), Bash(fd*), Bash(ls*), Bash(git log*), Bash(git diff*), Read(*), Grep(*), Glob(*), Write(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# swarm:plan — plan, then have the swarm try to break the plan

> Read the `swarm:orchestrate` skill first for the fan-out mechanics (team creation, briefs, blinded verification, monitoring). This skill is the **plan mode** layered on top: research deeply, produce an OpenSpec-grade change proposal, and validate it against independent agents who plan the same feature blind.

You are planning: **$ARGUMENTS**

The deliverable is not a paragraph of intentions — it is a **change proposal at the level of [OpenSpec](https://openspec.dev/)**: a precise statement of the delta, the tasks to get there, and the spec it leaves behind. Then you de-risk it by having the swarm independently arrive at their own plans and reconciling.

## 1. Understand (read, don't guess)

Read `AGENTS.md` / `CLAUDE.md` if present. Grep for keywords related to the task, then **read** the files that own the patterns — trace the data flow end to end, identify every touch point and dependency. Explore with `Agent(subagent_type: "Explore")` for breadth; read the load-bearing files yourself.

## 2. Research the state of the world (mandatory web search)

Your weights are stale. Before proposing an approach that touches any external truth — a library's current API, a framework capability, a service's limits, a pricing tier, the current SOTA pattern, a model id — **WebSearch with the current year**, then `WebFetch` the authoritative doc and quote it. A plan built on remembered facts is a plan built on sand. Cite every external claim with a URL (and year). If three approaches exist in the wild, search all three before picking.

## 3. Find existing abstractions before proposing new code

For every piece of new code you're about to propose, ask:
- Is there an existing function that already does most of this?
- Can I extend an abstraction instead of inventing one?
- Can this be a one-line change in one place instead of new logic in many?

**Prefer extending existing code over writing new. Prefer one change in one place over many changes in many.**

## 4. Draft the OpenSpec-grade proposal

Structure the plan as a change proposal, not prose. (You don't need the `openspec/` tooling installed — you're borrowing its rigor and shape.)

- **`proposal.md`** — Why (the problem / user value), What changes (the delta in plain terms), and Impact (what this touches, what it foreclosing). One source of truth for the change.
- **`tasks.md`** — the ordered, checkable task list to execute the change. Each task names the file(s) it edits. This is exactly what a swarm or a `/code:loop` would drain.
- **Delta spec** — the behavior the system will have *after* this change: the new contract, endpoints, types, or UX, written as the source-of-truth spec a future change would diff against.

## 5. Verify — the swarm plans it blind

Fan out via `agents teams` (mechanics in `swarm:orchestrate`). Check who's signed in (`agents teams doctor` / `agents view --json`), then spawn 1–2 verifiers on **different** providers than yourself (codex, antigravity, …) — count by judgment, more for a wide or high-stakes plan. **`--mode plan`** (read-only).

Give each verifier: the feature description, the relevant context (key files, how the system works, your web-search citations). Do **NOT** share your proposed approach — ask them to independently produce their own plan. (Blinded verification per `swarm:orchestrate`.)

Compare:
- Did they identify the same touch points and files?
- Same scope, or did one find work you missed?
- Did they catch edge cases you missed?
- Is their approach simpler or more robust than yours?

Where approaches diverge significantly, that divergence is the real decision — evaluate which is better or fuse the strengths. Don't default to your own draft just because it's yours.

## Output

### Goal
One sentence. What are we building?

### Approach
A short paragraph: the high-level strategy and why it beats the alternatives you researched.

### Research
External facts that shaped the plan, each with a source URL (and year). State-of-the-world claims live here, verified — not in your memory.

### Verification
The independent plans the swarm produced. Where they agreed (high confidence), where they diverged (the real decisions), and why you chose the final approach. Cite each finding to its teammate.

### Design
Only if there are visual or architectural changes. ASCII diagrams.

### Proposal (`proposal.md`)
Why / What changes / Impact.

### Tasks (`tasks.md`)
Ordered, checkable, each naming its file(s). Drainable by `/code:loop` or fanned out via `agents teams`.

### Delta spec
The contract the system holds after the change — the source of truth a future change diffs against.

### Edge cases
Enumerated, each with how the plan handles it.

### Testing
Scenarios to cover — happy path and the edges that matter.

### Review artifact (HTML)
After the proposal is written, render the plan as a self-contained HTML file and open
it on the machine the user sits at — follow the **`plan-render`** skill for the LOOK
(house structure, product-brand theming, light/dark toggle, ≥1 hand-authored inline-SVG
diagram) and the `/plan` command's Step 9 for the open-on-Mac transport, using the
injected **Host & Fleet** context to pick and reach the browser host. Don't duplicate the
recipe; reuse it.

## Constraints

No human-time estimates (wall-clock minutes / edit counts / token cost only). No "nice to have" additions. No backwards-compat planning unless asked. Do exactly what was asked — no scope creep.
