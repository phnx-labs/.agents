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
| `/work:research` | **A hard research question** answered across DISTINCT engines blind to each other — Codex (web search), Grok (X/Twitter community), Antigravity (Google), Perplexity (broad browser-driven **Deep Research** — the dedicated mode, never Computer/Control-browser), Claude (deep-read + reconcile). Cross-checks every claim (single-sourced = a lead, not a fact) and promotes the cited result to the project's durable-artifacts home (`.agents/artifacts/` by default). |
| `/work:resume` | **Pick a whole PROJECT's work back up** (top-level alias `/resume`). Best-effort auto-detect the project from the CWD (git repo + subdir → Linear), reconstruct its in-flight work (live + interrupted sessions, open PRs, worktrees, open/doing tickets), present it not-progressing-first, then **offload each item to a `role=worker` device** — never the interactive/personal box. One project (vs `work:loop`'s whole board); reconstructs full state (vs `work:dispatch`'s one item). |
| `/work:demo` | **Prove landed work, don't just claim it shipped.** The post-ship capstone: recover the ORIGINAL intent (not the diff), exercise the shipped thing in its **real** environment (installed/deployed, never the dev build) on **real representative inputs** signed in as the owner via `agents browser`/`agents computer`, put before/after side by side with a **measured** delta, then deliver an analyzed report on the owner's screen + attach it to the PR. Top-level alias: **`/demo`**. The answer to "show me a demo..". |

## Skills

| Skill | Role |
| --- | --- |
| `work:loop` | Orchestrator for overnight / multi-item drain. Composes engineering patterns from `code:loop`, including its merge-on-green completion. Its `triage` mode is the board-wide keep-and-schedule-or-cancel decision pass. |
| `work:resume` | Re-enter a project: identify it from the CWD, reconstruct its in-flight work read-only, then offload each not-progressing item to a worker (composes `work:loop`'s worker-spawn path, scoped to the one project). The orchestrating session only reconstructs + monitors — it never becomes the compute node, since it may be on the personal laptop. Reached via `/work:resume` or the top-level `/resume` alias. |
| `work:research` | Multi-modal research: frame the question into angles, fan out across engines that each see a different slice (Codex/web, Grok/X, Antigravity/Google, Perplexity/broad Deep Research, Claude/deep-read) **blind to each other**, cross-check claims across sources (single-sourced = a lead to verify), and synthesize one cited artifact into the project's durable-artifacts home (`.agents/artifacts/` by default). Composes `run` + `teams` + `browser` + `artifacts`. |
| `work:demo` | The post-ship demonstration ritual — seven steps from recovering intent to delivering an analyzed report. Reached via `/work:demo` or the top-level `/demo` alias. |
| (dispatch is command-first today) | One-item path in `commands/dispatch.md`. |

## How the pieces fit

```
/work:resume      → re-enter ONE project: reconstruct its in-flight work, resume on workers
/work:loop triage → decide keep/cancel/priority on the whole board
/work:loop        → drain everything clear, unattended, spread load
/work:dispatch    → one item, any kind
/work:research    → one question, many engines (blind), one cited answer
/work:demo        → after it lands, PROVE it — real env, before/after, report
/code:loop        → engineering-only queue (worktrees, merge-oriented)
```

- **`/work:resume` vs `/work:loop`** — resume is scoped to the **one project** you're in and
  reconstructs its *full* state (sessions, PRs, worktrees, tickets) before resuming; loop is
  the whole board across every project. Both **offload execution to workers** — resume reuses
  loop's worker-spawn path, scoped. Neither runs compute on a `role=personal` box.

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
