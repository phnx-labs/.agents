<p align="center">
  <img src=".assets/fleet.png" alt="agents-cli — one mesh, many machines, fully wired" width="100%">
</p>

<h1 align="center">.agents-system</h1>

<p align="center">
  <b>The system layer for <a href="https://www.npmjs.com/package/@phnx-labs/agents-cli">agents-cli</a></b><br>
  npm-shipped defaults — commands, skills, plugins, hooks, rules, and permissions — that every agent inherits.
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/@phnx-labs/agents-cli"><img src="https://img.shields.io/npm/v/@phnx-labs/agents-cli.svg?style=flat-square&label=agents-cli" alt="npm version"></a>
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="license MIT">
  <img src="https://img.shields.io/badge/PRs-welcome-a3e635?style=flat-square" alt="PRs welcome">
  <img src="https://img.shields.io/badge/layer-system-22d3ee?style=flat-square" alt="system layer">
</p>

<p align="center">
  <img src=".assets/claude.png" height="34" alt="Claude Code" title="Claude Code">&nbsp;&nbsp;
  <img src=".assets/chatgpt.png" height="34" alt="Codex" title="Codex">&nbsp;&nbsp;
  <img src=".assets/gemini.png" height="34" alt="Gemini" title="Gemini">&nbsp;&nbsp;
  <img src=".assets/cursor.png" height="34" alt="Cursor" title="Cursor">&nbsp;&nbsp;
  <img src=".assets/opencode.png" height="34" alt="OpenCode" title="OpenCode">
</p>

---

## What this is

A **DotAgents repo**: a directory of agent config that `agents-cli` reads. This one is the
**system layer** — the baseline that ships with the CLI and lands at `~/.agents/.system/` on
every machine.

You rarely edit it. `agents-cli` stacks four repos of the same shape and merges them, so your
own tweaks sit above the shipped defaults:

| Layer | Path on disk | Edited by |
|---|---|---|
| **Project** | `<project>/.agents/` | project maintainers |
| **User** | `~/.agents/` | **you** |
| **Extras** | `~/.agents-<alias>/` | opt-in bundle authors |
| **System** | `~/.agents/.system/` *(this repo)* | upstream PRs |

Resources resolve **project → user → extras → system**. A same-named resource at a higher
layer wins; everything else unions in.

> **Want to change something?** Don't edit this repo. Add the same-named file under
> `~/.agents/` and it wins. On your machine this repo is a **pull-only mirror** — local edits
> are overwritten on the next update.

## Quick start

```bash
npm install -g @phnx-labs/agents-cli
agents setup     # clone this repo into ~/.agents/.system/ + install agent CLIs
agents view      # what's installed across every agent and version
agents doctor    # every warning at a glance: repo-behind, sign-in, sync status, orphans
```

## What's inside

Each directory has a `README.md` for humans (a catalog of everything in it) and an
`AGENTS.md` for agents (the rules for changing it).

| Directory | What it holds |
|---|---|
| [`commands/`](commands/README.md) | Slash commands — `/plan`, `/debug`, `/finish`, `/output`, one `.md` per command |
| [`skills/`](skills/README.md) | Skills — multi-file capabilities like `browser`, `teams`, `sessions`, `mq` |
| [`plugins/`](plugins/README.md) | Plugins — bundles of related skills and commands (`code`, `swarm`, `fleet`, `share`) |
| [`hooks/`](hooks/README.md) | Lifecycle scripts — session-start context injection, prompt expansion, Stop-gates, guards |
| [`rules/`](rules/README.md) | The ruleset every agent gets as its memory file, composed from `subrules/` |
| [`permissions/`](permissions/README.md) | Canonical YAML permission rules, translated per agent |
| [`cli/`](cli/README.md) | Manifests for host CLIs (`mq`, `jq`, `linear`) that agents-cli installs |
| [`routines/`](routines/README.md) | Scheduled agent runs (cron / one-shot) |
| [`subagents/`](subagents/README.md) | Named sub-agent definitions |
| [`webhooks/`](webhooks/README.md) | Inbound webhook handlers |

## How a change reaches your agents

Editing a layer does **not** change your agents. The layers are the source; each agent home
(`~/.claude/`, `~/.codex/`, …) is a materialized copy. You edit, then **sync** — a deliberate
step that does not run on launch.

```
   ~/.agents/.system/   ┐
   ~/.agents-<alias>/   ├─ merge (project→user→extras→system) ─► agents sync ─► ~/.claude/  ~/.codex/  ~/.gemini/ …
   ~/.agents/           │                                        (materialize)   (per agent + version)
   <project>/.agents/   ┘
```

| I want to… | Command |
|---|---|
| Update the shipped defaults | `agents repo pull system` |
| Update everything, then re-materialize | `agents sync` |
| Sync into one agent, or every version of it | `agents sync claude` · `agents sync claude@all` |
| Rebuild homes with no git or network | `agents repo refresh` |
| Heal every gap across every installed version | `agents doctor --fix` |
| Add an opt-in extras bundle | `agents repo add gh:owner/.agents-work` |

### Is it out of date?

`agents doctor` is the one place that collects every drift warning, and it reports two
independent kinds of "out of date":

- **Repo behind origin** — a *source* layer is outdated → `agents repo pull system`.
- **Materialization drift** — the source changed but the agent homes weren't rebuilt. The
  **Sync status** section labels each installed version `fresh`, `stale` (sources changed
  since last sync → `agents sync`), or `cold` (never synced).

`agents check` is the same detection as a script-friendly exit code for a pre-commit hook or
CI; `agents check --devices` runs it across every registered device.

### Look inside a layer

```bash
agents inspect system              # this repo: path, git state, sync ahead/behind, counts
agents inspect system --skills     # every skill this layer ships
agents inspect system --skill learn  # full detail for one resource (fuzzy match)
agents resources                   # the merged, first-wins surface across all four layers
```

## Customizing

Two supported paths — both keep this repo pull-only:

1. **Override one resource.** Drop a same-named file under `~/.agents/` (same directory shape
   as this repo), then `agents sync`.
2. **Add a whole bundle.** Register another repo that merges above system, below your user
   repo:
   ```bash
   agents repo add gh:phnx-labs/.agents-extras   # /verify, /animate, /image, /compose
   agents repo list
   agents repo disable extras                     # turn off without deleting
   ```

Extras are kept out of the system layer on purpose: they carry heavier dependencies and paid
API keys, so the default install stays fast and works anywhere with no setup.

## Contributing

Read [`AGENTS.md`](./AGENTS.md) first — it is the maintenance contract, and it lists what must
stay in sync when you add a command, skill, hook, permission, or plugin. Work in a worktree,
open a PR, never commit on `main`.

## Local-only (gitignored)

Runtime state written into this directory on your machine but never committed:
`versions/`, `shims/` (installed CLIs); `sessions/`, `swarm/`, `runs/`, `logs/` (execution
state); `permissions/groups/00-local.yaml`, `.environment`, `secrets`, `*.log`, `*.pid`
(machine-specific config). `agents.yaml` **is** tracked — it carries the hook manifest.

## License

MIT
