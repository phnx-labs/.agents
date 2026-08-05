---
name: plan-render
description: "Render an implementation plan as a beautiful, self-contained HTML doc by authoring Markdown and compiling it with artifacts-cli. Produces interactive inline-SVG figures, branded light/dark output, and opens it in the user's default browser. The Markdown source lives in the repo's .agents/artifacts/plans/ directory. Triggers on: render a plan, present a plan, plan-as-HTML, open the plan in the browser, plan mode, show the plan visually."
argument-hint: "[topic]"
allowed-tools: Bash(scp*), Bash(agents ssh*), Bash(agents browser*), Bash(open*), Bash(xdg-open*), Bash(find*), Bash(cp*), Bash(mkdir*), Bash(test*), Bash(git rev-parse*), Bash(artifacts*), Write
user-invocable: true
---

# plan-render — plans as browser-ready HTML via artifacts-cli

Every implementation plan should be a beautiful, reviewable HTML page that opens in the user's browser. The source of truth is **Markdown**: concise, token-efficient, and durable. The rendering is handled by `artifacts-cli`.

## Non-negotiable quality bar (read this first)

A plan HTML that is **only prose + inline `code` pills** is a failed delivery.
Both the compiler and the ExitPlanMode gate now enforce this:

| Must have | Why | Enforced by |
| --- | --- | --- |
| ≥1 **live** inline SVG with drawn elements (`rect`/`path`/`text`/…) | Reviewers need a figure, not a wall of bullets | `artifacts check` **error**; plan-html-reminder greps the HTML |
| ≥1 Markdown **table** (files / risks / validation) | Scanability | `artifacts check` warning |
| ≥1 **fenced** code block for commands/APIs | Inline `` `code` `` alone has no highlighting surface | `artifacts check` warning |
| ≥1 `artifact-callout` | Load-bearing takeaway | `artifacts check` warning |

Do **not** present until `artifacts render` exits 0 (it no longer writes HTML on validation errors). Do **not** leave empty SVG shells from the template — fill them with a real diagram.

**Anti-pattern (what just bit us):** dump issue notes as Markdown bullets, run `artifacts render`, open the HTML. That produces a dark page of monochrome pills with no figures and no code wells — unreadable.

## Output

- **HTML only** — no PDF is produced.
- **Destination** — write the Markdown source and rendered HTML into the repo's `.agents/artifacts/plans/` directory (create it if missing).
- **Self-contained** — the HTML has inline CSS, no CDN, and opens offline.

## Workflow

1. **Check the tool.**

   ```bash
   command -v artifacts
   ```

   If `artifacts` is missing, install artifacts-cli first and report the prerequisite.

2. **Resolve the repo root and artifact home.**

   ```bash
   ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
   ARTIFACTS_DIR="${ROOT:-.}/.agents/artifacts/plans"
   mkdir -p "$ARTIFACTS_DIR"
   ```

3. **Author the Markdown source.**

   Write `"$ARTIFACTS_DIR/plan-<slug>.md"` with at least this frontmatter:

   ```yaml
   ---
   kind: plan
   title: <plain, factual headline>
   summary: <~3-line problem statement and intended outcome>
   status: draft | implementing | awaiting-go
   tracking: "#<ticket-or-issue>"
   facts:
     - <key fact>
     - <key fact>
   ---
   ```

   Use the section structure required by the `plan` template:

   - `## Purpose` — what's broken or needed
   - `## Proposed Changes` — the change, with concrete files and functions
   - `## Public Interface` — commands, flags, or APIs introduced
   - `## Validation` — how to verify the change
   - `## Risks` — edge cases and mitigations
   - `## Tracking` — ticket links / next step

   A tagged files table and any other supporting tables can appear inside the relevant section.

   Use normal Markdown for prose, lists, tables, and code. Use inline HTML only for layouts Markdown cannot express (grids, panels, callouts) and **inline SVG for figures**.

4. **Make the figures interactive and beautiful.**

   The rendered HTML should look like a polished artifact, not a document. Use inline SVG liberally for:

   - architecture diagrams
   - timelines
   - before/after comparisons
   - flow charts
   - state machines

   Add interactivity where it helps readability:

   - **SMIL animation** for motion, geometry, transform, or paint changes
   - **CSS hover states** for emphasis or revealing detail
   - **clickable layers** or tabs for alternate views
   - **progressive disclosure** with `<details>` / `<summary>` blocks

   Every figure needs a clear reading order, labeled connectors, a caption, and a legend when color or line-style carries meaning. Follow the diagram conventions in `diagram-conventions.md` (this skill dir).

5. **Render to HTML.**

   ```bash
   SOURCE="$ARTIFACTS_DIR/plan-<slug>.md"
   artifacts render "$SOURCE" --format html
   ```

   This writes `plan-<slug>.html` next to the source.

6. **Inspect the output headlessly.**

   Open the rendered HTML in a headless browser and check:

   - both light and dark themes render correctly
   - desktop and mobile widths reflow cleanly
   - SVG figures are visible and animated/interactive elements work
   - no browser console errors

7. **Deliver it to the user's machine.**

   Resolve the online macOS device from the Host & Fleet context (never hardcode). If already on that machine, open directly; otherwise copy the HTML over:

   ```bash
   scp "$ARTIFACTS_DIR/plan-<slug>.html" <host>:/tmp/plan-<slug>.html
   agents ssh <host> 'open /tmp/plan-<slug>.html'
   ```

   Also copy the HTML into `~/Downloads` on the viewer's machine for portability:

   ```bash
   cp "$ARTIFACTS_DIR/plan-<slug>.html" "$HOME/Downloads/plan-<slug>.html"
   ```

   If there is no reachable browser host, still write the durable source + HTML and tell the user the exact path.

## Design and theming

- Use `artifacts init design` to create a project-wide `DESIGN.md` if one does not exist.
- Preserve an existing `DESIGN.md`; it owns both light and dark palettes, typography, density, radius, and layout spacing.
- Probe the target repo for brand tokens (design-system.css, tailwind config, logo/favicon colors) and reflect them in `DESIGN.md`.
- The light/dark toggle must be present and default to `prefers-color-scheme`.

## Voice

- The headline states plainly what the plan does.
- Name concrete files, functions, flags, and error strings.
- No marketing register: no "seamless", "powerful", "robust", "leverage", "simply".
- At most one em-dash per paragraph; never stack appositive dashes.

## Completion contract

- [ ] Markdown source written to `.agents/artifacts/plans/plan-<slug>.md` (not `/tmp/scratchpad`)
- [ ] `artifacts check` reports **no errors** (figure present; required sections present)
- [ ] HTML rendered next to the source with `artifacts render ... --format html` (exit 0)
- [ ] Grep the HTML: at least one `<svg` with a drawn primitive; at least one `<pre`/`<table`
- [ ] Output inspected headlessly in both themes and at desktop/mobile widths
- [ ] HTML opened on the user's machine and copied to `~/Downloads`
- [ ] Source, HTML path, and any warnings reported to the user
