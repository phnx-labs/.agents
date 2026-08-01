# design

One keyless, offline-first front door for design. `/design` routes a design intent to a
mode and renders it as self-contained HTML/SVG: no CDN, no paid keys, opens offline.

Ships in the default distribution (beside `plan-render` and `visualize`), so a fresh
install has it. Brand plugins (rush, prix) layer on top by calling `/design`; brand is
optional, never required.

## Modes

| Mode | Job | Output | Keys |
| --- | --- | --- | --- |
| `interface` | screens, pages, components, redesign | self-contained HTML | none |
| `prototype` | clickable multi-screen flows | linked HTML | none |
| `system` | design systems, tokens, `DESIGN.md` | tokens + HTML preview | none |
| `diagram` | architecture / flow / sequence / ER | HTML + hand-authored SVG | none |
| `dataviz` | infographics, charts, dashboards | HTML + SVG | none |
| `deck` | slide decks | HTML (PPTX optional) | none |
| `asset` | OG cards, logos, icons, posters | SVG/HTML (raster optional) | none for vector |
| `motion` | UI motion, micro-interactions | CSS/HTML | none |
| `critique` | review an existing screen | checklist verdict | none |

## Why offline-first

Most design jobs render better as editable vector/HTML than as a generated image. True
raster (photo, illustration, painterly cover) is an optional layer: with a backend it
generates; without one it degrades to a spec plus an editable placeholder plus enable-steps,
never a hard failure.

Every mode loads `skills/design/design-core.md` first: visual hierarchy, WCAG AA contrast,
colorblind-safe palettes, the brand-probe cascade, precise non-marketing copy, and
render/screenshot/critique verification. That shared core keeps quality consistent across
every mode and every user.
