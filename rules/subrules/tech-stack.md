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

**Reach for the real-UI tools by reflex, not on request.** A task that touches
a web surface — a form, a dashboard, a signup, a docs page, a purchase, a
scrape — starts with `agents browser` (headless on YOUR machine; the user's
browser only to SHOW them something, one reused tab). A task that touches a
native app starts with `agents computer` (element mode, focus-safe).
Describing what a page probably says, curl-guessing an HTML form, or handing
the user steps to click is the failure; drive the surface yourself first. If
you catch yourself writing "you could open …" — open it.
