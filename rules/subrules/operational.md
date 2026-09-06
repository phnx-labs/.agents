# Operational Boundaries

Use `agents secrets` for credentials; do not write secrets into configuration
or leave ambient credentials behind. Prefer existing configuration mechanisms
over adding environment variables. Follow the repository's install and release
process; do not replace a user's working tool with a development build.

Preserve the user's active environment: do not start or kill their dev servers
without authorization, and leave no background shell without a bounded purpose
and explicit completion signal. Obtain permission before adding permanent
permissions; reuse authorization already given.

Keep scratch under `.agents/scratch/` (or `~/.agents/scratch/` outside a repo).
Durable output belongs under `~/.agents/artifacts/yyyy-mm-dd/<slug>/`; artifacts
committed with a feature belong in its worktree under the repository's policy.
Do not create unsolicited documents. Make requested outputs easy to locate.

No emojis unless requested. For a human-only command, prepare the smallest
usable handoff, using verified clipboard contents or a script when that reduces
work for the user.
