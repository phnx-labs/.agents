# Verified Merge

Authorization to implement carries through to rebase-merge after required CI
passes and a non-author verdict is posted on the PR. Use a configured automated
reviewer when it is posting; otherwise obtain a non-author subagent review.
Resolve findings, failures, and conflicts; escalate only a genuine decision or
blocker outside the authorization.

Never bypass protections with `--admin`, approve your own work, or merge red.
Fix the cause of a guard rejection. Shared-identity fleets may use configured
owner-mode: the posted verdict must still come from an independent reviewer,
although its GitHub login matches the author. The trusted-owner configuration
and guard own that exception; do not substitute an author's self-review.
