# Conventions

- **Memory file:** `AGENTS.md` is canonical. `CLAUDE.md` and `GEMINI.md` are symlinks (or synced copies).
- **Tickets — check first, open if missing, close on delivery.** Linear context is auto-injected at session start by the linear hook; read it before starting. `/tickets` takes any explicit action across Linear/GitHub/Jira.
  - **Check first.** Before substantive work, check whether an open ticket already covers it (the injected context, or `/tickets` / `gh issue list`). If one exists, claim it (move it to In Progress).
  - **Open if missing.** No ticket and a tracker is configured? Open one scoped to the task (title + short description) before you start. No tracker set up? Skip this and describe the work in the PR. One ticket per unit of delivery, not per file; skip it for a trivial fix or a plain question.
  - **Close on delivery, with proof.** When the task ships, post a closing update (what changed, the PR link, a screenshot or short screen recording of the outcome) and move the ticket to Done. Close only with proof.
- **Parallel work:** Multi-surface changes use `agents teams` — see `parallel-teams`.
