# design:dataviz — infographics, charts, and dashboards

Turn data into a visual: infographics, charts, data-stories, and status dashboards
as **self-contained HTML with hand-authored inline SVG charts**. No chart library,
no CDN, keyless, offline.

## Load design-core first

Read `design-core.md`. Everything here inherits its hierarchy, spacing, type, color,
accessibility (contrast + colorblind-safe), brand-probe, precise copy, and mandatory
render/critique verification.

## When to use (vs neighbors)

- Data that needs a visual shape: a trend, a comparison, a distribution → **dataviz** (this).
- A diagram of structure, flow, or architecture (no quantitative axes) → **`diagram`**.
- A slide deck with charts embedded in a narrative flow → **`deck`**.
- A full UI screen that happens to include a chart → **`interface`**.

## The loop

1. **Understand the data and the one takeaway.** What is the single thing the chart
   should make undeniable? Every design decision follows from that answer.
2. **Pick the fitting chart type** (diagram-conventions "Charts" rules, non-negotiable):
   - Categorical comparison → bar, y-axis from zero.
   - Trend over time → line.
   - Distribution → histogram or box.
   - Correlation → scatter.
   - Part-to-whole → stacked bar; not a pie beyond ~3 slices.
   - Two-variable field → heatmap.
3. **Draw the SVG with labeled axes and direct labels.** Label every axis with quantity
   and units. Direct-label each series at its end; do not add a legend when a label
   at the data does the same job with less eye travel.
4. **Apply a colorblind-safe palette.** Categorical: Okabe-Ito. Sequential: Viridis.
   Never encode meaning by red-vs-green alone; pair color with shape or position.
5. **Delete chartjunk.** No 3-D, no gradients, no drop-shadows, no heavy gridlines,
   no rainbow/jet colormap. Remove until it breaks, then stop.
6. **Verify** (design-core §7): render via the `visualize` engine, screenshot, run the
   critique checklist, fix, re-render. The chart is not done until you have looked at it.

## Output & delivery

- **One self-contained `.html`** (inline CSS + inline SVG, no CDN) at
  `"$ROOT/.agents/design/<slug>.html"` or `/tmp/<slug>.html`. Opens offline. Keyless.
- Reuse the `visualize` HTML/SVG engine: the same file structure, the same spacing
  scale (4 / 8 / 12 / 16 / 24 / 32 / 48), the same dark/light toggle.
- Show the screenshot and quote the takeaway the chart makes visible; not just a path.

## Mode checklist

- [ ] One clear takeaway; the chart type matches the data shape (see loop step 2).
- [ ] Every axis labeled with quantity + units; y-axis starts at zero for bars.
- [ ] Series direct-labeled at the data; no legend where a label suffices.
- [ ] Okabe-Ito (categorical) or Viridis (sequential); color never the sole encoding.
- [ ] No chartjunk: no 3-D, no gradients, no decorative gridlines.
- [ ] Self-contained HTML, inline SVG, no CDN, opens offline.
- [ ] Rendered, screenshotted, and critiqued before "done".
