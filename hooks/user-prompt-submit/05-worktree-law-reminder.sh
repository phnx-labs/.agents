#!/bin/bash
# Injects a one-line worktree-law reminder into every prompt of every session.
#
# Owner directive (2026-08-15), after an agent wrote into a primary checkout on
# main: the rule must be re-asserted continuously, not just enforced at the
# blocked call. main-branch-guard remains the hard enforcement; this line keeps
# the rule inside every context window so agents plan around it instead of
# discovering it at the block. Deliberately one line — a reminder that costs a
# paragraph per turn would get the whole hook disabled.
cat >/dev/null
echo "Reminder (worktree law): every write goes through a linked worktree under <repo>/.agents/worktrees/<slug>/ + a PR. The user's primary checkouts are untouchable — never edit, commit, or switch branches there, on any branch."
exit 0
