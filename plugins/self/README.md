# self

Operations an agent performs on its **own** session — the "self" namespace is for an agent
acting on itself, not on code, the fleet, or the outside world.

## Commands

| Command | What it does |
|---|---|
| [`/self:close`](./commands/close.md) | Cleanly self-terminate this session — `SIGTERM` the harness so it flushes the transcript, saves state, and runs post-session hooks. Guarded so it never signals a shell / tmux / sshd parent. |
| [`/self:hibernate`](./commands/hibernate.md) | Hibernate THIS session until a future time, then wake it with full context (no transfer) to re-check a long wait — approval, deploy, review. |
| [`/self:reflect`](./commands/reflect.md) | Recall every correction and constraint from the active conversation before revising work. Thin wrapper over the `self:reflect` skill. |

## Skills

| Skill | What it does |
|---|---|
| [`self:reflect`](./skills/reflect/SKILL.md) | Recall all cumulative feedback, corrections, and constraints from the active conversation before rewriting or iterating. Portable — it loads by description match on every harness, not only where the `/self:reflect` command exists. Moved here from the flat `skills/` list so the reflect skill lives with its command. |

## `/self:close` — the exit primitive

There is no `/exit` tool exposed to an agent. The only self-exit is signalling the harness
process directly: the Bash tool's shell has the harness as its parent (`$PPID`), and `SIGTERM`
is the clean path (unlike `SIGKILL`). `/self:close` is that primitive and nothing more — it
does not recap, verify, or clean up.

Build on it, don't reach past it:

- **`/recap`** = summarize the session's state for handoff — does not exit. Run it before
  `/self:close` when you want a recap on the way out.
- **`/finish`** = drive the work to delivered (verify E2E, docs, commit, PR, close tickets) —
  does **not** exit.
- **`/self:close`** = just leave. Use it only when the work is genuinely wrapped or you were
  asked to end the session — never to dodge unfinished work.

## How it runs headlessly

`/self:close` runs two calls: a read-only
`ps -o comm= -p $PPID` guard that refuses infra parents, then **exactly** `kill -TERM $PPID`.
That exact form is allowlisted by the `self` permission group
([`permissions/groups/12-self.yaml`](../../permissions/groups/12-self.yaml)), so in auto/headless
mode the self-exit is not blocked by the permission classifier — while the allow stays scoped to
this one form (direct parent, `TERM` only), never a general `kill`.

## Enabling

Registered in [`.claude-plugin/marketplace.json`](../../.claude-plugin/marketplace.json) and
materialized into every installed agent version on `agents sync`. Enable it per agent to let
that agent end its own run.

---

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
