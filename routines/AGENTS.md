# routines/ — maintenance contract

Humans start at [README.md](./README.md).

One `.yml` per routine. `name` must match the filename. A routine shipped here fires on
every install that pulls this repo, unattended, so it must be safe to run on a machine
nobody is watching.

## Prefer `command:` over an agent

A routine can run a shell `command:` or an LLM agent. **Use `command:` for anything
deterministic.** An agent-mode routine depends on a logged-in account, burns tokens, and
gambles on account rotation — the now-removed `check-updates` routine (PHNX-3695: replaced
by the agents-cli daemon's own `self-update` service) was originally agent-mode and failed on
a logged-out version with `Not logged in · /login`. Version compare, git fast-forward, install,
notify: all deterministic, all `command:`.

Reach for an agent only when the work genuinely needs judgment.

## Shape

```yaml
name: worktree-sweep         # must equal the filename
schedule: 30 4 * * *         # cron, in the daemon's local time
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
- Never assume a tool is a real binary — a shell tool can be a lazy shell function in some
  setups. Use `command -v <tool>` with a fallback to the absolute path.

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

Users override a shipped routine with a same-named file in `~/.agents/routines/`. Device
activation is membership in `~/.agents/devices/<hostname>/agents.yaml`; never put mutable
`enabled:` or `devices:` state in a shipped definition and never mutate this file on a machine.
