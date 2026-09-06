---
name: dispatch
description: "Dispatch one task, coding or non-coding, to a capable executor and own its delivery. Use for /dispatch, /work:dispatch, a ticket, a described task, or the next clear task in a named project."
argument-hint: "[task, ticket, or project]"
user-invocable: true
---

# Dispatch one task

Dispatch **$ARGUMENTS**. `/dispatch` defaults to the current project;
`/work:dispatch` also accepts other projects and non-coding work. With no concrete
target, ask for the task. A board sweep belongs to `work:loop triage`.

## Establish what is actually needed

Before planning or spawning, search relevant open PRs, tracker tickets, recent
changes, and active sessions. Read matches and ownership; coordinate with an
existing executor rather than launch duplicate work. Reuse repository context
already established in the session. An unavailable lookup is an unknown.

For “next on this project,” choose clear, unblocked work within the user's stated
priorities; do not silently cancel or reprioritize their board. Clarify genuine
product choices while continuing independent discovery.

Give the task a clear outcome, scope, acceptance evidence, and relevant context.
For a bug, distinguish confirmed facts from hypotheses. Use `debug` when needed;
if the cause is still unknown, dispatch investigation with an explicit diagnostic
outcome rather than prescribe an unproven fix.

Keep the proposal lightweight for a clear task. Use a flow, before/after view, or
mockup when it makes the change easier to understand. Use `plan` for substantial
uncertainty, architecture, or product decisions; this is not a mandatory ceremony
for every dispatch.

## Commit tracking at execution

During exploratory planning, keep tracker discovery read-only and draft steps
local. When the approach is settled and execution is starting, refresh discovery
and reuse or claim suitable tracking. Create only genuinely missing substantive
work now being delivered; a PR may be enough for a small fix. Follow `tickets` for
tracker mechanics. Explicit ticket-management requests are still valid. Existing
authority to execute is sufficient; respect a planning-only request.

## Choose a capable executor

| Work | Owning capability |
| --- | --- |
| One engineering task | `run` |
| Independent parallel surfaces or verification | `teams` |
| Engineering queue | `code:loop` |
| Mixed work queue | `work:loop` |
| Research question or data pull | `research:research` (`/research`), or `browser` + `secrets` for one authenticated source |
| Hands-on product exploration | `research:product` |
| Design, content, or UI task | The matching domain skill, with `run`/`teams` when delegated |

Choose by capability, availability, and task needs. Do not automatically place
compute on the user's interactive machine. Follow `run`/`teams` for supported
commands, worktree setup, credential boundaries, and device mechanics. Include
the agreed scope, existing PR/ticket links, ownership boundaries, and acceptance
evidence in the brief. Never dispatch beyond the user's authorization.

## Own the finish

Confirm the executor actually starts and makes progress. Use status and output
evidence; inspect logs when they help diagnose a stall or failure. Keep monitoring
bounded and verify any durable watcher can observe and act on this run. A queued
job, successful spawn command, or registered watcher is not completion.

Resolve stalls and verify the composed result. For engineering delivery, satisfy
the repository's PR, independent review, required checks, and release process,
then verify the installed or deployed behavior when shipment is in scope. For
other work, verify its actual requested outcome. Close tracking with proof.

If a handoff was explicitly requested or agreed, name the accepting owner and
remaining work and report it as in flight. Otherwise retain responsibility
through delivery. Show visible results on the user's machine through the owning
presentation skill and give a concise, evidence-backed status.
