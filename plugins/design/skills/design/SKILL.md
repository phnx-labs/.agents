---
name: design
description: "One keyless, offline-first front door for design. Routes a design intent to a mode and renders it as self-contained HTML/SVG (no CDN, no paid keys): UI screens and flows, clickable prototypes, design systems and tokens (including brand identity, BRAND.md), architecture/flow/ER diagrams, infographics and data-stories, slide decks, vector assets (OG cards, SVG logos, icon sets, posters), critique of an existing screen, and anticipating a flow's dead-ends. True raster (photo, illustration, painterly cover) is an optional layer that degrades to a spec plus an editable placeholder rather than hard-failing. Every mode loads design-core first (hierarchy, WCAG AA contrast, colorblind-safe palettes, brand-probe, the anti-tells catalog of what makes a design look AI-generated, precise non-marketing copy, render/screenshot/critique verification). Triggers on: design a screen/page/UI, mock up, prototype, design system, tokens, brand, BRAND.md, wireframe, diagram this, infographic, dataviz, slide deck, logo, OG image, social card, icon, poster, critique this design, redesign, is this design any good, anticipate, flow improvement, dead-end."
allowed-tools: Bash(scp*), Bash(agents ssh*), Bash(agents browser*), Bash(open*), Bash(xdg-open*), Bash(node*), Bash(bun*), Bash(find*), Bash(cp*), Bash(mkdir*), Bash(test*), Bash(git rev-parse*), Write
user-invocable: true
---

# design — one keyless front door for design

Design work is scattered and often locked behind paid image backends. This plugin is the
single, brand-agnostic entry: `/design` reads the intent, picks a mode, and renders the
result on the **offline HTML/SVG substrate** (the `artifacts` engine —
self-contained, inline CSS/SVG, no CDN, no keys). It ships in the default distribution, so
a fresh install has it.

The bet that makes this cover the scenario space: **most design jobs have a better answer
in editable vector/HTML than in a generated raster.** A landing page, a prototype, a
diagram, an infographic, a deck, an OG card, a logo, an icon set, a poster — all render
crisp and editable with zero keys. True raster (a photo, an illustration, a painterly
cover) is a smaller, clearly-scoped layer that **degrades gracefully** when no backend is
configured, never a hard failure.

## Load design-core first

Every mode reads **`design-core.md`** before producing anything: visual hierarchy and
rhythm, accessibility (WCAG AA contrast, colorblind-safe palettes), the brand-probe
cascade, browsing for live current inspiration instead of frozen examples, the anti-tells
catalog (the tells that make a design look AI-generated), precise non-marketing copy, the
graceful-raster rule, and mandatory render/screenshot/critique verification. That shared
core is what keeps quality consistent across every mode and every user.

## Routing — pick the mode from the intent

| The user asks for | Mode | Output | Keys |
| --- | --- | --- | --- |
| a screen, page, UI, dashboard; "make this look good"; redesign | `interface` | self-contained HTML | none |
| something to click through; a multi-screen flow | `prototype` | linked HTML screens | none |
| a design system, tokens, components, a `DESIGN.md`, or brand identity (`BRAND.md`, voice) | `system` | tokens + HTML preview | none |
| an architecture / flow / sequence / ER / org diagram | `diagram` | HTML + hand-authored SVG | none |
| an infographic, data-story, chart, status dashboard | `dataviz` | HTML + SVG | none |
| a slide deck (pitch, talk, teaching) | `deck` | HTML slides (PPTX optional) | none |
| an OG card, social graphic, logo, icon set, poster, favicon | `asset` | SVG/HTML (raster optional) | none for vector |
| motion, a micro-interaction, an animated hero | `motion` | CSS/HTML animation | none |
| "is this any good?", audit a screen/site, find design inconsistencies | `critique` | ranked findings + fix brief | none |
| "what happens after this?", fix a dead-end flow, anticipate next action | `anticipate` | before/after ASCII + rationale | none |
| a photo, illustration, or painterly cover | `asset` (raster) | raster, or spec + placeholder | optional backend |

When the intent is vague ("make me something nice"), ask one clarifying question about the
job, then route. Never guess between two very different modes silently.

## The modes

Each mode file lives beside this one. Read design-core first, then the mode:

- **`interface.md`** — screens, pages, components; redesign from a screenshot.
- **`prototype.md`** — clickable multi-screen HTML flows.
- **`system.md`** — design systems, tokens, `DESIGN.md`, brand definition.
- **`diagram.md`** — architecture/flow/sequence/ER via `diagram-conventions.md` notation.
- **`dataviz.md`** — infographics, charts, data-stories, dashboards.
- **`deck.md`** — slide decks (HTML-first, PPTX when asked).
- **`asset.md`** — OG cards, logos, icons, posters (vector-first); raster with graceful degradation.
- **`motion.md`** — CSS/HTML motion and micro-interactions.
- **`critique.md`** — audit an existing screen, site, or app: deterministic checks via
  `scripts/check-contrast.ts` (WCAG ratios computed, hex/rgb/oklch) and
  `scripts/check-tells.ts` (anti-tells, offline violations, color-only status), plus the
  screenshot critique; outputs ranked findings, a paste-ready fix brief, and standing
  design laws for the project's docs. Direct door: `/design:critique <target>`.
- **`anticipate.md`** — diagnose a dead-end flow and propose the continuation (before/after ASCII, no implementation).

## Deliver it (reuse the artifacts transport)

Write the artifact self-contained. Pick its home once: if the repo has an `.agents/` dir,
`"$ROOT/.agents/design/<slug>.html"`; else `/tmp/<slug>.html`. Then render it, **look at
the screenshot**, run the critique checklist, and open it in the user's DEFAULT browser on
the machine they sit at (resolve the online device from the Host and Fleet context) — the
browser they actually use, which needs no fleet browser profile: `open <path>` (macOS) /
`xdg-open <path>` locally, or `scp` it over and `agents ssh <host> 'open /tmp/<slug>.html'`
when remote. `agents browser` is the agent's own automation profile for the headless
screenshot above, not how you show the user; only reach for
`agents browser navigate --url file://<path>` when a profile is configured and you
re-render the SAME file repeatedly (it reuses one tab instead of a fresh tab per `open`).
For a shareable asset, also drop a PDF/PNG in `~/Downloads`. See `artifacts/SKILL.md` for
the full delivery and PDF steps; do not re-derive them.

## Portability (why this works for any user)

- **Ships default.** This plugin lives in the system repo (the npm defaults), beside
  `artifacts`, not in `.agents-extras` and not in a personal repo.
- **Keyless core.** The HTML/SVG substrate needs no API key and works offline. That covers
  interface, prototype, system, diagram, dataviz, deck, critique, and vector assets.
- **Raster degrades.** True raster uses a backend if one exists, otherwise emits a spec +
  editable placeholder + enable-steps and exits successfully (design-core §8).
- **Brand is optional.** Unbranded output is tasteful by default; brand plugins layer on
  top by calling `/design`.
