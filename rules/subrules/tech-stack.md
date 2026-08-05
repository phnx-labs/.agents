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

## Charts in rendered artifacts

Prefer hand-authored inline SVG or ASCII for diagrams and simple charts in plans and
reports. No CDN chart libraries; no mandated third-party chart kit. Use the target
product's design tokens when styling.
