# design:deck — slide decks as a self-contained HTML presentation

Produce a pitch, talk, or teaching deck as **self-contained HTML** — one `<section>`
per slide, keyboard navigation (arrow keys), 16:9 aspect ratio, the design-core
type and spacing scale. Opens offline by double-click. No backend or API key needed.

## Load design-core first

Read `design-core.md`. Everything here inherits its hierarchy, spacing, type, color,
accessibility (contrast + readable at projection size), brand-probe, precise copy,
and mandatory render/critique verification.

## When to use (vs neighbors)

- A sequence of slides — pitch, talk, teaching → **deck** (this).
- A single screen, page, or component → **`interface`**.
- One standalone chart or infographic → **`dataviz`**.
- Several screens the user clicks through → **`prototype`**.

## The loop

1. **Outline the narrative.** One idea per slide, a clear arc: opening hook, problem,
   body, close. Write the outline before touching HTML. If the arc is muddled, the
   deck will be.
2. **Brand-probe** (design-core §4): skin to the target's tokens, or the house
   fallback. Decks are often projected — check that the palette holds up at scale.
3. **Build the HTML shell.** One `<section>` per slide; a shared CSS token set
   (spacing scale, type scale, palette) defined once at the top. Arrow-key navigation
   in ~30 lines of vanilla JS: left/right to step slides, Escape to first slide.
4. **One focal point per slide.** Minimal text — a headline, at most a short line of
   body or three tight bullets. If a slide needs more, split it. Never use a slide as
   a paragraph dump.
5. **Charts and data.** Delegate any in-deck chart to `dataviz`; paste the resulting
   inline SVG into the slide. Do not invent a chart in free-form HTML.
6. **Verify** (design-core §9): render, screenshot the opening slide and at least two
   body slides, run the critique checklist, fix, re-render.

## Output & delivery

- **One self-contained `.html`** (inline CSS + JS, no CDN) at
  `"$ROOT/.agents/design/<slug>-deck.html"` or `/tmp/<slug>-deck.html`. Offline.
  Keyless. Navigable with arrow keys from the first slide.
- Screenshot the title slide and two representative body slides; show them, not a
  description. Open on the user's machine (see `SKILL.md` delivery).
- **PPTX export** is a follow-on: `reveal.js` with the pptx plugin, or
  LibreOffice headless from the HTML, are viable paths — neither is wired by
  default. Note it as available if the user asks.

## Mode checklist (on top of design-core)

- [ ] Narrative outlined first — one idea per slide, clear arc from open to close.
- [ ] One self-contained HTML file; arrow-key navigation; 16:9 ratio.
- [ ] One focal point per slide; no paragraph dumps.
- [ ] Shared token set (spacing, type, palette) defined once and reused across slides.
- [ ] In-deck charts delegated to `dataviz`; SVG pasted inline.
- [ ] Contrast readable at projection size (large-text 3:1 minimum, body 4.5:1).
- [ ] Skinned to brand tokens if found, else a tasteful house fallback.
- [ ] Title slide and at least two body slides screenshotted and critiqued before "done".
