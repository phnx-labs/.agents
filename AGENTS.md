# .agents-system — maintenance contract

This file is for the agent editing this repo. Humans start at [README.md](./README.md).

This repo is the **system layer** of agents-cli: the npm-shipped defaults that land at
`~/.agents/.system/` on every machine and get merged under the user's own `~/.agents/`.
Everything here ships to every agent on every box, so a broken file here breaks the fleet.

## The two-file convention

Every directory carries both, and they do different jobs. Do not merge them.

- **`README.md`** — for humans. What lives here, and a table listing every item with a
  one-line description linked to its source file. It is a **catalog**, not a tutorial.
- **`AGENTS.md`** — for agents. The invariants: what must stay in sync, what the file
  format is, what breaks if you get it wrong. Declarative and short.

`AGENTS.md` is canonical; `CLAUDE.md` and `GEMINI.md` are symlinks to it
(`ln -s AGENTS.md CLAUDE.md`). Edit `AGENTS.md` only — a symlink target edited directly is
stomped on the next sync.

**One exception: `rules/AGENTS.md` is not a maintenance file.** It is the *composed ruleset*
that syncs into every agent as its memory file. `rules/` therefore carries its maintenance
guidance in `rules/README.md` instead. Never write maintenance notes into `rules/AGENTS.md`
— they would be injected into every agent's context on the fleet.

Subdirectory `AGENTS.md` files are **not** synced into agent prompts. Only `rules/` is
(`profiledKind` maps `rules` -> `'memory'`, `apps/cli/src/lib/resources.ts:64-65`). Verified: the
composed `~/.claude/CLAUDE.md` carries the ruleset and no other directory's `AGENTS.md`.

## Adding a resource — what must stay in sync

Adding a file is never the whole change. Each kind has a second place that must be updated,
or the resource exists on disk and is invisible or dead:

| Kind | Add | Also update |
|---|---|---|
| command | `commands/<name>.md` with `description:` frontmatter | the table in `commands/README.md` |
| skill | `skills/<name>/SKILL.md` with `name:` + `description:` | the table in `skills/README.md` |
| hook | `hooks/<NN>-<name>.{sh,py}` **and** the `hooks:` entry in `agents.yaml` | the table in `hooks/README.md`; ship a `_test.sh` beside it |
| permission | a fragment in `permissions/groups/` | run `permissions/build.sh` to regenerate `default.yaml` |
| plugin | `plugins/<name>/` with its own `README.md` | the table in `plugins/README.md` |
| rule | `rules/subrules/<name>.md` | the `default` preset in `rules/rules.yaml`, then regenerate `rules/AGENTS.md` |
| CLI manifest | `cli/<tool>.yaml` | the table in `cli/README.md` |
| routine | `routines/<name>.yml` | the table in `routines/README.md` |

A hook is the sharpest edge: the script alone does nothing. Registration is the
`hooks:` entry in `agents.yaml`, and an unregistered script is dead code.

## Authoring a new capability — group it, and give it a front door

**Group related skills into a plugin rather than shipping them loose.** A plugin is the
unit that carries a namespace, its own README, and a manifest. Loose skills that share a
domain — an industry, a function, one product's workflow — should be one
`plugins/<name>/` with its skills inside, not N entries competing in the flat `skills/`
list. The test: if two skills would always be installed together, or if a reader would
ask "which of these three do I use?", they are one plugin. A skill stays top-level only
when it is genuinely standalone and cross-domain (`browser`, `mq`, `sessions`).

**Give every user-facing skill a slash command that routes to it.** A skill loads when
the model decides its `description` matches; a command fires when the user types it.
Those are different doors, and a skill with no command can only be reached by asking the
agent nicely. Add `commands/<name>.md` (or `plugins/<p>/commands/<name>.md`) that routes
to the skill — the command stays thin, the behavior stays in the skill, and they never
fork (see the `/commit` → `/code:commit` alias pattern).

**But the command is an accelerator, never the only door.** Commands are not universal
across harnesses, and skills very nearly are. From the capability table
(`apps/cli/src/lib/agents.ts`):

| Capability | Coverage |
|---|---|
| skills | every harness (version-gated on `goose` ≥1.25.0, `droid` ≥0.26.0) |
| commands | **not** on `openclaw`, `kimi`, `hermes`; on `codex` only **below** 0.117.0 |
| plugins | **not** on `amp`, `kiro` |

So a capability that only works when its command exists is broken on four harnesses.
Write the skill so it is complete on its own, then add the command as the fast path.
Never move logic out of the skill and into the command. When a plugin is the right
grouping but a target harness has no plugin support, say so in the plugin's README
rather than silently shipping something a third of the fleet cannot load.

## Every user-visible change updates CHANGELOG.md

A change to a command, skill, hook, rule, permission, or plugin adds an entry under the next
version in `CHANGELOG.md`, in the same delivery. Exempt, and say so in the PR: pure internal
refactors, test-only changes, self-evident renames.

## Never edit this repo in place on a machine

`~/.agents/.system/` is a **pull-only mirror**. Local edits there are overwritten on the next
`agents sync system`. Change it the same way as any repo: a worktree under
`.agents/worktrees/<slug>/` branched from `origin/main`, then a PR. Never commit on `main`.

To change behavior on one machine without touching this repo, add the same-named file under
`~/.agents/` — the user layer wins on a name collision.

## Verify a change reached an agent, not just the repo

Merged is not live. After a change lands, the proof is that the resource is registered in an
agent's version home, not that the checkout is current:

```bash
agents sync system            # git-sync the repo (refuses on a dirty tree)
agents sync claude@all system # reconcile this repo's resources into every installed Claude
agents inspect hooks          # the hook is registered, with its events
```

## Tests

Hooks carry `<name>_test.sh` beside the script and it must pass before the PR. Test against
the real critical path — no mocking. A guard hook additionally needs a fixture proving it
**fails closed**: the blocked input is refused when its JSON parser is absent.
