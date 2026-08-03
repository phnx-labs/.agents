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
(`resourceDir('rules') -> 'memory'`, `apps/cli/src/lib/resources.ts:64`). Verified: the
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
