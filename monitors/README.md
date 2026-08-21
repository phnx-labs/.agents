# Monitors

Durable event-triggered watchers. A monitor fires on a **change** — it watches a
SOURCE, detects a CONDITION, and fires an ACTION (run an agent, run a routine,
notify, or POST a webhook). The daemon owns the loop, so a monitor outlives the
agent that enabled it.

If you want something to fire on a **clock** instead of a change, that is a
[routine](../routines/README.md), not a monitor.

A monitor shipped here is a **system-layer built-in**: it lands at
`~/.agents/.system/monitors/` on every box via the `.system` pull, the CLI
discovers it, and it is **opt-in** — disabled until you run
`agents monitors enable <name>`. A copy under `~/.agents/monitors/` shadows the
built-in, so you can customize one per box without editing this repo.

## What ships here

| Monitor | Source | What it does |
|---|---|---|
| [`pr-merge-on-green`](./pr-merge-on-green.yml) | poll `pr-merge-on-green.sh` (`gh search prs` + `gh pr view --repo`), every 5 min | Rebase-merges this machine's own open PRs once CI is green **and** a non-author verdict is on the same PR (a GitHub APPROVED review or an APPROVE comment; same check as `merge-guard.sh`). Opt-in; disabled until enabled. |

## Using them

```bash
agents monitors list                       # see every monitor + its enable state
agents monitors enable pr-merge-on-green    # turn the built-in on (this box)
agents monitors test pr-merge-on-green      # dry-run: evaluate the source once, no action
agents monitors pause pr-merge-on-green      # temporarily stop it
```

`pr-merge-on-green` needs `gh` authenticated on the box. It scopes to your own
GitHub user (`gh search prs --author @me`) and names `--repo` on every per-PR
`gh` call, so it still evaluates when the daemon's cwd is not a git checkout
(RUSH-2848). Enable it on the one box you want to own merges from — enabling it
on several boxes has each daemon race to merge the same PRs.

**Version note:** the system-layer monitors mechanism ships in agents-cli
1.22.36. On an older CLI the built-in is inert (not discovered) — harmless, since
it is opt-in and off until enabled.
