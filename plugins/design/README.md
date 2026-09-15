# design

One keyless, offline-first front door for design. `/design` routes a design intent to the
right focused skill and renders it as self-contained HTML/SVG: no CDN, no paid keys, opens
offline.

Ships in the default distribution (beside `artifacts`), so a fresh
install has it. Brand plugins (rush, prix) layer on top by calling `/design`; brand is
optional, never required.

## Skills

Four skills are real, independently invocable doors — each loads `design-core.md` (via
the `design` skill) for the shared doctrine, then its own loop:

| Skill | Job | Output | Keys |
| --- | --- | --- | --- |
| [`design:system`](./skills/system/SKILL.md) | design systems, tokens, `DESIGN.md`, and brand identity (`BRAND.md`) — new or refined | tokens + HTML preview | none |
| [`design:graphics`](./skills/graphics/SKILL.md) | standalone graphics — OG cards, logos, icon sets, posters, favicons — new or refined | SVG/HTML (raster optional) | none for vector |
| [`design:prototype`](./skills/prototype/SKILL.md) | screens, clickable multi-screen flows, redesign, and motion — new or refined | self-contained/linked HTML | none |
| [`design:critique`](./skills/critique/SKILL.md) | audit a screen/site/app; find inconsistencies | ranked findings + fix brief + design laws | none |

There is no separate `brand` skill — brand identity is part of `design:system` (see
`skills/system/SKILL.md`), since it is the identity layer a design system is built from,
not a distinct deliverable.

## The router (`design` skill)

Everything else stays behind the `design` skill itself as mode files (`skills/design/`),
routed to on intent rather than promoted to their own doors — these are less common jobs,
and giving each its own skill would bloat the picker without adding a job people ask for
by name:

| Mode | Job | Output |
| --- | --- | --- |
| `diagram` | architecture / flow / sequence / ER | HTML + hand-authored SVG |
| `dataviz` | infographics, charts, dashboards | HTML + SVG |
| `deck` | slide decks | HTML (PPTX optional) |
| `anticipate` | diagnose a dead-end flow, propose the continuation | before/after ASCII + rationale |

## Commands

| Command | Routes to |
| --- | --- |
| `/design` | the front door — reads the intent, picks a skill or mode |
| `/design:system <intent>` | `design:system` directly |
| `/design:graphics <intent>` | `design:graphics` directly |
| `/design:prototype <intent>` | `design:prototype` directly |
| `/design:critique <url\|file\|screenshot\|pages…>` | `design:critique` directly — auditing is a different verb from producing (review vs build, the same split as `code:review` vs `code:loop`), so it earns its own door |

## Deterministic checkers (`skills/critique/scripts/`)

`design:critique` (and every skill's design-core §9 self-verification) leans on two bun
scripts so quality claims are computed, never guessed:

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

Every skill loads `skills/design/design-core.md` first: visual hierarchy, WCAG AA contrast,
colorblind-safe palettes, the brand-probe (gather everything that exists, not just the
first match), browsing the live web for current inspiration instead of frozen examples,
the preflight for refining an existing surface (§10 — open guidelines/tokens/components
visually, inspect representative live flows, prefer refining over replacing), the
anti-tells catalog (deferring to an established convention when one exists), precise
non-marketing copy, and render/screenshot/critique verification. That shared core keeps
quality consistent across every skill and every user.

## Only one design door

This is the single design plugin in the fleet. There is no separate `create:design`
or user-layer `design` skill — those were folded in here and retired (RUSH-2504) so
`/design` is the one front door, cross-harness.
