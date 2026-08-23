# Merge on a Verified Non-Author Review

Rebase-merge once CI is green and a non-author verdict is posted on the PR (the `code-reviewer` subagent, or the repo's configured automated reviewer). `merge-guard.sh` blocks admin bypass, self-approval, red merges, and merges without a posted verdict — fix the cause, never route around it.
