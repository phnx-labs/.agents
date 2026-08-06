---
description: Fan work across parallel agents via agents teams — default run, or plan / spec / debug
argument-hint: "[plan|spec|debug|run] <task>  |  <task to fan out>"
---

**`/swarm` is the top-level front door to the `swarm` plugin.** Full procedures live in
skills; this command only routes and invokes.

## Route `$ARGUMENTS`

Strip a leading mode word if present (case-insensitive), then invoke the matching skill
with the **rest** of `$ARGUMENTS` (or the full string if no mode prefix):

| First word | Skill |
|---|---|
| `plan` | `swarm:plan` |
| `spec` | `swarm:spec` |
| `debug` | `swarm:debug` |
| `run` (or anything else / empty mode) | `swarm:run` |

Examples:

- `/swarm plan auth refresh` → Invoke `swarm:plan` with `auth refresh`
- `/swarm spec sessions resume` → Invoke `swarm:spec` with `sessions resume`
- `/swarm debug 401 on /me` → Invoke `swarm:debug` with `401 on /me`
- `/swarm split the release script across hosts` → Invoke `swarm:run` with the full task

`swarm:run` reads `swarm:orchestrate` (the shared fan-out engine). Specialized modes also
read orchestrate first, then layer their own phases.

## Then

Invoke the skill selected above. Arguments: the remaining task text after the mode word
(or all of `$ARGUMENTS` when there is no mode prefix).
