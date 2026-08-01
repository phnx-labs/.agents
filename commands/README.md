# Commands

> Layered with `~/.agents/commands/`. Same name in your user repo wins; everything else unions in.

Slash commands are prompt templates. Type `/debug the auth flow` and the command file expands into a full debugging methodology prompt, with your text replacing `$ARGUMENTS`.

## How Commands Work

Each `.md` file in this directory becomes a slash command. The file content is a prompt template:

```markdown
---
description: Debug an issue with systematic root cause analysis
---

You are debugging: $ARGUMENTS

## The Discipline

The root cause is NEVER where the error appears...
```

When you type `/debug the login is broken`, Claude receives the full prompt with "the login is broken" substituted for `$ARGUMENTS`.

## Commands vs Skills

Commands are **one-shot prompt expansions** - they fire once and are done.

Skills are **persistent capabilities** - they load into context and stay active, often with supporting scripts and reference files.

Use a command when you want a specific methodology applied once. Use a skill when you need ongoing capability with tools and context.

## Commands

The command files in this directory, with optional team augmentation for complex scopes:

**Planning**
- `/plan` — Feature planning with mandatory artifacts (mockups, diagrams, state machines). Forces grounded discussion. For large features, automatically validates with a team.

**Debugging & Maintenance**
- `/debug` — Systematic root cause analysis. Maps the full data path, reads every file in the chain, builds evidence. For complex bugs, verifies with independent teammates.
- `/clean` — Remove tech debt, consolidate duplicate code, clean up patterns. For large codebases, parallelizes scanning across areas.
- `/recap` — Summarize the current situation — facts first, hypotheses grounded in evidence, next steps. Spawns teams for actionable items.
- `/test` — Identify critical paths and validate them. For complex scopes, distributes testing across a team.

**Shipping & Review**
- `/commit` — **Alias of `/code:commit`** (code plugin). Split changes into the maximum number of small logical commits and push in the background. Canonical definition lives in the `code` plugin; this is the short name.
- `/review` — **Alias of `/code:review`** (code plugin). Recap the session's goal, list every PR it opened, review each in parallel, then merge / request-changes / close-as-duplicate per verdict. Canonical definition lives in the `code` plugin; this is the short name.
- `/finish` — Anti-stopping driver **and** ship gate: refuses to stop at a recap/blocker/partial handoff and drives the task to delivered — verify E2E, docs, commit, PR, optional release, close tickets.
- `/done` — Recap the session for handoff, then cleanly **self-exit** (SIGTERM the harness). Assumes the work is already delivered; for the ship gate use `/finish`.
- `/prune` — Delete merged branches and worktrees locally and on origin. Conservative — never removes work that could be lost.

**Task Management**
- `/tickets` — Auto-detect the project's tracker (Linear / GitHub / Jira / etc.) and work with it. Uses whichever tracker skill is available; falls back to repo signals (`gh issue list`, etc.) if none is loaded.
- `/monitors` — Set up or manage a durable event-triggered watcher (`agents monitors`): watch a source (command / HTTP / file / fleet device), fire an agent / routine / notification on change. Routines fire on a clock; monitors fire on a change.
- `/continue` — Resume a previous task with context recovery (single session).
- `/recover` — Recover *many* interrupted sessions after a crash: find them across version homes, understand each in parallel, finish the agent-doable work headlessly (subagents / `agents teams`) rather than resurrecting a terminal swarm, and hand back only what needs the user — as one easy action. Holds irreversible/outward actions for an explicit yes.

**Delegation**
- `/teams` — Arrange agents into teams for parallel execution. Create, add members, start, monitor, and collect results.

**Observability**
- `/output` — Fleet-wide token-burn + shipped-output report over a window (default 24h). Runs `agents output --all-hosts`, re-queries relay-only machines that timed out, then renders an HTML dashboard, drops a PDF in `~/Downloads`, and opens it in the browser.

> Capabilities like `/secrets`, `/sessions`, `/audit`, and `/design` are **skills**, not commands — see [`skills/`](../skills/). They're invocable the same way (`/name`) but live in the skills layer with their own tooling and context.

## Team Augmentation

Several commands automatically use `agents teams` when the scope is complex:

- `/debug` — Verifies root cause with independent teammates for multi-service bugs
- `/plan` — Validates approach with independent planners for large features
- `/clean` — Parallelizes scanning across frontend/backend/shared/docs for large codebases
- `/test` — Distributes testing across areas for complex scopes
- `/recap` — Spawns teams for 2+ clear, actionable items instead of listing them
- `/review` — Reviews each open PR in parallel, one reviewer per PR

Run `agents teams --help` for team management commands.

## Creating Commands

1. Create `commands/<name>.md`
2. Add frontmatter with a `description`
3. Use `$ARGUMENTS` where user input should appear
4. Commit and sync (`agents pull` on other machines)

Keep prompts focused. One methodology per command. If you need scripts or reference files, make it a skill instead.

## Patterns Worth Noting

**Forcing functions** - Commands like `/plan` require artifacts before discussion. You can't hand-wave; you must draw the mockup first.

**Evidence chains** - `/debug` builds explicit chains: "file_a.ts:45 receives X, transforms to Y, passes to B" - making reasoning visible and verifiable.

**Grounded hypotheses** - `/recap` distinguishes facts from hypotheses, and requires evidence for each hypothesis.

These patterns prevent the most common failure mode: talking about code without reading it.
