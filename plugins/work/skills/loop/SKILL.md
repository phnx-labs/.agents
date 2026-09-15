---
name: loop
description: "Deliver a ticket, branch, PR, or queue across coding and non-coding work, including unattended and multi-project drains. Triage mode decides which board items to keep and schedule or cancel. Use for /loop, /work:loop, landing work, overnight drains, or board triage."
argument-hint: "[ticket | branch/PR | project/filter | checklist | --todos | all | overnight | triage [scope]]"
user-invocable: true
---

# work:loop

Own the requested work through verified delivery. This is the single queue workflow for
engineering, browser and native tasks, design, content, and research. Use the `tickets`
skill for tracker mechanics and repository policy for checks, review, merge, and release.

## Queue and ownership

`$ARGUMENTS` selects a described task, ticket, branch, PR, project, tracker filter (`--label`, `--query`),
Markdown checklist, or repository `--todos`. A branch or PR is a queue of one. With no
argument, resume recoverable queue state (`_meta/queue.json` if present) or the current
PR/session scope; if none exists, drain clear authorized work across projects.
Explicit `all` or `overnight` selects that broader drain. `triage [scope]` runs the
board-decision mode below instead of a plain drain.

Normalize each item to its intended result, kind, project/repository, acceptance evidence,
and ownership. Before adopting it, check tickets, open PRs, and active sessions. Continue
owned work; coordinate with an active owner rather than racing or taking over. Respect
human holds and delegated agent ownership; do not infer assignment from labels. Reject
unknown agent identifiers rather than treating them as an empty queue.

Claim work when execution starts, recheck ownership before the first mutation, and keep
scope changes and handoffs on its ticket. Claims are best-effort deduplication, not locks.
Link tracked items in PRs. Keep active, delivered, and parked queue state recoverable by
another session. Fetch the board once per pass, write meaningful updates, and honor shared
rate limits. A plain drain skips items needing a keep/cancel decision.

## Execute and spread work

Choose direct work, `agents run`, or `agents teams` according to task boundaries. Use the
`run` and `teams` skills for current dispatch mechanics and live capacity. Spread independent
tracks across available workers and accounts; give each ownership, dependencies, and
success evidence. Do not place implementation workers on the interactive machine without
authorization. One small item needs no team ceremony.

Confirm workers start and progress. Re-home auth, quota, or host failures after checking
the real operation on the replacement; a login probe proves no write capability. Do not
patch product code around a broken execution host. Bound waits by expected runtime and
recover stalls. Dispatch and process exit status are not delivery evidence.

| Kind | Execution and proof |
|---|---|
| Engineering | Read repository instructions and canonical build/test/release entry points. Use a linked worktree under `<repo>/.agents/worktrees/` from the freshly fetched default branch. Implement, verify the real flow, use `work:commit`, open the PR, and carry it through the repository's review, checks, merge, and release requirements. `code:review` supplies independent engineering review; `code:health` and `code:refactor` supply assessment and improvement when needed. |
| Browser / portal | Use `browser` and existing credential mechanisms; exercise the authorized flow and capture its resulting state. |
| Native app | Use `computer`; verify the real result without stealing the user's desktop. |
| Design / assets | Use the design or image skills appropriate to the task; inspect the rendered artifact and interactions. |
| Outreach / content | Use the appropriate writing and channel tools. Send or publish only when authorized; otherwise finish a reviewable draft and record the remaining action. |
| Research | Use the research workflow and current sources; deliver a cited answer or requested artifact. |

Recover context from sessions, ticket/PR history, and the owning code before asking the
user for information already available. Keep credentials in existing secret mechanisms;
never create identities or export credentials to route around a blocker.

## Verify and deliver

Preserve the primary checkout and other people's edits. Keep owned PR branches current
through the supported rebase workflow, preserving both intents in conflicts. Reuse valid
verification for unchanged code; rerun what new edits or failures invalidate. Investigate
failed checks at their actual failing step and resolve code or infrastructure causes.

Carry findings and checks through the repository's merge policy. Never bypass protections,
approve your own work, or merge red. For distributables, follow the canonical release
process and verify the installed or deployed artifact before closing the ticket. Inspect
UI captures and exercise changed interactions with `browser` or `computer`.

For each item, independently inspect the PR, artifact, or real-world result. A worker's
report, successful exit, or an old result file is insufficient. Close with links and
concise acceptance evidence. Clean up only owned, completed worktrees and merged branches
through the supported safe cleanup path. Keep transcripts and sensitive context private.

Report the actual stage: delivered, merged but not shipped, draft awaiting an authorized
action, or parked with the missing condition. An open PR is an intermediate stage. A
blocked item does not make the rest of the queue complete.

## Blockers and unattended runs

Resolve ordinary conflicts, reviewer findings, and CI failures. Park only a genuine
user-owned decision or exhausted external blocker, naming what remains and the smallest
next action; continue independent work. Halt a queue for a shared failure, exhausted
budget, or user instruction that makes continuing inappropriate.

During unattended drains, do not wait for absent user input. Leave a durable status on
the ticket or queue, using only an authorized notification channel. A parked item needs
a verified watcher with a completion signal if work will continue in the background;
otherwise report it as unverified. End with a compact recap of delivered, merged,
and parked items, including what needs the user.

## Triage mode

Triage changes the selected board's keep/cancel decisions, not just its execution order.
First read current product goals, project milestones, roadmap, and explicit holds. Use the
nearest incomplete dated milestone to establish urgency unless a stated priority overrides
it. If no goal can be recovered, ask once for it; leave dependent decisions pending rather
than inventing a goal. In an unattended run, record that missing decision and continue only
independent work.

Each item has one of two outcomes:

- **Keep and schedule:** worth doing now; place it in the current cycle or milestone with
  Todo or later status. Complete small, fully scoped authorized work in the same pass.
- **Cancel:** stale, superseded, speculative, or off-goal; close with a concise reason.

Do not use Backlog, no cycle, or a low-priority someday state as a substitute for deciding.
A real human/external hold is the exception: retain its state and name what and whom it
awaits. Use the tracker's existing taxonomy. For a tracker without cycles, use an active
milestone. Report before/after open and current-cycle counts, link keep/cancel decisions
with reasons, and name unresolved holds. Reduce stale work; do not just reshuffle it.
