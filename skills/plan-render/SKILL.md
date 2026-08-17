---
name: plan-render
description: "Render an implementation plan as a beautiful, self-contained HTML doc by authoring Markdown and compiling it with artifacts-cli. Produces interactive inline-SVG figures, branded light/dark output, and opens it in the user's default browser. The Markdown source lives under the repo's dated artifact layout: .agents/artifacts/yyyy-mm-dd/. Triggers on: render a plan, present a plan, plan-as-HTML, open the plan in the browser, plan mode, show the plan visually."
argument-hint: "[topic]"
allowed-tools: Bash(scp*), Bash(agents ssh*), Bash(agents browser*), Bash(open*), Bash(xdg-open*), Bash(find*), Bash(cp*), Bash(mkdir*), Bash(test*), Bash(git rev-parse*), Bash(artifacts*), Write
user-invocable: true
---

# plan-render — plans as browser-ready HTML via artifacts-cli

Every implementation plan should be a beautiful, reviewable HTML page that opens in the user's browser. The source of truth is **Markdown**: concise, token-efficient, and durable. The rendering is handled by `artifacts-cli`.

## Non-negotiable quality bar (read this first)

A plan HTML that is **only prose + inline `code` pills** is a failed delivery.
Both the compiler and the cross-harness presentation gate enforce this:

| Must have | Why | Enforced by |
| --- | --- | --- |
| `surface` frontmatter | The validator must know whether architecture or product behavior is the review surface | `artifacts check` **error** |
| Current + proposed product views for non-`internal` plans | Reviewers see the actual behavior change, not a prose approximation | `artifacts check` **error**; plan-html-reminder checks semantic HTML |
| ≥1 **live** drawn SVG for `internal` plans | Reviewers need a real architecture/flow/state figure | `artifacts check` **error** |
| A drawn figure **inside** every `## …architecture…` section | A row-per-module table lists the parts and drops every relationship between them — which module calls which, where a contract is duplicated, what the change moves. The check is scoped to the section, so a figure under `## Proposed Changes` does not cover it; a `###` subsection inside it does | `artifacts check` **error** |
| ≥1 Markdown **table** (files / risks / validation) | Scanability | `artifacts check` warning |
| ≥1 **fenced** code block for commands/APIs | Inline `` `code` `` alone has no highlighting surface | `artifacts check` warning |
| ≥1 `artifact-callout` | Load-bearing takeaway | `artifacts check` warning |

Do **not** present until `artifacts render` exits 0. User-visible plans show both
current and proposed product views. Prefer captured screenshots or terminal output;
when capture is impossible, use a faithful mockup labeled `data-evidence="mockup"`.
Architecture diagrams do not substitute for behavior views.

**Anti-pattern (what just bit us):** dump issue notes as Markdown bullets, run `artifacts render`, open the HTML. That produces a dark page of monochrome pills with no figures and no code wells — unreadable.

## Output

- **HTML only** — no PDF is produced.
- **Destination** — write the Markdown source and rendered HTML under `.agents/artifacts/yyyy-mm-dd/` (create the date dir if missing). Same layout as any related artifact.
- **Self-contained** — the HTML has inline CSS, no CDN, and opens offline.

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

3. **Author the Markdown source.**

   Write `"$ARTIFACTS_DIR/plan-<slug>.md"` (i.e. `.agents/artifacts/yyyy-mm-dd/plan-<slug>.md`) with at least this frontmatter:

   ```yaml
   ---
   kind: plan
   surface: internal | cli | web | native | api | workflow
   title: <plain, factual headline>
   summary: <~3-line problem statement and intended outcome>
   status: draft | implementing | awaiting-go
   tracking: "#<ticket-or-issue>"
   facts:
     - <key fact>
     - <key fact>
   ---
   ```

   Follow the planning contract in the `plan-presentation` rule for the section
   order and the pre-present gates. On top of the `plan` template's sections, a plan
   leads with **Focus for review** (what you want weighed in on) and **Intent** (the
   user's ask restated), and carries a **Current architecture** section, drawn as a
   figure (before and after when the plan changes the shape):

   - `## Focus for review` — 2-5 bullets, at the very top
   - `## Intent` — the user's ask in their own words
   - `## Current architecture` — how the modules work today and how they talk to each
     other, **drawn** (boxes for the modules, arrows for what calls what; before/after
     when the plan changes the shape). `artifacts check` errors when this section has
     no figure — a table of files is not an architecture. Keep a table alongside the
     figure for per-file detail if it helps; it does not replace the figure.
   - `## Purpose` — what's broken or needed
   - `## Proposed Changes` — the change, with a **per-file diff** of each change
     (use the `code-diff` component: collapsible, +/- coloured, line numbers — see below)
   - `## Public Interface` — commands, flags, or APIs introduced
   - `## Plan` — the to-do checklist, mirrored from `TaskCreate` (rendered, with status)
   - `## Validation` — how to verify the change
   - `## Risks` — edge cases and mitigations
   - `## Tracking` — ticket links / next step

   **Show the implementation as real code, not a file table.** For each file that
   changes, render the actual change as a diff — the relevant hunk only, added lines
   green, removed lines red — with the `code-diff` component. Until artifacts-cli ships
   it, fall back to a fenced ```` ```diff ```` block (do not put fenced code inside
   `<details>` — artifacts-cli drops it). Render the to-do list with the `checklist`
   component (fall back to a `- [ ]` task list).

   Use normal Markdown for prose, lists, tables, and code. Use inline HTML only for layouts Markdown cannot express (grids, panels, callouts) and **inline SVG for figures**.

4. **Show the behavior, then supporting architecture.**

   For `cli`, `web`, `native`, `api`, and `workflow`, include one
   `.artifact-behavior` figure with `data-state="current"` and
   `data-state="proposed"`. Give each state `data-evidence="capture"` or
   `data-evidence="mockup"`. Match the real product layout, components, typography,
   and output; a conceptual box diagram does not count.

   For `internal`, use a real architecture, flow, timeline, or state figure.

5. **Make supporting figures interactive and beautiful.**

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

6. **Render to HTML.**

   ```bash
   SOURCE="$ARTIFACTS_DIR/plan-<slug>.md"
   artifacts render "$SOURCE"
   ```

   This writes `plan-<slug>.html` next to the source.

7. **Inspect the output headlessly.**

   Open the rendered HTML in a headless browser and check:

   - both light and dark themes render correctly
   - desktop and mobile widths reflow cleanly
   - SVG figures are visible and animated/interactive elements work
   - no browser console errors

8. **Deliver it to the user's machine.**

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

- Use `artifacts new design` to create a project-wide `DESIGN.md` if one does not exist.
- Preserve an existing `DESIGN.md`; it owns both light and dark palettes, typography, density, radius, and layout spacing.
- Probe the target repo for brand tokens (design-system.css, tailwind config, logo/favicon colors) and reflect them in `DESIGN.md`.
- The light/dark toggle must be present and default to `prefers-color-scheme`.

## Voice

- The headline states plainly what the plan does.
- Name concrete files, functions, flags, and error strings.
- No marketing register: no "seamless", "powerful", "robust", "leverage", "simply".
- At most one em-dash per paragraph; never stack appositive dashes.

## Completion contract

- [ ] Markdown source written to `.agents/artifacts/yyyy-mm-dd/plan-<slug>.md` (not `/tmp/scratchpad`)
- [ ] `surface` declares the review surface; non-internal plans show current + proposed capture/mockup evidence
- [ ] `artifacts check` reports **no errors** (surface + required sections present)
- [ ] HTML rendered next to the source with `artifacts render <source>.md` (exit 0)
- [ ] Grep the HTML: internal plan has a drawn SVG, or user-visible plan has `.artifact-behavior` plus current/proposed evidence; at least one `<pre`/`<table`
- [ ] Output inspected headlessly in both themes and at desktop/mobile widths
- [ ] HTML opened on the user's machine and copied to `~/Downloads`
- [ ] Source, HTML path, and any warnings reported to the user
