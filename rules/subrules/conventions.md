# Conventions

- **Memory file:** `AGENTS.md` is canonical; `CLAUDE.md` and `GEMINI.md` are
  symlinks (or synced copies).
- **Tickets — claim first; enrich before you create; open one only for work you
  are delivering now.** Linear context is injected at session start; read it
  before starting. Search the board for a ticket that already covers the work
  and claim it. **Default to NOT creating.** When you have something worth
  recording, first look for an existing ticket that overlaps — same subsystem,
  same bug class, same surface — and **consolidate into it**: add your detail as
  a comment, sharpen its description, attach evidence, link the related ticket.
  A more complete existing ticket beats a new near-duplicate every time; two
  tickets for one problem is the failure, not the safe choice. Fold overlapping
  tickets into one canonical ticket and cancel the rest rather than letting
  parallel copies accumulate. Open a genuinely new one only when nothing on the
  board covers **work you are actually delivering in this session** — never for
  a follow-up you thought of, an idea, or something you noticed in passing.
  Those go in your one owner update as a line (`feed-status-posts`); a ticket is
  what someone opens when they decide to do the work, not a place to park a
  suggestion. Skip trivial fixes and plain questions entirely. Close on delivery
  with proof (what changed, the PR link, a screenshot or recording). The
  `tickets` skill takes any explicit tracker action. Why the restraint: 100+
  agents each closing a session by filing what they noticed keeps the board
  inflating — a single AGI-project pass found 95 open with **48 opened in the
  last three days**, most never started by anyone. Consolidating what exists is
  the work; minting another Todo is not.
- **Parallel work:** multi-surface changes use `agents teams` — see
  `parallel-teams`.
