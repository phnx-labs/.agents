# design:motion — UI motion and micro-interactions as CSS/HTML animation

Produce **self-contained HTML/CSS** that animates a UI element, hover or press state,
entrance sequence, loading indicator, or animated SVG — keyless and offline. The output
is real, runnable code, not a description of motion. Full video composition (Remotion)
is a follow-on requiring bun, ffmpeg, and Chromium; do not block on it.

## Load design-core first

Read `design-core.md`. Everything here inherits its hierarchy, spacing, type, color,
accessibility (contrast + colorblind-safe), brand-probe, precise copy, and mandatory
render/critique verification — including the `prefers-reduced-motion` rule.

## When to use (vs neighbors)

- Something moves, transitions, or animates → **motion** (this).
- A static screen or component, no animation → **`interface`**.
- Clickable flow across multiple screens → **`prototype`**.
- A chart, diagram, or data graphic → **`diagram`** / **`dataviz`**.

## The loop

1. **Define the motion precisely.** Name what moves (element, property), the trigger
   (hover, load, scroll, click), easing curve, and duration. Motion should clarify
   state or hierarchy — it is not decoration.
2. **Brand-probe** (design-core §4): skin colors, type, and spacing to the target's tokens
   or the house fallback before adding motion on top.
3. **Implement in CSS/HTML.** Use `@keyframes` for multi-step animations and `transition`
   for state changes. Keep durations short (100–300 ms for micro-interactions; up to 600 ms
   for entrances). Prefer `transform` and `opacity` — they stay on the compositor.
4. **Guard `prefers-reduced-motion: reduce`.** Every animated rule must have a
   `@media (prefers-reduced-motion: reduce)` block that sets `animation: none` and
   `transition: none`. No motion reaches a user who has opted out.
5. **Verify.** A headless screenshot captures one frame, not motion. Bake the meaningful
   final state (the post-animation resting position) so the screenshot is legible and
   passes the critique checklist. Open in a browser to observe the animation live.

## Output & delivery

- **One self-contained `.html`** (inline CSS, no CDN) at
  `"$ROOT/.agents/design/<slug>.html"` or `/tmp/<slug>.html`. Opens offline. Keyless.
- Screenshot the final resting state and show it; note in the caption that the live
  animation requires a browser. Open the file on the user's machine (see `SKILL.md` delivery).
- For animated SVG, inline the `<svg>` in the HTML and drive it with CSS `@keyframes`
  or SMIL `<animate>` — not JavaScript when CSS suffices.
- Full video (Remotion compositions): flag as NEEDS-SETUP and defer to a follow-on session.

## Mode checklist

- [ ] Motion defined precisely: what moves, trigger, easing, duration.
- [ ] Motion serves function (state, hierarchy, feedback) — not applied for novelty.
- [ ] `@media (prefers-reduced-motion: reduce)` block present; animation/transition zeroed.
- [ ] `transform` and `opacity` used over layout-triggering properties where possible.
- [ ] Durations proportional: micro-interactions ≤ 300 ms; entrances ≤ 600 ms.
- [ ] Final resting state is meaningful and passes the design-core critique checklist.
- [ ] Rendered, screenshotted (final state), and reviewed in a browser before "done".
