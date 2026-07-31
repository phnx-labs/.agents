# design-core — the taste every mode inherits

Every `design` mode loads this first. It is the difference between "generated something"
and "designed something", and it applies equally to a founder's landing page and an
engineer's architecture diagram. All of it is keyless and offline: none of this needs an
API key or a paid backend.

## 1 · The offline-first doctrine

The primary substrate is **self-contained HTML/SVG** — the same engine as `plan-render`
and `visualize` (inline CSS/SVG, no CDN, opens offline by double-click). Most design jobs
have a better answer in editable vector/HTML than in a generated raster: pages, UIs,
prototypes, diagrams, dataviz, decks, OG cards, logos, icons, posters. Reach for raster
generation only when the deliverable is genuinely photographic or painterly. See
**§6 graceful raster**.

## 2 · Visual quality (the non-negotiables)

- **Hierarchy.** One clear focal point per view; size, weight, and space encode importance.
  If everything is bold, nothing is.
- **Spatial rhythm.** A consistent spacing scale (4 / 8 / 12 / 16 / 24 / 32 / 48). Align to
  a grid. Whitespace is structure, not leftover.
- **Type scale.** A small set of sizes with deliberate ratios; one or two families;
  generous body line-height (~1.5). Never more than a couple of weights.
- **Color.** A restrained palette: one accent, a neutral ramp, semantic states. Color
  carries meaning, not decoration.
- **Restraint.** Remove until it breaks, then add back one step. No gradient-on-gradient,
  no drop-shadow pileup, no chartjunk.

## 3 · Accessibility, baked in (never an afterthought)

- **Contrast.** Body text meets WCAG AA (4.5:1; 3:1 for large text). State the ratio; do
  not guess it.
- **Colorblind-safe.** Never encode meaning by red-vs-green alone; pair color with shape,
  label, or position. Categorical uses Okabe-Ito; sequential uses Viridis. Reuse the
  palettes in `../../skills/plan-render/diagram-conventions.md`.
- **Focus and motion.** Visible focus rings on interactive elements; honor
  `prefers-reduced-motion`; nothing conveyed by hover alone.
- **Text.** Real, selectable text over text-baked-into-an-image; tap targets at least 44px.

## 4 · Brand-probe (on-brand when a brand exists, tasteful when not)

Before rendering, probe the target for a brand and skin the output in it. Fall through in
order, first hit wins (the same cascade as `plan-render`):

1. **Design tokens** — `design-system.css`, `theme.ts/css`, `tokens.json`, a `brand/` dir.
2. **Framework config** — `tailwind.config.*` theme, CSS custom properties.
3. **Brand assets** — logo / favicon / `site.webmanifest` `theme_color`; sample the hues.
4. **Live UI** — a screenshot or a running app; eyedrop the palette.
5. **House fallback** — the dark + light editorial palette, used only when no brand exists.

Brand is a **layer, not a requirement**. Unbranded output must still be tasteful by
default. Brand plugins (rush, prix) skin on top by calling `/design`; never require them.

## 5 · Precise, non-marketing copy

All copy in a design follows the `code-quality` "write prose precisely" rule: name the
concrete thing, drop the marketing register (no slogans, no "Critically:" drama, no filler
adjectives like "seamless" or "powerful"), and cap em-dashes at one per paragraph. A
headline states what the thing is or does; it is not a tagline. A shareable marketing asset
may carry one accurate punchy line, but the body copy stays plain.

## 6 · Graceful raster (never hard-fail)

When a job needs true raster:

1. **Prefer vector first.** A logo, icon, OG card, or poster is usually better as SVG/HTML.
   Render it that way and you need no backend at all.
2. **Use a backend if configured.** If an image backend is available (a configured `image`
   or `higgsfield` skill, for example), delegate to it.
3. **Degrade, do not fail.** If no backend is configured, emit three things and exit
   successfully: (a) an editable SVG/HTML placeholder at the correct dimensions; (b) a
   complete generation spec (subject, style, palette, aspect ratio, negative prompts);
   (c) one line on how to enable a backend. The user is never left staring at an error.

## 7 · Verification is mandatory (see it, then critique it)

No visual mode is done until you have **rendered it, looked at it, and critiqued it**:

1. Render the HTML/SVG (a headless screenshot, or open it in a browser).
2. Look at the screenshot against the stated intent.
3. Run the critique checklist below; fix what fails; re-render. Repeat until it passes.

## The critique checklist (also the standalone `critique` mode)

Score each. Anything failing is a fix, not a nit.

1. **Focal point** — is there one clear thing the eye lands on first?
2. **Hierarchy** — do size, weight, and space match importance?
3. **Alignment and rhythm** — consistent grid and spacing scale?
4. **Type** — readable sizes, sane line-height, at most two families and weights?
5. **Color** — restrained palette, meaning-carrying, on-brand or tastefully neutral?
6. **Contrast (a11y)** — body text at least 4.5:1, and not color-alone for meaning?
7. **Copy** — precise, concrete, non-marketing; the headline states rather than sells?
8. **Density** — enough whitespace; nothing cramped or chartjunky?
9. **Consistency** — components and tokens reused, not reinvented per view?
10. **Intent** — does it actually do the job the user asked for?
