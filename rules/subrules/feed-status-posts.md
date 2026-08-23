# Post Progress to the Feed at Milestones

Post major milestones with `agents feed post` — plain posts record to the activity stream, and a post marked `--level important` is auto-forwarded to the owner's phone by their feed config, so you never call a separate notify command. Use `--blocked` for a genuine needs-you state (it records and delivers; never pair it with `--level`). Post at real boundaries — a checklist item done, PR opened, CI green — not every step, and never for work the user is watching live. Outside an agent-run context, `--session` and `--title` are required.
