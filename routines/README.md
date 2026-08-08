# Routines

Scheduled agent runs. A routine fires on a **clock** — a cron schedule or a one-shot time.
The scheduler daemon starts on the first `agents routines add`.

If you want something to fire on a **change** instead of a clock, that is a
[monitor](../skills/monitors/SKILL.md), not a routine.

## What ships here

| Routine | Schedule | What it does |
|---|---|---|
| [`check-updates`](./check-updates.yml) | Mondays 09:00 | Keeps the box current — upgrades `agents-cli` when npm is ahead, fast-forwards `~/.agents/.system` to `origin/main`, and notifies only if something actually changed |
| [`watchdog`](./watchdog.yml) | every 3 min | Nudges stalled agent sessions (no-op unless `watchdog.enabled` is on) |
| [`device-probe`](./device-probe.yml) | every 3 min | Refreshes device reachability, surfaces newly-seen tailnet nodes |
| [`tmux-reconcile`](./tmux-reconcile.yml) | every 5 min | Retrofits the guarded tmux pane-died hook onto managed sessions |
| [`launch-health`](./launch-health.yml) | every 6h | Probes each agent's default version actually launches; repairs a gutted install |
| [`fleet-cache-warm`](./fleet-cache-warm.yml) | every 3 min | Publishes this host's auth-health + fleet-status rows for `agents fleet status` |
| [`session-cache-warm`](./session-cache-warm.yml) | every 3 min | Publishes this host's local active sessions for the shared warm cache |
| [`usage-refresh`](./usage-refresh.yml) | every 5 min | Refreshes the usage cache the `agents run` router reads, off the hot path |
| [`auto-dispatch`](./auto-dispatch.yml) | every 3 min | Dispatches delegated Linear tickets through agents-cli's cloud-provider layer (opt-in per project; pin with `agents routines devices auto-dispatch --set <device>`) |

`check-updates` and the 8 housekeeping routines above all run on **every** box
independently — no designated primary, no SSH fan-out (`auto-dispatch` is the
exception: pin it to one device once your fleet has more than one box running
the same opted-in project, or every box will dispatch the same tickets). They
fail soft: a failing step never aborts the rest. The 8 housekeeping routines
require an agents-cli build that ships `agents __daemon-tick` (RUSH-2353).

## Using them

```bash
agents routines list
agents routines pause check-updates      # turn it off on this machine
agents routines run check-updates        # fire it now
```

To change what a shipped routine does on your machine, put a same-named file in
`~/.agents/routines/` — the user layer wins and this file is never mutated in place.

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
