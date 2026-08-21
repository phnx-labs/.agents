# Task Checklists — Keep One for Real Work, Bound to the Ticket

Multi-step work — 3+ distinct steps, anything you'd track in your head across
many tool calls, or any task tied to a ticket — gets a `TaskCreate` checklist,
one item per step, walked `pending → in_progress → completed` as you go. It is
the acceptance rubric (done = every item completed) and it makes the session
legible (`agents sessions` shows `✓6/8 · <current item>`). Skip it for
single-step or trivial tasks — a checklist for a one-liner is noise.

Bind it to the task: pair a ticket when a tracker is connected (create or claim
one once the work is real and scoped; move it to In Progress); stamp items with
the ticket via `TaskCreate` `metadata` (e.g. `metadata.ticket: "RUSH-1234"`);
reflect milestones on the ticket as items complete, and close it on delivery
with proof (see `conventions`).
