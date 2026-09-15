# design:prototype — motion and micro-interactions

For a hover or press state, entrance sequence, loading indicator, animated SVG, or
transition between screens. Load this after [`design-core.md`](../design/design-core.md)
and `SKILL.md`; it is a layer on top of a screen or flow you're already building or
refining, not a separate deliverable.

Motion is **self-contained HTML/CSS** — keyless and offline. The output is real,
runnable code, not a description of motion. Full video composition (Remotion) is a
follow-on requiring bun, ffmpeg, and Chromium; do not block on it.

## The loop

1. **Define the motion precisely.** Name what moves (element, property), the trigger
   (hover, load, scroll, click), easing curve, and duration. Motion should clarify
   state or hierarchy — it is not decoration.
2. **Refining existing motion?** Run the preflight (design-core §10): watch the real
   transition live (`browser`) rather than guessing its timing from the CSS alone —
   easing and duration are often tuned by eye, not documented. When a transition's
   timing, easing, or scroll behavior materially matters to the job, record a short,
   bounded interaction video and review it before changing anything; defer the capture
   mechanics to the `browser`/`computer`/`artifacts` skills.
3. **Implement in CSS/HTML.** Use `@keyframes` for multi-step animations and
   `transition` for state changes. Keep durations short (100–300 ms for
   micro-interactions; up to 600 ms for entrances). Prefer `transform` and `opacity` —
   they stay on the compositor.
4. **Guard `prefers-reduced-motion: reduce`.** Every animated rule must have a
   `@media (prefers-reduced-motion: reduce)` block that sets `animation: none` and
   `transition: none`. No motion reaches a user who has opted out.
5. **Verify.** A headless screenshot captures one frame, not motion. Bake the
   meaningful final state (the post-animation resting position) so the screenshot is
   legible and passes the critique checklist. Open in a browser to observe the
   animation live.

## Notes

- For animated SVG, inline the `<svg>` in the HTML and drive it with CSS `@keyframes`
  or SMIL `<animate>` — not JavaScript when CSS suffices.
- Full video (Remotion compositions): flag as NEEDS-SETUP and defer to a follow-on
  session; it is out of scope for this skill.
- Screenshot the final resting state and show it; note in the caption that the live
  animation requires a browser.

## Checklist

- [ ] Motion defined precisely: what moves, trigger, easing, duration.
- [ ] Motion serves function (state, hierarchy, feedback) — not applied for novelty.
- [ ] `@media (prefers-reduced-motion: reduce)` block present; animation/transition zeroed.
- [ ] `transform` and `opacity` used over layout-triggering properties where possible.
- [ ] Durations proportional: micro-interactions ≤ 300 ms; entrances ≤ 600 ms.
- [ ] Refining existing motion: watched live, and a bounded video captured when timing
      materially matters.
- [ ] Final resting state is meaningful and passes the design-core critique checklist.
- [ ] Rendered, screenshotted (final state), and reviewed in a browser before "done".
