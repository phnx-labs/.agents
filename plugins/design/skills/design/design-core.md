# design-core — the taste every mode inherits

Every `design` mode loads this first. It is the difference between "generated something"
and "designed something", and it applies equally to a founder's landing page and an
engineer's architecture diagram. All of it is keyless and offline: none of this needs an
API key or a paid backend.

## 1 · The offline-first doctrine

The primary substrate is **self-contained HTML/SVG** — the same engine as the
`artifacts` skill (inline CSS/SVG, no CDN, opens offline by double-click). Most design jobs
have a better answer in editable vector/HTML than in a generated raster: pages, UIs,
prototypes, diagrams, dataviz, decks, OG cards, logos, icons, posters. Reach for raster
generation only when the deliverable is genuinely photographic or painterly. See
**§8 graceful raster**.

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
  palettes in the `artifacts` skill's `references/diagram-conventions.md`.
- **Focus and motion.** Visible focus rings on interactive elements; honor
  `prefers-reduced-motion`; nothing conveyed by hover alone.
- **Text.** Real, selectable text over text-baked-into-an-image; tap targets at least 44px.

## 4 · Brand-probe (on-brand when a brand exists, tasteful when not)

Before rendering, probe the target for a brand and skin the output in it. Fall through in
order, first hit wins (the same cascade as `artifacts`):

0. **`BRAND.md`** at the repo root — read it directly; it is the authoritative brand
   source (voice, palette, type, positioning, anti-tells). If it exists, use it and
   skip the remaining steps unless you need a specific token not covered there.
1. **Design tokens** — `design-system.css`, `theme.ts/css`, `tokens.json`, a `brand/` dir.
2. **Framework config** — `tailwind.config.*` theme, CSS custom properties.
3. **Brand assets** — logo / favicon / `site.webmanifest` `theme_color`; sample the hues.
4. **Live UI** — a screenshot or a running app; eyedrop the palette.
5. **House fallback** — the dark + light editorial palette, used only when no brand exists.

Brand is a **layer, not a requirement**. Unbranded output must still be tasteful by
default. Brand plugins (rush, prix) skin on top by calling `/design`; never require them.
A full brand identity (voice, palette, type, anti-tells, `BRAND.md`) is defined by the
**`system`** mode, not a separate mode — see `system.md`.

## 5 · Live inspiration, not frozen examples

Before rendering, especially for an unfamiliar domain or when the brand-probe (§4) finds
nothing to skin to, browse for real, **current** inspiration instead of relying on
memorized or hardcoded examples — training-data recall and a frozen example file both go
stale, and stale references are exactly what produces the tells in §6.

1. Use the `browser` skill to open 2-4 real, live sites relevant to the job (the same
   category of product, or named references the user gives) and screenshot them.
2. Look at what you captured before drawing on it: what does it actually do with
   hierarchy, density, type, color — not what you assume it does from the name.
3. Borrow specific, nameable choices ("dense left-aligned nav with mono labels, flat
   buttons, no drop-shadow"), never the whole composition. Never copy a screenshot's
   layout wholesale — synthesize your own from what several examples do.
4. Treat what you find as a positive AND a negative reference: note what to borrow and
   what to deliberately avoid (an of-the-moment trend that reads as generic).

This replaces keeping a fixed set of example screenshots in the skill itself — those
freeze in time the moment they're written and start training toward whatever was current
then. Live browsing keeps the reference set current for every render.

## 6 · Anti-tells — what makes a design look AI-generated

A design gets flagged as AI-made for one of two reasons: a **trained-corpus signature**
(the model reproduces the same handful of "tasteful indie SaaS" landing pages from its
training data) or a **tagline-factory voice** (copy that reads like the model trying to
sound design-y). Both are diagnosable; check every render against this list before
calling it done, and avoid the combination even when one move alone would be fine.

1. **Italic serif display headlines** (Tiempos / Newsreader / GT Sectra Italic, often one
   italicized accent word). Now the default "tasteful AI tool" look. Use a heavy sans
   display (NB International, Söhne, GT America, Geist) at 700/800, or all-mono display
   (JetBrains Mono, Berkeley Mono, IBM Plex Mono) instead.
2. **Two-tone "muted gray + bright white" headlines** — first line bright, next line
   `text-zinc-500`, same font and weight. Use a single tone; get hierarchy from size or
   weight, or a kicker label / accent word / underline rule instead.
3. **Italic mid-sentence accent words** ("You stay the *architect*."). Bold the word, set
   it in mono in the accent color, or don't emphasize at all.
4. **Italic asides under list items** ("— because windows you cannot see are windows you
   cannot trust."). Delete the aside, or rewrite it as a concrete sentence with a verb
   and a noun.
5. **Latin / typographic section markers** (`§ № I · the editor, reconsidered`). Drop
   them, or use the most boring label possible ("01 / Features", "Workflow").
6. **Sodium amber / warm cream on warm off-black** (`#ebe6da` on `#0d0c0b` with a
   `#ffb347` accent). Pick a CRT phosphor green, a desaturated chartreuse, a real brand
   color, or commit to pure achromatic instead.
7. **"Made on a Sunday on cold brew" colophons.** Say something concrete (a real
   changelog timestamp, an actual build number, a one-sentence positioning statement) or
   say nothing.
8. **The strikethrough metaphor headline** ("Your editor is not ~~a text box~~. It is a
   *foreman*."). Lead with the actual product claim, in plain language.
9. **The lucide-react feature-card grid** (3×3 or 2×3 cards, one icon, a short title, a
   sentence). Show the product instead — a diff hunk, real terminal output, an actual
   screenshot — or use a numbered text list / comparison table.
10. **"Built for X. Trusted by Y." sequencing** — hero, then a grayscale logo row (often
    invented), then features. If there are no real logos, don't fake the row; use one
    specific, credible testimonial or skip social proof on a v0.x product.
11. **Gradient accent buttons + drop-shadow glow halos.** Flat color, square or 4-6px
    corners, no glow. Or a fully outlined button.
12. **Em-dash-heavy prose** — clauses separated by em-dashes every other sentence. Use
    periods and short sentences; keep at most one em-dash per paragraph (§7).

**How to use this list.** Check every render against it. For any tell that's present,
decide deliberately — keep it with a reason, or replace it with the alternative. If
three or more are present together, the design reads as AI-made regardless of how nice
it looks individually, even though no single move is forbidden in isolation. The goal is
not to avoid every move an LLM ever makes — it's to avoid the recognizable *combination*.
This catalog is meant to evolve: when a render is called out for a new tell, add it here
so every mode inherits the fix.

## 7 · Precise, non-marketing copy

All copy in a design follows the `code-quality` "write prose precisely" rule: name the
concrete thing, drop the marketing register (no slogans, no "Critically:" drama, no filler
adjectives like "seamless" or "powerful"), and cap em-dashes at one per paragraph. A
headline states what the thing is or does; it is not a tagline. A shareable marketing asset
may carry one accurate punchy line, but the body copy stays plain.

## 8 · Graceful raster (never hard-fail)

When a job needs true raster:

1. **Prefer vector first.** A logo, icon, OG card, or poster is usually better as SVG/HTML.
   Render it that way and you need no backend at all.
2. **Use a backend if configured.** If an image backend is available (a configured `image`
   or `higgsfield` skill, for example), delegate to it.
3. **Degrade, do not fail.** If no backend is configured, emit three things and exit
   successfully: (a) an editable SVG/HTML placeholder at the correct dimensions; (b) a
   complete generation spec (subject, style, palette, aspect ratio, negative prompts);
   (c) one line on how to enable a backend. The user is never left staring at an error.

## 9 · Verification is mandatory (see it, then critique it)

No visual mode is done until you have **rendered it, looked at it, and critiqued it**:

1. Render the HTML/SVG (a headless screenshot, or open it in a browser).
2. Look at the screenshot against the stated intent.
3. Run the critique checklist below, and the anti-tells list (§6); fix what fails;
   re-render. Repeat until both pass.

For the mechanical half of that pass, use the two scripts in the `critique` mode's
`scripts/` directory instead of judging by eye: `bun scripts/check-contrast.ts`
computes the WCAG ratios §3 demands (never guess a ratio), and
`bun scripts/check-tells.ts <file.html>` flags the §6 tells, §1 offline violations,
and §3 color-only glyphs that are detectable from markup. The screenshot critique
stays mandatory — the scripts cover only what markup can prove.

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
10. **Anti-tells (§6)** — fewer than three tells present in combination?
11. **Intent** — does it actually do the job the user asked for?
