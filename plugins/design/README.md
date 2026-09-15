# Design

Create new work or refine an existing product through focused workflows. Start from the
product's guidelines, components, visual patterns, and observed interactions.

## Commands and skills

| Command | Skill | Use it for |
| --- | --- | --- |
| `/design` | [design](skills/design/SKILL.md) | Choose the workflow for the task |
| `/design:system` | [system](skills/system/SKILL.md) | Guidelines, tokens, components, interaction patterns, and brand identity |
| `/design:graphics` | [graphics](skills/graphics/SKILL.md) | Logos, icons, favicons, and other graphic assets |
| `/design:prototype` | [prototype](skills/prototype/SKILL.md) | Screens, components, interactive flows, and UI motion |
| `/design:critique` | [critique](skills/critique/SKILL.md) | Evidence-based assessment and concrete findings |

The commands are thin routes to real skills. Each selected workflow loads the
[shared design practice](skills/design/design-core.md) through the resolved `design`
skill. It does not load every other workflow. Existing brand plugins can keep routing
through `/design`.

Refinement begins by reading and visually inspecting existing guidelines and product
examples, then exercising relevant states and interactions. A short interaction recording
is captured and reviewed when timing or a sequence matters; state captures and an action
trace suffice otherwise. Existing implementation and conventions take precedence over
new defaults. Review-only requests remain assessments.

## On-demand references

| Reference | Use it for |
| --- | --- |
| [Diagrams](skills/design/diagram.md) | Structure, architecture, and relationships |
| [Data visualization](skills/design/dataviz.md) | Charts, comparisons, and data stories |
| [Decks](skills/design/deck.md) | Presentation design in the requested format |
| [Flow diagnosis](skills/design/anticipate.md) | Dead ends, recovery, and next actions |

## Checkers

These remain owned by the critique skill and are resolved from its installed directory:

- [check-contrast.ts](skills/critique/scripts/check-contrast.ts) computes contrast from
  foreground/background pairs; it does not establish complete accessibility compliance.
- [check-tells.ts](skills/critique/scripts/check-tells.ts) flags possible markup and style
  issues. Its heuristics require judgment against the product's own conventions.

Use the existing app stack for authorized implementation. Standalone HTML/SVG previews
can be self-contained and offline; use the available image capability when raster work
is requested. A placeholder is not a finished image. Delivery follows the owning
`artifacts`, `browser`, or `computer` workflow.
