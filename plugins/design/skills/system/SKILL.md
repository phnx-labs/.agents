---
name: system
description: "Create or refine a design system: token scales, component specs, and brand identity. Produces a DESIGN.md documenting every token and component, a self-contained live token-preview page, and — when brand definition is in scope — a BRAND.md. Refines an existing system's actual tokens and components before proposing new ones. Triggers on: design system, design tokens, component library, DESIGN.md, brand identity, BRAND.md, rebrand, style guide."
allowed-tools: Bash(agents browser*), Bash(agents computer*), Bash(bun*), Read, Write
user-invocable: true
---

# design:system — token scales, component specs, brand identity, and the live preview

Produce a design system as two artifacts: a `DESIGN.md` documenting every token
scale and component spec, and a self-contained HTML **token-preview page** that
renders the palette, type ramp, spacing scale, and core components live so the
system is visible and testable, not merely described. When the job covers brand
identity — voice, positioning, anti-tells — this skill also produces `BRAND.md`,
the layer upstream of `DESIGN.md`. Keyless and offline.

## Load design-core first

Read [`design-core.md`](../design/design-core.md). Everything here inherits its
hierarchy, spacing, type, color, accessibility (contrast + colorblind-safe),
brand-probe, live-inspiration, anti-tells catalog, precise copy, the refinement
preflight (§10), and mandatory render/critique verification.

## When to use (vs neighbors)

- Reusable tokens and components as a system, new or refined → **system** (this).
- Brand identity — voice, positioning, anti-tells, `BRAND.md` → **system** (this);
  there is no separate `brand` skill. Brand is the identity layer *of* the system.
- A single screen or several linked screens built from a system → **`design:prototype`**.
- A standalone graphic (logo, icon, OG card, poster) → **`design:graphics`**.
- Judging an existing screen against a rubric, not building → **`design:critique`**.

## The loop

1. **Preflight (design-core §10).** Read every source the brand-probe (§4) finds —
   `BRAND.md`, `DESIGN.md`, tokens, component source — not just the first match; open
   the actual guidelines page, Storybook, or living style guide visually with `browser`
   (or `computer` for a native app); inspect representative live components in their
   real states (hover/focus, disabled, error), not a single screenshot. Write down what
   you observed before drafting any proposal.
2. **Decide: refine or define.** If a system already exists, the job is refining its
   actual scales and components — carry its real values forward, do not replace them
   with a fresh default set. Only where the preflight finds nothing does step 3's
   defaults apply.
3. **Define the scales** (only where none already exist to reuse):
   - **Color ramp**: a 10-step neutral (50–950) and a 10-step accent; semantic
     aliases (`--color-bg`, `--color-surface`, `--color-text-primary`,
     `--color-text-secondary`, `--color-border`, `--color-accent`,
     `--color-success`, `--color-warning`, `--color-error`).
   - **Type scale**: `xs / sm / base / lg / xl / 2xl / 3xl / 4xl`; one or two
     families; body line-height 1.5; heading line-height 1.2.
   - **Spacing scale**: `4 / 8 / 12 / 16 / 24 / 32 / 48` px.
   - **Radius**: `sm (2px) / md (6px) / lg (12px) / full (9999px)`.
   - **Shadow**: two levels (card + raised); no more.
4. **Document as `DESIGN.md`.** Token table per scale — the existing values when
   refining, the defaults from step 3 only when none existed — then component specs
   for buttons (sizes + variants), inputs (states: default / focus / error / disabled),
   and cards (border, padding, shadow).
5. **Write `BRAND.md` when the request covers brand definition** — a new
   product, a rebrand, or drift ("this design feels off" and the cause is the
   brand file, not the render). See **Brand identity** below for the file spec.
6. **Render the preview.** One self-contained HTML file — swatches for every color
   token, the type ramp with a real sentence at each size, the spacing scale as
   labeled blocks, and the three core components rendered live.
7. **Verify** (design-core §9): render, screenshot, run
   `bun ../critique/scripts/check-contrast.ts` on every text-on-background pair
   (state the ratio), check against the anti-tells catalog (design-core §6, mindful
   of its refinement note when an established convention exists), fix failures,
   re-render.

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
- Show the preview via `agents browser show` on the user's interactive host (see
  the `browser` skill) — do not hardcode `open`/`xdg-open` or a `/tmp`/`~/Downloads`
  default. Include the contrast ratios stated for each text token. Do not declare
  done until the preview is visible.

## Mode checklist (on top of design-core)

- [ ] Preflight run (design-core §10): existing guidelines/tokens/components opened
      visually, representative live states inspected, observations written down
      before any proposal.
- [ ] Existing scales and components carried forward when a system already exists;
      step-3 defaults used only where the preflight found nothing to reuse.
- [ ] `DESIGN.md` covers every token and all three component specs (button, input, card).
- [ ] `BRAND.md` written only when brand definition was explicitly requested, with all
      five body sections (who we are, voice, what we are not, references, anti-tells).
- [ ] Preview page renders palette swatches, type ramp, spacing scale, and live components.
- [ ] Contrast ratio stated (not guessed) for every text-on-background token pair; all meet AA.
- [ ] Checked against the anti-tells catalog (design-core §6); established conventions
      deferred to; three-or-more-present fixed otherwise.
- [ ] Rendered, screenshotted, and critiqued before "done".
