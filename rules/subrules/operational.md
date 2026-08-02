# Operational Guardrails

> Small, load-bearing negatives and workflow mechanics. See `foundations` (F1–F5)
> for the stance; these are the tactics.

- **Ask about scope; decide about implementation.** Unclear what the user *wants* (requirements, scope, priorities)? Ask — 30 seconds beats hours of wrong work. Unclear *how* to implement what they asked for? Decide, state reasoning briefly, keep going (F1).
- **Workflow rhythm: ACT → VERIFY → SHOW → CONTINUE.** See a problem, fix it — don't ask permission for obvious fixes. Path clear? Take it, don't narrate. Unsure which path? Decide, state the reason in one line, continue (F1).
- **Design before code — for *new* design only** (a UI flow, architecture, a pipeline shape): show a mockup/diagram, then ship. For follow-ups and edits, skip it and go straight to code.
- **Waiting: echo/sleep only, never `Monitor` / `ScheduleWakeup` / `until` loops** (they fail silently). Short waits (<2 min): `cmd && sleep N && check && echo "result: …"`. Long waits (2+ min): `run_in_background: true` with a trailing finish-echo so you know the next action when it fires. Never say "I'll check back later" — the echo keeps you in the loop.
- **No emojis** in code, comments, commits, or user-facing output — unless explicitly asked.
- **No credentials in env vars or config.** Use `agents secrets` (OS keychain-backed).
- **No locally built CLIs.** Install globally (`npm i -g`, `cargo install`); don't invoke `./bin/foo`.
- **No background shells left running.** Foreground, or explicit `run_in_background` with a finish signal.
- **No toasts.** Silent success, inline errors.
- **No unsolicited .md files.** No README/docs/summary/notes unless asked. (Updating *existing* docs + CHANGELOG for a real user-visible change is required, not this — see F3.)
- **Permissions:** add permanent agent permissions to settings once; don't re-prompt the same action across sessions.
- **Images:** include the full file path so the user can click to preview.
- **Don't:** start/kill dev servers without asking; add backwards-compat shims you weren't asked for; reach for `find` when a faster finder like `fd` is available.
