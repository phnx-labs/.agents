# sessions plugin

Lifecycle and analytics for agent conversation transcripts. One namespace for **picking work
back up** (in this window, or headlessly after a crash) and **seeing how the fleet works**.

Instructions live in **skills**. Plugin and top-level commands only say
`Invoke the \`sessions:…\` skill` so harnesses that prefer skills (and skip slash-command
bodies) still get the full procedure.

## Skills

| Skill | Use when |
| --- | --- |
| `sessions:continue` | Resume one (or a group of) prior session(s) **in this window** — load transcript, verify what landed, finish the work. Reattach only on a genuine live interactive signal. Also the engine behind post-crash **finish-headlessly** recovery (`/continue recover`). |
| `sessions:finish` | Drive the **current** task to fully delivered — verify E2E, docs, commit, PR, release checklist, close the ticket. The anti-stopping driver: never ends at a recap, blocker, or partial handoff. |
| `sessions:insights` | Analyze how you and your agents work. **Conductor** over `agents insights`, `agents insights mix`, `agents insights perf`, and `agents sessions stats` — returns evidence-backed actions. No separate `/trends` or `/perf` plugin commands. |
| `sessions:fork` | Fork a session into a NEW same-harness sibling seeded with a recap of the source — cross-device and cross-harness, the "git branch" of sessions (the original is untouched). Bare = fork the current session; `<id>` = fork a specific one. |
| `sessions:search` | Pull ranked, snippet-level context from prior sessions on a topic — layered `agents sessions` discovery plus the bundled [`recall.py`](./skills/search/recall.py) fallback that recovers assistant answers the index never stores (it only holds user turns + title/topic/project). |

## Commands

Only `continue` and `search` keep a plugin-namespaced command door;
`finish`, `insights`, and `fork` are reached through their top-level alias only
(one door per skill, not two) — see `../../commands/README.md`.

| Command | Invokes |
| --- | --- |
| `/sessions:continue` | `sessions:continue` |
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

## How the five verbs differ

```
continue          →  this agent finishes the work (here; group-capable)
continue recover  →  finish many mid-task sessions headlessly after a crash (not windows)
finish            →  drive the CURRENT task to delivered (anti-stopping ship gate)
fork              →  branch into a NEW independent session (original untouched)
insights          →  orchestrate local analytics engines → actions
search            →  pull ranked, snippet-level context from PAST sessions on a topic
```

> Re-entering a whole **project** (its in-flight sessions, PRs, worktrees, tickets) and
> resuming that work on the fleet is [`/work:resume`](../work/README.md), not a sessions verb.
> The old `sessions:restore` (reopen crashed terminal windows) was removed — crash recovery
> now finishes work headlessly via `/continue recover`.

## Requirements

- [`agents-cli`](https://github.com/phnx-labs/agents-cli) on `$PATH` with `agents sessions`,
  `agents insights`, `agents insights mix`, `agents insights perf` available for the surfaces you invoke.
- `python3` (stdlib only) on `$PATH` for `sessions:search`'s `recall.py` fallback.

## Conventions

- **Skill-first.** Behavior changes go in `skills/*/SKILL.md`. Commands stay one-line
  invoke wrappers. Top-level aliases stay thin — never fork the procedure into the alias.
- **Local analytics.** Insights never upload raw transcripts; engines stay on-machine
  unless the user opts into a shareable artifact.
- **Recovery finishes work, it doesn't reopen windows.** `/continue recover` drives many
  mid-task sessions to done headlessly — prefer that over resurrecting a swarm of terminals.

---

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
