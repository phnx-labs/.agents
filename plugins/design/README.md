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
| `system` | design systems, tokens, `DESIGN.md`, and brand identity (`BRAND.md`) | tokens + HTML preview | none |
| `diagram` | architecture / flow / sequence / ER | HTML + hand-authored SVG | none |
| `dataviz` | infographics, charts, dashboards | HTML + SVG | none |
| `deck` | slide decks | HTML (PPTX optional) | none |
| `asset` | OG cards, logos, icons, posters | SVG/HTML (raster optional) | none for vector |
| `motion` | UI motion, micro-interactions | CSS/HTML | none |
| `critique` | audit a screen/site/app; find inconsistencies | ranked findings + fix brief + design laws | none |
| `anticipate` | diagnose a dead-end flow, propose the continuation | before/after ASCII + rationale | none |

There is no separate `brand` mode — brand identity is part of `system` (see
`skills/design/system.md`), since it is the identity layer a design system is
built from, not a distinct deliverable.

## Commands

| Command | Routes to |
| --- | --- |
| `/design` | the front door — reads the intent, picks a mode |
| `/design:critique <url\|file\|screenshot\|pages…>` | the `critique` mode directly — auditing is a different verb from producing (review vs build, the same split as `code:review` vs `code:loop`), so it earns its own door |

## Deterministic checkers (`skills/design/scripts/`)

The critique mode (and every mode's §9 self-verification) leans on two bun scripts so
quality claims are computed, never guessed:

- **`check-contrast.ts`** — WCAG 2.x ratios for hex / rgb() / oklch() pairs, translucent
  foregrounds composited; AA/AAA verdicts, exit 1 on failure. Design-core §3 says "state
  the ratio; do not guess it" — this is the tool that makes that possible.
- **`check-tells.ts`** — static linter over an HTML file for the anti-tells catalog (§6),
  external-CDN/offline violations (§1), and empty color-only status glyphs (§3), each
  finding with line numbers. Heuristic by design: findings are lines to open and judge.

## Why offline-first

Most design jobs render better as editable vector/HTML than as a generated image. True
raster (photo, illustration, painterly cover) is an optional layer: with a backend it
generates; without one it degrades to a spec plus an editable placeholder plus enable-steps,
never a hard failure.

Every mode loads `skills/design/design-core.md` first: visual hierarchy, WCAG AA contrast,
colorblind-safe palettes, the brand-probe cascade, browsing the live web for current
inspiration instead of frozen examples, the anti-tells catalog (the tells that make a
design read as AI-generated — generic gradients, italic serif display, lucide-icon feature
grids, and the rest), precise non-marketing copy, and render/screenshot/critique
verification. That shared core keeps quality consistent across every mode and every user.

## Only one design door

This is the single design skill/plugin in the fleet. There is no separate `create:design`
or user-layer `design` skill — those were folded in here and retired (RUSH-2504) so
`/design` is the one front door, cross-harness.
