# routines/ — maintenance contract

Humans start at [README.md](./README.md).

One `.yml` per routine. `name` must match the filename. A routine shipped here fires on
every install that pulls this repo, unattended, so it must be safe to run on a machine
nobody is watching.

## Prefer `command:` over an agent

A routine can run a shell `command:` or an LLM agent. **Use `command:` for anything
deterministic.** An agent-mode routine depends on a logged-in account, burns tokens, and
gambles on account rotation — `check-updates` was originally agent-mode and failed on a
logged-out version with `Not logged in · /login`. Version compare, git fast-forward, install,
notify: all deterministic, all `command:`.

Reach for an agent only when the work genuinely needs judgment.

## Shape

```yaml
name: check-updates          # must equal the filename
schedule: 0 9 * * 1          # cron, in the daemon's local time
enabled: true
timeout: 15m
command: |
  ...
```

## Fail soft, and stay quiet

- One failing step must never abort the rest. Guard every external call with `|| true` or an
  explicit branch, and print what happened.
- **Notify only when something changed.** A routine that reports "nothing to do" every week
  trains the user to ignore it.
- Never assume a tool is a real binary — `npm` is a lazy shell function in some setups. Use
  `command -v npm` with a fallback to the absolute path, as `check-updates` does.

## Every box self-updates independently

Do not add a `devices:` restriction or an SSH fan-out to make one machine the primary for
fleet-wide upkeep. Each box running the same routine covers both the single-laptop case and
the large-fleet case, with no coordinator to go stale.

## Adding a routine

1. `routines/<name>.yml` with `name` matching the filename.
2. Add its row to the table in [`README.md`](./README.md), including the schedule.
3. Add a `CHANGELOG.md` entry under the next version.
4. Run it once with `agents routines run <name>` and quote the real output in the PR. A
   routine that has never fired is untested.

Users override a shipped routine with a same-named file in `~/.agents/routines/`, or disable
it with `agents routines disable <name>`. Never expect to mutate this file on their machine.
