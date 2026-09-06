---
name: learn
description: "Learn the codebase a coding session just worked in, and write what a future agent would otherwise re-derive into that project's AGENTS.md — entry points, architecture, non-obvious invariants, how to navigate. The primary durable output of a coding session is the project's own memory file, not the code plugin. May also fold a genuinely durable coding-workflow lesson into a code:* skill via the top-level `learn` engine's filters, but that's secondary. Triggers on: 'learn this codebase', 'update AGENTS.md', 'what should future agents know about this repo', 'learn from this coding session', 'improve the code plugin', 'what should the engineering loop have done'."
argument-hint: "[empty = current session/repo | session-id | topic | path to a monorepo package]"
allowed-tools: Bash(agents *), Bash(git *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Read(*), Write(*), Edit(*), Task(*)
user-invocable: true
---

# code:learn

Use `$ARGUMENTS` to select the session, topic, or package; otherwise use the current work.
Preserve durable project knowledge that a future agent would otherwise need to rediscover.
Routine work or an already adequate explanation may warrant no change.

Read the `docs` skill's `write-agents-md.md` guidance before editing project memory.
Understand the relevant entry points, ownership boundaries, contracts, and non-obvious
pitfalls from actual source and observed behavior. Separate enforced invariants from
design intent and assumptions.

## Where the knowledge belongs

Update the nearest existing `AGENTS.md` entry; root guidance holds the repo map and shared
contracts, component guidance holds local knowledge. Correct stale explanations rather
than appending a competing version. Add a file only when the component needs a persistent
contract, not merely because this session visited it.

Keep rationale and useful repo-relative symbol pointers. Exclude secrets, machine-local
state, absolute home paths, and facts trivially discoverable from a name or one search.
Edit canonical `AGENTS.md`; its `CLAUDE.md` and `GEMINI.md` mirrors follow the repository's
convention. Update a paired README catalog when resource inventory changed.

Use an authorized linked worktree and the normal PR workflow. When the change is still
open, keep its documentation with it. If it already landed, use a focused follow-up PR;
never rewrite completed history merely to attach a lesson.

## Refining the workflow

A recurring lesson about how work is executed may belong in the nearest existing
`code:*` skill: queue ownership in `loop`, review in `review`, architecture in `refactor`,
and commits in `commit`. Tool mechanics belong in that tool's skill; release details
belong in the repository release process. Use the top-level `learn` engine's filters
for workflow changes: generalization, recurrence, root cause, and durability.

Prefer correcting or replacing existing guidance over adding a new instruction. A new
skill requires a missing capability, not an incident or ordinary good judgment. Check
callers when changing a workflow's promised output so its contract remains consistent.
Verify every durable claim against the actual implementation and report what changed,
or why no new guidance was needed.
