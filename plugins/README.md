# Plugins

A plugin bundles related commands and skills into one installable unit with its own
namespace. `/work:loop`, `/code:review`, `/swarm`, and `/fleet:onboard` all come from plugins.

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
| Pick a whole **project's** work back up (resume it on workers) | **work** | `/work:resume` (`/resume`) |
| Prove landed work — demo it in its real env, before/after, report | **work** | `/demo` (`/work:demo`) |
| A hard research question — many engines, blind, one cited answer | **research** | `/research` (`/research:research`) |
| Explore a PRODUCT hands-on — drive it, prove claims visually | **research** | `/research:product` |
| Engineering queue through release | **work** | `/loop` (`/work:loop`) |
| Commit code, docs, assets, or configuration | **work** | `/commit` (`/work:commit`) |
| PR review or whole-repo architecture scan | **code** | `/code:review` |
| Parallel agents / blind plan / spec / debug | **swarm** | `/swarm`, `/swarm:plan`, … |
| Resume prior work / recall / session analytics | **sessions** | `/continue`, `/finish`, `/insights`, `/recall`, `/fork` |
| Current repository's agent output, cost, mix, and workflow tax as HTML | **yc** | `/yc:workweave` |
| Onboard a bare device / profile a sluggish machine | **fleet** | `/fleet:onboard`, `/fleet:profile` |
| Offline design render | **design** | `/design` |
| Agent self-exit | **self** | `/self:close` |

`work` owns delivery across all kinds of work. `code` owns engineering assessment,
review, refactoring, and codebase learning.

## What ships here

| Plugin | Commands | What it's for |
|---|---|---|
| [`code`](./code/README.md) | 4 | Engineering assessment and improvement: `/code:health`, `/code:review`, `/code:refactor`, and `/code:learn`. Review uses the portable [`code-reviewer`](../subagents/code-reviewer/AGENT.md). |
| [`work`](./work/README.md) | 5 | Shared delivery: `/work:dispatch`, `/work:resume`, `/work:loop` (`/loop`), `/work:commit` (`/commit`), and `/work:demo`. Queue delivery includes engineering and mixed work; `loop triage` decides the board. |
| [`research`](./research/README.md) | 2 | Get the real, evidenced answer — `/research` (`/research:research`) answers a hard research question across DISTINCT engines blind to each other (Codex/web, Grok/X, Antigravity/Google, Perplexity/broad Deep Research, Claude/deep-read + reconcile), cross-checks every claim (single-sourced = a lead, not a fact) and promotes a cited artifact; `/research:product` explores a PRODUCT hands-on — composes `research:research` for the claimed surface + sentiment, then signs up/installs and DRIVES the real product through each user journey (screenshot every step, a clip of the headline flow, favicon-tagged journey diagrams + claims-vs-reality), never one idle screenshot and a wall of text |
| [`swarm`](./swarm/README.md) | 4 | Fan a task across parallel agents — top-level `/swarm` + `/swarm:run`, `/swarm:plan`, `/swarm:spec`, `/swarm:debug` (test/qa removed; plan/spec require mock-ups) |
| [`fleet`](./fleet/README.md) | 2 | Fleet-wide ops — `/fleet:onboard` brings a bare box to parity and mints its agent auth in the same flow, `/fleet:profile` profiles a sluggish machine and attributes the load to agents-cli surfaces |
| [`design`](./design/README.md) | 5 | Create or refine systems, graphics, and interactive prototypes; critique existing design |
| [`self`](./self/README.md) | 3 | Agent self-operations — `/self:close` cleanly self-terminates the session (guarded SIGTERM to the harness); `/self:hibernate` sleeps the session until a future time; `/self:reflect` recalls corrections and constraints before revising work |
| [`sessions`](./sessions/README.md) | 2 | Session lifecycle + analytics — `/sessions:continue` finishes prior work here (crash recovery finishes headlessly via `/continue recover`), `/sessions:search` pulls ranked snippet-level context from prior sessions (falls back to a bundled `recall.py` that recovers assistant answers the index misses); `/sessions:finish`/`/sessions:insights`/`/sessions:fork` skills are reached only via their top-level `/finish` `/insights` `/fork` aliases, and `/recall` aliases `/sessions:search` |
| [`yc`](./yc/README.md) | 1 | Local recreations of YC startup products using a general-purpose agent plus focused skills/scripts; first recipe `/yc:workweave` turns indexed agent sessions, output, cost, resource use, hook/command latency, and friction into private HTML |

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
