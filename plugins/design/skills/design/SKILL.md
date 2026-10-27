---
name: design
description: "Route design work to systems, graphics, prototypes, or critique. Supports creating new work and refining existing products using their guidelines and observed interactions."
argument-hint: "[design task or existing surface]"
user-invocable: true
---

# Design

Choose the workflow that owns the requested outcome. Each focused skill is complete on its
own; load only the one selected. Clarify only an ambiguity that changes the deliverable; do
not ask the user to choose a command.

| Outcome | Workflow |
| --- | --- |
| Create or refine guidelines, tokens, components, interaction patterns, or brand identity | `design:system` |
| Create or refine icons, logos, favicons, and standalone graphics | `design:graphics` |
| Create or refine screens, components, interactive flows, or UI motion | `design:prototype` |
| Assess an existing visual or interactive surface | `design:critique` |

For a mixed request, start with the central outcome and load another workflow only for its
part. For a diagram, chart or data story, deck, or a flow's dead end, follow the practice
below and then the matching file in this folder: [diagram.md](diagram.md),
[dataviz.md](dataviz.md), [deck.md](deck.md), or [anticipate.md](anticipate.md).

## Shared practice

Use the product's conventions and the user's scope; creating, refining, and reviewing are
different tasks.

1. **Choose the medium.** Refine an existing app in its own stack and component library
   when implementation is requested. A design-only request stays a proposal or prototype.
   For a standalone preview, use editable HTML/SVG and the `artifacts` skill for authoring
   and delivery; offline previews are self-contained.
2. **Understand the existing system first.** Find the product's `DESIGN.md`, `BRAND.md`,
   rendered guidelines, tokens and theme files, component library, assets, and relevant
   implementation, and read them together. Open the rendered guidelines and representative
   pages with `browser` or `computer`. Name the repeated choices (type, spacing, density,
   icon geometry, component variants, state feedback, navigation, motion) and cite where
   each comes from. Distinguish intended rules from drift; do not invent behavior for a
   surface you could not open.
3. **Visual quality.** Hierarchy, alignment, density, type, and spacing serve the task.
   Reuse the product's scales and patterns; add a new default only where none exists or the
   redesign explicitly changes it, and explain consequential changes.
4. **Accessibility.** Measure contrast from actual colors (AA: 4.5:1 for ordinary text, 3:1
   for large); never guess a ratio. Do not encode meaning by color alone. Exercise keyboard
   navigation and visible focus, labels, validation, disabled states, and touch use. Honor
   reduced-motion preferences.
5. **References.** Start with the product's own examples and the user's references. For a
   new direction, browse current examples and inspect them before borrowing a choice.
6. **Copy.** Precise language, realistic content, the product's voice. Labels explain
   actions and outcomes. Never invent testimonials, usage counts, or claims.
7. **Raster assets.** Use the image capability when artwork is needed. A placeholder or a
   generation brief is unfinished work; label it and say what remains.
8. **Observe interactions before changing them.** Walk the journey: entry, primary action,
   feedback, next step, back/cancel, recovery, and the hover, focus, loading, empty, error,
   and success states. Record a short clip when timing or sequence matters and review its
   frames. A captured file alone is not evidence that anyone inspected it.
9. **Verify and deliver.** Inspect the result at the relevant sizes and themes and repeat
   the affected interactions. Run `bun ../critique/scripts/check-contrast.ts --json
   '<pairs>'` on actual color pairs and `bun ../critique/scripts/check-tells.ts <file>` on
   available markup (paths relative to this folder); treat their style warnings as prompts
   to inspect, not laws. Fix findings, inspect again, show the result on the user's machine,
   and state what changed, what was exercised, and what remains unverified.

For naming a move precisely see [vocabulary.md](vocabulary.md); for composing a whole page,
[composition.md](composition.md); for studying reference sites, [research.md](research.md).
These are optional depth, not prerequisites.
