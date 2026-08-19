---
name: visualize
description: "Turn a concept, dataset, or codebase/session finding into ONE beautiful, self-contained HTML visual by authoring Markdown and compiling it with artifacts-cli. Produces interactive inline-SVG figures, branded light/dark output, and opens it in the user's browser. The Markdown source lives under the repo's dated artifact layout: .agents/artifacts/yyyy-mm-dd/. The general-purpose sibling of plan-render. Triggers on: visualize this, make an infographic, turn this into a shareable page/poster, explain this visually, data story, status dashboard, 'show X as a graphic', content I can post."
argument-hint: "[topic]"
allowed-tools: Bash(scp*), Bash(agents ssh*), Bash(agents browser*), Bash(open*), Bash(xdg-open*), Bash(find*), Bash(cp*), Bash(mkdir*), Bash(test*), Bash(git rev-parse*), Bash(artifacts*), Write
user-invocable: true
---

# visualize — concepts & data as browser-ready HTML via artifacts-cli

Insight trapped in scrollback or a table nobody reads doesn't travel. Render it as one beautiful, self-contained HTML page that opens in the user's browser.

The source of truth is **Markdown**; the rendering is handled by `artifacts-cli`.

## Output

- **HTML only** — no PDF is produced.
- **Destination** — write the Markdown source and rendered HTML under `.agents/artifacts/yyyy-mm-dd/` (create the date dir if missing). Same layout as plans and other artifacts.
- **Self-contained** — inline CSS/SVG, no CDN, opens offline by double-click.

## Workflow

1. **Check the tool.**

   ```bash
   command -v artifacts
   ```

   If `artifacts` is missing, install artifacts-cli first and report the prerequisite.

2. **Resolve the repo root and dated artifact home.**

   ```bash
   ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
   DATE=$(date +%F)
   ARTIFACTS_DIR="${ROOT:-.}/.agents/artifacts/$DATE"
   mkdir -p "$ARTIFACTS_DIR"
   ```

3. **Choose a shape.**

   The shape sets the spine of the page:

   - **infographic** — one big idea, a few striking numbers, a hero diagram. Skimmable.
   - **explainer** — walks a concept step by step; each `<h2>` is a beat, each with a figure.
   - **status-dashboard** — live state of a system/fleet/project: stat tiles + topology/map SVG + status table.
   - **data-story** — narrative over a dataset: finding → chart → so-what, repeated.
   - **comparison** — before/after or A-vs-B via a two-column figure layout.

4. **Author the Markdown source.**

   Write `"$ARTIFACTS_DIR/<slug>.md"` with at least this frontmatter:

   ```yaml
   ---
   kind: visual
   title: <one punchy, accurate headline>
   summary: <~3-line single takeaway>
   status: draft
   context: <topic>
   facts:
     - <key number or finding>
     - <key number or finding>
   ---
   ```

   Use the section structure required by the `visual` template:

   - `## Story` — the narrative or single takeaway
   - `## Data` — supporting table or list (optional)
   - `## Figure` — the main inline SVG figure(s)

   Use normal Markdown for prose, lists, tables, and code. Use inline HTML only for grids, panels, stat tiles, callouts. Use **inline SVG for every figure**.

5. **Make the figures the point — and make them delightful.**

   A visualize page whose only visual is a table has failed its one job. Every concept with structure — actors, layers, flows, comparisons, states — gets a real SVG figure.

   Add interactivity and motion where it helps:

   - **SMIL animation** for motion, geometry, transform, or paint changes
   - **CSS hover states** for emphasis, tooltips, or revealing detail
   - **Clickable layers** or tabs for alternate views
   - **Progressive disclosure** with `<details>` / `<summary>` blocks
   - **Count-up numbers or status dots** — but guard animations under headless view:
     ```js
     if (navigator.webdriver) return;
     ```

   Every figure needs:

   - a clear reading order
   - labeled connectors or axes
   - a caption that names what it shows
   - a legend when color or line-style encodes meaning

   Follow the diagram conventions in `plan-render/diagram-conventions.md`.

6. **Render to HTML.**

   ```bash
   SOURCE="$ARTIFACTS_DIR/<slug>.md"
   artifacts render "$SOURCE"
   ```

   This writes `<slug>.html` next to the source.

7. **Inspect the output headlessly.**

   Open the rendered HTML in a headless browser and check:

   - both light and dark themes render correctly
   - desktop and mobile widths reflow cleanly
   - SVG figures are visible and any animated/interactive elements work
   - no browser console errors

8. **Deliver it to the user's machine.**

   Resolve the online macOS device from the Host & Fleet context (never hardcode). Show it in **one reused browser tab** with `agents browser navigate` — re-presenting an updated visual refreshes the SAME tab in place instead of piling up a new duplicate tab every time (a raw `open` opens a fresh tab per call). If you are already on that machine, navigate directly (no scp/ssh needed):

   ```bash
   agents browser navigate --url "file://$ARTIFACTS_DIR/<slug>.html"
   ```

   Otherwise copy the HTML over first, then navigate on that host:

   ```bash
   scp "$ARTIFACTS_DIR/<slug>.html" <host>:/tmp/<slug>.html
   agents ssh <host> 'agents browser navigate --url file:///tmp/<slug>.html'
   ```

   Fall back to a single `open` only when that host has no drivable browser profile (`agents ssh <host> 'agents browser profiles list'` is empty and `agents browser start` can't auto-pick one):

   ```bash
   agents ssh <host> 'open /tmp/<slug>.html'
   ```

   Also copy the HTML into `~/Downloads` on the viewer's machine for portability:

   ```bash
   cp "$ARTIFACTS_DIR/<slug>.html" "$HOME/Downloads/<slug>.html"
   ```

   If there is no reachable browser host, still write the durable source + HTML and tell the user the exact path.

## Design and theming

- Use `artifacts new design` to create a project-wide `DESIGN.md` if one does not exist.
- Preserve an existing `DESIGN.md`; it owns both light and dark palettes, typography, density, radius, and layout spacing.
- Probe the target repo for brand tokens and reflect them in `DESIGN.md`.
- The light/dark toggle must be present and default to `prefers-color-scheme`.

## Voice

- One punchy, accurate headline is fine; body copy stays plain.
- Name the real thing: the metric, system, number, file, or function.
- No filler adjectives, no "Critically:" drama, at most one em-dash per paragraph and never stacked appositive dashes.

## Completion contract

- [ ] Markdown source written to `.agents/artifacts/yyyy-mm-dd/<slug>.md`
- [ ] HTML rendered next to the source with `artifacts render <source>.md`
- [ ] Output inspected headlessly in both themes and at desktop/mobile widths
- [ ] ≥1 inline SVG figure; interactive/animated elements verified
- [ ] HTML opened on the user's machine and copied to `~/Downloads`
- [ ] Source, HTML path, and any warnings reported to the user
