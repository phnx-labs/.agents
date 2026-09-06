# Task Checklists — Keep One for Real Work, Bound to the Ticket

Multi-step work — 3+ distinct steps, anything you'd track in your head across
many tool calls, or any task tied to a ticket — gets a `TaskCreate` checklist,
one item per step, walked `pending → in_progress → completed` as you go. It is
the acceptance rubric (done = every item completed) and it makes the session
legible (`agents sessions` shows `✓6/8 · <current item>`). Skip it for
single-step or trivial tasks — a checklist for a one-liner is noise.

A planning checklist is local draft state, not a tracker commitment. Link existing
tickets when relevant, but do not create one or move it to In Progress to satisfy
this rule. At the transition to execution, refresh discovery and claim/enrich an
existing ticket; create only missing substantive work being delivered (see
`conventions`). Stamp items with `TaskCreate` metadata when a ticket exists
(e.g. `metadata.ticket: "RUSH-1234"`); reflect execution milestones there and close
only with delivery proof. The checklist works without a ticket.
