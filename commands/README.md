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
| [`/plan`](./plan.md) | Plan like a staff engineer — live research, system diagrams, alternatives considered, rendered as a visual HTML artifact opened on your screen (subsumes `/visualize`) |
| [`/swarm`](./swarm.md) | Front door to the `swarm` plugin — fan work across parallel agents (`run` by default; or `plan` / `spec` / `debug`) |
| [`/debug`](./debug.md) | Trace the data path, attribute regressions to the responsible agent/session and explain how they slipped, then have independent agents confirm the root cause (routes to `swarm:debug`) |
| [`/blame`](./blame.md) | Trace a regression — a feature that worked and silently broke — to the culprit change, the removed/skipped test that let it through, and the agent/session behind it. Read-only forensics, no fix |

Multi-agent plan/spec/debug live under `/swarm …` and `/swarm:plan` / `/swarm:spec` /
`/swarm:debug` (see [`plugins/swarm`](../plugins/swarm/README.md)). Cleaning up technical
debt moved into the code plugin, and became architectural restructuring there:
[`/code:refactor`](../plugins/code/README.md).

## Ship and review

| Command | What it does |
|---|---|
| [`/finish`](./finish.md) | Alias of `/sessions:finish` — drive the current task all the way to delivered: verify end-to-end, docs, commit, PR, release checklist, close the ticket. Never stops at a recap, blocker, or partial handoff |
| [`/demo`](./demo.md) | Alias of `/work:demo` — demonstrate landed work: recover the original intent, exercise the shipped thing in its REAL environment on real representative inputs (signed in as the owner via `agents browser`/`agents computer`), before/after side by side with a measured delta, then deliver an analyzed report on your screen + the PR. The answer to "show me a demo.." |

Reviewing and merging PRs is [`/code:review`](../plugins/code/README.md). To
recap-and-leave, run `/recap` then [`/self:close`](../plugins/self/README.md).

## Recap and resume

| Command | What it does |
|---|---|
| [`/recap`](./recap.md) | Recap the current session, or transfer concise context from a prior session selected by ID, prefix, or keywords |
| [`/continue`](./continue.md) | Alias of `/sessions:continue` — resume prior work **in this session** (reattach only if genuinely live); group-capable. Also finishes crashed sessions headlessly (`/continue recover`). |
| [`/resume`](./resume.md) | Alias of `/work:resume` — pick a whole **project's** work back up: best-effort detect the project from the CWD (git repo + subdir → Linear), reconstruct its in-flight work (sessions, PRs, worktrees, tickets), then **offload** each item to a `role=worker` device — never the personal box. One project (vs `/work:loop`'s whole board). |
| [`/insights`](./insights.md) | Alias of `/sessions:insights` — orchestrate `agents insights` + trends + perf + sessions stats into evidence-backed actions |
| [`/recall`](./recall.md) | Alias of `/sessions:search` — pull ranked, snippet-level context from prior sessions on a topic, without loading full transcripts. Falls back to the bundled `recall.py` when the CLI is thin — it's the only path that recovers assistant answers, since the index never stores them. |
| [`/fork`](./fork.md) | Alias of `/sessions:fork` — fork this conversation into a NEW, independent session in a fresh terminal; the original is untouched. |
| [`/learn`](./learn.md) | Post-session reflection that writes durable improvements forward — distill the lessons that generalize and route them to the right skill/rule/memory; `/learn <target>` audits one skill or command across all past sessions |

The procedures for `/continue`, `/insights`, `/recall`, and `/fork` live in the
[`sessions` plugin](../plugins/sessions/README.md) skills; `/resume` lives in the
[`work` plugin](../plugins/work/README.md). Top-level files only invoke those skills (same
pattern as `/continue` → `/sessions:continue`). Recovering after a crash finishes the work
headlessly via [`/continue recover`](../plugins/sessions/README.md) — the old
window-reopening `sessions:restore` was removed.

`/hibernate` and `/reflect` moved to the [`self` plugin](../plugins/self/README.md) as `/self:hibernate` and `/self:reflect`.

## Coordinate

| Command | What it does |
|---|---|
| [`/dispatch`](./dispatch.md) | Take one task from idea to a working agent — understand the repo, spec fast, debug-skill for bugs, quick plan, file the ticket, dispatch |
| [`/teams`](./teams.md) | Spawn parallel agents to work on a task together |

The `tickets` skill is the general-purpose primitive (list, claim, comment, close).
[`/work:loop triage`](../plugins/work/README.md) is a board-wide sweep that forces every open
item to a real decision — keep-and-schedule-this-cycle or cancel, never Backlog.
`/dispatch` is the single-task path from idea to a running agent.
[`/work:loop`](../plugins/work/README.md) is the unattended **queue** drain across projects
and kinds (not engineering-only). Easy to confuse: `/work:loop triage` decides the board
without touching code; `/dispatch` always ends with an agent building something;
`/work:loop` keeps going unattended until the clear queue is empty.

## Present

| Command | What it does |
|---|---|
| [`/visualize`](./visualize.md) | Turn any concept, dataset, or finding into one self-contained branded HTML visual — infographic, explainer, status dashboard, data story, comparison. Routes to the `artifacts` skill's `kind: visual` |

## Observe

Machine profiling is [`/fleet:profile`](../plugins/fleet/README.md); durable watchers are the `agents monitors` CLI + the [`monitors` skill](../skills/README.md).

## Related

Several commands escalate to `agents teams` when the scope is wide: `/debug`, `/plan`,
`/recap`, `/dispatch` (and `/code:refactor`, for independent moves in its landing phase).

Capabilities like `/secrets`, `/sessions`, and `/browser` are **skills**, not commands —
see [`skills/`](../skills/README.md). They are invoked the same way but carry their own
tooling. Plugins ship namespaced commands (`/code:loop`, `/swarm:run`, `/fleet:sync`) — see
[`plugins/`](../plugins/README.md).

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
