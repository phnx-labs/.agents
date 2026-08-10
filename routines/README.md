# Routines

Scheduled agent runs. A routine fires on a **clock** — a cron schedule or a one-shot time.
The scheduler daemon starts on the first `agents routines add`.

If you want something to fire on a **change** instead of a clock, that is a
[monitor](../skills/monitors/SKILL.md), not a routine.

## What ships here

| Routine | Schedule | What it does |
|---|---|---|
| [`check-updates`](./check-updates.yml) | Mondays 09:00 | Keeps the box current — upgrades `agents-cli` when npm is ahead, fast-forwards `~/.agents/.system` to `origin/main`, and notifies only if something actually changed |

`check-updates` runs on **every** box independently — no designated primary, no
SSH fan-out. It fails soft: a failing step never aborts the rest.

The 8 daemon-housekeeping routines that used to live here (watchdog, device-probe,
tmux-reconcile, launch-health, fleet-cache-warm, session-cache-warm, usage-refresh,
auto-dispatch) were each a thin `agents __daemon-tick <name>` cron wrapper
(RUSH-2353). That housekeeping now moves into daemon-owned services rather than
system-level routines every install pulls (RUSH-2465).

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
