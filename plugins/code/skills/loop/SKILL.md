---
name: loop
description: "Take a ticket, branch, PR, or queue through implementation, verification, independent review, merge, and the repository release process. Use for landing work or draining a backlog."
argument-hint: "[PROJ-123 | --label=… | --query=… | path/to/list.md | --todos | (empty = resume)]"
allowed-tools: Bash(agents *), Bash(gh *), Bash(git *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Read(*), Write(*), Edit(*), Task(*), WebFetch(*), WebSearch(*)
user-invocable: true
---

# code:loop

Own the requested queue through delivery. Use `$ARGUMENTS` to select a ticket, branch,
PR, tracker filter (`--label`, `--query`), Markdown checklist, or repo `--todos`.
With no argument, resume from the last `_meta/queue.json` or current PR/session state.
A branch or PR is a queue of one; it needs no multi-item planning ceremony.

## Scope and ownership

Understand each item's intended result and acceptance evidence. Before adopting it,
check relevant tickets, open PRs, and active sessions for existing work. Continue work
you own; coordinate with another active owner rather than racing or taking over.
Reuse the existing ticket. Create one only when committing to execute work that has no
suitable ticket, not while exploring a plan or merely noticing a follow-up.

Claim work when execution starts and keep meaningful scope changes, blockers, and
handoffs on its ticket. Link the ticket in the PR so other workers can find it.
Queue state must distinguish active, delivered, and parked items and be recoverable by
another session. Tracker claims are best-effort deduplication, not an atomic lock;
recheck ownership before starting when another worker could have claimed the same item.

## Execution

Use linked worktrees under `<repo>/.agents/worktrees/`, based on the current default
branch. Preserve the user's primary checkout and unrelated work. Read the repository's
instructions and canonical build, test, and release entry points.

Choose direct work, `agents run`, or `agents teams` according to the work's boundaries.
Use the `run` and `teams` skills for dispatch mechanics. Parallel tracks need independent
ownership or explicit dependencies, enough available capacity, and success evidence.
Do not place implementation workers on the user's interactive machine without authorization.

Keep owned PR branches current using the repository's supported rebase workflow.
Resolve conflicts to preserve both intents; inspect generated changes before staging.
Use `code:commit` for cohesive commits and `code:review` for independent review.
Investigate failed checks at their actual failing step: fix code defects in scope,
and address infrastructure failures through the appropriate operational path.

## Verification and delivery

Verify the changed behavior with the repository's appropriate checks and real flow.
Reuse valid evidence for unchanged code; rerun what new changes or failures invalidate.
A worker's exit status is not delivery evidence: inspect its output and actual result.
For changed UI behavior, drive the real surface with `browser` or `computer`, inspect
captures, and show the relevant result to the user.

Carry owned work through findings, CI, and merge under the repository's merge policy.
For distributables, follow the canonical release process and verify the installed or
deployed artifact before closing the ticket. Close with the PR/release link, delivery
result, and concise verification evidence. Do not upload raw session transcripts;
keep sensitive context in its authorized private location.

Clean up only your own completed worktrees and branches when safe. Report the actual
stage of each item: delivered, merged but not shipped, or parked with the missing condition.

## Blockers and unattended runs

Conflicts, reviewer feedback, and ordinary CI failures are work to resolve. Stop an item
for a genuine user-owned choice or an exhausted external blocker, record what is needed,
and continue independent items. Halt the queue for a shared failure, exhausted budget,
or a user instruction that makes continuing inappropriate.

Unattended runs must finish with a durable status instead of waiting for absent input.
Use only the notification channel authorized by the invocation. If none is specified,
the ticket or queue record is the handoff. Respect tracker rate limits: fetch once per
pass, write meaningful changes, and honor rate-limit responses rather than retrying a
shared exhausted API. For agent queues, use delegated ownership, not labels, and reject
unknown agent identifiers instead of interpreting them as an empty queue.
