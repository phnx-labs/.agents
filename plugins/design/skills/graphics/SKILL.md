---
name: graphics
description: "Create or refine a standalone graphic asset, vector-first: OG/social card, logo, icon set, favicon, poster, flyer, invite, resume, or any other self-contained deliverable. Edits real vector/HTML wherever the content is typographic, geometric, or structural; degrades gracefully to a spec plus placeholder for genuinely photographic or painterly output. Triggers on: logo, icon, favicon, OG image, social card, poster, flyer, brand mark, vector asset, refine this icon/logo."
allowed-tools: Bash(agents browser*), Bash(bun*), Read, Write
user-invocable: true
---

# design:graphics — standalone graphic assets, vector-first

Produce or refine a standalone graphic — OG/social card, logo, icon set, favicon, poster,
flyer, invite, resume, or any other self-contained deliverable — as editable
vector (SVG/HTML) wherever the content is typographic, geometric, or structural.
Reserve raster generation for genuinely photographic or painterly output, and
degrade gracefully when no image backend is configured.

## Load design-core first

Read [`design-core.md`](../design/design-core.md). Everything here inherits its
hierarchy, spacing, type, color, accessibility (contrast + colorblind-safe),
brand-probe, the refinement preflight (§10), precise copy, and mandatory
render/critique verification. Pay particular attention to §8 (graceful raster):
that rule is in practice here, not just in principle.

## When to use (vs neighbors)

- A standalone graphic (card, logo, icon, poster, flyer, resume), new or refined
  → **graphics** (this).
- A screen, page, or component the user interacts with → **`design:prototype`**.
- A reusable token/component library → **`design:system`**.
- Judging an existing graphic against a rubric, not building → **`design:critique`**.

## The loop

1. **Classify the asset.** Is the deliverable typographic, geometric, or structural
   (OG card, logo, icon, poster, flyer, resume)? Vector path. Is it genuinely
   photographic or painterly (a photo illustration, a painterly cover)? Raster path.
   When in doubt, the vector path is correct.

2. **Refining an existing asset:** run the preflight (design-core §10) — open the
   current file (or the live rendered asset) visually, not just as markup or a
   filename, and write down what it actually does before changing anything. Carry
   its established palette, type, and construction forward; propose a new default
   only where nothing established exists to refine.

3. **Vector path (default, keyless).**
   - OG/social cards: self-contained HTML rendered to PNG via headless screenshot.
   - Logos: SVG, using real `<text>` or geometric shapes; no raster embed.
   - Icon/favicon sets: master SVG + exported sizes (16, 32, 180, 192 px) via the
     same headless render pipeline.
   - Posters, flyers, invites, resumes: self-contained HTML rendered to PDF or
     print-size PNG.
   - Brand-probe (design-core §4) before rendering; skin to the target's tokens or
     the house fallback.

4. **Raster path (optional, degrades).**
   - If a configured image backend is available (`image` or `higgsfield` skill),
     delegate to it with a complete prompt.
   - If no backend is configured, do not hard-fail. Emit all three of the following
     and exit successfully (design-core §8):
       (a) An editable SVG/HTML placeholder at the correct dimensions, with real
           typographic and layout structure so the result is immediately useful.
       (b) A complete generation spec: subject, style, palette, aspect ratio,
           mood/lighting, negative prompts.
       (c) One line on how to enable a backend (e.g., "configure the `image` skill
           to generate this with a model"). Never claim a raster was generated when
           only the placeholder and spec were produced.

5. **Verify** (design-core §9): render the output, screenshot it, run the critique
   checklist, fix what fails, re-render. Done only when you have looked at it.

## Output & delivery

- **Vector deliverables:** one `.svg` or one self-contained `.html` (inline CSS,
  no CDN) at `"$ROOT/.agents/design/<slug>.svg"` or `"$ROOT/.agents/design/<slug>.html"`.
  Opens offline. Keyless.
- **Exported sizes** (icons/favicons): write each PNG to
  `"$ROOT/.agents/design/<slug>-<size>.png"` alongside the master SVG.
- **Raster deliverables:** the backend's output file, or the placeholder SVG/HTML
  plus the generation spec written to `"$ROOT/.agents/design/<slug>-spec.md"`.
- Show the result via `agents browser show` on the user's interactive host (see the
  `browser` skill) — do not hardcode `open`/`xdg-open` or a `/tmp`/`~/Downloads`
  default. Show the screenshot; do not describe it.

## Mode checklist

- [ ] Asset classified as vector or raster before any rendering begins.
- [ ] When refining, the preflight (design-core §10) ran and the existing construction
      was carried forward, not replaced by a fresh default.
- [ ] Vector path taken for all typographic, geometric, or structural deliverables.
- [ ] Raster path: backend used if configured, placeholder + spec emitted if not.
- [ ] Placeholder (if emitted) is editable and at the correct dimensions, not a blank box.
- [ ] Generation spec (if emitted) is complete: subject, style, palette, aspect ratio,
      negative prompts.
- [ ] Brand-probe completed; output skinned to tokens or a tasteful house fallback.
- [ ] Contrast at least AA; nothing conveyed by color alone.
- [ ] Copy is precise and concrete — headlines state, not sell.
- [ ] Rendered, screenshotted, and critiqued against the design-core checklist before "done".
