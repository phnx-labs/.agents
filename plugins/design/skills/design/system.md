# design:system — token scales, component specs, brand identity, and the live preview

Produce a design system as two artifacts: a `DESIGN.md` documenting every token
scale and component spec, and a self-contained HTML **token-preview page** that
renders the palette, type ramp, spacing scale, and core components live so the
system is visible and testable, not merely described. When the job covers brand
identity — voice, positioning, anti-tells — this mode also produces `BRAND.md`,
the layer upstream of `DESIGN.md`. Keyless and offline.

## Load design-core first

Read `design-core.md`. Everything here inherits its hierarchy, spacing, type,
color, accessibility (contrast + colorblind-safe), brand-probe, live-inspiration,
anti-tells catalog, precise copy, and mandatory render/critique verification.

## When to use (vs neighbors)

- Reusable tokens and components as a system → **system** (this).
- Brand identity — voice, positioning, anti-tells, `BRAND.md` → **system** (this);
  there is no separate `brand` mode. Brand is the identity layer *of* the system.
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
   and cards (border, padding, shadow).
4. **Write `BRAND.md` when the request covers brand definition** — a new
   product, a rebrand, or drift ("this design feels off" and the cause is the
   brand file, not the render). See **Brand identity** below for the file spec.
5. **Render the preview.** One self-contained HTML file — swatches for every color
   token, the type ramp with a real sentence at each size, the spacing scale as
   labeled blocks, and the three core components rendered live.
6. **Verify** (design-core §9): render, screenshot, run the contrast check on every
   text-on-background pair (state the ratio), check against the anti-tells
   catalog (design-core §6), fix failures, re-render.

## Brand identity (`BRAND.md`)

`BRAND.md` is a self-contained, plain-text brand identity: *who the product is*,
so `DESIGN.md` has something to derive from. The intended reader is an LLM doing
design work — it lets every later render feel like the brand without re-explaining
it each session. It lives at the repo root, has three parts, and cross-references
`DESIGN.md` via `{brand.palette.accent}`-style token paths:

1. **YAML frontmatter** — machine-readable identity tokens:

   ```yaml
   ---
   version: alpha
   name: "Product Name"
   tagline: "One accurate line, not a slogan."
   voice: [direct, terminal-fluent, low-decoration, opinionated]
   audience: [who this is for, concretely]
   palette:
     background: "#0a0908"
     text: "#ebe6da"
     accent: "#5fff8f"
   typography:
     display: { family: "...", weights: [500, 700] }
     body:    { family: "...", weights: [400, 500, 700] }
   references:
     positive: ["what we look toward, and why"]
     negative: ["what we look away from, and why"]
   avoid: ["specific anti-tells this brand rejects — see design-core §6"]
   ---
   ```

2. **Narrative body** — required sections, each concrete rather than aspirational:
   - **Who we are.** One declarative paragraph: what the product is, who it's
     for, what it does. Not "we strive to..."; not "on a mission to...".
   - **Voice.** Concrete adjectives, each with a do-say / don't-say pair.
   - **What we are not.** The negative space — positioning, copy, or aesthetic
     moves that are off-limits.
   - **References.** Positive rooms to be in, negative rooms to leave — pull
     these from a live-inspiration pass (design-core §5), not memory.
   - **Anti-tells.** The brand-scoped subset of design-core §6: which specific
     tells this brand rejects, and why, e.g. "no italic serif display — reads
     as Claude.ai-adjacent; this brand is mono-first."

3. **Interview, don't assume.** Draft `BRAND.md` by running through the body
   sections with the user — push for the negative space ("what are we *not*?")
   and named references, not "make it nice." Pick frontmatter tokens that are
   derivable from the answers, not from your own taste.

**`BRAND.md` vs `DESIGN.md`:** `BRAND.md` is identity, voice, and *why* the
palette is what it is; `DESIGN.md` is the tokens, the component specs, and the
*how*. If you're documenting "primary button radius is 8px" in `BRAND.md`, that
belongs in `DESIGN.md`. If you're documenting "we sound direct, not whimsical" in
`DESIGN.md`, that belongs in `BRAND.md`. `DESIGN.md` token values may reference
`BRAND.md` tokens; `BRAND.md` never references `DESIGN.md`.

## Output & delivery

- **`DESIGN.md`** (and **`BRAND.md`** when brand definition was requested) at
  `"$ROOT/.agents/design/"` or the repo root, depending on where existing docs
  live.
- **One self-contained `<slug>-preview.html`** (inline CSS, no CDN) at
  `"$ROOT/.agents/design/<slug>-preview.html"`. Opens offline. Keyless.
- Open the preview on the user's machine; show the screenshot with contrast ratios
  stated for each text token. Do not declare done until the preview is visible.

## Mode checklist (on top of design-core)

- [ ] Brand-probe cascade run; seed hues documented with source.
- [ ] All five scales defined: color ramp + semantic aliases, type, spacing, radius, shadow.
- [ ] `DESIGN.md` covers every token and all three component specs (button, input, card).
- [ ] `BRAND.md` written only when brand definition was explicitly requested, with all
      five body sections (who we are, voice, what we are not, references, anti-tells).
- [ ] Preview page renders palette swatches, type ramp, spacing scale, and live components.
- [ ] Contrast ratio stated (not guessed) for every text-on-background token pair; all meet AA.
- [ ] Checked against the anti-tells catalog (design-core §6); three-or-more-present fixed.
- [ ] Rendered, screenshotted, and critiqued before "done".
