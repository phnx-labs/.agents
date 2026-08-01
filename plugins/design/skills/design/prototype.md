# design:prototype — clickable multi-screen HTML flow

Produce a navigable prototype: real `<a href>` links between screens, all in a
self-contained folder the user can open offline without a build toolchain. Not a
wireframe and not a picture of a UI — a thing you click through.

## Load design-core first

Read `design-core.md`. Everything here inherits its hierarchy, spacing, type, color,
accessibility (contrast + colorblind-safe), brand-probe, precise copy, and mandatory
render/critique verification.

## When to use (vs neighbors)

- Several screens the user should click between → **prototype** (this).
- One screen or component → **`interface`**.
- Reusable tokens/components as a system, not a screen → **`system`**.
- A diagram or a chart, not a UI → **`diagram`** / **`dataviz`**.

## The loop

1. **Map the flow.** Name every screen and its outgoing transitions: which button goes
   where. One primary action per screen. If the user's brief is vague, ask for the
   two or three core paths before building.
2. **Brand-probe** (design-core §4): extract tokens and skin `_shared.css`. The
   prototype inherits those tokens; screens never hard-code a color or size that
   belongs in the token file.
3. **Build each screen.** One `.html` per screen, real semantic HTML and selectable
   text, every nav link pointing to the correct sibling file by relative path. No
   JavaScript router — just `<a href="screen-name.html">`.
4. **Wire `index.html`.** Landing screen (or a minimal flow map) linking to the first
   real screen; visiting the folder drops the user at the right starting point.
5. **Verify by clicking through.** Open `index.html`, walk every declared path, and
   screenshot the key screens. Run the critique checklist on each screen; fix what
   fails; re-screenshot.

## Output & delivery

- **A folder** at `"$ROOT/.agents/design/proto-<slug>/"` (or `/tmp/proto-<slug>/`)
  containing:
  - `_shared.css` — design tokens and shared component styles, no CDN.
  - `<screen-name>.html` per screen — inline only what is screen-specific.
  - `index.html` — entry point.
- All files open offline by double-click. Keyless. No build step.
- Open `index.html` on the user's machine when done; show screenshots of at least
  the first and last screens in the primary path.

## Mode checklist

- [ ] Every screen in the declared flow has a corresponding `.html` file.
- [ ] All nav links are real `<a href>` paths; none are dead or `#`.
- [ ] `_shared.css` holds tokens; screens import it and do not reinvent values.
- [ ] Real semantic HTML and selectable text on every screen.
- [ ] Contrast at least AA; nothing conveyed by color alone.
- [ ] Skinned to brand tokens if found, else a tasteful house fallback.
- [ ] Clicked through every declared path and screenshotted key screens before "done".
