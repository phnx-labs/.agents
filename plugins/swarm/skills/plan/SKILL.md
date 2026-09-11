---
name: plan
description: "Plan a feature or system change with a visual product brief, goals/non-goals, user journeys, accurate diagrams, and independent verification where useful. Use for /plan, native plan mode, swarm plan, or a change proposal before building."
argument-hint: "[feature or change to plan]"
user-invocable: true
---

# Plan a reviewable change

Plan **$ARGUMENTS**. Make the intended outcome and proposed change understandable
before implementation. This is a change proposal; `swarm:spec` documents the
capability's durable contract. Scale the plan to the uncertainty and impact.
This skill owns the planning contract for `/plan`, `/swarm:plan`, native plan
mode, and requests made in ordinary language. Commands only route here.

## Choose the depth

For a small, settled change, keep the proposal compact: outcome, affected behavior,
implementation steps, and success checks. For substantial or uncertain changes,
include the product brief, important flows, alternatives, and dependencies below.
Maintain a current harness checklist for substantial plans. Do not turn a routine
implementation update into a separate planning exercise.

## Ground the scope

Read the relevant repository instructions and current implementation. Search open
PRs, relevant tickets through the `tickets` skill, recent changes, and active
ownership before proposing work. Read matches and coordinate overlaps; failed
lookups remain unknowns. Reuse context already established in this session.
Verify consequential external assumptions against current authoritative sources.
Use real product captures where they explain existing behavior.

Keep tracker discovery read-only during design iteration. Draft steps belong in
the plan and supported local checklist. When the approach is settled and execution
is about to begin, refresh discovery, reuse suitable tracking, and create only
missing substantive work being delivered. Follow `tickets` for this boundary;
explicit tracker-management requests remain valid. Planning-only requests stay
in planning. Existing authority to implement does not require a new approval gate.

## Explain the product before the implementation

Use the resolved `artifacts` skill's `references/product-brief.md` for the brief
and `references/diagram-conventions.md` for technical views. Keep the brief within
the plan rather than creating another document by default.

The reader should understand:

- Who this serves, the problem, and the observable outcome.
- Goals with success checks and non-goals with reasons.
- Relevant user journeys, including important failure and recovery behavior.
- Current versus proposed behavior, scope, dependencies, and compatibility.
- The chosen approach, material alternatives and tradeoffs, risks, and unknowns.
- A practical implementation checklist and how the result will be verified.

Do not invent requirements, performance targets, or empty sections to fill a
format. Prefer existing capabilities and the smallest coherent change. Decide
implementation details; involve the user when competing outcomes or priorities
require their choice.

## Make the change visible

Lead with a useful product overview, flow, or before/after view. Choose diagrams
for the question: actors and outcomes for a product overview, decisions for a
user flow, participants and ordered messages for a sequence, components and data
stores for architecture, and nodes and boundaries for deployment.

Use accurate system terminology, meaningful shapes, recognizable labeled icons
where helpful, directed and labeled relationships, and consistent color that
reinforces meaning without carrying it alone. Rectangles are appropriate for
components; do not use them indiscriminately for actors, decisions, or storage.
Distinguish observed facts from proposals. Keep comparable views visually aligned.
Show product-faithful mockups for the changed UI states that matter; do not invent
screens for backend-only work.

Present the relationships visually; use tables only when the `artifacts` contract
allows them. Put long inventories in a grouping figure or an appendix. Make cited
files clickable links to the relevant revision, and keep evidence beside the claim.

Author in Markdown, then render, inspect, and deliver HTML through `artifacts`. Its schema and semantic
figure markup are the renderer contract; keep those mechanics there. Follow the
repository's artifact location and use a linked worktree for committed output.
Commit feature plans through the feature worktree and PR alongside the change.
Include existing tracking links without creating tickets to fill a section.

## Check the approach and finish honestly

Use independent planning or adversarial review when uncertainty, complexity, or
impact warrants it; an explicit request for swarm verification includes it.
Give independent planners the problem and evidence before your preferred answer.
Resolve disagreements against the code and requirements, and record consequential
findings and decisions in the plan. Use `run`/`teams` for dispatch mechanics.

Before presenting a rendered plan, follow `artifacts` for the independent
`artifact-critic` review and its recorded passing verdict. Presentation review
is required even when a second planning investigation is unnecessary; the two
reviews answer different questions. Resolve presentation findings before delivery.

Present the inspected artifact where the user can review it. A plan is complete
when it makes the change and its validation reviewable; implementation is complete
only at its authorized delivery stage. When emitting a final plan outside native
plan mode, include `<!-- agents-plan -->` so the presentation check recognizes it.
