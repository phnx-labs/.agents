---
name: workweave
description: "Render a fast, private WorkWeave-style engineering-intelligence report from every locally indexed agent session for the current repository. Reuses agents sessions, insights, output, cost, resource stats, hook/command latency, and guard-friction engines; writes Markdown + HTML and opens the result. Triggers on: /yc:workweave, workweave report, project agent analytics, engineering intelligence dashboard, chart our agent sessions."
allowed-tools: Bash(agents sessions*), Bash(agents insights*), Bash(agents perf*), Bash(agents browser*), Bash(artifacts *), Bash(git *), Bash(jq *), Bash(mkdir *), Bash(date *), Bash(bun *), Read(*), Write(*)
---

# yc:workweave

Turn data agents-cli already keeps locally into a decision-useful engineering-intelligence
report. This is a composed view over existing engines, not a new analytics pipeline.

## 1. Resolve scope

Require a Git repository. Resolve the canonical project key from the origin repository name
so linked-worktree directory names do not split one project into several dashboards.

```bash
ROOT=$(git rev-parse --show-toplevel)
ORIGIN=$(git remote get-url origin)
PROJECT=$(basename "${ORIGIN%.git}")
DATE=$(date +%F)
OUT="$ROOT/.agents/artifacts/$DATE"
WINDOW=30d
mkdir -p "$OUT/workweave-data"
```

Parse `$ARGUMENTS` exactly:

- `--since <window>` controls time-windowed engines; default `30d`.
- `--since all` uses all history where supported. For an engine that does not accept `all`,
  derive the earliest timestamp from the session census and pass that ISO date.
- `--no-open` renders and inspects without opening the user's browser.
- Reject unknown arguments with the accepted forms instead of silently ignoring them.

Set `WINDOW` to the parsed `--since` value when supplied. The session census is always
all-time for `PROJECT`, independent of the chart window.

## 2. Refresh the local index and collect once

Do not read transcript files directly. The bundled collector scans registered harness roots,
updates changed sessions in the local index, paginates through every row, strips identity,
paths, session IDs, topics, and recovery metadata in memory, then runs the independent JSON
engines in parallel. It records optional-engine failures as gaps instead of fabricating
zeros. The durable evidence contains projected aggregate fields only; never paste transcript
bodies into the report.

```bash
SKILL_DIR="$HOME/.agents/plugins/yc/skills/workweave"
[ -d "$SKILL_DIR" ] || SKILL_DIR="$HOME/.agents/.system/plugins/yc/skills/workweave"
bun "$SKILL_DIR/scripts/collect.ts" --since "$WINDOW" --project "$PROJECT" \
  --out "$OUT/workweave-data/report.json"
```

For `--since all`, derive `DAYS` from the earliest session, with a minimum of 1. Otherwise
convert the accepted day/week/month window to whole days. Read `report.json` before writing
conclusions. Its `gaps` object names unavailable optional engines; disclose each gap and
continue with the other real data. Never replace it with a fabricated zero. The session
census and `artifacts` are required and fail loud.

If `resources.json` reports low historical coverage, run
`agents sessions backfill resources`, re-run both resource queries, and disclose the
backfill. Do not run transcript-content `--narrative`; synthesis stays local in this agent.

## 3. Select the current project honestly

The session census, resources, hooks, and commands are directly project-filtered. The
behavior engine groups by project: select only the exact `PROJECT` group from its JSON before
charting. Canonical project cost, generated output, duration, harness mix, model mix, and
daily activity come from `sources.sessionMetrics`, aggregated from the sanitized census.
Never add together unrelated projects.

The direct mix recipes and `agents perf friction` currently have no project filter. Include
useful panels from them only with a visible **fleet-wide** label. `shippedOutput` is optional
because older installed CLI versions ignore nested `--json`; when it is in `gaps`, show
project session output/cost but state that PR/commit attribution is unavailable. Do not imply
fleet-wide figures belong only to this repository.

## 4. Build an outcome-first visual report

Load the top-level `artifacts` skill and follow its report contract. Write
`$OUT/workweave-$PROJECT.md`; Markdown is the source of truth and HTML is generated output.
Use exact values from the JSON and keep raw evidence linked by relative path.

The first viewport must work as a dashboard, not a document cover followed by prose. Use a
short one-line title and a one-sentence frontmatter summary. Put `## Pulse` before the
template-required `## Summary`; the metric grid is the first content under `## Pulse`, with no
introductory paragraphs above it. Put the shared window/project in card labels and one concise
caption below the grid, then show the first trend chart before methodology. Use
`sources.sessionComparison` for prior-period deltas. Show `n/a` when the previous period is
empty; do not turn division by zero into a 100% change.

Use this reading order:

1. **Pulse** — a dense two-row metric strip for generated tokens, recorded cost, cache savings,
   session hours, sessions, and active days. Each label states the window and the unit; each
   supported metric shows its previous-window delta.
2. **Engineering outcomes** — shipped PRs/commits, code-review or quality evidence, and cost per
   shipped unit when the installed CLI exposes them. If unavailable, render one compact gap card
   naming the missing engine. Never put token volume in a card labeled “engineering output”.
3. **Activity over time** — a wide linear-scale chart of daily sessions, generated tokens, and
   cost. Use aligned small multiples rather than a dual axis. Mark the prior-window baseline.
4. **Harness + model composition** — two compact charts with exact session, generated-token,
   and cost shares. Prefer ranked horizontal bars over decorative pies.
5. **Efficiency** — actual versus no-cache cost, generated tokens per dollar, duration, and
   shipped units when available. State that correlation is not causation.
6. **Process** — project-scoped hook p50/p95/p99, total observed hook time, block rate, slow CLI
   commands, and repeated retries. Rank by avoidable time, not invocation count.
7. **Friction + opportunities** — repeated failures/guard loops, behavioral actions, most-used
   resources, and never-invoked resources. Mark fleet-wide evidence on the panel itself.
8. **Method + caveats** — window, project key, generated timestamp, engine commands, coverage,
   missing fields, and the distinction between agent activity and shipped engineering work.

### Visual contract

- Build **at least eight semantic figures**: one dashboard metric strip, one activity trend,
  two composition charts, one cost comparison, two process charts, and one ranked opportunity
  figure. A figure may contain aligned small multiples when they share a scale or question.
- Make charts carry the explanation: concise title, one-sentence metric definition, exact
  headline value, plot, source/scope label. Do not introduce a chart with a paragraph wall.
- Use a restrained flat palette, thin borders, no glow, no gradients, no decorative icons, and
  no card that contains only a generic label. Preserve the artifacts light/dark themes.
- Use an 8/12/16/24/32 spacing rhythm. Keep related cards in two- or three-column
  `artifact-grid` layouts on desktop and one column on mobile. Avoid a six-card grid followed by
  large empty vertical gaps.
- A metric name must describe its actual unit: **generated tokens**, **session cost**, **session
  hours**, **merged PRs**, **review cycles**. “Output” alone is forbidden unless the value is a
  shipped-work measure.
- Every chart needs `viewBox`, `role="img"`, `aria-label`, exact value labels, a text legend,
  and a zero baseline. Use no CDN, Mermaid, hidden tooltip, or dual axis. Color is never the only
  encoding. Use the same scale for directly compared bars.
- Keep the report self-contained and selectable. Do not embed screenshots of another product or
  imitate its navigation, logo, proprietary score, or orange palette.

Never expose account emails, absolute home paths, session IDs, transcript excerpts, tokens,
or secrets. Aggregate accounts and machines unless the user explicitly asks for a private
drill-down.

## 5. Render, inspect, and open

```bash
artifacts check "$OUT/workweave-$PROJECT.md"
artifacts render "$OUT/workweave-$PROJECT.md"
```

Inspect the real HTML at desktop and mobile widths and in both themes. Confirm every chart
is visible, labels do not collide, there is no page overflow, and the console is clean.
Fix the Markdown and re-render; never edit generated HTML. Capture real proof into
`$OUT/workweave-screens/`: desktop overview, desktop process/diagnostics, desktop findings,
and mobile overview. Use screenshots of the rendered report itself, not mockups. Keep account,
machine, and session identity out of every capture.

Unless `--no-open` was passed, reuse one browser tab:

```bash
agents browser navigate --url "file://$OUT/workweave-$PROJECT.html"
```

Finish with the exact window/project, 3–5 decision-useful findings grounded in quoted
figures, caveats, absolute Markdown/HTML paths, and the four screenshot paths. Put the desktop
overview screenshot in front of the user when the harness supports images. Do not publish or
share the report unless the user explicitly asks.
