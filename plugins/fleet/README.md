# fleet plugin

Fleet-wide operations across every machine you've registered with `agents devices`.
Curated, tested recipes on top of the `agents devices` / `agents repo` primitives —
the value is the exact sequence, the per-platform handling, and the guardrails, so no
one has to re-derive them live.

This plugin manages the *fleet as a whole* (keeping many machines in parity). For
single-machine repo/agent management use the built-in `agents repos` / `agents repo`
commands; for wiring up SSH/Tailscale access use the [`devices`](../../skills/devices/)
skill.

## Requirements

- [`agents-cli`](https://github.com/phnx-labs/agents-cli) installed and on `$PATH` on
  the orchestrating machine, and reachable devices registered (`agents devices list`).
- SSH reach to each device (Tailscale or otherwise) — `agents ssh <dev>` works.
- `git` on each device, with its DotAgent repos already cloned (that's what
  `fleet:onboard` will bootstrap; `fleet:sync` assumes they exist).

## Commands

| Command | What it does |
| --- | --- |
| `/fleet:sync` | Pulls **every registered DotAgent repo** (`system`, `user`, and any extra) to `origin` latest on **every online device**, then refreshes the installed agents. Non-destructive: `git merge --ff-only` only — it reports repos blocked by local edits instead of clobbering them. Handles the fast-forward workaround (`agents repo pull` doesn't FF), the transient GitHub-SSH throttle (retry once), and Windows PowerShell quoting. Ends with a repo × device matrix. |
| `/fleet:onboard <device>` | Brings a **bare new device** up to fleet parity: introspects a healthy reference node, then installs agents-cli, the agent CLIs, the DotAgent repos, the shared fleet SSH key, the non-interactive PATH shim, the device registration, and agent auth. **Discovery-first** — it reads `agents <cmd> --help` + `agents doctor` at run time rather than hardcoding a CLI surface that drifts. Additive + idempotent (installs only what's missing). Credentials via sanctioned paths only (`agents secrets`, `agents profiles login`, the agent's native login, `agents setup`) with explicit authorization — **never** copied host-to-host. |

## Safety bar

One hard line: **never clobber local work**.

`/fleet:sync` uses `git merge --ff-only` and nothing else — never `reset --hard`,
`checkout -- .`, `clean`, `stash`, `pull`, or any `--force`, not even to make a
stubborn repo advance. `user` and team repos are user-authored and each machine
carries different local drift; a repo that can't fast-forward is *reported*, not
forced. Sync never auto-commits or pushes a device's local edits (that's a separate,
explicit `--push` opt-in). Offline devices are reported, never block the rest.
