# Tooling & Stack Conventions

Right tool for the job:

| Task | Tool |
| --- | --- |
| Issue tracker (Linear/GitHub/Jira) | `tickets` skill — auto-detects |
| Browser automation | `browser` skill (`agents browser`) |
| Interactive terminal (REPLs, TUIs) | `agents pty` |
| Parallel coding agents | `agents teams` — see `parallel-teams` |
| Credentials | `agents secrets` — OS keychain-backed |
| Release/publish | `/code:release` |
| What's already in flight | injected at session start; `gh pr list`, `agents sessions --active` |

Charts in rendered artifacts: hand-authored inline SVG or ASCII. No CDN chart
libraries; style with the target product's design tokens.
