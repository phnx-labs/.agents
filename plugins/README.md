# Plugins

A plugin bundles related commands and skills into one installable unit with its own
namespace. `/work:loop`, `/code:loop`, `/swarm`, and `/fleet:sync` all come from plugins.

The system layer ships the lightweight, no-paid-key plugins. Heavier or key-required ones live
in the opt-in `.agents-extras` bundle instead, so the default install stays fast and works
anywhere with no setup.

**Human map of "what should I run?":** the root [`README.md`](../README.md) § *What should
I run?* and § *Automate your work*. This page is the plugin catalog.

## When to use which plugin

| Situation | Plugin | Command |
|---|---|---|
| Overnight / unattended drain of **any** clear work (all projects) | **work** | `/work:loop` |
| One mixed task (code *or* browser/outreach) | **work** | `/work:dispatch` |
| Prove landed work — demo it in its real env, before/after, report | **work** | `/demo` (`/work:demo`) |
| Engineering queue to **merge** | **code** | `/code:loop` |
| PR review or whole-repo architecture scan | **code** | `/code:review` |
| Parallel agents / blind plan / spec / debug | **swarm** | `/swarm`, `/swarm:plan`, … |
| Resume / restore / recall sessions / session analytics | **sessions** | `/continue`, `/finish`, `/insights`, `/recall`, `/fork`, `/sessions:restore` |
| Current repository's agent output, cost, mix, and workflow tax as HTML | **yc** | `/yc:workweave` |
| Multi-machine sync / onboard | **fleet** | `/fleet:sync`, `/fleet:onboard` |
| Publish HTML artifact | **share** | `/share` (`--private` for `--no-cover --expire 7d`) |
| Offline design render | **design** | `/design` |
| Agent self-exit | **self** | `/self:close` |

`work` is kind-agnostic and unattended-first. `code` is engineering-first and merge-oriented.
Do not stretch `code:loop` into browser outreach — use `work:loop`.

## What ships here

| Plugin | Commands | What it's for |
|---|---|---|
| [`code`](./code/README.md) | 5 | The coding loop — `/code:loop`, `/code:review` (session PRs / cold PR review / whole-repo scan, three modes on one skill), `/code:learn` (writes project AGENTS.md nav notes), `/code:refactor` (architectural restructuring, plus a `quality` small-change mode), and `/code:commit`. `/code:review` spawns the repo's [`code-reviewer`](../subagents/code-reviewer/AGENT.md) subagent, which ships from `subagents/`, not from this plugin. |
| [`work`](./work/README.md) | 3 | General-purpose work — `/work:loop` unattended multi-project drain with load spread + browser/computer, whose `triage` mode forces the whole board to keep-and-schedule or cancel; `/work:dispatch` is ONE unit of work (coding or not); `/work:demo` (top-level `/demo`) is the post-ship capstone — recover intent, exercise the shipped thing in its real environment on real inputs, before/after side by side, deliver an analyzed report |
| [`swarm`](./swarm/README.md) | 4 | Fan a task across parallel agents — top-level `/swarm` + `/swarm:run`, `/swarm:plan`, `/swarm:spec`, `/swarm:debug` (test/qa removed; plan/spec require mock-ups) |
| [`fleet`](./fleet/README.md) | 3 | Fleet-wide ops — `/fleet:sync` brings every device to latest, `/fleet:onboard` brings a bare box to parity and mints its agent auth in the same flow, `/fleet:profile` profiles a sluggish machine and attributes the load to agents-cli surfaces |
| [`share`](./share/README.md) | 1 | Publish agent-generated HTML to a link on your own Cloudflare R2 — `/share` (auto OG cover), `/share --private` (`--no-cover --expire 7d`) |
| [`design`](./design/README.md) | 1 | One keyless, offline-first front door for design — routes an intent to a mode and renders self-contained HTML/SVG |
| [`self`](./self/README.md) | 3 | Agent self-operations — `/self:close` cleanly self-terminates the session (guarded SIGTERM to the harness); `/self:hibernate` sleeps the session until a future time; `/self:reflect` recalls corrections and constraints before revising work |
| [`sessions`](./sessions/README.md) | 3 | Session lifecycle + analytics — `/sessions:continue` finishes prior work here, `/sessions:restore` re-opens crash windows, `/sessions:search` pulls ranked snippet-level context from prior sessions (falls back to a bundled `recall.py` that recovers assistant answers the index misses); `/sessions:finish`/`/sessions:insights`/`/sessions:fork` skills are reached only via their top-level `/finish` `/insights` `/fork` aliases, and `/recall` aliases `/sessions:search` |
| [`yc`](./yc/README.md) | 1 | Local recreations of YC startup products using a general-purpose agent plus focused skills/scripts; first recipe `/yc:workweave` turns indexed agent sessions, output, cost, resource use, hook/command latency, and friction into private HTML |

<p align="center">
  <img src="../.assets/share.png" alt="/share — one command turns any agent-generated HTML into a shareable link with an auto OG cover" width="82%">
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
agents repo add gh:phnx-labs/.agents-extras   # heavier, key-required workflows
agents repo list
agents repo disable extras                     # turn off without deleting
```

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
