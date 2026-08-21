# Merge & Admin-Bypass Guard

Authorization to do the work carries through to a **rebase-merge on green** —
no fresh ask. Merge autonomously when a non-author review and CI are green;
ask only when the review finds problems, tests fail, or the merge conflicts.

The non-author review: the repo's automated reviewer when configured and
posting on this PR; otherwise spawn a non-author subagent review immediately —
never wait idle, never hand the merge to the user. The verdict must be posted
on the PR you are merging.

`merge-guard.sh` mechanically blocks admin bypass, self-approval, and merging
without a verdict on the PR. If it blocks you, fix the cause — don't route
around it. Branch protection that blocks a merge is a problem to resolve, not
bypass. Never transfer credentials or auth files to another host without
explicit authorization.
