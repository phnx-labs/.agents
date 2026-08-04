---
name: artifacts
description: "Author token-efficient plans, reports, and visuals as Markdown, then render them with artifacts-cli into branded light/dark HTML, tagged document or poster PDFs, and optional public shares. Triggers on: create an artifact, render this Markdown, Markdown plan, artifact report, visual report, poster PDF, artifacts-cli, or replace hand-written HTML with a reusable artifact template."
argument-hint: "[plan|report|visual] [source.md]"
user-invocable: true
author: Phoenix Labs
version: 0.1.0
license: Apache-2.0
---

# Artifacts

Use `artifacts` to keep the source concise and durable: write Markdown once, add
semantic HTML or inline SVG only where layout requires it, then compile the same
source to responsive HTML and PDF. Do not hand-author a complete HTML document.

## Choose The Artifact

- `plan`: implementation intent, public interface, validation, risks, tracking.
- `report`: findings, evidence, and recommendations.
- `visual`: an infographic, comparison, diagram, or poster-led explanation.

Use the user's requested kind. Otherwise choose from the content, not the desired
output format; every kind can compile to HTML and PDF.

## Workflow

1. Check the installed tool:

   ```bash
   command -v artifacts
   ```

   If `artifacts` is missing, report that concrete prerequisite. Do not replace
   it with a hand-written HTML fallback.

2. Write the Markdown source directly. The only required frontmatter is `kind`
   (plan, report, or visual) and `title`; `template` is inferred and provenance
   (project, repository, branch, harness, agent, human, host, session, date)
   auto-fills at render time from the Git checkout and agent environment.
   Declared values always win — declare `tracking`, `status`, `facts`, `header`,
   `footer`, or any provenance value you want to control. Follow the section
   structure for the kind (`artifacts template <kind>` shows it), or scaffold
   the whole file with `artifacts new <kind> --out <source.md>`. Do not repeat
   provenance in the body. Use normal headings, lists, tables, images, and fenced
   code. Reach for direct HTML only for grids, panels, figures, and callouts;
   reach for inline SVG for architecture, timelines, process diagrams, and other
   semantic figures. **Illustrate actively**: any concept that has structure —
   actors, layers, flows, comparisons, states — gets a real SVG figure, not a
   paragraph approximation. A figure earns its place with tinted concept boxes,
   labeled connectors, and a caption that names the reading order; follow the
   palette and layout recipe in
   [references/authoring.md](references/authoring.md#diagram-recipe) so figures
   look designed rather than incidental. Read
   [references/authoring.md](references/authoring.md)
   before adding HTML or SVG.

3. Render in one step:

   ```bash
   artifacts render <source.md>                          # writes <source>.html next to it
   artifacts render <source.md> --format html,pdf        # both outputs
   artifacts render <source.md> --format pdf --layout poster
   ```

   Use `document` layout for paginated plans and reports, `poster` for visuals
   or when the user asks for one continuous page. Errors fail the render; fix
   them at the Markdown source or `DESIGN.md`, never by editing generated HTML.

4. Inspect the actual output headlessly. Verify both themes, desktop and mobile
   widths, image loading, diagram bounds, document overflow, and browser console
   errors. Use the available headless browser or screenshot tooling. Do not run
   `artifacts preview`, `open`, or another interactive-browser command unless the
   user explicitly asked for the artifact to be opened. Rasterize representative
   PDF pages and look for clipped code, split figures, missing backgrounds, or
   blank media.

5. Share only on explicit request:

   ```bash
   artifacts share <source.md> --expire 30d
   ```

   Shared links are public and unlisted, not private. Never place credentials in
   Markdown or `DESIGN.md`; use the configured share endpoint or
   `ARTIFACTS_SHARE_TOKEN`.

## Helpers

- `artifacts new <kind> --out <source.md>` — scaffold the frontmatter and
  section skeleton instead of writing it by hand.
- `artifacts init design` — adopt project-wide branding (`DESIGN.md`). Preserve
  an existing `DESIGN.md`; it owns both light and dark palettes, typography,
  density, radius, layout spacing, content width, and print margins. If exact
  fonts are required but unavailable, add local font files or register a
  directory with `artifacts setup --fonts-dir <dir>`; otherwise retain and
  report the emitted fallback-font warning.
- `artifacts check <source.md>` — validate without rendering.
- `artifacts estimate <source.md>` — exact `o200k_base` Markdown-versus-rendered
  token counts when the user asks about authoring-token cost.

## Completion Contract

- Markdown remains the source of truth; generated HTML/PDF are build outputs.
- Metadata appears once in frontmatter and renders into the document chrome.
- Existing project branding is preserved in both light and dark themes.
- `artifacts check` exits successfully, with any accepted warnings named.
- The rendered HTML has been inspected at desktop/mobile widths and in both themes.
- The requested PDF layout has been raster-inspected, not merely generated.
- No user browser was opened unless explicitly requested.
- Report the source, HTML, PDF, and optional share paths or URLs.
