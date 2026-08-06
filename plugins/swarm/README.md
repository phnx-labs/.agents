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
| `/swarm:plan` | Before building anything non-trivial. Research, **mock-ups**, OpenSpec-grade change proposal, blind independent planners, reconcile. |
| `/swarm:spec` | Durable **source-of-truth** contract of a capability (SHALL + Given/When/Then) so other agents and humans do not invent wrong behavior — reverse-engineered from real code, drift-checked, with **mock-ups** for any UI/flow surface. |
| `/swarm:debug` | Non-obvious bug; wrong diagnosis is expensive. Trace the data path, blind multi-provider root-cause confirm, then close the loop. |

## plan vs spec (similar, not the same)

| | `/swarm:plan` | `/swarm:spec` |
|---|---|---|
| Question | What **delta** should we build next? | What does this capability **already guarantee**? |
| Shape | Change proposal + tasks + delta | Purpose + Requirements (RFC 2119) + scenarios |
| Time | Forward-looking | Present contract (the *is*) |
| Audience | Builders draining the change | Anyone who must not break or re-invent the capability |
| Mock-ups | **Required** for any UI / multi-step flow in the proposal | **Required** for any UI / multi-step flow in the contract |

Both produce a reviewable HTML artifact (via `plan-render`). Both use the swarm to try to
break the draft (blind independent plans / specs).

## Removed

`/swarm:test` and `/swarm:qa` are gone from this plugin (unused). For ordinary test writing
use top-level `/test` or `code:verify`; for browser walks use the `browser` skill / a
generic `/swarm:run` brief.

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
