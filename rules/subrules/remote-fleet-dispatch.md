# Dispatching Agents to Remote Fleet (SSH) Devices

```bash
agents run <agent> "<prompt>" --device <box> --remote-cwd <ABS repo path> --mode <mode> --name <handle>
```

- **Never `ssh <box> 'agents run …'`** — the open ssh channel leaks stdin and
  the remote agent blocks forever. The native `--device` path launches detached
  and survives dropped connections. `--device auto` picks by affinity +
  headroom; name a box only when the task needs that machine.
- Fleet devices (SSH/Tailscale, `agents devices`) are not cloud devices
  (`rush cloud` / codex-cloud pods) — different commands and lifecycle.
- `--remote-cwd` must be an absolute git-repo path that exists ON the remote.
  Resolve the remote home first (`agents ssh <box> 'echo $HOME'`) — a bare
  `~`/`$HOME` expands on the local box and silently targets a nonexistent path.
  (`agents run` only; teammates use `--worktree` or `--cwd`.)
- Dispatch whichever harness is confirmed working on the box — spreading across
  harnesses is the point of the fleet, not more clones of yourself.

**Probe with the operation you will actually perform.** A `--mode plan` ping
proves install + login, nothing more — capability differs per operation class.
If the work writes, probe a real write (`git fetch` + `git worktree add`); a PR
→ probe a commit; a credential → a real authenticated request. Known trap:
codex cannot write anywhere on this fleet (bwrap uid-map failure on Linux,
sandbox denial on macOS) yet the dispatch exits 0 — send write-heavy work to
claude on a write-probed box; codex stays fine for read-only analysis. Never
silently escalate to a sandbox-off flag to dodge a failure — move to a
box/harness that works and say the box changed.

**Detached (`--no-follow`) runs:** status is only true through
`agents devices ps` (it reconciles from the remote `.exit` file; the raw cache
under `~/.agents/.cache/hosts/` stays "running" forever). A killed process or
rebooted box never writes `.exit`, and no command rescues that record — so
bound every wait with a ceiling from the job's expected runtime, then treat it
as dead (`agents devices stop <id>`) or probe the pid directly
(`ssh <host> 'ps -p <pid>'`). Dispatch records are local to the box that
dispatched. Harvest with `agents logs <id>` once status leaves running.

**Monitor at the service level** — `agents sessions preview <id>` for the
brief, `agents sessions --active` for the fleet. Never cat/tail a dispatched
agent's full transcript (its output bills back to you as input); pull the raw
log only to grep the single failing line.
