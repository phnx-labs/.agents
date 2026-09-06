---
description: Commit and push cohesive, independently understandable changes using repository conventions.
---

Commit and push the requested changes. Arguments: $ARGUMENTS

Work in a linked worktree under `<repo>/.agents/worktrees/`, preserving the primary
checkout and unrelated edits. Inspect staged and unstaged changes before selecting
explicit paths. The invocation authorizes committing its scope, not every local change.

Use cohesive commits that remain understandable and valid independently. Separate
unrelated changes; keep implementation, tests, required configuration, and generated
outputs together when they form one working increment. `squash` or `chunky` requests
coarser coherent groups; do not manufacture commits to meet a file-count target.

Follow repository message conventions. Otherwise use a concise conventional commit
that names the specific change; include a body when rationale helps. Do not add
promotional or generated-by footers or AI coauthor trailers.

Keep credentials and accidental build outputs out of Git. Judge intentional assets,
fixtures, lockfiles, and generated files in repository context; size or extension alone
is not a reason to interrupt. Add appropriate ignore rules for accidental untracked
output. Preserve intentional tracked content and ask only when its intended treatment
cannot be established safely.

Honor repository checks and reuse valid verification already completed for the change.
`no-verify` is an explicit request to skip optional local hooks; it does not authorize
bypassing mandatory security, worktree, or merge guards. Do not claim an unchecked path
was verified.

Push the commits and verify the remote result. A background push needs a checked finish
signal before reporting success. If nothing is in scope to commit, say so without
creating an empty commit. When the task includes delivery, continue through the PR and
release workflow using `code:loop`.
