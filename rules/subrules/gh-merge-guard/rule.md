# Merge & Admin-Bypass Guard

Authorization to do the work carries through to the merge — an in-session "build it / open a PR / fix this" authorizes a **rebase-merge on green**, no fresh ask needed. What still needs explicit authorization is merging *past* the safety rails: never bypass branch protection, never rubber-stamp your own code, never merge red.

- **Merge autonomously on green; ask only on red.** A non-author review **and** passing CI = rebase-merge without asking (see `truly-agentic-git-workflow`). Fall back to `AskUserQuestion` (merge / iterate / close) only when the review finds problems, tests fail, or the merge conflicts. "Green" means a genuine independent review + CI, never a rubber stamp.
- **Never `gh pr merge --admin`.** Admin bypass merges past branch protection and required reviews. The bundled `merge-guard.sh` (PreToolUse) blocks it. Merge *without* `--admin` so protections still apply — if protections block the merge, that's a red to resolve, not a thing to bypass.
- **Never self-approve your own PR.** Reviewing and approving code you wrote, then merging it, is not review. The reviewer that clears the green must be someone — or some agent — other than the author.
- **Never transfer credentials or auth files** (tokens, `~/.rush/user.yaml`, keychain exports) to another host or VM without explicit authorization. Don't attempt the transfer first and surface a question only after a guard blocks you.
