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
- **Fix-now beats file-later; never create a project.** You are an agent — your
  job is to help the user *finish* work and get closer to their goals, not to
  manufacture more of it. So before you run `linear create`, decide honestly:
  (1) if it can be fixed **now**, fix it now; (2) if it's small but out of your
  lane in this session, **dispatch an agent** to fix it — with a worktree and
  full context, then monitor it (see the `dispatch` skill / `parallel-teams` for
  the how) — rather than filing; (3) open an issue **only** when it genuinely
  needs deep investigation, the scope is unclear, or it is multi-day work. A
  small, clear, fixable thing filed as a ticket is not tracking — it is bloat
  that buries the real work and manufactures follow-up churn, the
  smallest-thing-you-should-have-just-fixed failure the board keeps drowning in.
  And **agents never create Linear projects** — project structure is the owner's
  call, not something an agent invents mid-task (a stray auto-created "FastWispr
  Growth" project is exactly the failure). If a new project is genuinely
  warranted, suggest it in your owner update and let the owner decide; organize
  work now with an existing project + milestone or a tracking issue with a
  checklist. Both are enforced at the point of action by the `linear-guard`
  PreToolUse hook (denies `linear projects create`; nudges on `linear create`).
- **Amend the description, don't pile comments.** When a ticket needs more or
  corrected context, edit its **description** so it stays one source of truth —
  don't append another comment that makes the next reader reconcile the first
  message against the last and guess which is current. Don't cite an old ticket
  by ID either: its context may be stale — read what it held, then fold the
  current truth into the description. Comments are for delivery proof (a PR link,
  a screenshot, a decision), not for restating the ticket. The `linear-guard`
  hook nudges on a bare `linear update --comment`.
- **Parallel work:** multi-surface changes use `agents teams` — see
  `parallel-teams`.
