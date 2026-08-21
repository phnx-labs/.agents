# Merge & Admin-Bypass Guard

Authorization to do the work carries through to a **rebase-merge on green** — no
fresh ask. What still needs explicit authorization is merging past branch
protection or review requirements.

- Merge autonomously on green (non-author review + passing CI). Fall back to
  `AskUserQuestion` only when the review finds problems, tests fail, or the
  merge conflicts.
- The verdict must be ON the PR you are merging — `merge-guard.sh` blocks a
  `gh pr merge` whose PR carries neither an APPROVED review nor a fresh APPROVE
  verdict comment. A verdict "carried from" another PR satisfies nothing.
- Non-author review source: the repo's automated reviewer when configured and
  posting on this PR; otherwise spawn a non-author subagent review immediately.
  Never wait idle, never hand the merge to the user.
- Never `gh pr merge --admin` (blocked by `merge-guard.sh`). If branch
  protection blocks the merge, that's a red to resolve, not bypass.
- Never self-approve your own PR. The clearing reviewer must be someone — or
  some agent — other than the author; an automated repo reviewer or a
  non-author subagent counts, you never do.
- Never transfer credentials or auth files to another host without explicit
  authorization.
