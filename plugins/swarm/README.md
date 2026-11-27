# swarm plugin

Modes that use a team of independent agents to check a conclusion: a plan, a spec, or a
root cause. Each mode runs on the **`agents teams` CLI**, and the mechanics of splitting
work across a team (tracks, boundaries, blinded verification, the seam check) live in
the [`teams`](../../skills/teams/SKILL.md) skill, so they are written down once.

**Skill-first.** Commands only say `Invoke the \`swarm:…\` skill`.

## Front door

| Surface | Use when |
| --- | --- |
| **`/swarm`** (top-level) | Routes `plan` / `spec` / `debug` to that mode; any other task loads the `teams` skill |
| `/plan`, `/spec`, `/debug` (top-level) | Aliases of `/swarm:plan`, `/swarm:spec`, `/swarm:debug` |

## Modes

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
`/plan` already includes visualization; `/visualize` is not an additional required
step. Every plan opens with its goal, expected outcome and success checks, before
implementation details. An explicit request for another output format takes precedence.

## Removed

`/swarm:test` and `/swarm:qa` are gone from this plugin (unused). For ordinary test writing
follow the Strict Testing rule in the ruleset; for browser walks use the `browser` skill or a `/swarm <task>` team.

## History

Originally `/swarm`, `/splan`, `/stest`, `/sdebug`, … on Swarmify MCP. Rebuilt on
`agents teams` as `/swarm:*`. 0.5.0 simplifies to run + plan + spec + debug and a
top-level `/swarm` router; test/qa modes dropped. 0.6.0 folds the `orchestrate` engine
into the `teams` skill and drops `run`, which restated it; bare `/swarm <task>` loads `teams`.

---

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
