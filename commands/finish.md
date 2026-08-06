---
description: Finish the current task end-to-end instead of stopping at a recap, blocker, or partial handoff
---

You are finishing the current task. Context: $ARGUMENTS

This command is not a recap command. It is an execution intervention: recover the original goal, identify what remains, take the next concrete action, verify the real flow, and keep going until the task is truly delivered or a hard external blocker is proven.

> **`/finish` vs `/done`** — `/finish` is the **anti-stopping driver + ship gate**: it refuses to stop at a recap/blocker/partial handoff and drives the current task all the way to delivered — verify E2E → update docs → commit → PR → optional package release → close tickets. `/done` is the opposite end: it assumes the work is *already* delivered, prints a handoff recap, and then **self-exits the session**. For draining a *queue* of tickets/branches all the way to merged, use `/code:loop`.

## Step 1 - Recover The Contract

Re-read the conversation from the start and write a short working checklist:

- **Original ask:** what the user asked you to deliver
- **Scope changes:** follow-up requests or constraints added later
- **Commitments made:** actions you said you would do
- **Current state:** what is already done, in progress, or not started

Every checklist item needs a verdict: DONE, IN FLIGHT, NOT STARTED, or BLOCKED.

Do not trust memory. Back each DONE or BLOCKED verdict with fresh evidence: file:line, command output, test result, PR/deploy URL, HTTP response, ticket state, or the exact error.

## Step 2 - Convert Status Into Actions

For every IN FLIGHT, NOT STARTED, or BLOCKED item, choose the next executable action.

Before you call something blocked, make three distinct attempts to move it forward:

- Try the direct path.
- Try the canonical project script, CLI, browser automation, remote machine, or service-specific tool.
- Reduce scope to verify the critical path manually.

Quote the result of each attempt. If you cannot quote it, do not claim it.

If there are two or more independent actionable workstreams, start parallel work with the project's agent/team mechanism instead of queueing the tasks one by one. Give each teammate a clear boundary contract and require file:line quotes for every claim.

## Step 3 - Take The Next Action Now

Pick the smallest remaining item that advances delivery and execute it immediately.

Do not ask the user to choose between continuing and stopping. Do not hand back a mechanical command for the user to run when you can run it, drive it through a browser, use a remote box, call an API, or request the exact permission needed.

Allowed user questions are only for true forks that require human judgment, credentials, payments, public posting, destructive operations, or explicit production authorization. Use `AskUserQuestion` with forward-moving options. The first option should be the recommended action.

## Step 4 - Verify End-To-End

"Done" requires real output from the real path.

Choose verification based on the task:

- Code change: run the relevant tests and exercise the affected flow.
- Bug fix: reproduce the original failure or closest available case, then show the fixed behavior.
- CLI/script change: run the command and quote the output.
- API change: call the endpoint and quote the response.
- UI change: open the real screen and verify it behaves correctly.
- Deploy/release: run the canonical deploy/release script, then health-check or fetch the deployed artifact. Script completion alone is not proof.

If unrelated pre-existing failures block a full suite, prove that they are unrelated with a baseline run, touched-path tests, and file/commit evidence. Then use the project's documented narrower verification or deployment path if one exists. Do not hide behind a full-suite failure that is outside the task's blast radius.

## Step 5 - Ship The Finished Work

After verification, run the closing ship gate. Do not skip a sub-step; if one genuinely does not
apply, say so in the final report (e.g. "docs unchanged: pure bug fix, no user-visible surface").

**Docs.** Walk every changed file and ask: did this change anything a human reader would look up?
Update only the surface that applies — don't write new docs unless asked:

- **`AGENTS.md` / `CLAUDE.md` / `GEMINI.md`** (root or affected subdir) — the canonical map files.
  New module / top-level area / gotcha / file-locations pointer → add a one-line entry. These are
  maps, not territory; `CLAUDE.md` / `GEMINI.md` are usually symlinks — edit the real file.
- **`README.md`** — if user-facing setup/usage/install/quickstart changed (new flag, env var, command).
- **`CHANGELOG.md`** (if the repo has one) — a line for the user-visible change under the next version.
- **Help text / `--help`, in-code descriptions, entry-point comments** — if a flag, command argument,
  config key, or tool parameter was added/renamed/removed, update the string in code AND any examples.

What does NOT need docs: bug fixes, internal refactors with no behavior change, test-only changes,
self-evident small renames.

**Commit & PR.** Check `git status`; inspect every changed file in the diff. Commit completed work
if the project workflow expects agent commits; never commit incomplete or broken work. If on a
feature branch and the delivery path is a PR, push and open/update it, then attach the session
transcript as a **secret** gist for an audit trail (never `--public` unless the repo is public AND
you've reviewed the transcript):

```bash
BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
git rev-parse --abbrev-ref HEAD          # confirm not on $BASE
git push -u origin HEAD
gh pr create --title "..." --body "..."
agents sessions --last 50 --markdown > /tmp/session-export.md
GIST_URL=$(gh gist create /tmp/session-export.md --desc "Session transcript for PR" | tail -1)
gh pr comment --body "## Session Context
[Session transcript]($GIST_URL)"
```

**Release (if applicable).** If the work touches a publishable package, first check
**who is allowed to release it** — `release-to-fleet` is the authority and takes precedence over
this step:

```bash
agents routines list | grep -i release            # a scheduled train?
ls .github/workflows/ | grep -iE 'release|publish'
grep -rl 'release-lease' scripts/ 2>/dev/null     # a lease = already serialized
[ -f package.json ] && echo npm; [ -f Cargo.toml ] && echo crate
[ -f pyproject.toml ] && echo pypi; [ -f scripts/release.sh ] && echo release-script
```

**Repo with a release train** (a scheduled releaser, or a release script that claims a lease — see
`release-to-fleet` → *Known trains*): you are done at **merged + a changelog fragment**. Do not run
the release script, do not tag, do not publish, and do not ask whether to — name the train and when
it next runs, then move on. Two agents entering one release pipeline is what jammed `agents-cli` on
2026-08-02: four release attempts, zero published versions.

**Repo without one:** build, run the full test suite, then `AskUserQuestion` to confirm
("Release v{version} to {registry}?" — Yes / No / Skip). On confirm, run the release and verify it
landed in the registry, not just that the script exited 0.

**Tracker.** Update the issue tracker only with proof: commit, PR, deploy URL, test output, or
health-check response. For work that is proven-remaining (a deferred slice with a complete shippable
slice already delivered), create a follow-up ticket via the project's `/tickets` skill with a clear
title, the session context, and acceptance criteria — rather than silently dropping it.

Do not create summary `.md` files unless the task or project workflow requires them.

## Step 6 - Final Report

Only report after you have acted.

Use this shape:

```
Goal:
- [one sentence]

Delivered:
- [completed item] - proof: [file:line / command output / URL / response]

Verified:
- [test or real-flow command] - result: [actual result]

Remaining:
- None
```

If anything remains, it must be one of:

- A proven external blocker with three quoted attempts.
- A user-only action such as payment, credentials, destructive approval, public posting, or strategic judgment.
- A deliberately created follow-up ticket with acceptance criteria and proof that the current task's shippable slice is complete.

Forbidden endings — these are the stalls `/finish` exists to interrupt:

- "Want me to continue?" / "Should I do X next?"
- "Pick one and I'll continue."
- "Let me know if (or when) you want me to proceed."
- "Stopping here — let me know if you want more."
- "The remaining sequence is mechanical."
- "I can stop here."
- Any trailing question that hands the steering wheel back, or any status-only recap that does not take the next action first.

Required instead — every turn ends with an action, not a question:

- "Next: [doing X]" with the tool call in the **same turn** as the sentence announcing it.
- "X done. Next: [doing Y]" with the tool call in the **same turn**.
- For a genuine fork only (human judgment, credentials, payment, public posting, destructive/production approval): `AskUserQuestion` with two **forward-moving** options — never include a "stop" option.
