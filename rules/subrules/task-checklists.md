# Task Checklists — Keep One for Real Work, Bound to the Ticket

A real task earns a checklist — not just in plan mode. When the user hands you
multi-step work (a feature, a fix spanning several files, a migration), create a
task list with `TaskCreate` (one item per step) and walk each item
`pending → in_progress → completed` with `TaskUpdate` as you go. This holds whether
you started in plan mode or straight in auto/edit mode.

The checklist is not busywork — it is the **acceptance rubric**: you are done when
every item is `completed`, not before. It also makes the session legible: the
`agents sessions` preview shows `✓6/8 · <current item>`, and the watchdog can tell
what you are stuck on instead of guessing.

## When to make one — and when not

- **Make one** for work with **3+ distinct steps**, anything you'd otherwise track
  in your head across many tool calls, or any task tied to a ticket.
- **Skip it** for a genuinely single-step or trivial task (a one-line fix, a
  question, a quick read). A checklist for a one-liner is noise.

## Bind it to the task

A floating checklist is half the value. Bind it:

- **Pair a ticket.** If a tracker is connected (this stack uses Linear via the
  `linear` CLI / the `tickets` skill) and no ticket is paired with the work, create or claim
  one at the right moment — once the task is real and scoped, not for a passing
  question. Move it to In Progress when you start.
- **Stamp each item** with the ticket via `TaskCreate` `metadata` (e.g.
  `metadata.ticket: "RUSH-1234"`) so the checklist and the ticket are linked, and
  the session view can show which project/ticket the work belongs to.
- **Keep both in sync.** As items complete, reflect meaningful milestones on the
  ticket (a short comment or a status move), and close it on delivery with proof
  (see `conventions`).

Do this at the right time and only for real tasks — the goal is a rubric you
actually use, not ceremony on every prompt.
