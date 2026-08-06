---
name: routines
description: "Schedule agents to run on a cron schedule or one-shot at a specific time. The scheduler auto-starts on first add. Triggers on: 'schedule an agent', 'recurring job', 'cron', 'daily', 'every weekday', 'run at 2pm'."
argument-hint: "[add|list|run|logs|report|pause|resume|remove]"
allowed-tools: Bash(agents routines*)
user-invocable: true
---

# Routines Skill

Schedule agents to run on a cron schedule or one-shot at a specific time. Routines are YAML jobs that specify which agent runs, when, what task, and execution constraints.

## What a routine is

A YAML job with four parts:

- **Which agent** — claude, codex, antigravity, cursor, opencode
- **When** — cron schedule (recurring) or specific time (one-shot)
- **What task** — the prompt for the agent
- **Execution constraints** — mode, effort, timeout

The background scheduler auto-starts the first time you add a routine.

## Quickstart: recurring (cron)

```bash
# Every weekday at 9 AM
agents routines add daily-standup \
  --schedule "0 9 * * 1-5" \
  --agent claude \
  --prompt "Draft standup from git log"
```

Cron format is standard 5-field (minute hour day month weekday).

## Quickstart: one-shot

Runs once at a specific time, then disables itself.

```bash
# Tomorrow at 2:30 PM
agents routines add hotfix-review \
  --at "14:30" \
  --agent codex \
  --prompt "Review hotfix PR #42"

# Exact date + time
agents routines add launch-check \
  --at "2026-06-01 09:00" \
  --agent claude \
  --prompt "Run launch readiness audit"
```

## From a YAML file

For complex routines with multiple settings, author a YAML and reference its path.

```bash
agents routines add ./weekly-report.yml
```

Example `weekly-report.yml`:

```yaml
name: weekly-report
schedule: "0 17 * * 5"
agent: claude
mode: edit
effort: high
timeout: 1h
timezone: America/Los_Angeles
prompt: |
  Summarize this week's shipped PRs and open issues.
  Post the summary to #engineering.
```

## Mode, effort, timeout

```bash
agents routines add backup-job \
  --schedule "0 2 * * *" \
  --agent claude \
  --prompt "Run nightly backup verification" \
  --mode edit \
  --effort high \
  --timeout 1h
```

| Flag | Default | Values |
|------|---------|--------|
| `--mode` | `plan` | `plan` (read-only), `edit` (can write files) |
| `--effort` | `auto` | `low \| medium \| high \| xhigh \| max \| auto` |
| `--timeout` | `30m` | Duration string (e.g., `30m`, `2h`) |

## Timezone

Interpret the cron schedule in a specific timezone.

```bash
agents routines add london-update \
  --schedule "0 9 * * *" \
  --timezone Europe/London \
  --agent claude \
  --prompt "Post morning update to #london"
```

## Create paused

```bash
agents routines add experimental --schedule "0 * * * *" --agent claude --prompt "..." --disabled
agents routines resume experimental
```

## Scheduler lifecycle

The scheduler auto-starts on first `add`. Manage manually:

```bash
agents routines status            # is the scheduler running?
agents routines start             # start it
agents routines stop              # stop all routines
agents routines scheduler-logs    # tail scheduler stdout
agents routines scheduler-logs --follow -n 200
```

## Inspect routines

```bash
agents routines list              # all routines + next run + last status
agents routines view daily-standup
```

## Test a routine right now

Run in the foreground, ignoring the schedule. Use this to validate prompts before letting them fire on schedule.

```bash
agents routines run daily-standup
```

## Pause and resume

```bash
agents routines pause daily-standup
agents routines resume daily-standup
```

## History, logs, and reports

Each fire is recorded as a run. Inspect them:

```bash
agents routines runs daily-standup           # list recent runs
agents routines logs daily-standup           # latest run's stdout
agents routines logs daily-standup --run <id>
agents routines report daily-standup         # extract markdown the agent produced
agents routines report daily-standup --run <id>
```

## Remove, edit

```bash
agents routines edit daily-standup           # opens the YAML in $EDITOR
agents routines remove daily-standup
```

## Sandboxing

Routines run with the permissions you grant them. Agents only see directories and tools you allow — same model as `agents run --mode plan/edit/full`. Use `--mode plan` for routines that should never write.

## Pattern: continuous ticket drain

Two routines turn an issue-tracker queue into a self-draining pipeline: a **triage** routine on one machine routes tickets to workers by label, and a **drain** routine on each worker lands them end-to-end (worktree → PR → CI → review → merge → close). Tested design points:

- **Machine routing is a label; agent ownership is not.** One drain routine per worker machine, keyed to a `host:<worker>` label. Tickets from any project share the queue; the ticket's project or `repo:*` label decides which checkout the loop works in. Do **not** reach for an `agent:<name>` label to say who owns a ticket — that is Linear's native `delegate` field (`linear update <ID> --delegate <name>`, queried with `linear tasks --agent <name>`), and a label that looks like ownership but isn't is what the two models fighting cost last time.
- **One triage writer.** A single routine assigns `host:<worker>` labels — one writer means no cross-machine claim race. Give triage no routing discretion: an opt-out label (e.g. `hold`) is human-only, because a ticket triage diverts pings nobody, while a ticket the drain parks notifies the user.
- **Gate with a pilot label first.** Route only tickets carrying an opt-in label until you trust the loop; widen by removing the gate.
- **`mode: skip`, `sandbox: false`.** Headless drains need full permissions, and (today) `sandbox: false` so the spawned agent sees real credentials — see "Headless claude auth" in the routines design doc. Auth headlessly via a secrets bundle named `claude` holding `CLAUDE_CODE_OAUTH_TOKEN`; the daemon injects it into scheduled runs. Manual `agents routines run` does not inject it — wrap with `agents secrets exec claude -- agents routines run <name>`.
- **Overlap lock with staleness.** Cron has no per-job overlap guard yet, so the drain prompt takes a lock dir (`mkdir /tmp/drain-<worker>.lock`) first, exits if it exists and is younger than the routine timeout, steals it if older (a leaked lock from a dead run must not deadlock the queue), and removes it on every exit path.
- **Escalation.** Give the prompt a verbatim notify one-liner (any messaging CLI). Blocked tickets get parked with a comment plus that ping; the loop continues.

Drain routine template (`drain-<worker>.yml`, register with `agents routines add drain-<worker>.yml`):

```yaml
name: drain-<worker>
schedule: "*/30 * * * *"
agent: claude
mode: skip
timeout: 2h
sandbox: false
prompt: |
  Unattended fleet drain on <worker>. No interactive user: never call
  AskUserQuestion, never wait for input.
  Overlap guard: mkdir /tmp/drain-<worker>.lock first; if it exists and is
  younger than 2 hours, exit immediately; if older, steal it. Remove it on
  every exit path.
  Queue: invoke the code:loop skill in unattended mode. Fetch tickets from
  your tracker filtered to label host:<worker> and status Todo.
  Notify command (verbatim, substitute ticket ID and blocker):
  <your messaging-CLI one-liner>
  Blocked ticket: park it with a comment, run the notify command, continue.
  Queue empty: remove the lock, exit with a one-paragraph summary.
```

The `code:loop` skill's "Unattended mode" and "Claim before you build" sections carry the rest of the contract (dedup against open PRs and active sessions, claim via Todo → In Progress, ticket ID in every PR title).

## Quick reference

| Command | Purpose |
|---------|---------|
| `add <name> --schedule ... --agent ... --prompt ...` | Create cron routine |
| `add <name> --at "14:30" --agent ... --prompt ...` | Create one-shot routine |
| `add ./file.yml` | Create from YAML |
| `list` | All routines + next run |
| `view <name>` | Show routine YAML |
| `edit <name>` | Open routine in $EDITOR |
| `run <name>` | Foreground run (ignores schedule) |
| `runs <name>` | Recent run history |
| `logs <name> [--run <id>]` | Stdout of a run |
| `report <name> [--run <id>]` | Extract markdown output |
| `pause <name>` / `resume <name>` | Disable / re-enable |
| `remove <name>` | Delete routine |
| `start` / `stop` / `status` | Scheduler lifecycle |
| `scheduler-logs [--follow] [-n N]` | Tail scheduler logs |

For everything else, run `agents routines --help`.
