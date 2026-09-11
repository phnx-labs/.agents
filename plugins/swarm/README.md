# swarm plugin

Fan a task out across a team of parallel coding agents, then synthesize. Runs on the
**`agents teams` CLI** (the Swarmify MCP is gone).

**Skill-first.** Commands only say `Invoke the \`swarm:…\` skill`. The shared engine is
the internal **`swarm:orchestrate`** skill (no command of its own).

## Front door

| Surface | Use when |
| --- | --- |
| **`/swarm`** (top-level) | Default entry — routes to `run` / `plan` / `spec` / `debug` from a leading mode word, else generic `run` |
| `/swarm:run` | Explicit generic fan-out (same as bare `/swarm <task>`) |

## Specialized modes (kept)

| Command | Use when |
| --- | --- |
| `/swarm:plan` | A reviewable change proposal. The [plan skill](skills/plan/SKILL.md) owns scope, evidence, visuals, success checks, and review requirements. |
| `/swarm:spec` | Durable **source-of-truth** description of how a capability behaves, in plain language (intent, behavior, sharp cases, what must not change) so other agents and humans do not invent wrong behavior — reverse-engineered from real code, with **mock-ups** for any UI/flow surface. |
| `/swarm:debug` | Non-obvious bug; wrong diagnosis is expensive. Trace the data path, attribute regressions to the responsible agent/session and explain how they slipped, then blind multi-provider root-cause confirm. |

## plan vs spec (similar, not the same)

| | `/swarm:plan` | `/swarm:spec` |
|---|---|---|
| Question | What **delta** should we build next? | What does this capability **already guarantee**? |
| Shape | Change proposal + tasks + delta | Intent + behavior + sharp cases + mock-ups |
| Time | Forward-looking | Present contract (the *is*) |
| Audience | Builders draining the change | Anyone who must not break or re-invent the capability |
| Mock-ups | Product-faithful views for changed UI states; diagrams for system behavior | **Required** for any UI / multi-step flow in the contract |

Both produce a reviewable HTML artifact through `artifacts`, including its independent
presentation review. Independent investigation follows each skill: planning uses it
when useful or explicitly requested; specification follows the `spec` contract.

## Removed

`/swarm:test` and `/swarm:qa` are gone from this plugin (unused). For ordinary test writing
follow the Strict Testing rule in the ruleset; for browser walks use the `browser` skill / a generic `/swarm:run`
brief.

## Principles

- **`agents teams`, not Swarm MCP.** `agents teams --help` / `agents teams doctor`.
- **Discover, then mix.** Signed-in providers only; diversity beats three of one model.
- **Size by judgment.** Wide for gnarly work, one (or none) for narrow.
- **Blinded verification** when the job is to *check* a conclusion.
- **`--mode plan`** for read-only tracks; **`--mode edit`** only when a track changes code.
- **Web-search first** for state-of-the-world facts.
- **Evidence or it didn't happen.** Every brief ends with file:line quotes.

## History

Originally `/swarm`, `/splan`, `/stest`, `/sdebug`, … on Swarmify MCP. Rebuilt on
`agents teams` as `/swarm:*`. 0.5.0 simplifies to run + plan + spec + debug and a
top-level `/swarm` router; test/qa modes dropped.

---

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
