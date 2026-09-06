# Product brief — make the intended behavior reviewable

A planning PRD is a product requirements brief, including for a CLI, workflow,
backend, or small feature. Explain the intended experience before the code change.
Keep it within the existing plan; scale the detail to the decision.

## Reading order

1. **What this is / who it is for / problem:** a short, concrete statement.
2. **Product overview diagram:** show the actor, entry point, main system boundary,
   meaningful handoffs, and outputs. Readable left-to-right or top-to-bottom, with
   recognizable icons and labels. The reader should understand the whole operation
   without reading the implementation. This is a conceptual view, not proof of
   deployment topology or a substitute for detailed architecture.
3. **Goals:** observable outcomes, each paired with a success check. Separate a
   measured baseline from a proposed target; do not invent either.
4. **Non-goals:** deliberate exclusions, each with its reason. Distinguish excluded
   work from deferred work and unresolved decisions; do not turn exclusions into a
   speculative roadmap.
5. **User journeys:** `Intent | Where it happens | What they do | Outcome`. Include
   the happy path and consequential failure/recovery paths. Simplify steps and
   duplicate surfaces while preserving the jobs. Choose the smallest coherent
   product surface; change, extend, or refactor an existing path before adding one.
6. **Requirements and acceptance:** concrete behavior and constraints, connected
   to the goals/journeys and executable validation. Include relevant reliability,
   privacy, accessibility, or latency constraints only when supported by the brief.
7. **Assumptions / open questions:** label unknowns, their evidence, and what would
   change if they prove false. Ask only for choices requiring the user's judgment.

Then show the technical design, alternatives, implementation changes, and delivery
checks. Preserve the renderer's required headings; this brief belongs in the
Intent/Purpose evidence band, not a new frontmatter schema or compiler gate.

## Visual contract

Use [diagram-conventions.md](diagram-conventions.md) to select the technical view
and [authoring.md](authoring.md) for offline SVG and layout. An overview is a
**product overview diagram**; actions and decisions form a **user-flow diagram**;
actor handoffs can use a **swimlane diagram**. Name each figure's type, scope, and
current/proposed status. Do not label an informal illustration UML, BPMN, or C4
unless it follows that notation.

Icons identify actors and resources; they never replace names or meaningful
shapes. Use one consistent icon family for generic concepts, or the official
service icons for an actual provider topology. Bundle SVG paths/assets locally;
no CDN dependency and no emoji substitutes. Keep labels readable at normal zoom.

Lead with the figure, then explain the consequential decision. Separate the
conceptual overview, technical architecture, and screen mockups: each answers a
different question. For UI work, retain real captures and product-faithful mockups.
For backend work, draw the flow and system boundaries without inventing a screen.

Before presentation, inspect the rendered pixels: trace the main path and recovery
path; check shape semantics, arrow direction, legend, boundary ownership, label
collisions, contrast in both themes, and mobile legibility. A correct SVG parse
alone does not validate the diagram's meaning.
