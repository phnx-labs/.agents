---
description: Spawn parallel agents to work on a task together
---

You are organizing a team for: $ARGUMENTS

## Single Agent vs Team

First decide: do you need one agent or multiple?

- **One agent**: `agents run <agent> "prompt" --mode edit --timeout 30m`
- **Multiple agents**: continue below

## Create Team

```bash
agents teams create <team-name>

# Edit-mode teams: isolate each teammate in its own git worktree
agents teams create <team-name> --enable-worktrees
```

Use `--enable-worktrees` whenever teammates will **edit** in parallel, so they don't collide on one checkout — one worktree per teammate type / independent surface.

## Add Teammates

For each independent piece of work:

```bash
agents teams add <team-name> <agent> "prompt" --name <role> --mode edit

# With per-teammate worktree isolation (team created with --enable-worktrees):
agents teams add <team-name> <agent> "prompt" --name <role> --worktree <role> --mode edit
```

`--worktree <name>` gives the teammate a dedicated worktree at `.agents/worktrees/<name>` on branch `agents/<name>`. The name must be **unique per teammate**. Name it after the surface the teammate owns.

**Agent selection:**
| Agent | Best for |
|-------|----------|
| claude | Deep analysis, architecture, complex code |
| codex | Fast implementation, straightforward tasks |
| cursor | Debugging, tracing, bug fixes |
| antigravity | Multi-system features, large context |

**Prompt must include:**
- Background: what and why
- File paths with line numbers
- Code patterns inline (don't just reference)
- Success criteria
- Keep-the-owner-informed line (verbatim): `Post to the feed at IMPORTANT milestones only — one line at start, at PR-opened, and at merge/blocked (agents feed post). On final delivery, mark it --level important so it reaches the owner (agents notify). Do NOT narrate every step.`
- End with: `Return file:line quotes for every claim.`

## Dependencies (if needed)

```bash
agents teams add <team> claude "Build API" --name backend
agents teams add <team> codex "Build UI" --name frontend --after backend
```

## Start

```bash
agents teams start <team-name> --watch
```

**Keep the owner informed, not spammed — orchestrator posts at boundaries only:**

- On `teams start`, record one feed line: `agents feed post --title "Team spawned" "spawned team <name> — <N> teammates on <tickets>"`.
- On team completion, record one line naming the composed outcome.
- When the whole team's composed work is **delivered** (the cross-track flow runs end-to-end), or a teammate is **blocked**, deliver to the owner — `agents feed post --title "..." "..." --level important` (an `agents notify` for genuine deliveries; `--blocked` for a real blocker).

One post per boundary, never per tool call. This is the record-vs-deliver split from [`feed-status-posts.md`](../rules/subrules/feed-status-posts.md): plain posts stay in the stream, `--level important` / `agents notify` reaches the phone.

## Monitor

```bash
agents teams status <team-name>
agents teams logs <team-name> <role>
```

## Resume / Message a Teammate

When a teammate stops with more to do (PR left open, hit a turn cap, needs redirecting), re-enter its **own** session with a follow-up instead of finishing by hand or spawning a fresh, context-less teammate.

```bash
# Resume a stopped teammate — its own session, your message as the next turn:
agents teams resume <team-name> <role> "review's in — merge the PR, then release"

# Same command, auto-routed by state (running -> mailbox steer, stopped -> resume):
agents teams message <team-name> <role> "skip the flaky test for now"
```

Works for every harness — resume delegates to `agents run --resume`. Also nudge a still-running teammate: the message is steered into its mailbox and read at its next tool call.

## Cleanup

```bash
agents teams disband <team-name>
```
