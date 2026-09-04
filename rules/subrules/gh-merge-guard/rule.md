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

## Owner-mode (shared-identity fleets)

Every fleet agent authenticates as one shared GitHub identity, so the
"non-author verdict" check can never be satisfied by a distinct GitHub login —
the code-reviewer's APPROVE always reads as self-authored and every PR
deadlocks onto the human owner. **Owner-mode** fixes that without weakening the
gate: when a PR's **own author** is a **trusted owner** (not merely when a
trusted identity happens to be running the merge — keying on the merger would
let a trusted owner clear a *third party's* self-approval), its own
code-reviewer APPROVE counts, while every other protection (real-word APPROVE,
no carried-from laundering, no negated/quoted approvals, and GitHub-enforced
CI-green) still applies, and `--admin` stays blocked — the owner merges plainly
on their ruleset exemption.

A trusted owner is a numeric GitHub user id in the allowlist (see
`hooks/lib/owner-mode.sh`), sourced from `AGENTS_MERGE_TRUSTED_OWNER_IDS`, the
user-layer file `~/.agents/trusted-owner-ids`, or the shipped-empty
`trusted-owner-ids` template. That id is exactly the repo ruleset's exempt
bypass actor, so owner-mode never grants more than GitHub already allows — it
only stops the local guard and `monitors/pr-merge-on-green.sh` from
false-blocking that one identity. Default (no id configured): off, no change.
Find your id with `gh api user --jq .id`.
