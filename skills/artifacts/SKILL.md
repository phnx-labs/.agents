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

2. Resolve the artifact directory. It lives in the DURABLE HOME, never in a
   git checkout:

   ```bash
   DATE=$(date +%F)
   ARTIFACTS_DIR="$HOME/.agents/artifacts/$DATE/<slug>"
   mkdir -p "$ARTIFACTS_DIR"
   ```

   `~/.agents/artifacts/` is outside every repository, is never reaped, and is
   already date-partitioned. The `<slug>` level exists so two agents working on
   the same day cannot collide on `plan.md`.

   Do NOT write into `<repo>/.agents/artifacts/`. That directory is TRACKED —
   untracked files inside it are what make `git checkout` and `git merge` refuse
   with "would be overwritten". Writing there also means writing into a primary
   checkout, which `main-branch-guard` denies. The only artifacts that belong in
   a repo are ones deliberately committed with their feature, through a worktree
   and a PR like any other tracked file.

   Alongside the Markdown and HTML, write `.artifact.json` so the artifact is
   findable days later by slug rather than by a path someone has to remember:

   ```json
   {"v":1,"slug":"<slug>","title":"<title>","kind":"plan","session":"<id>",
    "agent":"<harness>","host":"<machine>","share_url":null,"ticket":null,
    "created_at":"<date>","updated_at":"<date>"}
   ```

   When the artifact is published, record the returned slug in `share_url` and
   pass it back via `--slug` on the next publish — that is what keeps a
   long-running artifact on one stable link.

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

   **A render is verified only when you have looked at the actual pixels.** A clean
   `artifacts check`, an exit-0 render, an empty console, or a loader that reports
   "complete" are proxies, not proof — screenshot the output and read the image
   before you call any section done. A capture that lands mid-paint, mid-scroll, or
   on the wrong section looks authoritative while being wrong, and describing a
   section from a shot you never confirmed shows it is how a broken figure ships. On
   a tall page with a sticky nav, scroll the target into view, let it settle, and
   confirm the intended element is in the frame before trusting the shot.

7. When the user asks to view it, reuse one browser tab on their interactive
   machine. If the artifact was rendered elsewhere, copy it there first:

   ```bash
   scp "$SOURCE_HTML" <host>:/tmp/<slug>.html
   agents ssh <host> 'agents browser navigate --url file:///tmp/<slug>.html'
   ```

   `/tmp` is the only correct destination for this copy. Never `scp` an artifact
   into a checkout on the target machine — that is a write into someone's
   primary working tree from another host, and it is exactly how twelve
   untracked files ended up in the agents repo on `main`.

   Prefer publishing over copying when the artifact is worth keeping: a share
   link needs no file transfer at all, works from any machine, and survives the
   session.

   If no interactive host is reachable, retain the durable Markdown and HTML and
   report their exact paths.

8. Share only on explicit request:

   ```bash
   artifacts share "$SOURCE" --expire 30d
   ```

   Shared links are public and unlisted, not private. Never put credentials or
   confidential material in the source, `DESIGN.md`, or a public share.

## Evidence: captures and claims

A figure that carries evidence — a screenshot of a live page, a capture of a real
product — is the part a reader trusts most, so it is held above "the command
exited 0."

- **Settle a live page before capturing it.** Lazy-loaded images and scroll-reveal
  animations make the visible pixels lag the DOM, so a load count ("7/7 images
  loaded") is not "fully rendered." Scroll through to trigger lazy content, wait for
  the network to go idle and animations to finish, then look at the capture. Scrolling
  back to the top can re-trigger an entrance animation — capture in place, and read the
  image before embedding it. A mid-animation screenshot embedded as proof of a problem
  undercuts the very point it illustrates.
- **A claim about how a live surface behaves is confirmed by performing the action,
  not by reading the DOM once.** Whether a card, icon, or link navigates — click or
  hover it and observe the result. A single `<a>`-tag scan misses JS click handlers and
  mispositioned hit targets, and asserting "dead link" from one static probe puts a
  wrong claim in a deliverable. State in the figure how the behavior was verified.

## `kind: plan`

Write `~/.agents/artifacts/yyyy-mm-dd/<slug>/plan.md` with frontmatter shaped like:

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
implementation. Keep the floor headings below, in this relative order.
`artifacts check` errors if Purpose, Proposed Changes, Public Interface,
Validation, or Risks are missing.

Extra `##` sections that carry evidence belong between Intent/Purpose and
Proposed Changes. They are **content**, not a second closed heading list. Do
not mint empty `## Behavior first` / `## Competitive teardown` / `## Options
considered` shells to look complete. Put the evidence under whatever title
reads. When the topic has a live product, a competitor, or a real architecture,
the plan must actually contain:

- the flows the change must deliver, each with today's gap
- field notes from driving the live product, with captures
- a proposed-architecture system diagram (modules, arrows, layers — follow the
  diagram recipe in [references/authoring.md](references/authoring.md))
- load-bearing choices with options / implications / winner
- independent-panel findings (ADOPTED / REJECTED with `file:line`) when a panel ran
- external URLs for outside-world claims

A one-file bugfix skips this (one line for alternatives is enough). Do not
invent a second frontmatter schema. Do not drop required headings to make room.
A heading skeleton plus one invented SVG compiles and is not a plan a reviewer
can judge.

Floor headings, in this relative order:

1. `## Focus for review` — two to five concrete decisions or tradeoffs.
2. `## Intent` — restate the user's ask. (`## Purpose` also satisfies the checker.)
3. `## Current architecture` — a system diagram of how affected modules
   communicate today (boxes + arrows for calls / data / control; layers distinct).
   A filename table does not replace it. Add a proposed-state diagram when the
   architecture changes.
4. `## Proposed Changes` — show load-bearing changes as per-file `diff` fences.
5. `## Public Interface` — commands, flags, APIs, or visible behavior.
6. `## Plan` — render the task checklist.
7. `## Validation` — commands and end-to-end proof.
8. `## Risks` — concrete corner cases with `file:line` (misconfig, leaked
   resource, boot path that dies), not "this might be hard".
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

Write `~/.agents/artifacts/yyyy-mm-dd/<slug>/<slug>.md` with `kind: visual`, a precise
title, and a short single-takeaway summary. Choose the page shape from the
content: infographic, explainer, status dashboard, data story, or comparison.

Make one hero figure the visual spine of the page. A table alone does not count.
Use `## Story`, optional `## Data`, and `## Figure`, with the hero figure under
`## Figure`. Give it a clear reading order, labeled connectors or axes, a
caption, and — when color or line style carries meaning — direct labels on the
marks where the figure stays clean, or a legend when direct labels would clutter.

Use motion or interaction only when it improves comprehension: SVG/CSS hover,
SMIL, tabs, or progressive disclosure. Prevent automated capture from freezing
on initial animation values:

```js
if (navigator.webdriver) return;
```

Quantitative charts must use honest scales, units, source labels, and accessible
color choices. Use inline SVG for bespoke explanatory graphics; use the
project's established chart system when one exists.

Tell a story; let what you already know about visualization guide the piece. Name
the *Big Idea* in one sentence and the reader's *"so what"* before you chart, and
give the piece a narrative arc — beginning, tension, resolution or call to action.
Pick each visual by its job from the effective set — simple text or one big number,
table or heatmap, scatterplot, line, slopegraph, bar, stacked bar, waterfall — and
avoid pie, donut, 3D, and dual-axis. *Declutter*: cut chartjunk, reduce cognitive
load, group with Gestalt proximity and alignment. Then steer the eye with
*preattentive attributes* (size, color, position) — gray the context and highlight
the one thing that matters in a single accent color, keeping labels next to the
marks they name. Use the `dataviz` skill for the chart mechanics (palette, marks,
accessibility); this is the storytelling layer on top of it.

## When the artifact recommends

A `visual` or `report` that proposes changes is judged on whether a human grasps each
recommendation fast. Humans are visual — they read a diagram in a glance and skim past a
paragraph — so a recommendation carried by prose alone mostly does not land.

- **Show it, do not just tell it.** Every recommendation gets a mockup, a before/after,
  or a working demo — not a prose bullet. A suggestion with no picture hides whether it
  is feasible or even understood; the idea lands when the reader can see it. This is the
  same show-don't-tell discipline `kind: plan` enforces with its current/proposed
  behavior figure on user-visible surfaces — apply it to each proposal a visual or
  report makes.
- **A structured text block is a visual in disguise.** A paragraph that carries a
  comparison, a sequence, a set of options, or a cause and effect is faster to grasp as a
  table, a small diagram, a timeline, or a callout with the one takeaway pulled out. When
  you catch yourself writing several sentences of structure, render the structure instead
  and keep the prose to the point it makes.
- **Digestible, not a landing page.** The goal is accessible and quickly scannable — not
  marketing copy, not a slide deck, not a hero-section pitch. Lead with the visual, keep
  the words concrete and few, and never let "make it visual" turn into slop (see Voice).
- **Say why it matters.** Beside each recommendation, state the payoff and the cost of
  not doing it — the importance, not just the instruction.
- **Cite the record and stamp the date.** Every quantitative claim links to its primary
  source (the actual record, not a secondary summary or "the news said"), every dataset
  carries an as-of date or time-window, and a raw-records appendix ties each number back
  to its source. A number nobody can trace reads as invented — traceability is what lets
  the reader trust it was not.

## Voice

- State what the artifact shows; do not write a slogan for a plan.
- Name concrete files, functions, flags, metrics, and error strings.
- Avoid marketing filler and slop nouns. "Registry" / "platform" / "runtime"
  must resolve to a config table, an OCI image, a protocol, or they do not ship.
- Use at most one em dash per paragraph.
- Write architecture the way a staff engineer would: coupling points, boot
  sequence, control vs data plane, alternatives considered.

## Completion contract

- Markdown remains the source of truth in the dated artifact directory.
- `artifacts check` and `artifacts render` exit successfully.
- A plan satisfies its declared surface contract exactly.
- A visual contains one hero figure that carries the explanation.
- Every embedded capture was viewed at the pixel level before shipping, and any live
  page was fully settled before it was captured.
- When the artifact recommends, each recommendation is shown (mockup / before-after /
  demo) with its rationale, and every quantitative claim cites a primary source with a
  timeframe.
- The rendered HTML is self-contained and branded in light and dark themes.
- The output has been inspected headlessly at desktop and mobile widths.
- No user browser was opened unless requested.
- Report the source path, HTML path, and any accepted warnings or share URL.
