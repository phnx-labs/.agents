---
name: artifacts
description: "Author plans, reports, and visual explanations as Markdown, then render them with artifacts-cli into self-contained branded light/dark HTML. Use for implementation plans, plan mode, architecture diagrams, infographics, dashboards, comparisons, data stories, or any request to render or present an artifact visually."
---

# Artifacts

Author Markdown once, add semantic HTML or inline SVG where layout requires it,
then compile the source to responsive HTML. Do not hand-author a complete HTML
document and do not edit generated HTML.

## Choose the kind

- `plan`: implementation intent, behavior, architecture, validation, risks, and tracking.
- `visual`: one visual explanation, infographic, dashboard, comparison, or data story.
- `report`: findings, evidence, and recommendations. Follow the shared pipeline;
  choose figures that make the evidence easier to understand.

The kind changes the content contract, not the rendering pipeline.

## Shared pipeline

1. Check the installed CLI:

   ```bash
   command -v artifacts
   ```

   If it is missing, report that prerequisite. Do not replace it with a
   hand-written HTML fallback.

2. Resolve the dated artifact directory:

   ```bash
   ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
   DATE=$(date +%F)
   ARTIFACTS_DIR="${ROOT:-.}/.agents/artifacts/$DATE"
   mkdir -p "$ARTIFACTS_DIR"
   ```

3. Author Markdown directly under that directory. Require `kind` and `title`;
   require `surface` for plans. Provenance auto-fills from the Git checkout and
   agent environment. Declare values only when they need overriding.

   Put every related ticket, PR, issue, or design URL in `links`. Mirror those
   URLs under `## Tracking` in plans. Use `tracking` for a short primary id.

   Use Markdown for headings, prose, tables, lists, and fenced code. Use direct
   HTML only for grids, panels, figures, and callouts. Use inline SVG for
   architecture, flows, timelines, state diagrams, and other semantic figures.
   Read [references/authoring.md](references/authoring.md) before adding HTML or
   SVG; follow its diagram recipe.

4. Preserve the target product's visual language. Keep an existing `DESIGN.md`.
   If none exists and durable project branding is useful, create one with:

   ```bash
   artifacts new design
   ```

   Probe design tokens, CSS variables, Tailwind configuration, logos, and the
   live product. Define both light and dark palettes. Keep the in-page theme
   toggle and default it to `prefers-color-scheme`.

5. Validate and render:

   ```bash
   artifacts check "$SOURCE"
   artifacts render "$SOURCE"
   ```

   Rendering writes `<source>.html` beside the Markdown. Fix errors in Markdown
   or `DESIGN.md`, never in generated HTML.

6. Inspect the rendered file headlessly. Check both themes, desktop and mobile
   widths, image loading, SVG bounds, overflow, interactive behavior, and browser
   console errors. Do not open the user's browser unless explicitly requested.

7. When the user asks to view it, reuse one browser tab on their interactive
   machine. If the artifact was rendered elsewhere, copy it there first:

   ```bash
   scp "$SOURCE_HTML" <host>:/tmp/<slug>.html
   agents ssh <host> 'agents browser navigate --url file:///tmp/<slug>.html'
   ```

   If no interactive host is reachable, retain the durable Markdown and HTML and
   report their exact paths.

8. Share only on explicit request:

   ```bash
   artifacts share "$SOURCE" --expire 30d
   ```

   Shared links are public and unlisted, not private. Never put credentials or
   confidential material in the source, `DESIGN.md`, or a public share.

## `kind: plan`

Write `.agents/artifacts/yyyy-mm-dd/plan-<slug>.md` with frontmatter shaped like:

```yaml
---
kind: plan
surface: internal # internal | cli | web | native | api | workflow
title: <plain factual headline>
summary: <problem and intended outcome>
status: draft
links:
  - <ticket-or-PR-url>
---
```

The plan must begin with behavior the reviewer can judge, then explain the
implementation. Keep these headings, in this relative order — they are a
**floor**. `artifacts check` errors if Purpose, Proposed Changes, Public
Interface, Validation, or Risks are missing. Extra `##` sections that carry
evidence belong between Intent/Purpose and Proposed Changes; they are expected
when the topic has a live product, a competitor, or a real architecture:

- `## Behavior first` — the flows the change must deliver, each with today's gap
- `## Competitive teardown` / field notes — from driving the live product, with captures
- `## Proposed architecture` — drawn; not only diffs under Proposed Changes
- `## References` — external URLs for outside-world claims

Do not invent a second frontmatter schema. Do not drop required headings to make
room for extras. A heading skeleton plus one invented SVG compiles and is not a
plan a reviewer can judge.

Floor headings, in this relative order:

1. `## Focus for review` — two to five concrete decisions or tradeoffs.
2. `## Intent` — restate the user's ask. (`## Purpose` also satisfies the checker.)
3. `## Current architecture` — draw how affected modules communicate today;
   add a proposed state when the architecture changes.
4. `## Proposed Changes` — show load-bearing changes as per-file `diff` fences.
5. `## Public Interface` — commands, flags, APIs, or visible behavior.
6. `## Plan` — render the task checklist.
7. `## Validation` — commands and end-to-end proof.
8. `## Risks` — edge cases and mitigations.
9. `## Tracking` — linked tickets and PRs.

### Plan figure contract

Declare `surface` exactly as `internal`, `cli`, `web`, `native`, `api`, or
`workflow`. The plan-presentation guard reads this frontmatter before allowing a
plan to be presented.

For `surface: internal`, include at least one live drawn `<svg>` containing real
SVG primitives. Every `## ...architecture...` section must contain its own drawn
figure; a table names components but does not show their relationships.

For `cli`, `web`, `native`, `api`, and `workflow`, include one product-faithful
current-versus-proposed figure with this exact semantic contract:

```html
<figure class="artifact-figure artifact-behavior">
  <section data-state="current" data-evidence="capture">...</section>
  <section data-state="proposed" data-evidence="mockup">...</section>
</figure>
```

Each state must use `data-evidence="capture"` or `data-evidence="mockup"`.
Prefer a real capture of the live current product; otherwise build a faithful
mockup matching the actual layout, typography, components, and output. An
architecture SVG does not replace this behavior figure. A plan that lists
`.tsx`, `.jsx`, `.vue`, or `.svelte` components is treated as user-visible even
if it declares `surface: internal`.

The compiler's figure requirement is a floor (one drawn SVG, or one
current/proposed behavior figure). Live captures of the current product or
competitors, and a drawing inside every architecture section, are how the
plan becomes reviewable.

Also include at least one Markdown table, one fenced code block, and one
`artifact-callout`. Treat warnings about these as work to fix before presenting.
For multi-step plans, create the harness task checklist before presenting; the
Stop/plan-exit guard checks for it separately from the render.

## `kind: visual`

Write `.agents/artifacts/yyyy-mm-dd/<slug>.md` with `kind: visual`, a precise
title, and a short single-takeaway summary. Choose the page shape from the
content: infographic, explainer, status dashboard, data story, or comparison.

Make one hero figure the visual spine of the page. A table alone does not count.
Use `## Story`, optional `## Data`, and `## Figure`, with the hero figure under
`## Figure`. Give it a clear reading order, labeled connectors or axes, a
caption, and a legend whenever color or line style carries meaning.

Use motion or interaction only when it improves comprehension: SVG/CSS hover,
SMIL, tabs, or progressive disclosure. Prevent automated capture from freezing
on initial animation values:

```js
if (navigator.webdriver) return;
```

Quantitative charts must use honest scales, units, source labels, and accessible
color choices. Use inline SVG for bespoke explanatory graphics; use the
project's established chart system when one exists.

## Voice

- State what the artifact shows; do not write a slogan for a plan.
- Name concrete files, functions, flags, metrics, and error strings.
- Avoid marketing filler and vague nouns.
- Use at most one em dash per paragraph.

## Completion contract

- Markdown remains the source of truth in the dated artifact directory.
- `artifacts check` and `artifacts render` exit successfully.
- A plan satisfies its declared surface contract exactly.
- A visual contains one hero figure that carries the explanation.
- The rendered HTML is self-contained and branded in light and dark themes.
- The output has been inspected headlessly at desktop and mobile widths.
- No user browser was opened unless requested.
- Report the source path, HTML path, and any accepted warnings or share URL.
