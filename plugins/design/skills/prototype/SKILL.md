---
name: prototype
description: "Create or refine screens and interactive flows: a single screen or page, a clickable multi-screen HTML prototype with real links, a redesign of an existing screen (BEFORE diagram, 2-3 AFTER options, STOP for the user's pick), and UI motion/micro-interactions. Real semantic HTML you can open offline and hand to an engineer, not a picture of a UI. Triggers on: design a screen/page/UI, mock up, prototype, clickable flow, redesign this screen, make this look good, dashboard, landing page, animation, micro-interaction, transition."
allowed-tools: Bash(agents browser*), Bash(agents computer*), Bash(bun*), Read, Write
user-invocable: true
---

# design:prototype — screens and interactive flows

Produce or refine a screen, page, component, or clickable multi-screen flow as
**self-contained HTML** you can open offline and hand to an engineer as a real starting
point — not a picture of a UI. Covers landing pages, app screens, dashboards, forms,
marketing pages, resumes, one-pagers, and the navigable prototypes that link them
together, plus redesigning any of the above from a screenshot and adding motion to any
of the above.

## Load design-core first

Read [`design-core.md`](../design/design-core.md). Everything here inherits its
hierarchy, spacing, type, color, accessibility (contrast + colorblind-safe), brand-probe,
the refinement preflight (§10), precise copy, and mandatory render/critique verification.

## When to use (vs neighbors)

- A screen, several linked screens, a redesign, or motion on any of those → **prototype**
  (this).
- Reusable tokens/components as a system, not a screen → **`design:system`**.
- A standalone graphic, not something the user interacts with → **`design:graphics`**.
- Judging an existing screen against a rubric, not building → **`design:critique`**.

## The loop

1. **Scope the job.** One screen, or several the user should click between? For a
   multi-screen flow, name every screen and its outgoing transitions — which button
   goes where, one primary action per screen. If the brief is vague, ask for the two or
   three core paths before building.
2. **New, or refining something that exists?**
   - **New:** brand-probe (design-core §4) and skin to the target's tokens, or the
     house fallback.
   - **Refining an existing screen or flow:** run the preflight (design-core §10) —
     open the live screen(s) with `browser`/`computer`, inspect the real states
     (hover/focus, validation, loading, empty, error, success), note responsive
     breakpoints and any existing motion — then follow [`redesign.md`](./redesign.md):
     audit, draw the BEFORE diagram, propose 2-3 distinct AFTER options, fill the
     comparison table, then **stop** and wait for the user's pick before implementing.
3. **Structure before style.** Lay out hierarchy and grid first: focal point, sections,
   spacing scale (the target's own, or design-core's default when none exists).
   Semantic HTML, real selectable text.
4. **Build each screen.** One `.html` per screen; states (hover / focus / disabled)
   with visible focus rings; responsive at a couple of breakpoints. For a multi-screen
   flow: a shared `_shared.css` holding tokens (screens never hard-code a value that
   belongs there), every nav link a real `<a href="screen-name.html">` — no JS router —
   and an `index.html` entry point.
5. **Motion, if the job calls for it.** A hover/press state, entrance sequence, loading
   indicator, or animated transition between screens → follow [`motion.md`](./motion.md)
   beside this file for the CSS/keyframe discipline and the mandatory
   `prefers-reduced-motion` guard.
6. **Verify** (design-core §9): render, screenshot every distinct screen (both themes if
   the design supports light/dark), click through every declared nav path, run the
   checklist, fix, re-render.

## Output & delivery

- **One screen:** a self-contained `.html` (inline CSS, no CDN) at
  `"$ROOT/.agents/design/<slug>.html"`. Opens offline. Keyless.
- **A flow:** a folder at `"$ROOT/.agents/design/proto-<slug>/"` containing
  `_shared.css`, one `<screen-name>.html` per screen, and `index.html`.
- Show the result via `agents browser show` on the user's interactive host (see the
  `browser` skill) — do not hardcode `open`/`xdg-open` or a `/tmp`/`~/Downloads` default.
  Show the screenshots, not a description.

## Mode checklist (on top of design-core)

- [ ] One clear primary action per screen; obvious focal point.
- [ ] Real semantic HTML and selectable text, not a mock image.
- [ ] Responsive at 2 or more breakpoints; visible focus states.
- [ ] Contrast at least AA; nothing conveyed by color alone.
- [ ] Skinned to brand tokens if found, else a tasteful house fallback — or, when
      refining, the existing screen's actual tokens carried forward.
- [ ] Multi-screen: every nav link a real `<a href>`, none dead or `#`; `_shared.css`
      holds tokens; `index.html` present.
- [ ] Refining an existing screen: preflight run (design-core §10), BEFORE diagram
      drawn, 2-3 AFTER options presented, stopped for the user's pick before building.
- [ ] Motion present: `prefers-reduced-motion` guarded; final resting state legible.
- [ ] Rendered, screenshotted, clicked through, and critiqued before "done".
