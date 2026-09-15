---
name: design
description: "Route design work to systems, graphics, prototypes, or critique. Supports creating new work and refining existing products using their guidelines and observed interactions."
argument-hint: "[design task or existing surface]"
user-invocable: true
---

# Design

Choose the workflow that owns the requested outcome. Resolve skills through the current
skill catalog; load only the selected workflow. Each focused skill reads the shared
`design-core.md` beside this file before doing design work.

| Outcome | Workflow |
| --- | --- |
| Create or refine guidelines, tokens, components, interaction patterns, or brand identity | `design:system` — the design plugin's `system` skill |
| Create or refine icons, logos, favicons, and standalone graphics | `design:graphics` — `graphics` skill |
| Create or refine screens, components, interactive flows, or UI motion | `design:prototype` — `prototype` skill |
| Assess an existing visual or interactive surface | `design:critique` — `critique` skill |

For a mixed request, start with the central outcome and load another workflow only for
its part. Reuse context and observations across the work. Clarify only an ambiguity that
changes the deliverable; do not ask the user to choose a command.

For diagrams, charts/data stories, and decks, read `design-core.md` and then the matching
`diagram.md`, `dataviz.md`, or `deck.md` beside this file. Diagnose a flow's next step with
`anticipate.md`; use `design:prototype` when implementing the interaction is requested.
These references load on demand, not with every design task.
