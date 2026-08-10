# design:diagram — architecture, flow, and structural diagrams

Produce a structure diagram as **self-contained HTML with a hand-authored inline `<svg>`** —
no mermaid, no CDN chart library. Every node shape and arrowhead follows the field's standard
notation; a legend appears whenever color or line-style encodes meaning.

## Load design-core first

Read `design-core.md`. Everything here inherits its spatial rhythm, color discipline,
accessibility (contrast + colorblind-safe palettes), brand-probe, precise non-marketing copy,
and mandatory render/critique verification (§7).

## When to use (vs neighbors)

- A structure: services, actors, data models, processes, networks → **diagram** (this).
- Quantitative data (time series, distributions, comparisons) → **`dataviz`**.
- A screen, page, or component a user interacts with → **`interface`**.
- Several clickable screens → **`prototype`**.

## The loop

1. **Identify the notation.** Consult the `plan-render` skill's `diagram-conventions.md` and
   pick the notation that fits what the figure shows: C4 for service architecture, UML
   sequence for message ordering, UML class for type relationships, ER crow's-foot for data
   models, ISO 5807 shapes for control flow, BPMN for multi-actor processes, provider icons
   for network topology. Never invent a bespoke notation when a standard one exists.
2. **Draw the SVG correctly.** Use the notation's exact shapes and arrowheads: filled
   arrowhead = UML sync call; dashed open arrowhead = return; hollow triangle = inheritance;
   filled diamond = composition; crow's-foot glyphs for cardinality; diamond for ISO 5807
   decisions. Pick one flow direction (top-down or left-to-right) and hold it.
3. **Label every arrow** with what flows — for architecture, include the protocol. Label every
   node with its type. Every axis carries units when data is involved.
4. **Add a legend** whenever color or line-style encodes meaning. For C4 this is mandatory.
   Use colorblind-safe palettes: Okabe-Ito for categorical distinctions, Viridis for
   sequential encoding.
5. **Verify** (design-core §9): screenshot the rendered SVG and check it against the
   amateur-tells in `diagram-conventions.md` (unlabeled arrows, decision boxes not diamonds,
   mixed notations, color without a legend). Fix what fails and re-render.

## Output & delivery

- **One self-contained `.html`** (inline CSS and SVG, no CDN) at
  `"$ROOT/.agents/design/<slug>.html"` or `/tmp/<slug>.html`. Opens offline. Keyless.
- Screenshot and show it; open on the user's machine (see `SKILL.md` delivery). A diagram
  described but not rendered is not delivered.

## Mode checklist

- [ ] Notation matched to the figure type per `diagram-conventions.md`.
- [ ] Correct domain shapes and arrowheads — no plain rectangles with unlabeled arrows.
- [ ] One consistent flow direction throughout.
- [ ] Every arrow labeled with what flows; every node labeled with its type.
- [ ] Legend present whenever color or line-style carries meaning.
- [ ] Colorblind-safe palette (Okabe-Ito or Viridis); no red-vs-green-only encoding.
- [ ] Rendered, screenshotted, and checked against the amateur-tells before "done".
