# sessions plugin

Lifecycle and analytics for agent conversation transcripts. One namespace for **picking work
back up**, **seeing how the fleet works**, and **putting windows back** after a crash.

Instructions live in **skills**. Plugin and top-level commands only say
`Invoke the \`sessions:…\` skill` so harnesses that prefer skills (and skip slash-command
bodies) still get the full procedure.

## Skills

| Skill | Use when |
| --- | --- |
| `sessions:continue` | Resume one (or a group of) prior session(s) **in this window** — load transcript, verify what landed, finish the work. Reattach only on a genuine live interactive signal. Also the engine behind post-crash **finish-headlessly** recovery (`/recover`). |
| `sessions:insights` | Analyze how you and your agents work. **Conductor** over `agents insights`, `agents trends`, `agents perf`, and `agents sessions stats` — returns evidence-backed actions. No separate `/trends` or `/perf` plugin commands. |
| `sessions:restore` | Re-open sessions killed by a crash/reboot as **terminal windows**, each resuming its real transcript. Not "finish the work here". |

## Commands

| Command | Invokes |
| --- | --- |
| `/sessions:continue` | `sessions:continue` |
| `/sessions:insights` | `sessions:insights` |
| `/sessions:restore` | `sessions:restore` |

### Top-level aliases

| Alias | Forwards to |
| --- | --- |
| `/continue` | `sessions:continue` |
| `/insights` | `sessions:insights` |
| `/restore` | `sessions:restore` |
| `/recover` | `sessions:continue` in recover mode (many interrupted sessions; prefer finish over resurrect) |

The low-level browse/search skill remains the top-level [`sessions`](../../skills/sessions/SKILL.md)
skill (`agents sessions` CLI). This plugin does not replace it — it adds lifecycle +
analytics verbs on top.

## How the three verbs differ

```
continue  →  this agent finishes the work (here; group-capable)
recover   →  continue in multi-session crash mode (still finish, not windows)
restore   →  put the original windows back
insights  →  orchestrate local analytics engines → actions
```

## Requirements

- [`agents-cli`](https://github.com/phnx-labs/agents-cli) on `$PATH` with `agents sessions`,
  `agents insights`, `agents trends`, `agents perf` available for the surfaces you invoke.
- Optional: Ghostty (or another terminal emulator) on the interactive Mac for
  `sessions:restore` window relaunch.

## Conventions

- **Skill-first.** Behavior changes go in `skills/*/SKILL.md`. Commands stay one-line
  invoke wrappers. Top-level aliases stay thin — never fork the procedure into the alias.
- **Local analytics.** Insights never upload raw transcripts; engines stay on-machine
  unless the user opts into a shareable artifact.
- **Restore is expensive.** Never auto-open a swarm of live agents without an explicit
  count (or `all` in `$ARGUMENTS`).

---

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
