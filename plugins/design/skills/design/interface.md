# design:interface — screens, pages, and components

Produce a screen, page, or component as **self-contained HTML** you can open offline and
hand to an engineer as a real starting point, not a picture of a UI. Covers landing pages,
app screens, dashboards, forms, marketing pages, resumes, and one-pagers, plus **redesign**
from a screenshot of an existing screen.

## Load design-core first

Read `design-core.md`. Everything here inherits its hierarchy, spacing, type, color,
accessibility (contrast + colorblind-safe), brand-probe, precise copy, and mandatory
render/critique verification.

## When to use (vs neighbors)

- One or a few static screens or components → **interface** (this).
- Several screens the user should click between → **`prototype`**.
- Reusable tokens/components as a system, not a screen → **`system`**.
- A diagram or a chart, not a UI → **`diagram`** / **`dataviz`**.

## The loop

1. **Scope the job.** What screen, for whom, doing what? One primary action per screen.
2. **Brand-probe** (design-core §4): skin to the target's tokens, or the house fallback.
3. **Structure before style.** Lay out hierarchy and grid first: focal point, sections,
   spacing scale. Semantic HTML, real selectable text.
4. **Style with restraint.** Apply the palette and type scale; one accent; states
   (hover / focus / disabled) with visible focus rings; responsive at a couple of breakpoints.
5. **Redesign path:** given a screenshot, follow `interface-redesign.md` — audit the
   current screen, draw the BEFORE diagram, propose 2-3 distinct AFTER options each
   with a full ASCII layout, fill a comparison table, then STOP and wait for the
   user's pick before implementing anything.
6. **Verify** (design-core §9): render, screenshot, run the checklist, fix, re-render.

## Output & delivery

- **One self-contained `.html`** (inline CSS, no CDN) at
  `"$ROOT/.agents/design/<slug>.html"` or `/tmp/<slug>.html`. Opens offline. Keyless.
- Render and screenshot both themes if the design supports light/dark; open it on the
  user's machine (see `SKILL.md` delivery). Show the screenshot, not just a description.

## Mode checklist (on top of design-core)

- [ ] One clear primary action per screen; obvious focal point.
- [ ] Real semantic HTML and selectable text, not a mock image.
- [ ] Responsive at 2 or more breakpoints; visible focus states.
- [ ] Contrast at least AA; nothing conveyed by color alone.
- [ ] Skinned to brand tokens if found, else a tasteful house fallback.
- [ ] Rendered, screenshotted, and critiqued before "done".
