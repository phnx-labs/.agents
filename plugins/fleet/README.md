# fleet plugin

Fleet-wide operations across every machine you've registered with `agents devices`.
Curated, tested recipes on top of the `agents devices` / `agents repo` primitives —
the value is the exact sequence, the per-platform handling, and the guardrails, so no
one has to re-derive them live.

This plugin manages the *fleet as a whole* (keeping many machines in parity). For
single-machine repo/agent management use the built-in `agents repos` / `agents repo`
commands; for wiring up SSH/Tailscale access use `agents devices --help`
(`sync` / `register` / `config`) — the fleet device registry is also injected into every
session by the device-topology session-start hook.

## Requirements

- [`agents-cli`](https://github.com/phnx-labs/agents-cli) installed and on `$PATH` on
  the orchestrating machine, and reachable devices registered (`agents devices list`).
- SSH reach to each device (Tailscale or otherwise) — `agents ssh <dev>` works.
- `git` on each device, with its DotAgent repos already cloned (that's what
  `fleet:onboard` will bootstrap).

## Commands

| Command | What it does |
| --- | --- |
| `/fleet:onboard <device>` | Brings a **bare new device** up to fleet parity: introspects a healthy reference node, then installs agents-cli, the agent CLIs, the DotAgent repos, the shared fleet SSH key, the non-interactive PATH shim, the device registration, and **mints its agent auth in the same flow** — the token-minting recipes (native device/OAuth login in a per-device account slot, verified by the resulting email; Claude setup-token / API-key as the syncable alternative) are folded into the command itself, no user hand-off. **Discovery-first** — it reads `agents <cmd> --help` + `agents doctor` at run time rather than hardcoding a CLI surface that drifts. Additive + idempotent (installs only what's missing). Provider credentials provisioned via `agents accounts add`/`agents accounts sync`; OAuth flows run natively on the target; native auth material never copied host-to-host. |
| `/fleet:profile [menubar|daemon|doctor|sessions]` | Profile a sluggish machine, attribute the load to agents-cli surfaces (daemon, menu-bar, doctor/sessions pollers), read the logs to root-cause it, and file a GitHub issue on the public agents-cli repo. Optional focus narrows to one surface. |
