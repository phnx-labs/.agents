# Commands

Slash commands are prompt templates. Type `/debug the auth flow` and
[`debug.md`](./debug.md) expands into a full debugging prompt, with your text replacing
`$ARGUMENTS`.

One `.md` file here becomes one `/<name>` command. Layered with `~/.agents/commands/`: a
same-named file in your user repo wins, everything else unions in.

**Command or skill?** A command is a one-shot prompt expansion — it fires once and is done.
A [skill](../skills/README.md) is a persistent capability that stays loaded, often with its
own scripts and reference files. Use a command for a methodology applied once.

## Plan and build

| Command | What it does |
|---|---|
| [`/plan`](./plan.md) | Plan with grounded design — research, read code, create artifacts, optionally get early review |
| [`/debug`](./debug.md) | Trace the data path, hypothesize a root cause, then have independent agents confirm it before any fix |
| [`/clean`](./clean.md) | Identify and clean up technical debt, outdated code, and duplicates |
| [`/test`](./test.md) | Test critical paths — parallel validation for complex scopes |

## Ship and review

| Command | What it does |
|---|---|
| [`/commit`](./commit.md) | Split the working tree into the maximum number of small logical commits, then push. Alias of `/code:commit` |
| [`/review`](./review.md) | Review every PR the session opened, then merge or request changes per verdict. Alias of `/code:review` |
| [`/finish`](./finish.md) | Drive the current task to done end-to-end instead of stopping at a recap, blocker, or partial handoff |
| [`/done`](./done.md) | Recap the session, then cleanly self-exit (SIGTERM the harness) |
| [`/prune`](./prune.md) | Delete merged branches and worktrees locally and on origin — conservative, never removes recoverable work |

`/done` **exits** the session and assumes the work already shipped. `/finish` keeps
working until it has. They are easy to confuse.

## Recap and resume

| Command | What it does |
|---|---|
| [`/recap`](./recap.md) | Recap the current session, or transfer concise context from a prior session selected by ID, prefix, or keywords |
| [`/continue`](./continue.md) | Resume one task — reattach if it is live, otherwise load its local or explicitly located remote transcript |
| [`/recover`](./recover.md) | Recover *many* crashed sessions — finish the agent-doable work headlessly, hand back the rest as one action |
| [`/restore`](./restore.md) | Re-open sessions killed by a crash or reboot as Ghostty windows, resuming each |
| [`/hibernate`](./hibernate.md) | Sleep this same session until a future time, then wake it with full context to check a long wait |
| [`/reflect`](./reflect.md) | Recall every correction and constraint from the active conversation before revising work |

## Coordinate

| Command | What it does |
|---|---|
| [`/tickets`](./tickets.md) | Work with the project's issue tracker — auto-detects Linear, GitHub Issues, or Jira |
| [`/triage`](./triage.md) | Sweep the whole board — ground in real product goals, then force every item to keep-and-schedule-this-cycle or cancel. Never Backlog |
| [`/dispatch`](./dispatch.md) | Take one task from idea to a working agent — understand the repo, spec fast, debug-skill for bugs, quick plan, file the ticket, dispatch |
| [`/teams`](./teams.md) | Spawn parallel agents to work on a task together |

`/tickets` is the general-purpose primitive (list, claim, comment, close). `/triage` is a
board-wide sweep that forces every open item to a real decision. `/dispatch` is the
single-task path from idea to a running agent. Easy to confuse: `/triage` never touches
code; `/dispatch` always ends with an agent building something.

## Observe

| Command | What it does |
|---|---|
| [`/monitors`](./monitors.md) | Set up a durable event-triggered watcher. Routines fire on a clock; monitors fire on a change |
| [`/output`](./output.md) | Fleet-wide token-burn and output report across every device, rendered as an HTML dashboard and PDF |
| [`/profile`](./profile.md) | Profile a sluggish machine, attribute the load to agents-cli surfaces, read the logs to root-cause it, and file a GitHub issue on the public agents-cli repo |

<p align="center">
  <img src="../.assets/monitors.png" alt="/monitors — a general-purpose watcher primitive for the agent fleet" width="82%">
</p>

## Related

Several commands escalate to `agents teams` when the scope is wide: `/debug`, `/plan`,
`/clean`, `/test`, `/recap`, `/review`, `/dispatch`.

Capabilities like `/secrets`, `/sessions`, and `/browser` are **skills**, not commands —
see [`skills/`](../skills/README.md). They are invoked the same way but carry their own
tooling. Plugins ship namespaced commands (`/code:loop`, `/swarm:run`, `/fleet:sync`) — see
[`plugins/`](../plugins/README.md).

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
