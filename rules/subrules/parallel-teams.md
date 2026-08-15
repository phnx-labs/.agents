# Parallel Work via `agents teams`

Default to teams for changes touching 3+ independent surfaces. Single-threaded editing is the failure mode.

**Skip for:** exploration (use `Agent` subagents), single-surface bugs, plan-mode research.

## Boundary contracts are mandatory

Before spawning, present a distribution plan. Each teammate needs:

- **Owns** — explicit files.
- **Must NOT touch** — files owned by others.
- **Shared deps** — one canonical owner; everyone else imports.

If A waits on B's output to start, the split is wrong. Re-cut, or sequence with `--after`.

## Isolate every edit-mode teammate in its own worktree

For edit-mode teams, give each teammate its **own** git worktree — never let parallel teammates share one checkout. A shared working tree means every teammate mutates the same index and files at once: cross-writes, stale reads, and merge chaos, and it only gets worse the more parallel the work is. One worktree per teammate (i.e. per teammate *type* / independent surface) keeps them truly parallel.

- `agents teams create <team> --enable-worktrees` — turns on per-teammate isolation for the team.
- `agents teams add ... --worktree <role>` — dedicated worktree at `.agents/worktrees/<role>` on branch `agents/<role>`, fetched and branched off `origin/<default>` (both local and `--device`-pinned remote worktrees share this base policy, so a stale local checkout can't fork a teammate off old code). **The name must be unique per teammate** — two teammates cannot share one worktree name (the second `git worktree add` fails).
- Name the worktree after the surface the teammate owns (`--worktree auth`, `--worktree ui`) so it lines up with the boundary contract.
- Teammates that genuinely must co-edit the same files aren't independent — collapse them into **one** teammate; don't split then re-share. (A team-wide `--use-worktree <path>` makes *all* teammates share one existing checkout — that reintroduces the contention this rule avoids, so reach for it only when every teammate must build against one tree.)
- **Skip for plan-mode** (read-only) teams — no writes, no contention, no worktree needed.

## Pattern

```bash
agents teams create my-feature --enable-worktrees
agents teams add my-feature claude "Owns: src/auth/*. Not: src/ui/*. ..." --name auth --worktree auth --mode edit
agents teams add my-feature codex  "Owns: src/ui/*. Not: src/auth/*. ..." --name ui   --worktree ui   --mode edit --after auth
agents teams start my-feature --watch
```

Every brief includes Mission, Full scope, Owns, Must NOT touch, concrete code pattern, success criteria, the feed/notify line (below), and ends with the evidence line from `research-discipline`. The `/teams` command is the long-form playbook.

## Keep the owner informed, not spammed (every brief)

The feed/notify instruction is part of the mandatory brief contract, next to Owns / Must NOT touch / the completion contract. Every teammate brief must carry it verbatim:

> Post to the feed at IMPORTANT milestones only, never per step. Use a plain `agents feed post --title "<short subject>"` at start and at PR-opened (record-only). On final delivery — PR merged, or the composed work runs end-to-end — add `--level important` so it reaches the owner (`agents notify`). If you hit a real blocker, use `agents feed post --blocked` instead (never combined with `--level`). Do NOT narrate every step.

The orchestrator itself posts one feed line on `teams start` and on team completion, and reaches the owner only at delivery (`agents feed post --level important` / `agents notify`) or when a teammate is blocked (`--blocked`). This is the record-vs-deliver split — see [`feed-status-posts.md`](feed-status-posts.md): plain posts stay in the activity stream, `--level important` reaches the phone, `--blocked` opens a needs-you record. A milestone is a boundary, never a keystroke.

## Confirm a remote teammate's box can do the work BEFORE you spawn it

A teammate pinned to another box inherits that box's capabilities, and a box that cannot
run the work still accepts the dispatch and **exits 0**. Edit-mode teammates write —
worktree, edits, commits, a PR — so probe the box with a real write (`git fetch` +
`git worktree add`), not a read-only ping, and confirm the harness is signed in there.
Codex in particular cannot write anywhere on this fleet today; send write-heavy
teammates to a harness/box confirmed by a write probe. Full detail:
`remote-fleet-dispatch`, `unattended-verification`.

A teammate that silently produced nothing is worse than one that failed loudly: the
orchestrator counts it as a green track and composes on top of work that does not exist.

## Completion contract (every edit-mode brief)

A teammate whose work produces a PR is done when the PR is **merged or explicitly handed off to a named owner** — nothing else counts. "PR open, CI green, waiting for reviewer" is NOT completed: it's the top observed way team output gets stranded (an entire 11-teammate run once ended with every PR unmerged). Every edit-mode brief must include the line:

> Your task is complete only when your PR is merged, or you have handed it off by naming who/what now owns it. If you are waiting on CI or review, keep driving it: background `(gh pr checks <pr> --watch --fail-fast; echo "CI settled rc=$?")` and then **read that result back yourself on a later turn** — a backgrounded watch does NOT re-invoke you, and never a `while`/`until` loop. Do not stop, and do not claim you will be notified.

Mechanical backstop: the `verify-work-complete` Stop hook blocks a session from stopping with an open PR it created and no handoff — but the brief line is what makes teammates drive to merge instead of arguing with the gate.

## You own what you spawn — an armed watcher is a claim you must verify

F3 and `unattended-verification` ("exit code 0 is not evidence") applied to the act of
spawning: the postcondition is a teammate that is actually running and a watcher that is
actually alive, not a command that returned 0.

Spawning is not delivering. The single most expensive orchestrator failure on this
fleet is: start teammates, announce "I'll keep watch", then idle while nobody tracks
whether the work is moving — or whether the teammates spawned at all.

Measured, session `ea913c60` (2026-08-15): the orchestrator backgrounded a
`while true; do … done` poll and told the user *"the background poll re-invokes me
when the team settles."* `ps` showed **no such process**. Four teammates were still
`RUNNING` with nothing watching them. The claim was false and the session was idle —
exactly what it promised it was not.

Five obligations, all mechanical:

1. **Confirm the spawn.** `agents teams add`/`start` returning 0 is not a running
   teammate. Confirm with `agents teams status <team>` that each teammate you added
   is actually `RUNNING`, and say how many. A teammate that silently never started is
   counted as a green track and composed on top of (see the boundary-contract note
   above).
2. **Know which watcher actually wakes you — on the installed fleet, almost none do.**
   Measured 2026-08-15 on agents-cli **1.22.39**, the installed *and* latest published
   version:

   | Mechanism | Does it re-invoke an idle session? |
   |---|---|
   | `run_in_background: true` Bash watch | **No.** The launch result promises a notification; across two full transcripts that string appears only at launch. The child lives; the wake-up never comes. |
   | `agents monitors add --run` | **No.** Fires `ok`, action logs `skipped  (no output captured)`, nothing spawned (RUSH-2681 — fixed upstream, unreleased). |
   | `agents pr land --detach` | **Does not exist** here (`unknown command 'pr'`; RUSH-2394 fix, unreleased). |
   | in-session `Agent` subagent | **Yes** — its completion notification re-enters the turn. Dies with the session. |
   | `ScheduleWakeup` / `Monitor` | **Unmeasured.** `operational` says never; the `verify-work-complete` Stop gate accepts only these as a durable owner. Unresolved — do not assert either way. |

   So: **never `while true`, `until [ … ]`, or a bare `sleep` loop** (they die silently
   with their shell), and **never tell the user a backgrounded watch will re-invoke
   you** — that sentence is false and is why the owner ends up pinging sessions one by
   one. Plan to read the result back yourself, or put the wait inside a subagent.
   **Registered is not running, and fired is not ran** — check `agents monitors logs
   <name>` for a `skipped` action before treating a monitor as an owner. **If you
   cannot show the watcher is alive, do not tell the user you are watching.**
3. **When you park on a watcher, hand the user a receipt they can check.** A healthy
   wait and a dead one look identical from the outside — an idle session and a shell
   that may or may not still be running — so the owner ends up pinging every session
   one by one to find out which is which. Measured 2026-08-15, three sessions that were
   visually indistinguishable: `6805bf66` was **healthy** (watcher pid alive, builder
   `RUNNING · 21.0 minutes · 294 tools` waiting on CI shards); `ea913c60` was **dead**
   (watcher process gone, four teammates orphaned); `pr306-land` was **decorative** (fire
   logged `ok`, action `skipped`, nothing spawned). Never write the unfalsifiable form
   ("I'll be re-invoked when it settles") — write what can be checked at a glance:
   *"watcher pid 43234 alive; builder RUNNING 21m/294 tools on PR #2694; blocked on CI
   shards 1-2."* If you cannot produce those numbers, you do not have a watcher.
4. **A teammate `RUNNING` with no new tool calls and no branch push is a stall, not
   progress.** `--watch` blocks until the DAG drains and has no stall timeout, so one
   wedged teammate turns a correct watcher into an infinite wait that never re-invokes
   anyone. Give every wait a ceiling drawn from the job's own expected runtime; past it,
   `agents teams resume` the teammate or stop and re-dispatch it. Waiting longer is not
   monitoring.
5. **Track progress on cheap signals, never full logs.** `agents teams status`,
   `gh pr list`, `git ls-remote` answer "is it moving?". `agents teams logs` /
   `agents logs <id>` bill a teammate's whole transcript back to you as input —
   pull them only to grep a failure or decide on a restart. `RUNNING` for 27 minutes
   with no branch pushed is a **stall**: resume or re-dispatch it, don't keep waiting.

## Orchestrator completion contract (the whole swarm, not each track)

A teammate is done when its PR merges. **The orchestrator is not** — "all tracks merged" is the most seductive false finish line a swarm has. Each teammate's tests, its reviewer, and its CI only ever saw that teammate's own diff, so the one thing no track verified is the **seam between tracks**: where track A calls what track B built. That is exactly where the composed feature breaks (a real case: `imessage_dispatch.go` shelled out to `agents mission-control digest`, but the digest track shipped a bin named `mission-control-digest` — every PR was green, the feature was dead, and it was declared "landed end-to-end" without ever being run).

So the orchestrator's task is done only when:

- The **composed cross-track flow has been triggered end-to-end** — the actual user path that crosses the seams the tracks share — and its **real output quoted**. Not "3/4 PRs merged", not "CI green on each", not a table of green checkmarks.
- The verification runs against where the feature **actually executes** (the running daemon / installed binary / deployed service), not just `origin/main` — merged is not deployed, and code on `main` that no running process has loaded is not "working" (F3).
- If a seam genuinely can't be exercised, that hop is named as **unverified** in the recap — never folded into a "done end-to-end" claim. A green table is a report of merges, not proof of a working feature.

Mechanical backstop: for a session that ran an edit-mode swarm, the `verify-work-complete` Stop hook fires a swarm-specific self-audit when the final message claims completion — demanding the composed cross-track flow's real output, not per-track CI.
