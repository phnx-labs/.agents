# Parallel Work via `agents teams`

Default to teams for changes touching 3+ independent surfaces. Skip for
exploration (use `Agent` subagents), single-surface bugs, and plan-mode
research.

## Boundary contracts are mandatory

Present a distribution plan before spawning. Each teammate gets: **Owns**
(explicit files), **Must NOT touch** (files owned by others), and shared deps
with one canonical owner. If A waits on B's output to start, the split is wrong
— re-cut, or sequence with `--after`.

## One worktree per edit-mode teammate

Never let parallel teammates share a checkout — shared index and files mean
cross-writes and merge chaos. `agents teams create <team> --enable-worktrees`,
then `agents teams add … --worktree <role>` (name unique per teammate, named
for the surface it owns; branches off freshly-fetched `origin/<default>`).
Teammates that must co-edit the same files aren't independent — collapse them
into one. Plan-mode (read-only) teams skip worktrees.

## Pattern

```bash
agents teams create my-feature --enable-worktrees
agents teams add my-feature claude "Owns: src/auth/*. Not: src/ui/*. …" --name auth --worktree auth --mode edit
agents teams add my-feature codex  "Owns: src/ui/*. Not: src/auth/*. …" --name ui   --worktree ui   --mode edit --after auth
agents teams start my-feature --watch
```

Every brief includes Mission, full scope, Owns / Must NOT touch, a concrete
code pattern, success criteria, the evidence line from `research-discipline`,
and these two contract lines verbatim:

> Post to the feed at IMPORTANT milestones only, never per step. Plain
> `agents feed post --title "<short subject>"` at start and at PR-opened. On
> final delivery — PR merged, or the composed work runs end-to-end — add
> `--level important`. On a real blocker use `--blocked` instead (never with
> `--level`). Do NOT narrate every step.

> Your task is complete only when your PR is merged, or you have handed it off
> by naming who/what now owns it. If waiting on CI or review, keep waiting with
> a background watch — `(gh pr checks <pr> --watch --fail-fast; echo "CI
> settled rc=$?")` run in the background, never a `while`/`until` loop — do
> not stop.

## Confirm a remote box can do the work BEFORE spawning

A box that cannot run the work still accepts the dispatch and exits 0. Probe
with the operation the teammate will perform — for edit-mode that's a real
write (`git fetch` + `git worktree add`), plus the harness signed in there. A
teammate that silently produced nothing gets counted as a green track and
composed on top of — worse than a loud failure.

## You own what you spawn

**Dispatching is never a handoff.** A session or teammate you spawned is not a
valid "named owner" for your own stop — the completion contract's handoff
clause names a person or a pre-existing owner, never your own children. While
your dispatches run, either keep checking them on a bounded cadence (about
every 5 minutes: `agents teams status` / `agents sessions preview <id>` /
`gh pr view <pr>`) until they land, or arm a durable watcher
(`agents monitors add` on each child PR, or ScheduleWakeup) and park quoting
the armed watcher. "The dispatched agents will post to the feed" is the
unfalsifiable park item 3 bans, not a watcher.

1. **Confirm the spawn.** `agents teams status <team>` must show each teammate
   RUNNING — an add/start exit 0 is not a running teammate.
2. **Arm a watcher that survives, and prove it.** `agents monitors add`, or a
   background command with a finish-echo — never `while true`/`until`/bare
   `sleep` loops (they die with their shell). A monitor whose run logs
   `skipped (no output captured)` owns nothing — drive in-session and keep it
   as backstop. If you can't show the watcher is alive, don't claim you're
   watching.
3. **Park with a checkable receipt** — "watcher pid 43234 alive; builder
   RUNNING 21m/294 tools on PR #2694", never the unfalsifiable "I'll be
   re-invoked when it settles".
4. **RUNNING with no new tool calls and no branch push is a stall.** Give every
   wait a ceiling from the job's expected runtime; past it, `agents teams
   resume` or re-dispatch. Waiting longer is not monitoring.
5. **Track progress on cheap signals** (`agents teams status`, `gh pr list`,
   `git ls-remote`). Full logs bill the whole transcript back to you — pull
   them only to grep a failure.
6. **Every tick wake drives, then re-arms.** While teammates or dispatches
   run, each wake — a tick firing, a background notification — produces a
   concrete drive action (merge a PR that is green and mergeable, steer or
   resume a stalled teammate, re-dispatch a dead track; a bare status check
   counts only when it finds nothing actionable) AND re-arms the next bounded
   tick about 5 minutes out: a background `sleep 300 && agents teams status
   <team>` with a finish-echo. A wake that emits only a status recap, or a
   park phrased "I'll surface on the next real event", is abandonment —
   `teams start --watch` settles only when the whole team settles, never on a
   single merge, so the "real event" you defer to may never re-invoke you. A
   real orchestrator recapped through five ticks while two green MERGEABLE
   PRs sat unmerged, until the user had to ask "have they landed the features
   or no?".

## Orchestrator completion — the seam, not the tracks

"All tracks merged" is not done. Each track's tests and reviewer only saw its
own diff, so the seam between tracks — where A calls what B built — is exactly
what nobody verified. The swarm is done only when the composed cross-track flow
ran end-to-end, against where the feature actually executes (the installed
binary / running daemon, not just `origin/main`), with real output quoted. A
seam that genuinely can't be exercised is named unverified — never folded into
"done end-to-end". The `verify-work-complete` Stop hook audits exactly this.
