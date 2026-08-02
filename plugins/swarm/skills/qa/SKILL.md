---
name: qa
description: "QA an app with a swarm in waves — a smart orchestrator maps the QA surface, provisions several app instances on different ports, then fans QA agents across them in innings (first batch, then the next), scaling by complexity, and synthesizes a ranked ship/no-ship verdict. Drives running instances via `agents browser`, not a code-test runner. Triggers on: 'swarm qa', 'QA this app', 'parallel QA', 'walk the whole app', 'pre-release QA', 'test the running build'."
argument-hint: "[app, build, or scope to QA]"
allowed-tools: Bash(agents teams*), Bash(agents browser*), Bash(agents view*), Bash(agents run*), Bash(rg*), Bash(fd*), Bash(ls*), Bash(git log*), Read(*), Grep(*), Glob(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# swarm:qa — provision instances, then QA them in waves

> Read `swarm:orchestrate` first for the fan-out mechanics, provider discovery (`agents teams doctor` / `agents view --json`), and the judgment-based sizing rule. This skill is the **QA mode**: you are the smart admin who decides how to split QA across an app, stands up parallel instances, and runs agents against them in innings.

You are QA-ing: **$ARGUMENTS**

This is **behavioral QA of a running app** — click the real flows, watch the real output — not a unit-test runner (that's `/swarm:test`) and not a code diff gate (that's `/code:verify`). The driver is `agents browser` (CDP); the parallelism comes from running the app on **multiple ports at once** and fanning agents across them in **waves**.

## Phase 1 — Recon & split (you, the orchestrator)

Map the QA surface before spawning anything:
- Enumerate the critical flows, pages, and endpoints. If a canonical checklist exists for this app (e.g. a `QA.md`), use its sections as the natural split.
- Group into **independent QA tasks** — each a self-contained flow one agent can walk start-to-finish.
- Decide **wave size** and **agent count by judgment** (per `swarm:orchestrate` — no fixed table): more parallelism for a wide app, less for a focused surface. A wave is roughly as many tasks as you have free instances × signed-in providers.
- If a flow depends on a current external truth (a third-party API's behavior, a pricing screen, a SOTA expectation), **WebSearch with the current year** so agents QA against ground truth, not stale assumptions.

## Phase 2 — Provision instances (this skill spins them up)

Parallel QA needs parallel targets. This skill is your explicit authorization to **start app instances** — provision them, and **tear them all down in Phase 5**.

1. Find how the app runs and where the port is set — read its run scripts / dev-server invocation. Common shapes:
   - Web: `bun run dev` / `next dev` with a port override (`PORT=3001 bun run dev` or `--port 3001`).
   - Electron / native via CDP: launch with `--remote-debugging-port=<port>` (the established convention is `rush-local` on CDP `9222`, `rush-mac-mini` on `9223`).
2. Stand up **K instances on distinct ports**, K sized to the machine and the wave (don't exhaust the box). Health-check each (`curl -sS localhost:<port>` or the CDP `/json` endpoint) before using it — an instance that didn't bind is not a target.
3. Point a browser profile at each: reuse `rush-local` / `rush-mac-mini` where they fit, or create per-port profiles (`agents browser profiles create qa-<port> ...`).
4. **Fallback:** if the app genuinely can't run multiple instances, drop to **one shared instance with serialized waves** — fewer agents per inning, more innings. Say so in the recon summary; don't silently pretend you parallelized.

## Phase 3 — Plan the waves (innings)

Batch the QA tasks into waves. Assign each task an **agent (mixed signed-in providers)** and a **target port**. **Pre-declare every wave up front** and chain them with `--after` — hot-adding to a live team is not a clean primitive, so wave N+1's teammates are added now with `--after` on wave N's teammate names, and `start` drains the DAG, launching each inning as the previous one frees its agents and ports.

```bash
agents teams create qa-<app-slug>
# Wave 1 — first batch, each on its own port
agents teams add qa-<app-slug> claude "<brief: flow A @ port 3001>" --name w1-flowA --mode plan
agents teams add qa-<app-slug> codex  "<brief: flow B @ port 3002>" --name w1-flowB --mode plan
# Wave 2 — starts when wave 1 frees the ports/agents
agents teams add qa-<app-slug> antigravity "<brief: flow C @ port 3001>" --name w2-flowC --after w1-flowA --mode plan
agents teams add qa-<app-slug> claude "<brief: flow D @ port 3002>" --name w2-flowD --after w1-flowB --mode plan
agents teams start qa-<app-slug> --watch
```

`--mode plan` for observe/triage agents (the default — they read and report). `--mode edit` **only** for an agent whose job is to actually write bug reports to a file or issue tracker.

## Phase 4 — Execute & observe

Each QA agent's brief (full template in `swarm:orchestrate`) tells it to drive **its assigned port** and, critically, to **drain the silent-failure channels after every meaningful step**, not just at the end:

```bash
export AGENTS_BROWSER_TASK=$(agents browser start --profile qa-<port>)
agents browser tab add --url <flow entry>
agents browser click <ref> / type <ref> --text "..."
agents browser screenshot                 # visual evidence per step
agents browser console --level error      # JS errors the UI swallowed
agents browser errors                     # page/network errors
agents browser requests --filter api      # failed/4xx/5xx calls behind a "working" screen
agents browser done
```

A screen that *looks* fine while `console`/`errors`/`requests` show failures is a FAIL — this draining habit is the load-bearing part of UI QA. Each agent records, per flow: steps taken, screenshots, drained logs, and a verdict.

Monitor with `agents teams status qa-<app-slug> --since <iso-ts>` (sleep-poll, never `Monitor`). Unblock a stalled agent by reading its log and re-briefing.

## Phase 5 — Synthesize & tear down

- Aggregate findings across all waves; **dedupe** the same bug reported by multiple agents.
- Rank by severity using the reused taxonomy: **PASS** (flow works) / **REVIEW** (works but suspect) / **FAIL** (broken flow) / **BLOCKED** (couldn't test). For a release pass, roll up to a single **SHIP / NO-SHIP**.
- Each finding gets: the flow, the agent + provider, repro steps, and evidence (screenshot path + quoted log line). No claim without evidence.
- **`agents teams disband qa-<app-slug>`** and **kill every instance you started** (and any SSH-launched remote ones). Leaving dev servers running is a guardrail violation.

## Output

### Summary
App, surface covered, instances/ports used, waves run, providers mixed. Overall verdict (SHIP / NO-SHIP or PASS-rate).

### Findings (ranked)
Per finding: severity, flow, agent (provider), repro steps, evidence (screenshot + log quote).

### Coverage gaps
Flows not reached and why (BLOCKED reasons), so the next pass knows where to start.

### Teardown
Instances stopped, team disbanded — confirmed.
