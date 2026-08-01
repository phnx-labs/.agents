---
name: monitors
description: "Durable event-triggered watchers: watch a source, detect a change, and fire an agent, a routine, or a notification. The cross-agent layer — agents watching sources (the fleet, other agents) and reacting. Triggers on: 'watch for', 'monitor', 'when X changes run Y', 'notify me when', 'poll until', 'fire an agent on', 'watch the fleet', 'watch CI'."
argument-hint: "[add|list|view|test|pause|resume|device|logs|runs|remove]"
allowed-tools: Bash(agents monitors*)
user-invocable: true
---

# Monitors Skill

Durable, event-triggered watchers. **Routines fire on a *clock*; monitors fire on a *change*.** A monitor watches a source, decides whether it changed, and fires an action — spawn an agent, kick a routine, or notify. It runs in the same background daemon as routines, so it survives restarts and is fleet-schedulable.

Think of it as the **cross-agent layer**: agents watching sources — including the fleet and other agents — and firing agents in response.

## The model: source → condition → action

A monitor is three parts:

- **Source** — what to watch (a command's output, an HTTP endpoint, a file, a fleet device, a webhook).
- **Condition** — what counts as a fire (any change, a regex match, every tick), deduped by a native state store so it stays silent until something *actually* changes.
- **Action** — what to do (run an agent with the event in its prompt, kick a routine, notify, POST a webhook).

## When to reach for this (vs. siblings)

| You want… | Use |
|---|---|
| Run on a schedule (9am weekdays, hourly) | `agents routines` (clock) |
| Run when a *condition changes* (CI goes red, cert issues, box goes down) | **`agents monitors`** (change) |
| Nudge a *stalled agent session* to continue | `agents watchdog` |

## Quickstart

```bash
# CI goes red -> a Claude agent triages it (poll a command, diff, match a pattern)
agents monitors add ci-red \
  --poll 'gh pr checks 1249 --json name,bucket' 30s --match fail \
  --run claude --prompt 'CI failed: {event}. Diagnose and fix.' \
  --device yosemite-s0

# A fleet box goes unreachable or overloaded -> notify (watch the fleet itself)
agents monitors add box-down --watch-device mac-mini --on-change --notify telegram

# Poll an HTTPS endpoint every 8h; fire once when the body flips to "issued"
agents monitors add cert-issued \
  --poll-http 'https://secure.ssl.com/.../order' 8h --match issued --notify telegram
```

The daemon auto-starts on the first `add` (same scheduler as routines).

## Always dry-run first

`test` evaluates the source **once** and shows what it would emit + whether it would fire — no action, no state written. Use it to validate a monitor before it goes live.

```bash
agents monitors test ci-red
# → Observation: <what the source returned>
#   Would fire: yes | Emitted event summary: fail → would run claude
#   (dry run — no action taken, no state written)
```

## Sources (pick exactly one)

| Flag | Watches |
|---|---|
| `--watch '<cmd>'` / `--poll '<cmd>' <interval>` | a shell command's stdout |
| `--poll-http <url> <interval>` | an HTTP endpoint's status + body |
| `--watch-file <path>` | a file / directory for changes |
| `--watch-device <name>` | a fleet device's reachability + load headroom |
| `--on <src:event>` | a signed GitHub/Linear webhook |
| `--ws <url>` | a WebSocket stream |

> **v1 note:** `--on` (webhook) and `--ws` are *accepted* but their delivery is wired through a receiver in a follow-up — they won't fire yet. The poll-model sources (`--watch`/`--poll`/`--poll-http`/`--watch-file`/`--watch-device`) are live. Prefer those today.

## Conditions

| Flag | Fires when |
|---|---|
| `--on-change` (default) | the observation differs from last-seen (first observation is a silent baseline) |
| `--match '<regex>'` | the output matches the pattern (once per distinct match) |
| `--every` | every tick (opt-in; rate-limited) |
| `--dedupe-key '<expr>'` | override what counts as "the same event" (default: hash of the observation) |

The native state store (`~/.agents/.history/monitors/<name>/state.json`) is what keeps a monitor silent until a real change — no hand-rolled memory file needed.

## Actions (pick exactly one; the event is injected as `{event}`)

| Flag | Does |
|---|---|
| `--run <agent> --prompt '...'` | spawn an agent; `{event}` in the prompt is replaced with the fired event |
| `--routine <name>` | kick an existing routine |
| `--notify [channel]` | send a notification (default telegram) |
| `--webhook-out <url>` | POST the event |

Shared with routines: `--mode`, `--effort`, `--timeout` on `--run`.

## Placement: pin-to-one (exactly-once)

```bash
--device <name>     # OWNER: the single machine that evaluates + fires this monitor (exactly-once)
--devices <list>    # allowlist: each fires independently (advanced; matches routines' --devices)
--run-on <host>     # offload the ACTION to another host over SSH (distinct from the owner)
```

For a fleet-wide event you want handled once, pin the owner with `--device`. There is no distributed lock in v1 — if the owner is down, the monitor is down.

## Lifecycle & inspection

```bash
agents monitors list                 # every monitor: source, owner device, last fired
agents monitors view <name>          # full config + current watched-state + recent fires
agents monitors pause <name>         # disable
agents monitors resume <name>
agents monitors device <name> --set X  # (re)pin the owner device
agents monitors logs <name> [--run <id>]   # action run logs
agents monitors runs <name>          # fire history
agents monitors edit <name>          # open the YAML in $EDITOR
agents monitors remove <name>
```

A `rateLimit: {max, per}` in the config auto-pauses a runaway (firehose) monitor.

## From a YAML file

```yaml
name: cert-issued
source:
  type: poll-http
  url: https://secure.ssl.com/.../order
  interval: 8h
condition:
  mode: match
  match: issued
action:
  type: notify
  notifyChannel: telegram
device: zion
```

```bash
agents monitors add ./cert-issued.yml
```

## Quick reference

| Command | Purpose |
|---|---|
| `add <name> --poll '<cmd>' <interval> --match <re> --run <agent> --prompt '...'` | Watch a command; fire an agent on match |
| `add <name> --poll-http <url> <interval> --match <re> --notify` | Watch an endpoint; notify on match |
| `add <name> --watch-device <dev> --on-change --notify` | Watch a fleet box; notify on change |
| `test <name>` | Dry-run: evaluate once, show would-fire, no action |
| `list` / `view <name>` | Inspect monitors + state |
| `pause` / `resume` / `device --set` / `remove` | Manage |
| `logs` / `runs` | Fire history + action logs |

For everything else, run `agents monitors --help`.
