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
| [`/plan`](./plan.md) | Plan with grounded design — research, read code, create artifacts, optionally get early review |
| [`/swarm`](./swarm.md) | Front door to the `swarm` plugin — fan work across parallel agents (`run` by default; or `plan` / `spec` / `debug`) |
| [`/debug`](./debug.md) | Trace the data path, hypothesize a root cause, then have independent agents confirm it before any fix (routes to `swarm:debug`) |
| [`/clean`](./clean.md) | Identify and clean up technical debt, outdated code, and duplicates |

Multi-agent plan/spec/debug live under `/swarm …` and `/swarm:plan` / `/swarm:spec` /
`/swarm:debug` (see [`plugins/swarm`](../plugins/swarm/README.md)).

## Ship and review

| Command | What it does |
|---|---|
| [`/finish`](./finish.md) | Drive the current task to done end-to-end instead of stopping at a recap, blocker, or partial handoff |
| [`/done`](./done.md) | Recap the session, then cleanly self-exit (SIGTERM the harness) |

`/done` **exits** the session and assumes the work already shipped. `/finish` keeps
working until it has. They are easy to confuse.

## Recap and resume

| Command | What it does |
|---|---|
| [`/recap`](./recap.md) | Recap the current session, or transfer concise context from a prior session selected by ID, prefix, or keywords |
| [`/continue`](./continue.md) | Alias of `/sessions:continue` — resume prior work **in this session** (reattach only if genuinely live); group-capable. Also finishes crashed sessions headlessly (`/continue recover`). |
| [`/insights`](./insights.md) | Alias of `/sessions:insights` — orchestrate `agents insights` + trends + perf + sessions stats into evidence-backed actions |
| [`/fork`](./fork.md) | Branch this conversation into a new, independent session and open it where you work — the "git branch" of sessions, original untouched |
| [`/restore`](./restore.md) | Alias of `/sessions:restore` — re-open sessions killed by a crash or reboot as terminal windows |

The procedures for `/continue`, `/insights`, and `/restore` live in the
[`sessions` plugin](../plugins/sessions/README.md) skills. Top-level files only invoke
those skills (same pattern as `/continue` → `/sessions:continue`).

`/hibernate` and `/reflect` moved to the [`self` plugin](../plugins/self/README.md) as `/self:hibernate` and `/self:reflect`.

## Coordinate

| Command | What it does |
|---|---|
| [`/tickets`](./tickets.md) | Work with the project's issue tracker — auto-detects Linear, GitHub Issues, or Jira |
| [`/triage`](./triage.md) | Sweep the whole board — ground in real product goals, then force every item to keep-and-schedule-this-cycle or cancel. Never Backlog |
| [`/dispatch`](./dispatch.md) | Take one task from idea to a working agent — understand the repo, spec fast, debug-skill for bugs, quick plan, file the ticket, dispatch |
| [`/loop`](./loop.md) | Alias of `/work:loop` — unattended multi-project work drain (any kind; spread load; no review gate; browser/computer ok) |
| [`/next`](./next.md) | Confirm the current task is actually done, then surface (and if clear, claim) the next related task — checks for in-flight PRs/sessions first so it never duplicates work |
| [`/teams`](./teams.md) | Spawn parallel agents to work on a task together |

`/tickets` is the general-purpose primitive (list, claim, comment, close). `/triage` is a
board-wide sweep that forces every open item to a real decision. `/dispatch` is the
single-task path from idea to a running agent. `/loop` / `/work:loop` is the unattended
**queue** drain across projects and kinds (not engineering-only). `/next` is the boundary
command — run it right after finishing something to move to the next thing without
re-deriving the tracker or duplicating a sibling agent's in-flight work. Easy to confuse:
`/triage` never touches code; `/dispatch` always ends with an agent building something;
`/loop` keeps going unattended until the clear queue is empty; `/next` picks among
*existing* tickets rather than creating one.

## Observe

| Command | What it does |
|---|---|
| [`/output`](./output.md) | Fleet-wide token-burn and output report across every device, rendered as an HTML dashboard and PDF |

Machine profiling moved to [`/fleet:profile`](../plugins/fleet/README.md); durable watchers are the `agents monitors` CLI + the [`monitors` skill](../skills/README.md).

## Related

Several commands escalate to `agents teams` when the scope is wide: `/debug`, `/plan`,
`/clean`, `/recap`, `/dispatch`.

Capabilities like `/secrets`, `/sessions`, and `/browser` are **skills**, not commands —
see [`skills/`](../skills/README.md). They are invoked the same way but carry their own
tooling. Plugins ship namespaced commands (`/code:loop`, `/swarm:run`, `/fleet:sync`) — see
[`plugins/`](../plugins/README.md).

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
