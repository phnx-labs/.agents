# Routines

Scheduled agent runs. A routine fires on a **clock** — a cron schedule or a one-shot time.
The scheduler daemon starts on the first `agents routines add`.

If you want something to fire on a **change** instead of a clock, that is a
[monitor](../skills/monitors/SKILL.md), not a routine.

## What ships here

| Routine | Schedule | What it does |
|---|---|---|
| [`check-updates`](./check-updates.yml) | Mondays 09:00 | Keeps the box current — upgrades `agents-cli` when npm is ahead, fast-forwards `~/.agents/.system` to `origin/main`, and notifies only if something actually changed |
| [`worktree-sweep`](./worktree-sweep.yml) | daily 04:30 | Reclaims PR-bound worktrees whose work has landed, on every device — `routines/lib/worktree-sweep.sh` (plain git, no CLI command) removes a merged worktree **and** its branch, and fails closed on anything dirty, unlanded or undeterminable (PHNX-3503). Deliberately unpinned: its input is the firing box's own checkouts. Scope is an **allowlist** on `remote.origin.url` (override via `~/.agents/worktree-sweep.allow`); opt one in-scope repo out with a `.no-worktree-sweep` file at its root |
| `backfill-check-outcomes` | weekly Mon 07:00 | Derive stop-hook check outcomes from this box's transcripts into state.db (`check-outcome-backfill.py --write`) so gate changes have a false-positive denominator (RUSH-3032) |

`check-updates` runs on **every** box independently — no designated primary, no
SSH fan-out. It fails soft: a failing step never aborts the rest.

The 8 daemon-housekeeping routines that used to live here (watchdog, device-probe,
tmux-reconcile, launch-health, fleet-cache-warm, session-cache-warm, usage-refresh,
auto-dispatch) were each a thin `agents __daemon-tick <name>` cron wrapper
(RUSH-2353). None of that housekeeping belongs at system level, so RUSH-2495
takes it out of routines entirely as a hard cut: `tmux-reconcile`,
`launch-health`, and `auto-dispatch` are deleted outright; `session-cache-warm`
is dropped because `agents sessions --active` self-refreshes on read; and
`watchdog`, `device-probe`, `usage-refresh`, and `fleet-cache-warm` move to
plain daemon-core timers inside the daemon, not routines every install pulls.

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
