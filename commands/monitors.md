---
description: Set up or manage a durable event-triggered watcher (agents monitors) — watch a source, fire an agent/routine/notification on change. Routines fire on a clock; monitors fire on a change.
argument-hint: "[what to watch and what to do — e.g. 'watch CI on PR 1249, run claude if it fails']"
allowed-tools: Bash(agents monitors*)
---

You're being asked to set up or manage a **monitor**: $ARGUMENTS

(If `$ARGUMENTS` is empty, run `agents monitors list` and show what's already watching.)

A monitor watches a **source**, detects a **change**, and fires an **action**. Read the `monitors` skill (`SKILL.md`) if it's loaded — it's the contract. Otherwise follow this.

## Step 1: Map the intent to source → condition → action

Decode what the user wants into the three parts. Pick **one** source, **one** condition, **one** action.

**Source** (what to watch):
- a command's output → `--poll '<cmd>' <interval>` (e.g. `--poll 'gh pr checks 1249 --json name,bucket' 30s`)
- an HTTP endpoint → `--poll-http '<url>' <interval>`
- a file → `--watch-file <path>`
- a fleet box's health/reachability → `--watch-device <name>`
- (webhook `--on` / websocket `--ws` are accepted but don't fire yet in v1 — prefer poll sources)

**Condition** (when to fire):
- differs from last time → `--on-change` (default)
- matches a pattern → `--match '<regex>'`
- every tick → `--every`

**Action** (what to do — the fired event is injected as `{event}`):
- spawn an agent → `--run <agent> --prompt '... {event} ...'`
- kick a routine → `--routine <name>`
- notify → `--notify [channel]`
- POST a webhook → `--webhook-out <url>`

**Placement:** for a fleet-wide event handled once, pin an owner with `--device <name>` (exactly-once, v1). `--run-on <host>` offloads the action.

## Step 2: Dry-run before it goes live

Always `agents monitors test <name>` first — it evaluates the source once and shows whether it *would* fire and what it *would* emit, with no action and no state written. Confirm it matches intent, then let it run (the daemon auto-started on `add`).

```bash
agents monitors add ci-red \
  --poll 'gh pr checks 1249 --json name,bucket' 30s --match fail \
  --run claude --prompt 'CI failed: {event}. Diagnose and fix.' --device $(scutil --get LocalHostName 2>/dev/null || hostname)
agents monitors test ci-red      # verify before trusting it
```

## Step 3: Manage existing monitors

Map management intent onto the CLI:

| Intent | Command |
|---|---|
| "what's watching" / "list" | `agents monitors list` |
| "show / inspect X" | `agents monitors view X` |
| "pause / stop X" | `agents monitors pause X` |
| "resume X" | `agents monitors resume X` |
| "move X to device D" | `agents monitors device X --set D` |
| "did X fire / logs" | `agents monitors runs X` / `agents monitors logs X` |
| "delete X" | `agents monitors remove X` |

## Report concisely

After acting, report: what the monitor watches, when it fires, what it does, and its owner device — one or two lines. If you set one up, quote the `test` dry-run result so the user sees it would fire correctly.

## Anti-patterns

- Don't use a monitor for a schedule — that's `agents routines` (clock, not change).
- Don't skip `test` — a live monitor that fires wrong (or never) is worse than none.
- Don't reach for `--on`/`--ws` expecting them to fire in v1 — their delivery is a follow-up. Use poll sources.
- Don't leave a monitor unpinned for a fleet-wide event — without `--device` it can fire on every allowlisted box.
