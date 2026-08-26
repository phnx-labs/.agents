# Commands

Slash commands are prompt templates. Type `/debug the auth flow` and
[`debug.md`](./debug.md) expands into a full debugging prompt, with your text replacing
`$ARGUMENTS`.

One `.md` file here becomes one `/<name>` command. Layered with `~/.agents/commands/`: a
same-named file in your user repo wins, everything else unions in.

**Not sure which command?** Start from the root guide:
[**What should I run?**](../README.md#what-should-i-run) and
[**Automate your work**](../README.md#automate-your-work) in the repo README.

**Command or skill?** A command is a one-shot prompt expansion — it fires once and is done.
A [skill](../skills/README.md) is a persistent capability that stays loaded, often with its
own scripts and reference files. Use a command for a methodology applied once. Plugin
commands are often thin wrappers that only invoke a skill (harness-friendly).

## Plan and build

| Command | What it does |
|---|---|
| [`/plan`](./plan.md) | Plan like a staff engineer — live research, system diagrams, alternatives considered, render HTML |
| [`/swarm`](./swarm.md) | Front door to the `swarm` plugin — fan work across parallel agents (`run` by default; or `plan` / `spec` / `debug`) |
| [`/debug`](./debug.md) | Trace the data path, attribute regressions to the responsible agent/session and explain how they slipped, then have independent agents confirm the root cause (routes to `swarm:debug`) |
| [`/blame`](./blame.md) | Trace a regression — a feature that worked and silently broke — to the culprit change, the removed/skipped test that let it through, and the agent/session behind it. Read-only forensics, no fix |

Multi-agent plan/spec/debug live under `/swarm …` and `/swarm:plan` / `/swarm:spec` /
`/swarm:debug` (see [`plugins/swarm`](../plugins/swarm/README.md)). Cleaning up technical
debt moved into the code plugin, and became architectural restructuring there:
[`/code:refactor`](../plugins/code/README.md).

## Ship and review

Driving the current task all the way to delivered is [`/finish`](./finish.md) — alias of
`/sessions:finish`: verify end-to-end, docs, commit, PR, release checklist, close the
ticket; it never stops at a recap, blocker, or partial handoff. Reviewing and merging PRs is
[`/code:review`](../plugins/code/README.md). To recap-and-leave, run `/recap` then
[`/self:close`](../plugins/self/README.md).

## Recap and resume

| Command | What it does |
|---|---|
| [`/recap`](./recap.md) | Recap the current session, or transfer concise context from a prior session selected by ID, prefix, or keywords |
| [`/continue`](./continue.md) | Alias of `/sessions:continue` — resume prior work **in this session** (reattach only if genuinely live); group-capable. Also finishes crashed sessions headlessly (`/continue recover`). |
| [`/insights`](./insights.md) | Alias of `/sessions:insights` — orchestrate `agents insights` + trends + perf + sessions stats into evidence-backed actions |
| [`/learn`](./learn.md) | Post-session reflection that writes durable improvements forward — distill the lessons that generalize and route them to the right skill/rule/memory; `/learn <target>` audits one skill or command across all past sessions |

The procedures for `/continue` and `/insights` live in the
[`sessions` plugin](../plugins/sessions/README.md) skills. Top-level files only invoke
those skills (same pattern as `/continue` → `/sessions:continue`). Re-opening crashed
sessions as windows is [`/sessions:restore`](../plugins/sessions/README.md) (no top-level
alias); `/fork` is [`/sessions:fork`](../plugins/sessions/README.md).

`/hibernate` and `/reflect` moved to the [`self` plugin](../plugins/self/README.md) as `/self:hibernate` and `/self:reflect`.

## Coordinate

| Command | What it does |
|---|---|
| [`/dispatch`](./dispatch.md) | Take one task from idea to a working agent — understand the repo, spec fast, debug-skill for bugs, quick plan, file the ticket, dispatch |
| [`/teams`](./teams.md) | Spawn parallel agents to work on a task together |

The `tickets` skill is the general-purpose primitive (list, claim, comment, close).
[`/work:triage`](../plugins/work/README.md) is a board-wide sweep that forces every open
item to a real decision — keep-and-schedule-this-cycle or cancel, never Backlog.
`/dispatch` is the single-task path from idea to a running agent.
[`/work:loop`](../plugins/work/README.md) is the unattended **queue** drain across projects
and kinds (not engineering-only). Easy to confuse: `/work:triage` never touches code;
`/dispatch` always ends with an agent building something; `/work:loop` keeps going
unattended until the clear queue is empty.

## Present

| Command | What it does |
|---|---|
| [`/visualize`](./visualize.md) | Turn any concept, dataset, or finding into one self-contained branded HTML visual — infographic, explainer, status dashboard, data story, comparison. Routes to the `artifacts` skill's `kind: visual` |

## Observe

The fleet token-burn / output report moved to [`/work:output`](../plugins/work/README.md); machine profiling to [`/fleet:profile`](../plugins/fleet/README.md); durable watchers are the `agents monitors` CLI + the [`monitors` skill](../skills/README.md).

## Related

Several commands escalate to `agents teams` when the scope is wide: `/debug`, `/plan`,
`/recap`, `/dispatch` (and `/code:refactor`, for independent moves in its landing phase).

Capabilities like `/secrets`, `/sessions`, and `/browser` are **skills**, not commands —
see [`skills/`](../skills/README.md). They are invoked the same way but carry their own
tooling. Plugins ship namespaced commands (`/code:loop`, `/swarm:run`, `/fleet:sync`) — see
[`plugins/`](../plugins/README.md).

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
