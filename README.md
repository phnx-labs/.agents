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
**system layer** — the baseline that lands at `~/.agents/.system/` on every machine.

**Current cut: [`v0.2.0`](https://github.com/phnx-labs/.agents-system/releases/tag/v0.2.0)**
(2026-08-06). See [`CHANGELOG.md`](./CHANGELOG.md). There is no separate npm package for this
repo: hosts get it by **git pull of this repository** into the system layer.

```bash
agents repo pull system    # fast-forward ~/.agents/.system to origin
agents sync                # re-materialize hooks/rules/skills into agent homes
```

`agents setup`, SessionStart autosync, and the optional `check-updates` routine also keep
the layer current. Pin or inspect with `git -C ~/.agents/.system describe --tags`.

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

## What should I run?

Slash commands and plugins are how you steer an agent. Skills hold the long procedures;
many commands only say "invoke this skill." Use this map when you are not sure which verb
to type.

### By goal

| I want to… | Run | Plugin / notes |
|---|---|---|
| **Drain everything overnight** (any project, code *or* browser/outreach) without waiting on me | `/work:loop` | [`work`](plugins/work/README.md) — spreads load across accounts/hosts; **merges on green** behind a non-author review instead of leaving PRs for you |
| Finish a **queue of engineering tickets** (merge-oriented) | `/code:loop` | [`code`](plugins/code/README.md) — worktrees, CI, review/merge |
| **One** clear task (any kind) to an agent | `/work:dispatch` or `/dispatch` | `work` for kind-agnostic; top-level `/dispatch` leans engineering |
| Decide keep/cancel/priority on the **whole board** | `/work:triage` | Not a builder — decision layer only |
| Drive the **current task** to fully delivered | `/finish` | [`sessions`](plugins/sessions/README.md) — never stops at a recap or partial handoff |
| Fan work across **parallel agents** | `/swarm` (or `/swarm plan` / `spec` / `debug`) | [`swarm`](plugins/swarm/README.md) |
| Plan a feature with live research, diagrams, mock-ups + blind check | `/swarm plan …` or `/plan` | Swarm plan is multi-agent; `/plan` is single-agent grounded design |
| Durable **source-of-truth spec** of a capability | `/swarm spec …` | So others do not invent wrong behavior |
| Debug a non-obvious bug | `/debug` → `swarm:debug` | Blind multi-provider root cause |
| Resume prior work in **this** window | `/continue` | [`sessions`](plugins/sessions/README.md) |
| Re-open crash sessions as **windows** | `/sessions:restore` | Not the same as `/continue` |
| Finish many interrupted sessions **headlessly** | `/continue recover` | Mode of sessions continue |
| How we have been working (analytics) | `/insights` | insights + trends + perf + stats |
| Score a repository's structure for coding agents | `/code:score` | `AGENTS.md` coverage, directory organization, ranked visual report |
| Review PRs this session (or a whole repo scan) | `/code:review` | `code:review` — three modes |
| Learn a codebase into project `AGENTS.md` | `/code:learn` | Durable nav notes for future agents |
| Design / mockup offline | `/design` | [`design`](plugins/design/README.md) |
| Share an HTML plan/report | `/share` (`--private` for `--no-cover --expire 7d`) | [`share`](plugins/share/README.md) |
| Fleet: pull every device to latest | `/fleet:sync` | [`fleet`](plugins/fleet/README.md) |
| Drive a **website** | skill `browser` (`agents browser`) | Not a slash command — load the skill |
| Drive a **native Mac app** | skill `computer` | Same |
| Credentials | skill `secrets` | `agents secrets` |

### By situation (quick FAQ)

| Situation | Do this |
|---|---|
| "Keep moving — finish the queue while I sleep" | `/work:loop` on a **worker** host (not your interactive laptop). Prefer `agents run claude "/work:loop" --mode auto --device yosemite-s0` (or your worker). |
| "Only ship code PRs to merge" | `/code:loop` with a ticket filter — merge-oriented engineering loop. |
| "One ticket, not sure if code or web" | `/work:dispatch RUSH-1234` — classifies and routes. |
| "Board is a mess of maybe-later items" | `/work:triage` first, then `/work:loop` or `/code:loop` on what remains. |
| "Agents keep hitting rate limits / logouts" | Use `/work:loop` (forced load-spread) or `/swarm` with mixed harnesses and `--strategy balanced` — never one long single-account session. |
| "Machine crashed; windows are gone" | `/sessions:restore` for Ghostty/terminal relaunch; `/continue recover` to finish work headlessly. |
| "Pick up where that session left off" | `/continue <id-or-topic>`. |
| "Is this bug real / where is the root cause?" | `/debug`. |
| "What should I type for a random ask?" | Prefer a **verb that matches the outcome** (table above). If nothing fits, plain chat is fine — then fold a repeated pattern into a skill later with `/code:learn` or the top-level `learn` skill. |

### Plugins at a glance

| Plugin | Reach for it when… | Not when… |
|---|---|---|
| **[`work`](plugins/work/README.md)** | Multi-project, multi-kind, unattended drain; one mixed task | Pure engineering merge queue only → use `code` |
| **[`code`](plugins/code/README.md)** | Engineering loop, PR review, commit split, project AGENTS.md learn | Browser outreach / overnight mixed board → use `work` |
| **[`swarm`](plugins/swarm/README.md)** | You need parallel independent tracks or blind verification | Single small edit |
| **[`sessions`](plugins/sessions/README.md)** | Resume, restore windows, session analytics | Starting brand-new work |
| **[`fleet`](plugins/fleet/README.md)** | Many machines must stay in sync / onboard a box | Single-machine day-to-day |
| **[`share`](plugins/share/README.md)** / **[`design`](plugins/design/README.md)** | Publish HTML or render design offline | Shipping app code |

Catalog detail: [`plugins/README.md`](plugins/README.md) · full command list: [`commands/README.md`](commands/README.md).

## Automate your work

The system layer is built so agents can **run without you in the loop**. Patterns that work:

### 1. Overnight drain (recommended default)

Drain clear, unblocked work across projects — code PRs left for your review in the morning;
browser/portal/outreach finished when the agent can complete them alone.

```bash
# One-shot now on a worker (example)
agents run claude "/work:loop overnight" \
  --mode auto \
  --strategy balanced \
  --device yosemite-s0 \
  --timeout 4h
```

Or type **`/work:loop`** inside an agent session on a worker host.

That skill **spreads load** (teams + balanced accounts + re-home on logout/rate-limit). Do
not point the whole night at a single Claude account on one machine.

### 2. Engineering-only queue to merge

```text
/code:loop --label=…     # or a ticket id, or empty to resume
```

Use when "done" means **merged**, not merely "PR open."

### 3. Schedule it (cron)

[`routines`](skills/routines/SKILL.md) + the **continuous ticket drain** recipe in that
skill: one drain routine per worker, unattended `work:loop` or `code:loop`, overlap lock,
park blockers and continue. Register with `agents routines add ./drain-worker.yml`.

```bash
agents routines list
agents routines run drain-s0    # foreground test
```

### 4. One task at a time

```text
/work:dispatch RUSH-1234
/dispatch fix the menubar reclaim bug
```

### 5. After a crash

```text
/sessions:restore    # put windows back
/continue recover    # finish interrupted work headlessly
/continue <id>       # resume one thread here
```

### Skill-first note

Many harnesses load **skills** better than long slash-command bodies. Plugin commands are
thin wrappers (`Invoke the \`work:loop\` skill`). Prefer skills when automating headless
runs if a harness ignores command text.

## What's inside

Each directory has a `README.md` for humans (a catalog of everything in it) and an
`AGENTS.md` for agents (the rules for changing it).

| Directory | What it holds |
|---|---|
| [`commands/`](commands/README.md) | Slash commands — `/finish`, `/visualize`, `/code:loop`, `/code:score`, `/swarm`, `/continue`, … (see guide above) |
| [`skills/`](skills/README.md) | Skills — multi-file capabilities like `browser`, `teams`, `sessions`, `mq` |
| [`plugins/`](plugins/README.md) | Plugins — `work` (drain any kind), `code`, `swarm`, `sessions`, `fleet`, `share`, `design`, … |
| [`hooks/`](hooks/README.md) | Lifecycle scripts — session-start context injection, prompt expansion, Stop checks, guards |
| [`rules/`](rules/README.md) | The ruleset every agent gets as its memory file, composed from `subrules/` |
| [`permissions/`](permissions/README.md) | Canonical YAML permission rules, translated per agent |
| [`clis/`](clis/README.md) | Manifests for host CLIs (`mq`, `jq`, `linear`) that agents-cli installs |
| [`routines/`](routines/README.md) | Scheduled agent runs (cron / one-shot) |
| [`monitors/`](monitors/README.md) | Event-triggered watchers — poll a source, fire an action on change |
| [`subagents/`](subagents/README.md) | Named sub-agent definitions |
| [`webhooks/`](webhooks/README.md) | Inbound webhook handlers |

## Hooks change runtime — commands do not

| Surface | Runtime effect | User control |
|---|---|---|
| **Hooks** | Fire on SessionStart, PreToolUse, Stop, … without the agent “opening” them | Disable / re-enable per name (below) |
| **Commands / skills / plugins** | Available as tools; agents invoke them on demand | Always present; ignore if unused |
| **Rules** | Always-on memory / policy text | Override with a same-named user rule |

**Disable a system hook** (user layer wins after `agents sync`):

```yaml
# ~/.agents/agents.yaml
hooks:
  linear-tasks:
    enabled: false          # no Linear board inject at SessionStart
  expand-bang-commands:
    enabled: false          # bangcuts — see below
```

**Turn bangcuts off** (`` `!cmd` `` expansion — **shell from the prompt**). It is **on by
default** as of RUSH-2405, so any prompt carrying a bang block runs that command locally,
including a prompt injected by a watchdog, a monitor, or another agent. Disable it with the
same YAML as any other hook:

```yaml
# ~/.agents/agents.yaml
hooks:
  expand-bang-commands:
    enabled: false
    override: true          # optional — only silences the shadow warning
```

Then `agents sync`. See [`hooks/README.md`](./hooks/README.md#enabling-and-disabling-hooks).

Details and the full hook catalog: [`hooks/README.md`](hooks/README.md). A first-class
`agents hooks enable|disable` CLI is planned; YAML overlay is the supported path today.

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
