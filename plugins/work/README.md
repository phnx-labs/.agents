# work plugin

Get work done across the fleet — **any** kind, not just code. The `code` plugin owns
engineering-only patterns (`code:loop`); `work` is the layer above that routes and
drains **multi-project, multi-kind** work (browser, outreach, design, portals) because
the fleet holds browser + computer + secrets.

## Commands

| Command | Use when |
| --- | --- |
| `/work:loop` | **Unattended drain** of many items across projects. Spreads load (`agents teams` + balanced accounts + worker hosts). Uses browser/computer when the task needs it. **Drives each item to landed** — engineering merges on green behind a non-author review; you are asked only for a real product/credential decision. Its **`triage` mode** (`/work:loop triage`) instead forces every open board item to keep-and-schedule-this-cycle or cancel — never a hedge state. |
| `/work:dispatch` | **ONE** unit of work — ticket, described task, or "next on `<project>`". Classify coding vs non-coding, file clean if needed, route to the right executor, drive to done. Single-target; not a board sweep. |
| `/work:demo` | **Prove landed work, don't just claim it shipped.** The post-ship capstone: recover the ORIGINAL intent (not the diff), exercise the shipped thing in its **real** environment (installed/deployed, never the dev build) on **real representative inputs** signed in as the owner via `agents browser`/`agents computer`, put before/after side by side with a **measured** delta, then deliver an analyzed report on the owner's screen + attach it to the PR. Top-level alias: **`/demo`**. The answer to "show me a demo..". |

## Skills

| Skill | Role |
| --- | --- |
| `work:loop` | Orchestrator for overnight / multi-item drain. Composes engineering patterns from `code:loop`, including its merge-on-green completion. Its `triage` mode is the board-wide keep-and-schedule-or-cancel decision pass. |
| `work:demo` | The post-ship demonstration ritual — seven steps from recovering intent to delivering an analyzed report. Reached via `/work:demo` or the top-level `/demo` alias. |
| (dispatch is command-first today) | One-item path in `commands/dispatch.md`. |

## How the pieces fit

```
/work:loop triage → decide keep/cancel/priority on the whole board
/work:loop        → drain everything clear, unattended, spread load
/work:dispatch    → one item, any kind
/work:demo        → after it lands, PROVE it — real env, before/after, report
/code:loop        → engineering-only queue (worktrees, merge-oriented)
```

- **`/work:loop triage`** — board decisions. A plain `work:loop` drain skips items that need cancel/taste; `triage` mode is where those calls get made.
- **`/code:loop`** — engineering drain with merge-oriented "done". `work:loop` reuses its
  worktree/claim patterns **and its completion bar**: engineering items land **merged** on
  green behind a non-author review, never parked on the user as an open PR.

## Load-spreading (why this exists)

Real overnight failures: Claude logouts on m-boxes, bwrap failures, everything re-homed
onto two hosts. `work:loop` treats that as expected: always fan out with balanced
rotation, mixed harnesses, worker-only spawn, and re-home on auth/limit death.

## Conventions

- **Non-coding is first-class.** Browser + computer + secrets are how outreach, portals,
  and orders get done — not "file a ticket for later."
- **Unattended by default.** No `AskUserQuestion`; park real blockers and continue.
- **In flight ≠ done.** PR open or real-world proof; ticket updated.
- **Merged ≠ demonstrated.** Landing is half the job — `/work:demo` proves the shipped
  thing does what was asked, in its real environment, before you call it done.

---

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
