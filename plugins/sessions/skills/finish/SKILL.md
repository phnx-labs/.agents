---
name: finish
description: "Drive the current task to fully delivered — recover the goal, finish what remains, verify end-to-end, docs, commit, PR, release checklist, close the ticket. Never stops at a recap, blocker, or partial handoff. Triggers on: /finish, 'finish this', 'drive it to done', 'ship it', 'don't stop at a recap', 'see it through'."
argument-hint: "[extra context]"
allowed-tools: Bash(agents *), Bash(gh *), Bash(git *), Bash(linear *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Read(*), Write(*), Edit(*), Task(*), AskUserQuestion(*)
user-invocable: true
---

# sessions:finish — drive the current task to delivered

You are finishing the current task. Context: $ARGUMENTS

This is not a recap. It is an execution contract: recover the goal, finish what remains,
verify the real flow, and ship. If the current task is genuinely already delivered (e.g.
`/continue` just drove it there), say so **with evidence** and stop there.

> **`/finish` vs the neighbors.** For draining a whole *queue* of tickets/branches to
> merged, that's `/code:loop` (engineering) or `/work:loop` (any kind). To *recap and
> exit* the session, that's `/recap` then `/self:close`. `/finish` is the anti-stopping
> driver for the one task in front of you.

## 1 — Recover the contract

Re-read the conversation from the start and write a short checklist:

- **Original ask** — what the user asked you to deliver.
- **Scope changes** — follow-up requests or constraints added later.
- **Commitments** — actions you said you would take.
- **Current state** — what is done, in progress, or not started.

Every item gets a verdict: DONE, IN FLIGHT, NOT STARTED, or BLOCKED. Do not trust memory —
back each DONE or BLOCKED with fresh evidence: file:line, command output, test result,
PR/deploy URL, HTTP response, ticket state, or the exact error. If you can't quote it, it is
not DONE.

## 2 — Convert status into the next action

For every IN FLIGHT / NOT STARTED / BLOCKED item, pick the next executable action. Before
you call anything blocked, make three distinct attempts and quote each result: the direct
path; the project's canonical script / CLI / browser automation / remote box / API; then
reduce scope to verify the critical path manually. Two or more independent workstreams →
start parallel work with `agents teams` (boundary contracts, file:line evidence required),
not one-by-one queueing.

## 3 — Take the next action now

Pick the smallest remaining item that advances delivery and execute it immediately. Do not
ask the user to choose between continuing and stopping, and do not hand back a command for
the user to run when you can run it, drive it in a browser, use a remote box, call an API, or
request the exact permission needed. Reserve `AskUserQuestion` for a true fork that needs
human judgment, credentials, payment, public posting, or destructive/production approval —
with forward-moving options only (never a "stop" option), the recommended one first.

## 4 — Verify end-to-end

"Done" requires real output from the real path. Match the verification to the task:

- Code change → run the relevant tests and exercise the affected flow.
- Bug fix → reproduce the original failure (or nearest case), then show it fixed.
- CLI/script → run the command, quote the output.
- API → call the endpoint, quote the response.
- UI → open the real screen and confirm behavior.
- Deploy/release → run the canonical deploy/release, then health-check or fetch the deployed
  artifact. Script completion alone is not proof.

If unrelated pre-existing failures block a full suite, prove they're unrelated with a
baseline run + touched-path tests + file/commit evidence, then use the project's narrower
documented verification. Don't hide behind a full-suite failure outside the task's blast
radius.

## 5 — Ship the finished work

Run the closing ship checklist; if a sub-step genuinely doesn't apply, say so in the report.

**Docs.** Walk every changed file: did it change anything a human would look up? Update only
the surface that applies — don't write new docs unless asked:

- **`AGENTS.md` / `CLAUDE.md` / `GEMINI.md`** (root or affected subdir) — new module,
  top-level area, gotcha, or file-locations pointer. Maps, not territory; the harness copies
  are usually symlinks — edit the real file.
- **`README.md`** — user-facing setup/usage/install/quickstart changes (new flag, env var,
  command).
- **`CHANGELOG.md`** (if present) — a line for the user-visible change under the next version.
- **Help text / `--help`, in-code descriptions** — if a flag, argument, config key, or tool
  parameter changed, update the string AND any examples.
- No docs needed for: bug fixes, internal refactors with no behavior change, test-only
  changes, self-evident renames — say which.

**Commit & PR.** Check `git status`, inspect every changed file in the diff. Commit completed
work if the project expects agent commits; never commit broken or incomplete work. On a
feature branch with a PR delivery path, push and open/update the PR. For a **private** repo
only, attach a **redacted** session transcript as a **secret** gist for audit — never a
public gist, never on a public repo (link `<host>:<path>` instead).

**Release (if applicable).** If the work touches a publishable package, `release-to-fleet` is
the authority and takes precedence — and it has exactly two end states: you were asked to
ship (you own the whole chain, `merged → published → tagged → fleet-upgraded →
installed-version-verified`), or the user explicitly scoped you away from releasing (you name
who owns it). There is no release train, and "merged + a changelog fragment" is never where
/finish ends: if the registry is behind the default branch, driving or verifiably watching
the release **is the remaining work** — the lease (`release-lease.sh`) serializes concurrent
releasers, so start it and let the lease refuse you if another *verified-live* releaser
holds it. Verify the result landed in the registry (not just that the script exited 0). Do
not `AskUserQuestion` to confirm a release the session's goal already authorizes — that
re-ask is the banned stop.

**Tracker.** Update the issue tracker only with proof (commit, PR, deploy URL, test output,
health-check response). A follow-up ticket is **not** a way to call a small thing done: if
what remains is a few lines, a portability bug you hit, or a non-blocking review nit you
could address in the same branch, **fix it now** — filing it is bloat, not tracking (see
`conventions`, enforced by `linear-guard`). Open a follow-up ticket **only** when the
deferred slice is genuinely large or separately schedulable, out of this change's scope, and
nobody is delivering it in this session — and first search the board for an existing ticket
to enrich instead of a near-duplicate. When that bar is met, file via the `tickets` skill
with a clear title, context, and acceptance criteria — don't silently drop it.

## 6 — No stalling

Every turn ends with an action, not a question handed back. Forbidden endings — the stalls
this rule exists to interrupt:

- "Want me to continue?" / "Should I do X next?"
- "Pick one and I'll continue."
- "Let me know if (or when) you want me to proceed."
- "The remaining sequence is mechanical." / "I can stop here."
- Any trailing question that hands the steering wheel back, or a status-only recap that does
  not take the next action first.

Required instead: `Next: [doing X]` with the tool call in the **same turn** as the sentence
announcing it. For a genuine fork only (human judgment, credentials, payment, public posting,
destructive/production approval): `AskUserQuestion` with two **forward-moving** options, never
a "stop" option.

The current task is delivered only when Remaining is **None**, or what remains is one of: a
proven external blocker with three quoted attempts; a user-only action (payment, credentials,
destructive/production approval, public posting, strategic judgment); or a follow-up ticket
for a slice that clears the bar above — genuinely large or separately schedulable and out of
this change's scope, with the shippable slice already delivered. A follow-up ticket for
something you could have just fixed is not "done" — it is the stall this rule exists to stop.
