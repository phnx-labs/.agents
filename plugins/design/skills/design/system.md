# design:system — token scales, component specs, and the live preview

Produce a design system as two artifacts: a `DESIGN.md` documenting every token
scale and component spec, and a self-contained HTML **token-preview page** that
renders the palette, type ramp, spacing scale, and core components live so the
system is visible and testable, not merely described. Keyless and offline.

## Load design-core first

Read `design-core.md`. Everything here inherits its hierarchy, spacing, type,
color, accessibility (contrast + colorblind-safe), brand-probe, precise copy, and
mandatory render/critique verification.

## When to use (vs neighbors)

- Reusable tokens and components as a system → **system** (this).
- A single screen or page built from a system → **`interface`**.
- Several screens the user clicks between → **`prototype`**.
- A diagram or chart, not a UI → **`diagram`** / **`dataviz`**.

## The loop

1. **Brand-probe** (design-core §4): walk the cascade — design tokens, framework
   config, brand assets, live UI. If a brand exists, extract the seed hues and
   naming conventions. If not, derive a tasteful neutral-plus-one-accent set.
2. **Define the scales.** Nail these before touching components:
   - **Color ramp**: a 10-step neutral (50–950) and a 10-step accent; semantic
     aliases (`--color-bg`, `--color-surface`, `--color-text-primary`,
     `--color-text-secondary`, `--color-border`, `--color-accent`,
     `--color-success`, `--color-warning`, `--color-error`).
   - **Type scale**: `xs / sm / base / lg / xl / 2xl / 3xl / 4xl`; one or two
     families; body line-height 1.5; heading line-height 1.2.
   - **Spacing scale**: `4 / 8 / 12 / 16 / 24 / 32 / 48` px.
   - **Radius**: `sm (2px) / md (6px) / lg (12px) / full (9999px)`.
   - **Shadow**: two levels (card + raised); no more.
3. **Document as `DESIGN.md`.** Token table per scale, then component specs for
   buttons (sizes + variants), inputs (states: default / focus / error / disabled),
   and cards (border, padding, shadow). Emit `BRAND.md` (voice, do/don't, logo
   doctrine) only when the request explicitly covers brand definition.
4. **Render the preview.** One self-contained HTML file — swatches for every color
   token, the type ramp with a real sentence at each size, the spacing scale as
   labeled blocks, and the three core components rendered live.
5. **Verify** (design-core §7): render, screenshot, run the contrast check on every
   text-on-background pair (state the ratio), fix failures, re-render.

## Output & delivery

- **`DESIGN.md`** (and optionally `BRAND.md`) at `"$ROOT/.agents/design/"` or the
  repo root, depending on where existing docs live.
- **One self-contained `<slug>-preview.html`** (inline CSS, no CDN) at
  `"$ROOT/.agents/design/<slug>-preview.html"`. Opens offline. Keyless.
- Open the preview on the user's machine; show the screenshot with contrast ratios
  stated for each text token. Do not declare done until the preview is visible.

## Mode checklist (on top of design-core)

- [ ] Brand-probe cascade run; seed hues documented with source.
- [ ] All five scales defined: color ramp + semantic aliases, type, spacing, radius, shadow.
- [ ] `DESIGN.md` covers every token and all three component specs (button, input, card).
- [ ] `BRAND.md` written only when brand definition was explicitly requested.
- [ ] Preview page renders palette swatches, type ramp, spacing scale, and live components.
- [ ] Contrast ratio stated (not guessed) for every text-on-background token pair; all meet AA.
- [ ] Rendered, screenshotted, and critiqued before "done".
