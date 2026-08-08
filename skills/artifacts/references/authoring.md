# Artifact Authoring Contract

## Frontmatter

Only `kind` and `title` are required. `template` is inferred from `kind`, and
provenance (project, repository, branch, harness, agent, human, host, session,
date) auto-fills at render time from the Git checkout and agent environment —
declared values always win. `artifacts new` scaffolds the full shape:

```yaml
---
kind: plan
title: Concrete artifact title
summary: One precise sentence
header: Phoenix Labs / Engineering
footer: Internal planning artifact
project: artifacts-cli
context: rendering workflow
repository: phnx-labs/artifacts-cli
branch: feat/example
tracking: "#12"
status: draft
harness: codex
agent: gpt-5
human: Ada Lovelace
host: yosemite-s1
session: fcd64597
date: "2026-08-03"
facts:
  - One Markdown source
links:
  - https://github.com/phnx-labs/artifacts-cli/issues/12
  - https://github.com/phnx-labs/artifacts-cli/pull/34
  - url: https://linear.app/phnx/issue/RUSH-2119/title
    label: RUSH-2119
assets: []
---
```

### Work links (`links`)

`links` is multipurpose — tickets, PRs, issues, design docs from any tracker.
Each entry is either a plain `https://` URL or `{url, label?}`. When `label` is
omitted, the chip text is derived:

| URL shape | Chip text |
| --- | --- |
| GitHub `…/pull/N` | `PR #N` |
| GitHub `…/issues/N` | `#N` |
| Jira `…/browse/KEY-N` | `KEY-N` |
| Path containing `KEY-N` (Linear, etc.) | `KEY-N` |
| Explicit `label` | that label |
| Otherwise | last path segment or host |

Seed every related URL you already have when authoring. If you create tickets
during the session, append them to `links` and re-render before presenting. Also
list the same URLs under `## Tracking` as Markdown links so the body is readable
without relying on the chip row. Keep optional short ids in `tracking`; do not
add purpose-specific fields (`tickets:`, `prs:`) beside `links`.

Required body sections come from the kind's template (`artifacts template <kind>`
prints it). Keep them instead of inventing a second schema.

## Design Layout

Keep one `DESIGN.md`; do not introduce a competing theme file. Its `layout`
block accepts pixel numbers for `contentWidth`, `pagePadding`,
`mobilePagePadding`, `heroTop`, `heroBottom`, `sectionSpacing`, `figureSpacing`,
`panelPadding`, `footerSpacing`, and `printMargin`. Each `themes.light` /
`themes.dark` palette accepts `background`, `surface`, `surfaceAlt`, `line`,
`text`, `muted`, `accent`, `accentAlt`, `warn`, and `danger` hex colors.
These project-wide values
feed HTML, document PDF, and poster PDF. Artifact metadata remains only in the
Markdown frontmatter.

## Safe HTML Layout

Markdown remains the default. Inside a raw HTML block, write HTML rather than
Markdown syntax. Custom `<style>`, inline `style`, scripts, event handlers,
executable embeds, protocol-relative URLs, and unknown classes are rejected.

Supported classes:

| Class | Purpose |
| --- | --- |
| `artifact-grid artifact-grid-2` | Responsive two-column layout |
| `artifact-grid artifact-grid-3` | Responsive three-column layout |
| `artifact-panel` | One comparison or data panel |
| `artifact-stat` | Metric container |
| `artifact-stat-value` | Primary metric value |
| `artifact-stat-label` | Metric label |
| `artifact-figure` | Responsive raster or SVG figure |
| `artifact-figure-diagram` | Diagram surface that remains dark in both themes |
| `artifact-figure-wide` | Wide SVG with contained mobile scrolling |
| `artifact-figure-tall` | Centered portrait SVG with a width cap |
| `artifact-image` | Responsive raster image |
| `artifact-diagram` | Responsive inline SVG |
| `artifact-callout` | Load-bearing note |
| `artifact-callout-warn` | Caution note (pairs with `artifact-callout`) |
| `artifact-callout-danger` | Critical note (pairs with `artifact-callout`) |
| `artifact-legend` | Figure legend |
| `artifact-tag` | Compact label |
| `artifact-tag-accent` | Emphasized compact label |

Example:

```html
<section class="artifact-grid artifact-grid-2">
  <article class="artifact-panel">
    <h3>Markdown source</h3>
    <p>Concise content and metadata.</p>
  </article>
  <article class="artifact-panel">
    <h3>Compiled artifact</h3>
    <p>Responsive HTML and tagged PDF.</p>
  </article>
</section>
```

## Images And SVG

- List local files in frontmatter `assets` and reference them with `src`; the
  compiler embeds raster files into the HTML.
- Explicit `https:` images remain remote and therefore are not offline-durable.
- Give every image meaningful `alt` text.
- Give every SVG a `viewBox`, `role="img"`, and `aria-label`.
- Use `artifact-figure-wide` for landscape diagrams and
  `artifact-figure-tall` for portrait diagrams.
- Prefer semantic SVG primitives. Gradients, markers, filters, clip paths,
  masks, symbols, text paths, SVG images, and constrained SMIL geometry,
  transform, motion, and paint animation are supported.
- Do not animate URL-bearing attributes such as `href`.

## Plan quality gate

For `kind: plan`, validation is not optional chrome:

| Check | Level | Rule |
| --- | --- | --- |
| Plan surface | **error** | Declare `surface: internal|cli|web|native|api|workflow`. Internal plans need a live drawn SVG; user-visible plans need a semantic current/proposed `.artifact-behavior` figure with capture-or-mockup evidence. |
| Markdown table | warning | At least one `| … |` table (files, risks, validation) |
| Fenced code | warning | At least one fenced code block — commands belong here, not only as inline pills |
| `artifact-callout` | warning | One load-bearing takeaway for the reviewer |

`artifacts render` **does not write HTML** when any error is present. Fix the
Markdown source; do not open a partial file.

Empty SVG shells (template placeholders with only a comment) do **not** pass.

## Diagram Recipe

`<style>` and custom classes are rejected **inside SVG too**, so style every
element with presentation attributes instead of a shared class. Repeat the
attributes; do not try to define `.box` once in `<defs><style>`.

A readable architecture/comparison figure uses tinted fills, colored strokes,
and two text sizes:

| Role | Fill | Stroke | Use |
| --- | --- | --- | --- |
| Concept A | `#16120a` | `#f59e0b` (amber) | one side of a comparison |
| Concept B | `#0f160a` | `#a3e635` (lime) | the other side |
| Shared / hand-off | `#0e1418` | `#38bdf8` (blue) | bridges, shared layers |
| Connector | — | `#38bdf8`, `stroke-dasharray="3 3"`, `opacity="0.7"` | dashed parallels |

Text: labels `font-family="JetBrains Mono, monospace" font-size="11"` in the
concept's stroke color; box titles `font-size="12" fill="#c8c8c8"`; subtitles
`font-size="10" fill="#8a8a8a"` (both `font-family="Inter, system-ui, sans-serif"`).
Boxes: `rx="8"`, `stroke-width="1.5"`. Keep columns aligned on a grid
(e.g. x=40 and x=520 with a 100-unit gap) and pair rows across the gap with
dashed connectors. Figures are dark-first: these tints sit on the
`artifact-figure-diagram` surface, which stays dark in both themes and in
print. See `examples/showcase.md` for a complete figure.

## Generated Files

Do not edit compiled HTML to fix content or layout. It embeds the Markdown source
for `artifacts decompile`, but decompile is recovery, not the normal authoring
path. Make the correction in Markdown or `DESIGN.md` and regenerate all outputs.
