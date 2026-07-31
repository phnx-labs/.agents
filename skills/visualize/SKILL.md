---
name: visualize
description: "Turn a concept, dataset, or codebase/session finding into ONE self-contained, delightful, shareable HTML visual — an infographic, explainer, status-dashboard, data-story, or comparison — skinned in the target's brand (dark + light with a toggle), then opened in the user's browser and dropped as a poster PDF in Downloads. The general-purpose sibling of plan-render: same engine, not plan-scoped. Triggers on: visualize this, make an infographic, turn this into a shareable page/poster, explain this visually, data story, status dashboard, 'show X as a graphic', content I can post."
allowed-tools: Bash(scp*), Bash(agents ssh*), Bash(agents browser*), Bash(open*), Bash(xdg-open*), Bash(node*), Bash(find*), Bash(cp*), Bash(mkdir*), Bash(test*), Bash(git rev-parse*), Write
user-invocable: true
---

# visualize — concepts & data as browser-ready HTML

Insight trapped in scrollback or a table nobody reads doesn't travel. Render it as
**one self-contained `.html`** (inline CSS/JS/SVG, no CDN — opens offline by
double-click), skinned in the relevant brand, and open it in the user's browser —
plus a poster PDF in their Downloads so it's shareable/postable.

This is the **general-purpose sibling of `plan-render`**. It shares that skill's
engine verbatim — the brand-probe theming, the light/dark `◐` toggle, the
"hand-authored inline-SVG, never mermaid" rule, the self-contained constraint, and
the open-on-the-user's-Mac transport. Start from **`template.html`** here;
**`example.html`** is the gold reference (a fleet-status "arcade map" — a fully
themed, delightful instance showing the range).

## When to use this vs. its neighbors

- **`visualize` (this)** — arbitrary context → an *interactive, information-dense
  HTML* you open and share. Precise layout, real data, hand-drawn diagrams.
- **`plan-render`** — same engine, but *implementation plans* specifically (plan
  mode, `/plan`, `/swarm:plan`). Use it for plans; use this for everything else.
- **`visual-styles` / `image` / `image-craft`** — *raster PNGs* (AI-generated or
  PIL), social-post-sized. Reach for those when the output is an image to upload,
  not a page to open.
- **`rush:slides`** — HTML → **PPTX** deck. **`rush:pdf`** — Markdown → branded PDF
  doc. Neither is a shareable interactive HTML.

If the answer is "a page someone opens in a browser and it explains something at a
glance," it's this skill.

## Shapes — pick one, it sets the spine

Same primitives (`.hero`, `.fig`, `.callout`, `.tag`, tables, `.stat` tiles), different
emphasis:

- **infographic** — one big idea, a few striking numbers, a hero diagram. Skimmable.
- **explainer** — walks a concept step by step; each `<h2>` is a beat, each with a figure.
- **status-dashboard** — live state of a system/fleet/project: stat tiles + a topology or
  map SVG + a status table. (`example.html` is this shape.)
- **data-story** — a narrative over a dataset: finding → chart → so-what, repeated.
- **comparison** — before/after or A-vs-B via the `.grid2` two-column figure layout.

## Structure — flexible house, not a fixed schema

Unlike plan-render's fixed plan taxonomy, sections here follow the *content*. What's
constant:

- **Hero** — `.kicker` (`PRODUCT · TOPIC · KICKER`), an `<h1>` with one `.accent`
  phrase, a ~3-line `.sub` framing (**the single takeaway**), `.chip` metadata
  (data points, "as of DATE", source), a `.toc`.
- **Numbered `<h2>` sections** ordered by the story, not by "context→design→files".
- **≥1 hand-authored inline `<svg>` figure** in a `.fig`: the diagram/chart/map/timeline
  **is the point.** Never mermaid, never a CDN chart lib; draw it. A visualize page whose
  only visual is a table has failed its one job. When the figure has a standard notation for
  its domain (a chart type, C4, sequence, crow's-foot, BPMN, a P&ID), use it, and add a
  **legend** when color or line-style encodes meaning. See `diagram-conventions.md` (sibling `plan-render` skill dir).
- **`.stat` tiles** for headline numbers, **`.callout`** for the load-bearing takeaway,
  **tagged tables** where rows need status pills.
- **`.foot`** — one mono line; provenance / "as of" / a link, not a decision CTA.

Make it **delightful**, sized to the audience: count-up numbers, glowing status dots,
animated SVG flows, hover lifts — but taste over noise, and every animation must survive
print (see the guard below).

**Keep the copy precise.** Even on a shareable page, name the real thing (the metric, the
system, the number), not a vague stand-in, and hold the marketing register in check: no
filler adjectives, no "Critically:" drama, at most one em-dash per paragraph and never
stacked appositive dashes. A shareable visual may carry **one** punchy, accurate headline;
the body copy stays plain. (This is the `code-quality` "write prose precisely" rule, applied
to the page.)

## Theme + light/dark

Identical to `plan-render`: probe the target's brand (design tokens → framework config →
brand assets → live UI → house fallback) and skin by editing only the two `:root` blocks;
ship both palettes + the `◐` toggle defaulting to `prefers-color-scheme`; keep diagrams as
dark blueprint cards in both themes. See `plan-render/SKILL.md` for the full cascade — don't
re-derive it. (`example.html` shows a fully custom neon skin, dark-default, for a poster.)

## Where to write it

`ROOT=$(git rev-parse --show-toplevel 2>/dev/null)`; if `test -d "$ROOT/.agents"`, write
`"$ROOT/.agents/viz/<slug>.html"` (`mkdir -p` first) — durable, next to the code. Else
`/tmp/<slug>.html`. Set `HTML` to that path.

## Deliver it — open in the browser + poster PDF in Downloads

Land it on the machine the user sits at (resolve the online macOS device from the **Host &
Fleet** context — never hardcode a host; `scp` + `agents ssh` if you're remote). Then:

1. **Open the interactive HTML** in their default browser: `open "$HTML"` (or `xdg-open`).
2. **Drop a poster PDF in `~/Downloads`.** For a shareable/postable artifact you almost
   always want a **single-page, full-bleed poster** (not paginated Letter — a screen-designed
   visual sliced into bordered sheets looks broken). Render it sized to the exact content:

   ```bash
   # Playwright's bundled Chromium prints reliably; a fork like Comet CANNOT headless-print
   # (its updater hijacks the launch). Find the newest chrome-headless-shell:
   SHELL_BIN=$(ls -d "$HOME"/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell 2>/dev/null | sort -V | tail -1)
   PW=$(ls -d "$HOME"/src/*/*/agents/node_modules/playwright-core 2>/dev/null | head -1)
   node -e '
     const {chromium}=require(process.env.PW);
     (async()=>{const b=await chromium.launch({executablePath:process.env.SHELL_BIN,args:["--no-sandbox"]});
       const p=await b.newPage({viewport:{width:1200,height:900},deviceScaleFactor:2});
       await p.goto("file://"+process.env.HTML,{waitUntil:"load"}); await p.waitForTimeout(800);
       const h=await p.evaluate(()=>Math.ceil(document.body.getBoundingClientRect().height));
       await p.pdf({path:process.env.HOME+"/Downloads/"+process.env.SLUG+".pdf",
         width:"1200px",height:(h+6)+"px",printBackground:true,
         margin:{top:"0",right:"0",bottom:"0",left:"0"}});
       await b.close(); console.log("poster "+h+"px");})();' 2>&1 | tail -1
   ```

   (The `+6` is print-margin slop; on a near-empty *stub* page it can spill onto a 2nd page —
   harmless for any real content-sized visual, which stays one page. For a normal multi-page
   document PDF instead, use the `agents browser pdf` CDP path from `plan-render` — but for
   posters/infographics the single-page render above is the one.)

3. Tell the user it opened + the PDF path, with a 2–3 line summary.

**Graceful degradation:** no browser host → still write `$HTML`, say so. No Playwright/node
→ fall back to `agents browser pdf` (paginated) and note it.

## Gotchas (learned the hard way — don't re-hit these)

- **Chromium *forks* (Comet/Perplexity) can't `--headless` print** — the updater seizes the
  launch and never emits a file. Use Playwright's bundled `chrome-headless-shell`.
- **Count-up / entrance animations snapshot as `0` under headless print.** Bake the FINAL
  values into the HTML and skip the animation when automated:
  `if (navigator.webdriver) return;` before starting count-ups. Live view animates; print
  shows real numbers.
- **`open <file>` on macOS reuses a cached background tab** — edits may not reload. For a
  fresh render, open a uniquely-named file or set the front tab's URL.

## Checklist before you present

- [ ] One self-contained HTML at `$HTML` (`.agents/viz/` if the project has `.agents/`, else
      `/tmp`) — opens offline, no CDN.
- [ ] A **shape** chosen; sections ordered by the story.
- [ ] ≥1 hand-authored inline-SVG figure carrying the insight; no mermaid.
- [ ] Figure uses the domain's standard notation; a legend where color or line-style encodes meaning.
- [ ] Copy is precise: real names/numbers, no filler, ≤1 em-dash per paragraph (one accurate punchy headline is fine).
- [ ] Skinned in the relevant brand (or house fallback); light/dark toggle present.
- [ ] Animations guarded for print (`navigator.webdriver`); numbers baked in.
- [ ] **You looked at the rendered result** (screenshot both themes) and it's delightful.
- [ ] Single-page poster PDF in `~/Downloads`; HTML opened in the user's browser (or
      degradation noted).
