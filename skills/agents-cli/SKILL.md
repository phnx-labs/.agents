---
name: agents-cli
description: "Manage AI coding agent CLIs with agents-cli. Triggers on: 'agents add', 'agents use', 'agents pull', 'agents push', installing agent versions, syncing agent config, switching between agent versions, managing MCP servers, or when user mentions the agents-cli tool."
author: phnx-labs
version: 2.0.0
---

# agents-cli

`agents` is the control plane for AI coding agents on this machine. You have it available right now. It can do far more than version management — use it to recall prior work, coordinate parallel agents, dispatch to cloud, and drive interactive terminals.

When you need exact flags or syntax for anything below, run `agents <command> --help` directly.


## Session Recall

The most underused capability. Every conversation you (and other agents) have had is stored and searchable.

**You can search across sessions by topic, file path, or free text.** If you're about to implement something and wonder whether another agent already worked on it, search first.

**You can filter sessions by agent, project, or time window.** Useful when you want to see only Claude sessions from the last week, or all sessions touching a specific repo.

**You can extract specific roles from a session.** Pull only the user's messages to understand what was asked. Pull only thinking blocks to see the reasoning chain. Pull only tool calls to audit what was done. The `--include` and `--exclude` flags control this, and they compose with `--first`/`--last` to get a slice of the conversation.

**You can pull artifacts.** Every file written or edited during a session is tracked. You can list them or read a specific one by name — useful to recover work without re-reading the whole session.

**You can check what's running right now.** `--active` shows live sessions across terminals, teams, cloud, and headless agents. Use this before spawning duplicate work.

**You can read cloud-run sessions.** Sessions from cloud providers are also queryable via `--cloud`.

The key insight: sessions are your memory. Before starting a task, search for prior sessions on the same topic or repo. Before spawning a subagent, check if one is already active.


## Running Agents Programmatically

`agents run <agent> "prompt"` executes an agent headlessly and returns when done. You can set the reasoning effort, working directory, mode (plan/edit/full), and inject secrets or env vars. You can also resume a previous Claude session by session ID.

Use this when you want to delegate a bounded task to another agent and capture its output, rather than spawning a full team.


## Host Runs

Run an agent on another machine over SSH. The local CLI is just transport; tmux runs on the remote host.

```bash
# Interactive TTY session on the remote (no prompt required)
agents run claude --host yosemite-s0

# Headless task on the remote (still requires a prompt)
agents run claude "refactor auth" --host yosemite-s0

# Forward --mode, --model, --name, passthrough args after --, and --no-tmux
agents run claude --host yosemite-s0 --mode edit --model sonnet --name auth-refactor -- --no-tmux
```

- Omitting the prompt with `--host` takes the interactive path and forwards your local TTY.
- `--no-follow` is rejected for interactive host runs.
- `--interactive` and `--headless` are mutually exclusive.
- The remote machine must already have agents-cli installed and reachable; if not, enroll it with `agents hosts add <name>`.


## Teams: Parallel Multi-Agent Coordination

`agents teams` lets you create named groups of agents working in parallel on a shared task, with optional DAG-style dependencies (`--after`). Each teammate runs in the background; you use `status` to check in.

Team sessions appear in `agents sessions --teams` so you can read what each teammate did.

Use teams when a task has independent parallel workstreams (backend + frontend) or sequential dependencies (QA waits for both to finish). Run `agents teams --help` for the full interface.


## Cloud Dispatch

`agents cloud run` dispatches a task to a remote cloud agent. The task runs against a GitHub repo and branch. You can follow logs live, send follow-up messages, or cancel.

Use cloud dispatch when the task is too long-running for a local session, needs a clean environment, or should produce a PR.


## PTY: Interactive Terminal Sessions

`agents pty` gives you a real terminal session — essential for REPLs, TUIs, interactive CLIs, or anything that won't work in a plain shell. Start a session, send commands non-blocking, read the screen as clean text, send keystrokes.

You can also use `agents pty` to drive the `agents` CLI itself from within another agent — useful when you need to launch an interactive picker.


## Routines: Scheduled Recurring Agents

`agents routines` schedules agents to run on a cron schedule. Check existing routines before setting up new ones. You can run a routine immediately in the foreground to test it before enabling the schedule.


## Calling `agents` from automation

`agents` is a node program resolved via `/usr/bin/env node`. Automation contexts
with a minimal PATH — launchd/systemd units, cron, git hooks — must include a
node bin dir on PATH, or every `agents` call dies with
`env: node: No such file or directory` (silently, when stderr is redirected).
Symptom: a script that works in your shell no-ops under the scheduler.


## Version and Config Management

Install, switch, and inspect agent CLI versions. `agents view` shows installed versions and resources. `agents view <agent>@<version>` shows exactly what commands, skills, MCP servers, and memory files are active for a version.

Config (commands, skills, hooks, memory, MCP) is git-tracked in `~/.agents/` and syncs across machines via `agents pull` / `agents push`.
