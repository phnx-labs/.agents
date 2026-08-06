# work plugin

Get work done across the fleet — **any** kind, not just code. The `code` plugin owns
engineering-only patterns (`code:loop`); `work` is the layer above that routes and
drains **multi-project, multi-kind** work (browser, outreach, design, portals) because
the fleet holds browser + computer + secrets.

## Commands

| Command | Use when |
| --- | --- |
| `/work:loop` | **Unattended drain** of many items across projects. Spreads load (`agents teams` + balanced accounts + worker hosts). Uses browser/computer when the task needs it. **No review/merge gate** — finish agent-doable work, open PRs for the human to review later. Top-level alias: `/drain`. |
| `/work:dispatch` | **ONE** unit of work — ticket, described task, or "next on `<project>`". Classify coding vs non-coding, file clean if needed, route to the right executor, drive to done. Single-target; not a board sweep. |

## Skills

| Skill | Role |
| --- | --- |
| `work:loop` | Orchestrator for overnight / multi-item drain. Compose engineering patterns from `code:loop` without its merge-review completion. |
| (dispatch is command-first today) | One-item path in `commands/dispatch.md`. |

## How the pieces fit

```
/triage          → decide keep/cancel/priority (human-shaped)
/work:loop       → drain everything clear, unattended, spread load
/work:dispatch   → one item, any kind
/code:loop       → engineering-only queue (worktrees, merge-oriented)
```

- **`/triage`** — board decisions. `work:loop` skips items that need cancel/taste.
- **`/code:loop`** — engineering drain with merge-oriented "done". `work:loop` may
  reuse its worktree/claim patterns but **stops at PR open** by default (human reviews
  later). Do not run `code:review` merge from `work:loop`.
- **`/drain`** — short alias of `/work:loop`.

## Load-spreading (why this exists)

Real overnight failures: Claude logouts on m-boxes, bwrap failures, everything re-homed
onto two hosts. `work:loop` treats that as expected: always fan out with balanced
rotation, mixed harnesses, worker-only spawn, and re-home on auth/limit death.

## Conventions

- **Non-coding is first-class.** Browser + computer + secrets are how outreach, portals,
  and orders get done — not "file a ticket for later."
- **Unattended by default.** No `AskUserQuestion`; park real blockers and continue.
- **In flight ≠ done.** PR open or real-world proof; ticket updated.

---

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
