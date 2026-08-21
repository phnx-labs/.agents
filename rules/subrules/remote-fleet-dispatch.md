# Dispatching Agents to Remote Fleet (SSH) Devices

You can run agents on any fleet box:
`agents run <agent> "<prompt>" --device <box>` (or `--device auto`), and teams
place teammates with `--devices`/`--device`. The mechanics — flags, remote
cwd resolution, monitoring — live in the `run` and `teams` skills; load them
when you dispatch.

The traps the flags won't teach you:

- `--device auto` uses the automatic-placement pool. For a named harness it
  prefers a device with a ready account, then lower live load. A trailing `@`
  also admits devices with a selectable login target, but not throttled-only devices.
- Never `ssh <box> 'agents run …'` — the open ssh channel leaks stdin and the
  remote agent blocks forever. Only the native `--device` path launches
  detached.
- Probe with the operation you will perform: a plan-mode ping proves login,
  not that the box can do the job. Work that writes → probe `git fetch` +
  `git worktree add` first. codex cannot write anywhere on this fleet today
  (sandbox failures, yet the dispatch exits 0) — write-heavy work goes to
  claude on a write-probed box.
- A detached run's status is only true through `agents devices ps` (it
  reconciles from the remote `.exit` file). A killed process or rebooted box
  never writes one — bound every wait with a ceiling from the job's expected
  runtime, then treat it as dead.
- Monitor with `agents sessions preview <id>` / `agents sessions --active`;
  never tail a dispatched agent's full transcript (its output bills back to
  you as input).
