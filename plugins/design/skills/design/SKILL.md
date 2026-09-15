---
name: design
description: "One keyless, offline-first front door for design. Routes a design intent to the right focused skill and renders it as self-contained HTML/SVG (no CDN, no paid keys): design systems and tokens (system), screens and interactive flows (prototype), standalone graphics like logos/icons/OG cards (graphics), plus architecture/flow/ER diagrams, infographics, slide decks, critique of an existing screen, and anticipating a flow's dead-ends. True raster (photo, illustration, painterly cover) is an optional layer that degrades to a spec plus an editable placeholder rather than hard-failing. Every skill loads design-core first (hierarchy, WCAG AA contrast, colorblind-safe palettes, brand-probe, the preflight for refining what already exists, the anti-tells catalog of what makes a design look AI-generated, precise non-marketing copy, render/screenshot/critique verification). Triggers on: design a screen/page/UI, mock up, prototype, design system, tokens, brand, BRAND.md, wireframe, diagram this, infographic, dataviz, slide deck, logo, OG image, social card, icon, poster, critique this design, redesign, is this design any good, anticipate, flow improvement, dead-end."
allowed-tools: Bash(agents browser*), Bash(node*), Bash(bun*), Read, Write
user-invocable: true
---

# design — one keyless front door for design

Design work is scattered and often locked behind paid image backends. This plugin is the
single, brand-agnostic entry: `/design` reads the intent, picks a focused skill, and
renders the result on the **offline HTML/SVG substrate** (the `artifacts` engine —
self-contained, inline CSS/SVG, no CDN, no keys). It ships in the default distribution, so
a fresh install has it.

The bet that makes this cover the scenario space: **most design jobs have a better answer
in editable vector/HTML than in a generated raster.** A landing page, a prototype, a
diagram, an infographic, a deck, an OG card, a logo, an icon set, a poster — all render
crisp and editable with zero keys. True raster (a photo, an illustration, a painterly
cover) is a smaller, clearly-scoped layer that **degrades gracefully** when no backend is
configured, never a hard failure.

## Load design-core first

Every skill reads **[`design-core.md`](./design-core.md)** before producing anything:
visual hierarchy and rhythm, accessibility (WCAG AA contrast, colorblind-safe palettes),
the brand-probe (gather everything that exists, not just the first match), browsing for
live current inspiration instead of frozen examples, the preflight for refining an
existing surface (§10), the anti-tells catalog (the tells that make a design look
AI-generated, deferring to an established convention when one already exists), precise
non-marketing copy, and mandatory render/screenshot/critique verification. That shared
core is what keeps quality consistent across every skill and every user.

## Routing — pick the skill from the intent

Four focused skills cover the common jobs directly; call them straight from the picker
(`design:system`, `design:graphics`, `design:prototype`, `design:critique`) or route to
them from here:

| The user asks for | Skill | Output | Keys |
| --- | --- | --- | --- |
| a design system, tokens, components, a `DESIGN.md`, or brand identity (`BRAND.md`, voice) — new or refined | **`design:system`** | tokens + HTML preview | none |
| a screen, page, UI, dashboard, redesign, a clickable multi-screen flow, or motion/micro-interactions | **`design:prototype`** | self-contained/linked HTML | none |
| an OG card, social graphic, logo, icon set, poster, favicon, flyer, resume — or a photo/illustration | **`design:graphics`** | SVG/HTML (raster optional) | none for vector |
| "is this any good?", audit a screen/site, find design inconsistencies | **`design:critique`** | ranked findings + fix brief | none |

The remaining jobs are less common and stay routed through this skill's own mode files,
rather than bloating the three focused skills above with content they don't need day to
day:

| The user asks for | Mode | Output |
| --- | --- | --- |
| an architecture / flow / sequence / ER / org diagram | [`diagram.md`](./diagram.md) | HTML + hand-authored SVG |
| an infographic, data-story, chart, status dashboard | [`dataviz.md`](./dataviz.md) | HTML + SVG |
| a slide deck (pitch, talk, teaching) | [`deck.md`](./deck.md) | HTML slides (PPTX optional) |
| "what happens after this?", fix a dead-end flow | [`anticipate.md`](./anticipate.md) | before/after ASCII + rationale |

When the intent is vague ("make me something nice"), ask one clarifying question about the
job, then route. Never guess between two very different skills silently.

## Deliver it

Write the artifact self-contained under the repository/worktree path —
`"$ROOT/.agents/design/<slug>.html"` — then render it, **look at the screenshot**, run the
critique checklist, and show it to the user via `agents browser show <path>` on their
interactive host (see the `browser` skill for resolving that host and its viewer). Do not
hardcode `open`/`xdg-open` or default to `/tmp`/`~/Downloads`; the mechanics of *how* a
file reaches the user's screen belong to the `browser`/`artifacts` skills, not to this one
— defer to them rather than re-deriving delivery steps here. `agents browser start` (a
separate, headless automation profile) is for the agent's own render-and-inspect step, not
how you present the finished artifact. See the `artifacts` skill for the full delivery and
PDF/share steps; do not re-derive them.

## Portability (why this works for any user)

- **Ships default.** This plugin lives in the system repo (the npm defaults), beside
  `artifacts`, not in `.agents-extras` and not in a personal repo.
- **Keyless core.** The HTML/SVG substrate needs no API key and works offline. That covers
  system, prototype, graphics (vector), diagram, dataviz, deck, and critique.
- **Raster degrades.** True raster uses a backend if one exists, otherwise emits a spec +
  editable placeholder + enable-steps and exits successfully (design-core §8).
- **Brand is optional.** Unbranded output is tasteful by default; brand plugins layer on
  top by calling `/design`.
