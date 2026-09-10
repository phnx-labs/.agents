# Isolated Work, Verified Delivery

The primary checkout is untouchable on every branch. Tracked edits and commits
happen in a linked worktree under `<repo>/.agents/worktrees/<slug>/`, based on
freshly fetched `origin/<default>`, and land through a PR. Never switch or pull
the primary checkout; ignored scratch paths are unaffected.

Preserve other work: explicit commit paths, one worktree per editing agent,
rebase your own PR branch inside its worktree. No reset, stash, clean, forced
overwrite, or branch deletion as a shortcut, and no deleting refs that may hold
unmerged work; merged-PR cleanup is `gh pr merge --delete-branch` then removing
the clean, pushed worktree without `--force`.

A PR explains the behavior and carries real evidence: captures for visual
changes, quoted run output otherwise, or an honest no-run reason for docs-only
work. Link tracking and any shared plan; keep private assets and transcripts out
of public uploads. No generated-by or promotional footers on commits, PRs, or
issues. Own CI, review, merge, and release (`gh-merge-guard`, F3); verify the
installed result before calling it shipped, then reclaim the clean worktree.
