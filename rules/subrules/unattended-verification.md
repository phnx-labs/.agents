# Unattended Work Fails Silently — Assert the Outcome, Not the Exit Code

The reliability rule for anything that runs while nobody watches: routines,
cron, loop drains, detached dispatches, teammates. Every failure mode observed
in real unattended runs was a *silent success* — dispatch exit 0 with no shell,
notify `ok:true` with nothing delivered, "running" records for dead processes,
probes that exercised the wrong operation class, a previous run's leftover
output read as current, accepted YAML that silently dropped a field, a shared
quota exhausted fleet-wide. The discipline is making the run prove it did the
thing.

- **Exit code 0 is not evidence.** An agent that hits a wall, explains it
  politely, and exits is a zero exit with no work done. Close every unattended
  unit by asserting a mechanically checkable postcondition — the PR exists, the
  change is on `origin/<default>`, the file has the expected content, the
  comment is on the ticket, the send result says delivered. If it fails, say
  **unverified** and name the gap; never round up to done.
- **Probe with the operation you will actually perform.** Writes probe a write;
  credentials probe a real authenticated request; delivery checks the send
  result — a dry-run only proves the address resolved.
- **Read status through the command surface** (`agents devices ps`,
  `agents sessions`, `gh pr view`), never raw cache files — and still bound the
  wait with a ceiling from the job's expected runtime. Reconciliation reads an
  artifact the finished process left behind; a killed process leaves nothing,
  and that record reports "running" forever.
- **Cross-run state:** key every artifact to this run's id, clear or ignore
  prior artifacts at start, and never read a result before its completion
  marker exists.
- **Budget shared quotas.** Fetch a list once per run and work from it; write
  only when something changed; on a rate-limit error stop touching that API for
  the run. GitHub meters REST and GraphQL separately — check both with
  `gh api rate_limit`.
- **Fail loud to the owner only when real:** silence on healthy runs, one clear
  message on a genuine block or repeated postcondition failure. A job that
  pings hourly trains the owner to ignore it — and a job that can no-op forever
  unnoticed is itself defective; escalate on a drought of successful
  postconditions.
