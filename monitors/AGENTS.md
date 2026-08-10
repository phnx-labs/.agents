# monitors/ — maintenance contract

Humans start at [README.md](./README.md).

One `.yml` per monitor. `name` must equal the filename. A monitor shipped here
lands on every install that pulls this repo (`~/.agents/.system/monitors/`), so
it must be safe to leave present on a machine nobody is watching.

## Opt-in is the invariant — never ship an enabled built-in

**Omit the `enabled:` field entirely.** The system layer defaults a system-layer
built-in to **disabled** until `agents monitors enable <name>`. A monitor that
fires an action unattended (a merge, a deploy) must never turn itself on just by
being pulled onto a box. Writing `enabled: true` here would arm it fleet-wide on
the next `.system` pull — do not do it. A user copy under `~/.agents/monitors/`
shadows the built-in and is where a box opts in.

(Contrast routines: `routines/*.yml` set `enabled: true` because they are
deterministic housekeeping that is safe to run everywhere. An action monitor is
not — it acts on the outside world, so it stays off until a human enables it.)

## Shape

Validated by `validateMonitor` in agents-cli
`apps/cli/src/lib/monitors/config.ts` (hand-rolled, no zod). The load-bearing
fields:

```yaml
name: pr-merge-on-green      # must equal the filename
description: >-              # short, human
  ...
source:                      # exactly one source
  type: poll                 # command | poll | poll-http | webhook | ws | file | device
  interval: 5m               # required for poll / poll-http (30s, 15m, 8h, 1d)
  command: '...'             # required for command / poll (stdout is the observation)
condition:                   # how an observation becomes a fire
  mode: match                # on-change | match | every
  match: '[0-9].*'           # required for match mode; fires only when the matched value CHANGES
action:                      # exactly one action
  type: run                  # run | routine | notify | webhook-out
  agent: claude              # required for run
  mode: auto
  prompt: '... {event} ...'  # {event} is replaced with the fired observation
rateLimit:                   # optional firehose guard
  max: 6
  per: 1h
```

- **`poll` needs both `command` and `interval`.** The command's stdout is the
  observation; empty stdout with `mode: match` never fires.
- **`mode: match` fires once per distinct matched value**, not every tick — the
  engine only fires when the matched value differs from the last fire, so a
  still-true condition is reported once, not on a loop.
- **`mode: every` fires on every tick with a non-empty observation** — an empty
  or whitespace-only observation is silent, but it does NOT dedupe, so a
  still-true condition re-fires each tick. Use it (bounded by `rateLimit`) when an
  action must be **retried while its condition persists** — e.g. a merge that can
  fail silently, where `match`/`on-change` would report the unchanged PR set once
  and never retry. Empty-safe `every` requires agents-cli >= 1.22.36
  (phnx-labs/agents-cli#2536); an older CLI fires `every` on an empty poll too.
- **Placement:** leave `device` / `devices` unset so any box may own it once
  enabled; pin only when a monitor must run on a specific machine.

## Syncing

A monitor added here is picked up by the `.system` pull — no `agents.yaml` entry,
no registration step (unlike hooks). The one required cross-edit is the catalog
row in [`README.md`](./README.md) and the `monitor` row in the repo
[`AGENTS.md`](../AGENTS.md) sync table.

Validate a change without touching a live box: `validateMonitor` from the
agents-cli checkout, or `agents monitors test <name>` (dry-run) once the monitor
is present under `~/.agents/monitors/`.
