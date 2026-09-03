# Conventions

- **Memory file:** `AGENTS.md` is canonical; `CLAUDE.md` and `GEMINI.md` are
  symlinks (or synced copies).
- **Tickets — claim first; enrich before you create; open one only for work you
  are delivering now.** Linear context is injected at session start; read it
  before starting. Search the board for a ticket that already covers the work
  and claim it. **Default to NOT creating.** When you have real, deliverable work
  worth tracking, first look for an existing ticket that overlaps — same subsystem,
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
- **Fix-now beats file-later; never create a project.** Before you run `linear
  create`, stop and reflect: can this be fixed *right now* — by you, or by
  dispatching an agent (`agents run` / `agents teams`)? If yes, do that. A
  problem you could fix now, filed as a ticket, is not tracking — it is bloat
  that buries the real work and manufactures follow-up churn. This is the
  smallest-thing-you-should-have-just-fixed failure the board keeps drowning in.
  And **agents never create Linear projects** — project structure is the owner's
  call, not something an agent invents mid-task (a stray auto-created "FastWispr
  Growth" project is exactly the failure). Organize work with an existing
  project + milestone or an epic issue with a checklist; if a new project is
  genuinely warranted, suggest it in your owner update and let the owner decide.
  Both are enforced at the point of action by the `linear-guard` PreToolUse hook
  (denies `linear projects create`; nudges on `linear create`).
- **Parallel work:** multi-surface changes use `agents teams` — see
  `parallel-teams`.
