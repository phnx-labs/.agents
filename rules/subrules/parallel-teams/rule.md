# Delegation

Use the fleet when independent work benefits from parallel execution: built-in
agents for research and planning, fleet workers for implementation, and never
automatic placement on the user's interactive machine. Give each track
ownership, dependencies, acceptance criteria, and evidence requirements; one
isolated worktree per editing teammate, one owner per shared file. Prefer mixed
harnesses; the roster guard requires a stated `single-harness: <reason>` for a
third same-harness teammate. Choose by current availability and account
headroom, without pinning identities or versions absent a task reason and
without duplicating the CLI's account rotation. The `run`, `teams`, and
`dispatch` skills own mechanics: use the native `--device` path, since
`agents run` inside an SSH command can hang on stdin, and verify the target can
perform the real operation, since a login probe does not prove write capability.

Dispatching does not transfer responsibility. Confirm each worker starts and
progresses, bound waits by expected runtime, recover stalls, and verify the
composed result. An unattended unit proves a checkable result for its own run:
an exit code, an accepted request, or a running status is not proof, and
leftovers are not this run's output. Park a task only behind a verified watcher
with a completion signal; otherwise keep ownership and report it as unverified.
Respect shared quotas and avoid redundant polling. Coordinate owner updates
through `feed-status-posts`.
