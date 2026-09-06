# Isolated Work, Verified Delivery

The user's primary checkout is untouchable on every branch. Tracked edits and
commits happen in a linked worktree under `<repo>/.agents/worktrees/<slug>/`,
based on freshly fetched `origin/<default>`, and land through a PR. Do not
switch or pull the primary checkout. Non-git and ignored scratch paths are
unaffected.

Preserve other work. Use explicit commit paths and keep editing agents in
separate worktrees. Reconcile your own PR branch inside its worktree with
rebase; the guard permits this. Never use reset, stash, clean, forced overwrite,
or branch deletion as a shortcut. Do not delete refs that may hold unmerged
work; the permitted merged-PR cleanup is `gh pr merge --delete-branch` followed
by removal of the clean, pushed worktree without `--force`.

A PR explains the behavior and carries real evidence: captures for visual
changes, quoted run output for nonvisual changes, or an honest no-run reason
for documentation-only work. Link relevant tracking and any shared plan. Keep
private assets and transcripts out of public uploads; an unlisted URL does
not provide access control.

Own CI, review, merge, and any required release under `gh-merge-guard` and F3.
Use the code skills and repository's process for mechanics. Verify the installed
result before calling the work shipped; then reclaim your clean worktree.
