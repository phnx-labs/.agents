# sessions plugin

Lifecycle and analytics for agent conversation transcripts. One namespace for **picking work
back up**, **seeing how the fleet works**, and **putting windows back** after a crash.

Instructions live in **skills**. Plugin and top-level commands only say
`Invoke the \`sessions:…\` skill` so harnesses that prefer skills (and skip slash-command
bodies) still get the full procedure.

## Skills

| Skill | Use when |
| --- | --- |
| `sessions:continue` | Resume one (or a group of) prior session(s) **in this window** — load transcript, verify what landed, finish the work. Reattach only on a genuine live interactive signal. Also the engine behind post-crash **finish-headlessly** recovery (`/continue recover`). |
| `sessions:finish` | Drive the **current** task to fully delivered — verify E2E, docs, commit, PR, release checklist, close the ticket. The anti-stopping driver: never ends at a recap, blocker, or partial handoff. |
| `sessions:insights` | Analyze how you and your agents work. **Conductor** over `agents insights`, `agents insights mix`, `agents perf`, and `agents sessions stats` — returns evidence-backed actions. No separate `/trends` or `/perf` plugin commands. |
| `sessions:restore` | Re-open sessions killed by a crash/reboot as **terminal windows**, each resuming its real transcript. Not "finish the work here". |
| `sessions:fork` | Fork this conversation into a NEW, independent session and open it in a fresh terminal — the "git branch" of sessions (the original is untouched). Bare = fork the current session; `<id>` = fork a specific one. |
| `sessions:search` | Pull ranked, snippet-level context from prior sessions on a topic — layered `agents sessions` discovery plus the bundled [`recall.py`](./skills/search/recall.py) fallback that recovers assistant answers the index never stores (it only holds user turns + title/topic/project). |

## Commands

Only `continue`, `restore`, and `search` keep a plugin-namespaced command door;
`finish`, `insights`, and `fork` are reached through their top-level alias only
(one door per skill, not two) — see `../../commands/README.md`.

| Command | Invokes |
| --- | --- |
| `/sessions:continue` | `sessions:continue` |
| `/sessions:restore` | `sessions:restore` |
| `/sessions:search` | `sessions:search` |

### Top-level aliases

| Alias | Forwards to |
| --- | --- |
| `/continue` | `sessions:continue` |
| `/finish` | `sessions:finish` |
| `/insights` | `sessions:insights` |
| `/fork` | `sessions:fork` |
| `/recall` | `sessions:search` |

The low-level browse/search skill remains the top-level [`sessions`](../../skills/sessions/SKILL.md)
skill (`agents sessions` CLI). This plugin does not replace it — it adds lifecycle +
analytics verbs on top.

## How the six verbs differ

```
continue          →  this agent finishes the work (here; group-capable)
continue recover  →  continue in multi-session crash mode (still finish, not windows)
finish            →  drive the CURRENT task to delivered (anti-stopping ship gate)
restore           →  put the original windows back
fork              →  branch into a NEW independent session (original untouched)
insights          →  orchestrate local analytics engines → actions
search            →  pull ranked, snippet-level context from PAST sessions on a topic
```

## Requirements

- [`agents-cli`](https://github.com/phnx-labs/agents-cli) on `$PATH` with `agents sessions`,
  `agents insights`, `agents insights mix`, `agents perf` available for the surfaces you invoke.
- `python3` (stdlib only) on `$PATH` for `sessions:search`'s `recall.py` fallback.
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
