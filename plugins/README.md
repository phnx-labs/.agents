# Plugins

A plugin bundles related commands and skills into one installable unit with its own
namespace. `/work:loop`, `/code:loop`, `/swarm`, and `/fleet:sync` all come from plugins.

The system layer ships the lightweight, no-paid-key plugins. Heavier or key-gated ones live
in the opt-in `.agents-extras` bundle instead, so the default install stays fast and works
anywhere with no setup.

**Human map of "what should I run?":** the root [`README.md`](../README.md) § *What should
I run?* and § *Automate your work*. This page is the plugin catalog.

## When to use which plugin

| Situation | Plugin | Command |
|---|---|---|
| Overnight / unattended drain of **any** clear work (all projects) | **work** | `/work:loop` or `/loop` |
| One mixed task (code *or* browser/outreach) | **work** | `/work:dispatch` |
| Engineering queue to **merge** | **code** | `/code:loop` |
| PR review or whole-repo architecture scan | **code** | `/code:review` |
| Parallel agents / blind plan / spec / debug | **swarm** | `/swarm`, `/swarm:plan`, … |
| Resume / restore sessions / session analytics | **sessions** | `/continue`, `/insights`, `/sessions:restore`, `/sessions:fork` |
| Multi-machine sync / onboard | **fleet** | `/fleet:sync`, `/fleet:onboard` |
| Publish HTML artifact | **share** | `/share:public`, `/share:private` |
| Offline design render | **design** | `/design` |
| Agent self-exit | **self** | `/self:close` |

`work` is kind-agnostic and unattended-first. `code` is engineering-first and merge-oriented.
Do not stretch `code:loop` into browser outreach — use `work:loop`.

## What ships here

| Plugin | Commands | What it's for |
|---|---|---|
| [`code`](./code/README.md) | 7 | The coding loop — `/code:loop`, `/code:review` (session PRs / cold PR review / whole-repo scan, three modes on one skill), `/code:learn` (writes project AGENTS.md nav notes), `/code:clean` (make the codebase legible to agents: docs-as-claims verified against code, ranking by measured agent traffic, behavior-preserving PRs, a legibility scorecard per run), `/code:commit`, `/code:release` (publish a package/CLI/app to its registry — discover release process, run tests, changelog, publish, tag, verify live). Plus one self-contained command — `/code:prune` (remove merged branches/worktrees behind data-loss guards) — moved here when the standalone `git` plugin and top-level `/clean` were retired. `/code:review` spawns the repo's [`code-reviewer`](../subagents/code-reviewer/AGENT.md) subagent, which ships from `subagents/`, not from this plugin. |
| [`work`](./work/README.md) | 3 | General-purpose work — `/work:loop` (alias `/loop`) unattended multi-project drain with load spread + browser/computer; `/work:dispatch` is ONE unit of work (coding or not); `/work:output` is the fleet token-burn/output report |
| [`swarm`](./swarm/README.md) | 4 | Fan a task across parallel agents — top-level `/swarm` + `/swarm:run`, `/swarm:plan`, `/swarm:spec`, `/swarm:debug` (test/qa removed; plan/spec require mock-ups) |
| [`fleet`](./fleet/README.md) | 4 | Fleet-wide ops — `/fleet:sync` brings every device to latest, `/fleet:onboard` brings a bare box to parity, `/fleet:mint-auth` self-mints setup tokens, `/fleet:profile` profiles a sluggish machine and attributes the load to agents-cli surfaces |
| [`share`](./share/README.md) | 2 | Publish agent-generated HTML to a link on your own Cloudflare R2 — `/share:public` (auto OG cover), `/share:private` (unlisted, expiring) |
| [`design`](./design/README.md) | 1 | One keyless, offline-first front door for design — routes an intent to a mode and renders self-contained HTML/SVG |
| [`self`](./self/README.md) | 3 | Agent self-operations — `/self:close` cleanly self-terminates the session (guarded SIGTERM to the harness); `/self:hibernate` sleeps the session until a future time; `/self:reflect` recalls corrections and constraints before revising work |
| [`sessions`](./sessions/README.md) | 4 | Session lifecycle + analytics — `/sessions:continue` finishes prior work here, `/sessions:insights` orchestrates insights/trends/perf/stats, `/sessions:restore` re-opens crash windows, `/sessions:fork` branches into a new independent session; top-level `/continue` `/insights` are thin aliases |

<p align="center">
  <img src="../.assets/share.png" alt="/share:public — one command turns any agent-generated HTML into a shareable link with an auto OG cover" width="82%">
</p>

## Layout

```
plugins/<name>/
  README.md      # what this plugin is, and its commands
  commands/      # <name>:<command>.md — the namespaced slash commands
  skills/        # skills the plugin's commands load
```

Each plugin's own `README.md` lists its commands in detail.

## Installing and disabling

Plugins here are registered in
[`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) and materialized into
every installed agent version on `agents sync`. To add a bundle from elsewhere:

```bash
agents repo add gh:phnx-labs/.agents-extras   # heavier, key-gated workflows
agents repo list
agents repo disable extras                     # turn off without deleting
```

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
