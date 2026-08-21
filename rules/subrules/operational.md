# Operational Guardrails

- **Ask about scope; decide about implementation.** Unclear what the user wants
  → ask. Unclear how to build it → decide, state the reason in one line, keep
  going.
- **Rhythm: ACT → VERIFY → SHOW → CONTINUE.** See a problem, fix it — don't ask
  permission for obvious fixes.
- **Design before code — for *new* design only** (a UI flow, architecture, a
  pipeline shape). Follow-ups and edits go straight to code.
- **Waiting: echo/sleep only, never `Monitor` / `ScheduleWakeup` / `until`
  loops** (they fail silently). Short (<2 min): `cmd && sleep N && check &&
  echo "result: …"`. Long: `run_in_background: true` with a trailing
  finish-echo. Never say "I'll check back later".
- **No emojis** in code, comments, commits, or output — unless asked.
- **No credentials in env vars or config** — use `agents secrets`. Env vars are
  not a secure or configuration boundary: anything in them is visible ambient
  state. Configuration goes in real config files (`agents.yaml`, project
  config), and don't mint a new env var where a config entry, CLI flag, or
  function argument would do.
- **No locally built CLIs** — install globally.
- **No background shells left running** without an explicit finish signal.
- **No toasts.** Silent success, inline errors.
- **`/tmp` is banned for anything you produce.** The user comes back to agent
  output later, and `/tmp` gets wiped. Everything lands in the repo's
  `.agents/` workspace: `.agents/scratch/` for working files, screenshots, and
  one-shot scripts; `.agents/artifacts/yyyy-mm-dd/` for durable outputs (plans,
  reports, rendered HTML). Outside a repo, use `~/.agents/scratch/`.
- **No unsolicited .md files.** (Updating existing docs + CHANGELOG for a real
  user-visible change is required, not this — see F3.)
- **Permissions:** add permanent agent permissions to settings once; don't
  re-prompt the same action across sessions.
- **Images:** include the full file path so the user can click to preview.
- **Handing off a command the user must run**, in order: (1) clipboard
  (`pbcopy` / `xclip -selection clipboard` / `wl-copy`) — quote what you copied;
  (2) a one-shot script in `.agents/scratch/`, `chmod +x`, point them at it; (3)
  inline only as a last resort. Multi-line commands always go to a script.
- **Don't:** start/kill dev servers without asking; add unrequested
  backwards-compat shims; reach for `find` when `fd` is available.
