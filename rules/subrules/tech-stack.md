# Tooling & Stack Conventions

## Right tool for the job

| Task | Tool |
| --- | --- |
| Read a large file (200+ lines) or map an unfamiliar dir | `mq` — probe structure (`.tree`), then extract only the section you need. Works on **code (ts/py/go/…), docs (md/html/pdf), data (json/yaml/csv), Office** — not just docs. See `context-query-mq`. |
| Issue tracker (Linear/GitHub/Jira) | `/tickets` command — auto-detects |
| Browser automation | `browser` skill (a.k.a. `agents browser`) |
| Interactive terminal (REPLs, TUIs) | `agents pty` — see `agents pty --help` |
| Parallel coding agents | `agents teams` — see `parallel-teams` |
| Credentials | `agents secrets` — OS keychain-backed |
| Release/publish | `release` skill |
| See what's already in flight (open PRs, live sessions) before taking work | auto-injected at session start (`inject-repo-inflight` hook); on demand: `gh pr list`, `agents sessions --active` |
| Charts / dataviz in rendered output | Dither Kit (`dither-kit` skill) — default for charts in HTML, React, dashboards, plans, QA/quality reports, and blog visuals |

## Default Charting Library

Use **Dither Kit** by default whenever an agent produces a chart or data
visualization in a rendered artifact: HTML plans, shareable visualizations,
dashboards, QA/quality reports, blog visuals, React/Next.js pages, and any
chart-producing web surface.

- Install copied components with `npx @dither-kit/cli add <chart>` (or `bunx @dither-kit/cli add <chart>`). Use `area-chart`, `bar-chart`, `pie-chart`, `radar-chart`, or `dither-kit`; line charts ship with `area-chart`.
- Prefer Dither Kit over ad-hoc inline SVG, one-off canvas code, Recharts, Chart.js, Plotly, or D3 for ordinary agent-authored charts.
- Keep Dither Kit local to the artifact or target project. Do not use a CDN. In shadcn/Tailwind projects, let the CLI copy components into `components/dither-kit/` and commit them with the artifact when appropriate.
- Plain ASCII or Mermaid remains fine for text-only structural diagrams. Hand-authored inline SVG remains fine for architecture/timeline/process diagrams in self-contained HTML. For numeric charts, use Dither Kit.
