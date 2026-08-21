# Unattended Work Fails Silently — Assert the Outcome, Not the Exit Code

The reliability rule for anything that runs while nobody is watching: routines, cron,
`work:loop` / `code:loop` drains, detached `--device` dispatches, teams teammates.
This is **F3 ("done = the user-visible outcome, verified") applied to work with no
human in the loop**, and it exists because of a measured failure pattern, not a theory.

**Every failure mode observed in a real routine build was a *silent success*.** Not one
announced itself. Building one hourly routine surfaced seven, and each reported success
while doing nothing:

| What reported success | What was actually true |
|---|---|
| dispatch `exit 0` | the agent never got a shell (sandbox died); zero work done |
| `agents notify` → `ok:true` | nothing delivered — the credential is unreadable headless |
| dispatch record `"status": "running"` | process long dead, box idle |
| capability probe passed | it exercised a different operation class than the job |
| a result file read as current | it was the previous run's leftover output |
| `routines add` accepted the YAML | it silently dropped the `devices:` pin |
| ticket queries "working" | shared API quota exhausted fleet-wide |

Loud failures get noticed and fixed. **Silent ones are the only kind that matter at
3 AM**, because nobody reads a green log. So the discipline is not retries or timeouts
— it is making an unattended run *prove* it did the thing.

## Exit code 0 is not evidence

An agent that hits a wall, explains the wall politely, and exits is a **zero exit with
no work done**. That is the single most common unattended failure. Never treat process
success as task success.

Close every unattended unit of work by asserting a **postcondition you can check
mechanically**, and report *that*:

- Opened a PR → query the PR and confirm it exists and is in the expected state.
- Merged → confirm the change is on `origin/<default>`, not just that merge returned 0.
- Wrote a file / benchmark → confirm the path exists with expected content.
- Commented a ticket → confirm the comment is on the ticket.
- Sent a message → confirm the send result says delivered, not just that the CLI returned.

If the postcondition fails, say **unverified** and name the gap. Never round up to
"done". A run honestly reporting "dispatched, still running, will harvest next cycle"
is healthy; a run claiming a result it did not observe is the failure this rule exists
to prevent.

## Probe with the operation you will actually perform

A probe that skips the operation under test certifies nothing. Read-only probes pass on
machines that cannot write; unauthenticated paths pass where credentials are missing;
a dry-run passes where real delivery fails (`remote-fleet-dispatch` has the measured
probe table). If the job writes, probe a write. If it needs a credential, fire a real
authenticated request and check for 401. If it must deliver a message, check the send
result — a `--dry-run` only proves the address resolved.

## Read status through the command surface — and still bound the wait

Cache and state files under `~/.agents/.cache/` are written by whichever process last
touched them, so they go stale without any error. Ask the CLI (`agents devices ps`,
`agents sessions`, `gh pr view`), which reconciles on demand — but reconciliation is
not a liveness check: a killed process or rebooted box leaves no `.exit` artifact, and
that record reports `running` forever (`remote-fleet-dispatch` has the measured case).
Every wait therefore carries a concrete ceiling derived from the job's expected
runtime, after which the thing is treated as dead rather than slow; for certainty,
probe the process directly.

## Cross-run state: namespace it, and never read it without a completion marker

State that survives between runs is how a loop makes progress — and how it reports
confident nonsense. A leftover output file from the previous run, read before the
current run had written anything, produced a detailed and entirely wrong failure
diagnosis.

- Key every artifact to **this** run (a unique handle/id), and match on that key.
- Clear or ignore prior artifacts at the start; treat clearing as a correctness step.
- Never read a result until its completion marker exists. Absent or partial output is
  not a result — do not describe what the other side "did".

## Budget shared, rate-limited resources

An hourly job is 24 runs/day against quotas shared by the whole fleet on one token.
Linear (2500 req/hr) was exhausted in practice, taking down ticket reads for every
agent. GitHub meters two separate budgets per token (REST requests/hr and GraphQL
points/hr) and they drain independently, so a full REST budget says nothing about
GraphQL; check both with `gh api rate_limit` before a looping pass.

- Fetch a list **once** per run and work from that response; never re-query per item.
- Write only when something actually changed (keep a verified/seen record).
- On a rate-limit error: **stop touching that API for the run**, say so, let the next
  cycle pick it up. Never retry in a loop.

## Fail loud to the owner — but only when it is real

Unattended work must be able to raise its hand. Reach the owner (`agents notify`,
`agents feed post --blocked`) when a run is genuinely blocked or a postcondition failed
repeatedly — not on every cycle. A job that pings hourly trains the owner to ignore it,
and then the one that mattered is ignored too. Silence on a healthy run, one clear
message on a real change or a real block.

Corollary worth wiring in: if a job can no-op forever without anyone noticing, that is a
defect in the job. Track consecutive runs with no successful postcondition and escalate
on a drought.
