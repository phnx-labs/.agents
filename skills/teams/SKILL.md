---
name: teams
description: "Organize AI coding agents into teams that collaborate on a shared task. Create teams, add teammates, start them, monitor progress, and collect results. Use this skill when you need parallel agent execution. For single-agent dispatch, use `agents run` instead."
argument-hint: "[create|add|start|status|disband]"
allowed-tools: Bash(agents teams*), Bash(agents run*)
user-invocable: true
---

# Teams Skill

## Build the roster from what is installed

Before the first `add`: list the harnesses installed and healthy on this
machine (`agents view`), then spread tracks across them — write-heavy tracks
on write-probed harnesses, read-only verifier tracks on harnesses whose
headless `plan` mode is real (see the capability note below). Harness names
in the examples here are anchors, not prescriptions: substitute from your
installed set. The bundled `teams-roster-guard` (parallel-teams subrule)
blocks a 3rd same-harness teammate on a multi-harness machine unless the
brief states `single-harness: <capability reason>` — mixed is the default,
monoculture is the documented exception.


Organize AI coding agents into teams for parallel collaboration. This skill teaches you how to use the `agents teams` CLI.

## Single Agent vs Teams

- **Single agent**: Use `agents run <agent> "prompt" --mode edit` for one-off tasks
- **Multiple agents**: Use `agents teams` when you need parallel execution

## Quick Start

```bash
# Create a team
agents teams create my-feature

# Add teammates
agents teams add my-feature kimi "Implement the auth middleware" --name auth
agents teams add my-feature codex "Build the login UI" --name frontend

# Start the team
agents teams start my-feature --watch
```

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `list` | List your teams, most recent activity first | `agents teams list` |
| `create` | Start a new team | `agents teams create my-team` |
| `add` | Add a teammate | `agents teams add my-team claude "Task" --name role` |
| `start` | Launch pending teammates | `agents teams start my-team --watch` |
| `status` | Check who's working | `agents teams status my-team` |
| `active` | List every teammate running right now, across all teams | `agents teams active` |
| `resume` | Resume a stopped teammate — re-enter its own session with a message | `agents teams resume my-team backend "review's in — merge it"` |
| `message` | Send a follow-up: steers a running teammate, resumes a stopped one | `agents teams message my-team qa "skip the flaky test"` |
| `stop` | Stop a running teammate (resume it later with `resume`) | `agents teams stop my-team frontend` |
| `pr-watch` | Watch the PRs a team opened and react (fix red CI / review comments) | `agents teams pr-watch my-team` |
| `logs` | Read teammate output | `agents teams logs my-team frontend` |
| `remove` | Remove a stopped teammate's logs | `agents teams remove my-team frontend` |
| `disband` | Stop all and remove | `agents teams disband my-team` |
| `doctor` | Check installed agents | `agents teams doctor` |

## DAG Dependencies

Use `--after` to create dependencies:

```bash
# Backend first
agents teams add my-feature grok "Build API" --name backend

# Frontend waits for backend
agents teams add my-feature codex "Build UI" --name frontend --after backend

# QA waits for both
agents teams add my-feature droid "Run tests" --name qa --after backend,frontend

# Start drains the DAG automatically
agents teams start my-feature --watch
```

## Distributed Teams (teammates on other machines)

Place teammates on **different machines** across your fleet (from `agents devices`)
instead of all on the box running `teams start`. One orchestrator still drives the
DAG, polls status, and cleans up — teammates just execute over SSH. One vocabulary —
`--device` / `--devices`; all optional (omit it and
every teammate runs local, exactly as before).

```bash
# Send ONE teammate elsewhere — no pool needed
agents teams create feat
agents teams add feat codex "build the API" --name backend --device yosemite-s0
agents teams add feat kimi "build the UI"   --name ui               # stays local
agents teams start feat --watch

# A device POOL — unpinned teammates auto-schedule across it (least-loaded)
agents teams create feat --devices zion,yosemite-s0 --repo https://github.com/you/repo.git
agents teams add feat grok "..." --name w1                          # auto-scheduled
agents teams add feat claude "..." --name w2 --device yosemite-s0    # or pin
```

**Where a teammate runs** — resolved at launch, top-down:

1. teammate `--device X` → **X** (explicit pin, no pool required)
2. else single-device pool → that device (whole team there)
3. else multi-device pool → **auto-scheduled** (least-loaded)
4. else → **local** (today's behavior)

- `--devices <list>` on `create` declares the pool; `--repo <url|path>` is how each
  device gets the code (defaults to the local checkout's `origin`, reused or cloned
  into `~/.agents/repos/<team>`). Per-teammate worktrees work over SSH too.
- `status` / `logs` show each teammate's host. **POSIX hosts only** in v1 (Windows
  hosts are rejected with a clear message).
- **`--remote-cwd` does not exist on `teams add` — it hard-errors, it is not a silent no-op.** `--remote-cwd` is an `agents run` flag; passing it to `teams add` fails loud with a hard error and a message pointing at `--worktree`/`--cwd` instead. A teammate's working directory is set by `--worktree <role>` (isolated) or `--cwd <dir>` (shared checkout) — never `--remote-cwd`.

## Modes

| Mode | Use When |
|------|----------|
| `plan` (default) | Read-only work: research, audit, analysis |
| `edit` | Code changes: implementation, refactoring |
| `auto` | Same as `edit`, plus harness-native auto-approval of safe operations — Claude/Copilot via the smart classifier (still prompts on risky ops), Codex via never-prompt `approval_policy=never`, Droid via `--auto high` |

Always use `--mode plan` for security audits, research, and analysis.

**Teammates run headless, so plain `edit` can stall waiting for an approval prompt
nobody answers.** `edit` lets a teammate write files but does not auto-approve
anything; an operation that requires approval just sits there unattended. `auto` runs
the same permissions plus each harness's native auto-approval that clears safe ops on
its own: Claude/Copilot's smart classifier, Codex's never-prompt
`approval_policy=never`, Droid's high-auto. It is usually the right default
for an unattended edit-mode teammate; reach for plain `edit` only when you actively
want it to pause on ambiguous operations (e.g. a human is watching that teammate's
session). Default coverage by harness: `plan`/`edit`/`auto` are all headless-capable
on claude/codex/droid/opencode; kimi/grok/cursor/antigravity have no headless `plan`
and silently downgrade a `plan` request to `auto`.

## Worktree Isolation (edit-mode teams)

By default all teammates share the current checkout. For parallel **edit** work, give each teammate its **own** git worktree so they don't collide on one working tree — one worktree per teammate type / independent surface.

```bash
# Turn on per-teammate isolation for the team
agents teams create my-feature --enable-worktrees

# Each teammate gets a dedicated worktree (.agents/worktrees/<name>, branch agents/<name>)
agents teams add my-feature kimi "Owns: src/auth/*" --name auth --worktree auth --mode edit
agents teams add my-feature codex  "Owns: src/ui/*"   --name ui   --worktree ui   --mode edit
agents teams start my-feature --watch
```

- **Name the worktree after the surface** the teammate owns; the name must be **unique per teammate** (two teammates can't share one worktree name).
- `--cwd <dir>` sets a plain working directory for a teammate when you don't want a worktree.
- `--use-worktree <path>` on `create` makes **all** teammates share one existing checkout — the opposite of isolation; use only when every teammate must build against one tree.
- **Skip worktrees for `--mode plan`** teams — read-only, no contention.
- Worktrees are cleaned up on `stop`/`disband` when clean, and kept if they have uncommitted changes.
- Both local and `--device`-pinned remote worktrees fetch `origin` and branch off `origin/<default>` — a stale local checkout can't fork a teammate off old code.

## The teammate brief contract (every edit-mode brief)

Every edit-mode brief carries the fixed parts — Mission, Full scope, **Owns**, **Must NOT touch**, a concrete code pattern, success criteria — ends with the evidence line (`Return file:line quotes for every claim`), and includes these two lines **verbatim**:

**Feed/notify** — keep the owner informed, not spammed:

> Post to the feed at IMPORTANT milestones only, never per step. Use a plain `agents feed post --title "<short subject>"` at start and at PR-opened (record-only). On final delivery — PR merged, or the composed work runs end-to-end — add `--level important` so it reaches the owner (deprecated alias: `agents notify`). If you hit a real blocker, use `agents feed post --blocked` instead (never combined with `--level`). Do NOT narrate every step.

**Completion contract:**

> Your task is complete only when your PR is merged, or you have handed it off by naming who/what now owns it. If you are waiting on CI or review, keep waiting with a background watch — `(gh pr checks <pr> --watch --fail-fast; echo "CI settled rc=$?")` run in the background, never a `while`/`until` loop — do not stop.

A teammate is done only when its PR is **merged or handed to a named owner** — "PR open, CI green, waiting for review" is the top way team output gets stranded (a real 11-teammate run once ended with every PR unmerged). The `verify-work-complete` Stop hook backstops this, but the brief line is what makes teammates drive to merge.

## Orchestrator: post at boundaries, verify the seam

You (the orchestrator) post one plain `agents feed post` on `teams start` and on team completion, and reach the owner only at delivery (`agents feed post --level important` (deprecated alias: `agents notify`)) or when a teammate is blocked (`--blocked`) — never `--level` together with `--blocked`.

**"All tracks merged" is not done.** Each teammate's tests and reviewer only saw its own diff; the **seam between tracks** — where track A calls what track B built — is the one thing nobody verified, and exactly where the composed feature breaks (a real case: a track shelled out to `agents mission-control digest` while the other track shipped a bin named `mission-control-digest` — every PR green, the feature dead). Before calling the swarm done: trigger the **composed cross-track flow end-to-end** against where it actually runs (installed binary / running daemon / deployed service, not just `origin/main`) and **quote its real output**. A green table is a report of merges, not proof of a working feature. If a seam genuinely can't be exercised, name it **unverified** — never fold it into "done end-to-end".

## Monitoring

**Spawning is not delivering. You own the team until it lands.** The most expensive
failure this skill has is an orchestrator that starts teammates, says "I'll keep
watch", and then sits idle while nobody tracks whether the work is progressing —
or whether the teammates even spawned. Measured on session `ea913c60`: the
orchestrator armed a `while true; do … done &` poll, told the user *"the background
poll re-invokes me when the team settles"*, and the loop was **dead** — `ps` showed
nothing, while four teammates were still RUNNING with no one watching.

### Arm a watcher that survives — then prove it is alive

```bash
# Durable (survives this session ending). Note the interval is a SECOND argument to
# --poll, and --run takes an agent NAME with the prompt in --prompt.
agents monitors add pr-sweep-done \
  --poll 'agents teams status my-feature --json' 5m \
  --run claude --prompt 'Team my-feature settled — verify each PR merged, then land it'

# In-session: background command + a finish-echo, so the harness re-invokes you.
( agents teams start my-feature --watch; echo "TEAM SETTLED rc=$? — next: verify each PR merged" )
```

Run the background form with `run_in_background: true`.

**Never** `while true`, `until [ … ]`, or a bare `sleep` loop. They exit silently
when the shell that owns them goes away, and you are left claiming a watch that
does not exist.

**Then assert it — this is F3 applied to the watcher itself.** A watcher is not armed
because the command returned 0. Check the postcondition and quote it:

```bash
agents monitors list | grep pr-sweep-done       # registered?
agents monitors logs pr-sweep-done              # did the ACTION actually run?
ps -p "$WATCH_PID" >/dev/null && echo alive     # background watcher still running?
```

**Registered is not running, and fired is not ran.** `agents monitors runs <name>`
reporting a fire as `ok` while `agents monitors logs <name>` reports that same run as
`skipped  (no output captured)` means the action never executed and no agent was
spawned — the monitor is decorative. Reproduced on agents-cli 1.22.39 on 2026-08-15,
which is both the installed and the latest published version (RUSH-2681). **While that
is true, a monitor cannot be the owner of anything** — drive the work in-session and
treat the monitor as a backstop.

If you cannot show that output, **do not tell the user you are watching.**

### Check progress at the service level, never the full log

Poll the cheap signals — they answer "is it moving?" without billing a teammate's
whole transcript back into your context:

```bash
# Check status
agents teams status my-feature

# Delta poll (efficient)
agents teams status my-feature --since 2026-04-24T09:00:00-07:00

# Ground truth for "did it actually deliver?" — cheaper and truer than any log
gh pr list --state open --limit 30 --json number,title,statusCheckRollup
git ls-remote --heads origin | grep my-feature
```

**`agents teams logs` is a debugging tool, not a progress check.** Reading a
teammate's transcript bills its output tokens back to you as input, for no signal
you cannot get above. Pull it only to `grep` the failing line when status already
says `FAILED`, or to decide whether to `resume` a stalled teammate.

### A teammate that stalls is yours to restart

`agents teams status` showing `RUNNING · 27 minutes · 50 tools` with no branch push
is a stall, not progress. Nudge it (`agents teams resume`, below) or stop and
re-dispatch it. Waiting longer is not monitoring.

## Resume / Message a Teammate

A teammate often stops with more to do — a PR left open awaiting review, a headless run that hit a turn cap, a task worth redirecting. `agents teams resume` re-enters that teammate's **own** session with your message as the next user turn, so it picks up with full context instead of you finishing by hand or spawning a fresh, context-less teammate.

```bash
# Nudge a teammate that stopped with its PR open:
agents teams resume my-feature backend "review's in — rebase-merge the PR, then release"

# teams message is the same command, auto-routed by the teammate's state:
agents teams message my-feature qa "skip the flaky screenshot test for now"
```

Routing: a **running** teammate is steered via its mailbox (delivered at its next tool call, no re-launch); a **stopped** one (completed / failed / stopped) is **resumed** — re-launched through its original backend/worktree and flipped back to `running`; a **pending** one is refused until you `teams start` it. Every harness: resume delegates to `agents run --resume` (native for Claude/Codex, `/continue` replay for the rest).

## Best Practices

- **Let account rotation default** — a bare `agents teams add <team> claude "…"` (no `@version`, no `--profile`) inherits the `balanced` strategy: weighted-random across healthy accounts by remaining headroom, skipping rate-limited ones. Pin `claude@<version>` or `--profile` only when a teammate needs a specific version/identity — pinning opts that teammate out of rotation.
- **Mix agents** if available — different agents have different blind spots
- **Use `--mode plan`** for read-only work (audits, research)
- **Give full context** — each teammate needs the big picture plus their specific task
- **Demand evidence** — end prompts with: `Return file:line quotes for every claim`
- **Run in parallel** — most tasks don't depend on each other
- **Name teammates** with `--name` for easy reference
- **Isolate edit-mode teammates** — `--enable-worktrees` on create + `--worktree <name>` per teammate, so parallel edits don't collide on one checkout

## Short Aliases

```
teams c  = create    teams a  = add       teams s  = status
teams rm = remove    teams d  = disband   teams ls = list
```
