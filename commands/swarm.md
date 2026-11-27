---
description: Fan work across parallel agents via agents teams, or run a swarm mode (plan / spec / debug)
argument-hint: "[plan|spec|debug] <task>  |  <task to fan out>"
---

Strip a leading mode word from `$ARGUMENTS` (case-insensitive) and invoke the matching
skill with the rest:

| First word | Skill |
|---|---|
| `plan` | `swarm:plan` |
| `spec` | `swarm:spec` |
| `debug` | `swarm:debug` |
| anything else | `teams`, with the full `$ARGUMENTS` (follow "Split a task across a team") |

Examples:

- `/swarm spec sessions resume` → invoke `swarm:spec` with `sessions resume`
- `/swarm debug 401 on /me` → invoke `swarm:debug` with `401 on /me`
- `/swarm split the release script across hosts` → invoke `teams` with the full task
