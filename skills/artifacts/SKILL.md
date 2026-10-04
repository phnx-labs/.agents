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

2. Resolve a durable artifact directory before writing. Honor the repository
   policy when output ships with a feature: commit it through a linked worktree.
   For standalone output, first check whether the usual home below is itself
   inside a git checkout:

   ```bash
   DATE=$(date +%F)
   ARTIFACTS_DIR="$HOME/.agents/artifacts/$DATE/<slug>"
   ```

   `~/.agents/` can itself be a checkout. If so, use a linked worktree for
   committed output or a durable directory outside that checkout, such as
   `~/.local/share/agents/artifacts/`. Check this before creating files. The
   `<slug>` level keeps concurrent authors from colliding on `plan.md`.

   Never write into a primary checkout, locally or when copying to another
   machine. Whether `<repo>/.agents/artifacts/` is tracked depends on that
   repository. Deliberately committed artifacts belong in its linked worktree
   and PR; do not assume a directory name makes a write safe. Once the boundary
   check is complete and the destination is chosen, create it with
   `mkdir -p "$ARTIFACTS_DIR"`.

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

3. Capture the subject project before authoring in that directory. Run
   `agents projects list --json` and match the project the artifact is about,
   using its repository and bound directories. `name` is the stable project ID;
   `linear.name`, when present, is its readable name. Keep IDs unchanged,
   including dots, dashes and underscores; do not guess a display name by
   title-casing a repository slug. A shared monorepo alone may not identify
   which project the artifact concerns.

   From the subject project's checkout or linked worktree, scaffold into the
   absolute durable output path, then edit that Markdown:

   ```bash
   artifacts new visual --project <registered-project-id> --out "$SOURCE"
   ```

   Choose `plan`, `report`, or `visual` for the task. Require `kind` and `title`;
   require `surface` for plans. Verify `project`, `repository`, `harness`, and
   `agent` in the written frontmatter before rendering. For hand-authored
   Markdown, supply these explicitly from the same subject context. Rendering
   a file in `~/.agents/artifacts/` cannot infer its subject checkout from its
   storage location. If no registered project matches, use the known project
   name and actual repository; leave unknown metadata unknown.

   Preserve the creating harness when another agent merely re-renders the file.
   The renderer owns its creator logo, cover and favicon; do not hand-build
   those in the body. Use a concise artifact title without repeating the project
   prefix. If recording `created` and `updated`, use real ISO timestamps with a
   timezone, preserve `created`, and change `updated` only when the source
   changes. Never reset either timestamp when the page is opened.

   Put every related ticket, PR, issue, or design URL in `links`. Mirror those
   URLs under `## Tracking` in plans. Use `tracking` for a short primary id.

   Use Markdown for headings, prose, tables, lists, and fenced code. Use direct
   HTML only for grids, panels, figures, and callouts. Use inline SVG for
   architecture, flows, timelines, state diagrams, and other semantic figures.
   Read [references/authoring.md](references/authoring.md) before adding HTML or
   SVG; follow its diagram recipe.

   Design a reading path: the conclusion and consequence first, the important
   comparison or relationship next, then inspectable detail and sources. A reader
   should know what matters before opening anything. Preserve correct terms,
   qualifications, units, denominators, timeframes and unresolved decisions; when
   rewriting, account for the original claims rather than quietly dropping them.

   Choose the form by the reader's task. Use prose for a simple claim, aligned
   tables for exact lookup or a few comparable options, charts for quantitative
   patterns, and diagrams for containment, dependencies or sequence. A card is
   useful for an independent unit; do not automatically turn every record into a
   tile or every number into a stat. Long inventories belong behind disclosure or
   in an appendix. A table warning asks for judgment, not automatic conversion.

   Make meaningful detail inspectable. A service, chart mark or stage that invites
   a click should reveal its actual modules, evidence or explanation. Prefer the
   renderer's reusable components: run `artifacts components`, then
   `artifacts components <name>` for its input contract and example. Fill in data;
   let the renderer own layout, keyboard behavior and printing. If the installed
   version lacks that command or component, use supported native disclosure or
   links and state the limitation. Do not invent a component, callback, or working
   control the renderer does not implement. See the authoring reference.

   Cite evidence near the claim it supports, with descriptive links or `excerpt`
   fences pinned to the source revision. Put source details inside the relevant
   disclosure when they interrupt the overview. Decorative chips and repeated
   metadata must not dominate the reading path.

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
   console errors. Exercise each meaningful control: open, inspect, close, follow
   sources, and navigate by keyboard. Check expanded states and effective text
   size after SVG scaling, not just the declared font size. Capture the normal
   entry view as well as the detail being demonstrated. Do not open the user's browser unless explicitly requested.

   **A render is verified only when you have looked at the actual pixels.** A clean
   `artifacts check`, an exit-0 render, an empty console, or a loader that reports
   "complete" are proxies, not proof — screenshot the output and read the image
   before you call any section done. A capture that lands mid-paint, mid-scroll, or
   on the wrong section looks authoritative while being wrong, and describing a
   section from a shot you never confirmed shows it is how a broken figure ships. On
   a tall page with a sticky nav, scroll the target into view, let it settle, and
   confirm the intended element is in the frame before trusting the shot.

7. Before presenting a `kind: plan` or `kind: report`, get a non-author verdict
   on the presentation. Spawn the `artifact-critic` subagent by name
   ([subagents/artifact-critic/AGENT.md](../../subagents/artifact-critic/AGENT.md));
   on a harness without named subagents, hand that definition to an independent
   `agents run` on another harness. Never review your own artifact from the
   authoring session. Resolve every BLOCKING finding, re-render, and let the
   critic record its verdict in the frontmatter as
   `review: {agent, session, verdict, findings}`. A plan is not presentable
   without `verdict: pass`; the plan-presentation hook checks for it. Only this
   block can answer a table warning.

8. Deliver a durable, obvious entry point. When the user asks to see it, open
   the finished HTML on their interactive machine with the configured viewer
   (`agents browser show <path-or-url> --json`). Check the result for the actual
   viewer or fallback. If rendering elsewhere, copy the self-contained HTML and
   any linked companion files into a dated durable artifact directory there;
   never write into a primary checkout. Give the exact entry link in the reply.

   For a visual change, include inspected before/after captures at comparable
   widths and states, with a short statement of the expected difference. For
   interaction, show the opened state or a short recording as well as the entry
   view. Label mockups as proposed and captures as observed; screenshots of a
   prototype do not prove a production rollout. If the interactive machine is
   unreachable, retain the files and report their exact paths.

9. Share only on explicit request:

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

Write `<selected artifact directory>/plan.md` with frontmatter shaped like:

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
implementation. Read [references/product-brief.md](references/product-brief.md)
for the product overview, goals, non-goals, journeys, and acceptance checks. Keep the floor headings below, in this relative order.
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
- independent-panel findings (ADOPTED / REJECTED, linked to `file:line`) when a panel ran
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
8. `## Risks` — concrete corner cases linked to `file:line` (misconfig, leaked
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

Also include one fenced code block and one `artifact-callout`. Treat warnings
about these as work to fix before presenting. A table is not a floor and never
was a substitute for the required behavior or architecture figure; choose other
forms by the reading-task guidance in step 3.
For multi-step plans, create the local harness task checklist before presenting;
this does not require creating or claiming tracker tickets during planning. The
Stop/plan-exit guard checks for it separately from the render.

## `kind: visual`

Write `<selected artifact directory>/<slug>.md` with `kind: visual`, a precise
title, and a short single-takeaway summary. Choose the page shape from the
content: infographic, explainer, status dashboard, data story, or comparison.

Make one hero figure the visual spine of the page. A table alone does not count.
Use `## Story`, optional `## Evidence`, and `## Figure`, with the hero figure under
`## Figure`. Choose supporting evidence by its job: excerpts, captures, charts, or exact-value
tables. Give it a clear reading order, labeled connectors or axes, a
caption, and — when color or line style carries meaning — direct labels on the
marks where the figure stays clean, or a legend when direct labels would clutter.

Use interaction to reveal structure, compare states, or inspect evidence while
keeping the main conclusion visible. Prefer a supported component with embedded
detail over a hand-built control. Show an explicit affordance and useful opened
state; hover alone must not hide essential information. Motion is optional and
must respect reduced motion. Do not ask authors to add scripts to Markdown:
the renderer owns behavior, and authored scripts are rejected.

Quantitative charts must use honest scales, units, source labels, and accessible
color choices. Use inline SVG for bespoke explanatory graphics; use the
project's established chart system when one exists.

Tell a story; let what you already know about visualization guide the piece. Name
the *Big Idea* in one sentence and the reader's *"so what"* before you chart, and
give the piece a narrative arc — beginning, tension, resolution or call to action.
Pick each visual by its job from the effective set — simple text or one big number,
table or heatmap, scatterplot, line, slopegraph, bar, stacked bar, waterfall — and
avoid donut, 3D, and dual-axis (pie only up to ~3 slices, matching `dataviz`'s
mechanics). *Declutter*: cut chartjunk, reduce cognitive
load, group with Gestalt proximity and alignment. Then steer the eye with
*preattentive attributes* (size, color, position) — gray the context and highlight
the one thing that matters in a single accent color, keeping labels next to the
marks they name. For the chart mechanics (palette, marks, accessibility) load the
`design` skill's `dataviz` mode; this is the storytelling layer on top of it.

## When the artifact recommends

Make the current problem, proposed result and reason for the change reviewable.
For visible UI changes, show a real current capture beside a product-faithful
proposed state or working prototype. Match the viewport and task; label what was
observed, inferred from code, proposed, or actually verified after implementation.
For behavior or architecture, show the relevant flow or relationship and retain
exact conditions in nearby prose. A simple recommendation can remain a sentence;
putting paragraphs inside SVG boxes does not improve communication.

Keep the comparison close to the recommendation, and attach the evidence that
lets the reader check it. Distinguish merged code from released and verified
behavior. Quantitative claims need sources and timeframes; estimated reductions
remain estimates until measured. Do not invent precision, causal links, module
breakdowns or live results to make a visual look complete.

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
- Recommendations include their rationale and evidence; visible changes have a
  comparable before/after or working demonstration. Quantities retain sources and
  timeframes. Interactive figures have been exercised in their opened states.
- The rendered HTML is self-contained and branded in light and dark themes.
- The output has been inspected headlessly at desktop and mobile widths.
- A plan or report carries `review:` with `verdict: pass` from the artifact
  critic, a session that is not the author's, and every table it still holds
  is one the critic accepted.
- No user browser was opened unless requested.
- Report the source path, HTML path, and any accepted warnings or share URL.
