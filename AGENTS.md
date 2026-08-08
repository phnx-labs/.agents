# .agents-system — maintenance contract

This file is for the agent editing this repo. Humans start at [README.md](./README.md).

This repo is the **system layer** of agents-cli: the npm-shipped defaults that land at
`~/.agents/.system/` on every machine and get merged under the user's own `~/.agents/`.
Everything here ships to every agent on every box, so a broken file here breaks the fleet.

## North star — every change here buys agents more *safe* autonomy

The hooks, rules, permissions, and commands in this repo exist for one purpose: to let an
agent act on the user's behalf with **more autonomy, safely** — reliably, predictably, and
manageably, without a human babysitting each step. Judge every change you make here against
that goal. The pull is always toward *more* the agent can do on its own; the discipline is
that it stays trustworthy while doing it.

- **The guardrails counter agent laziness — they don't just forbid.** A hook fires on an
  event nobody asked for, which is what turns "the agent should have…" into "the agent
  always does." Prefer a guardrail that makes the safe path the automatic one over a rule
  that merely asks an agent to remember. The point is to *enable* reliable action, not to
  cage it.
- **Cross-harness by default.** A capability must work on every harness the fleet runs —
  Claude Code, Codex, and the rest — not just the one you tested in. Skills are near-
  universal; commands and plugins are not (see the coverage table under "Authoring a new
  capability"). Ship the behavior in the portable layer, then add the accelerator on top.
- **Cross-platform and cross-device by default.** macOS, Linux, and Windows; the user's
  laptop and every worker box. A hook or script that assumes one shell, one path style, or
  one bash version silently breaks the others — bash 3.2 on macOS is the usual tripwire (see
  the hooks contract). Autonomy that works on only one machine is not autonomy.
- **Predictable beats clever.** Creativity is welcome; unpredictability is not. An agent and
  the user must both be able to reason about what a change will do *before* it runs. Fail
  closed, make the safe action the easy one, and never trade manageability for a one-off win.
- **Protect what can't be undone.** Autonomy stops at irreversible loss. An agent may remove
  its own worktree freely, but it must **never delete a branch — local or remote**; accidental
  branch deletion has lost real work. Local deletion is already denied (permission groups +
  git-guard); the git-guard is being extended to the remote vectors (`git push --delete`,
  `gh pr merge --delete-branch`) so the ban is complete. Never add a permission or guardrail
  exception that re-enables it, and when you weigh a new capability, ask what it destroys if
  it fires wrongly.

## The two-file convention

This section is **this repo's instance** of the general rule. The rule itself — including
when a directory wants neither file — lives in the
[`write-agents-md`](./skills/docs/write-agents-md.md) docs subskill. Change it there first; this section
records only how it lands here, plus the `rules/` exception below.

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
| plugins | **not** on `amp`, `kiro`; version-gated on `codex` ≥0.128.0, `gemini` ≥0.8.0 |

So a capability that only works when its command exists is broken on four harnesses.
Write the skill so it is complete on its own, then add the command as the fast path.
Never move logic out of the skill and into the command. When a plugin is the right
grouping but a target harness has no plugin support, say so in the plugin's README
rather than silently shipping something a third of the fleet cannot load.

## Common mistakes in this repo — check yourself against these first

Every one of these has actually happened here. They share a shape: the change looks
complete, nothing errors, and the thing silently does not work.

| Mistake | Why it bites | The check |
|---|---|---|
| **Hand-editing a generated file** | `rules/AGENTS.md` is composed from `rules/subrules/` + `rules.yaml`; `permissions/default.yaml` is built by `permissions/build.sh`. A hand edit is erased by the next regeneration and reads later as a mystery regression | Edit the source (`subrules/`, `groups/`), then regenerate and commit the output |
| **Dropping a hook registration in an unrelated commit** | A script with no `hooks:` entry never fires, and nothing fails — its own `_test.sh` still passes. Four scripts sat dead for months this way: `606db6e` ("fix pre-commit validator") silently removed 27 lines from `agents.yaml`, and `8b006a6` ("remove legacy hook config") removed both guards while only `rm-guard` was later restored | When a commit touches `agents.yaml`, compare the hook count before and after. `grep -r <script> agents.yaml hooks/` — the second path catches a script another hook invokes, like `verify-delivery-chain.py` |
| **Writing maintenance notes into `rules/AGENTS.md`** | That file is the *composed ruleset* synced into every agent as its memory file. A note there ships to every agent on every machine | Maintenance guidance for `rules/` goes in `rules/README.md` |
| **Putting a `README.md`/`AGENTS.md` in a resource directory on an old CLI** | Before the doc-file filter (`isDirectoryDoc` in `resources.ts`), every `.md` in `commands/` became a slash command — `commands/README.md` installed a `/README` into every agent home | `ls ~/.claude/commands/` on the target box and look for a doc name — check the installed home, not the repo |
| **Editing `~/.agents/.system/` in place** | It is a **pull-only mirror**. Local edits are overwritten by the next `agents sync system` | Change it via a worktree + PR; to override on one machine, add the same-named file under `~/.agents/` |
| **Citing a `file:line` or symbol without opening it** | A wrong pointer is worse than none — the next agent trusts it. A citation here named a `resourceDir()` that does not exist and pointed one line short of the code it described | Open the file at that line and confirm the text before committing the claim |
| **Assuming merged means live** | Merged is not published; published is not installed. A fix can be on `main` while every box still runs a binary without it | Run the *installed* artifact and confirm the behavior, not the repo state |
| **Adding a resource without its second edit** | The file exists but is invisible or dead — see the sync table above | Walk the row for that kind before opening the PR |

## Instructions for agents working in a repo travel two ways

Neither requires the person cloning the repo to configure anything, and this is how a
repo instructs an agent it has never met:

- **`AGENTS.md`, committed** (with `CLAUDE.md`/`GEMINI.md` symlinked to it) — every harness
  reads its own memory file out of the clone. This is where repo-wide policy, the
  mistakes above, and any review conventions belong.
- **`<repo>/.agents/`, committed** — a full DotAgents layer that ships in-tree:
  `.agents/commands/`, `.agents/skills/`. It resolves at **project** precedence, ahead of
  the user's own `~/.agents/` (`resolveResource` / `listResources` in
  `apps/cli/src/lib/resources.ts`), so a repo-shipped command wins over a same-named
  personal one.
- **`<repo>/.agents/rules/`, committed** — project rules, compiled into the repo's
  `AGENTS.md` (plus per-agent symlinks) by `compileRulesForProject`
  (`apps/cli/src/lib/rules/compile.ts`). No-op only when `<repo>/.agents/rules/` is
  absent, and it will not clobber an `AGENTS.md` you hand-wrote.

  It does **not** wholesale-replace the contributor's rules. `composeRules`
  (`compose.ts:173-225`) does three distinct things, and the second is the useful one:

  1. **Per-name shadowing** — the preset's named subrules resolve first-layer-wins
     (project > user > extras > system), so a project `foo.md` replaces the system's
     `foo.md`. Only same-named fragments are affected.
  2. **Auto-append** — every subrule in a **non-system** layer that the preset never
     named is appended anyway. So dropping `.agents/rules/subrules/foo.md` into a repo
     ships it to every contributor with **no `rules.yaml` edit at all**. System-layer
     subrules outside the preset are skipped (`if (layer.scope === 'system') continue`).
  3. **Order** — preset order first, then auto-appends, with the project layer's first.

  The one true wholesale override is the preset *definition*: `resolvePreset` takes the
  first layer defining that name, so a project's `default` replaces the system's subrule
  **list**, not its files.

**So the simplest way to ship repo instructions to a contributor's agent is to drop one
file**: `<repo>/.agents/rules/subrules/<topic>.md`, committed. Auto-append picks it up —
no `rules.yaml`, no preset, no setup on their side.

**Know the limit before you design around presets.** A repo *can* define presets in its
own `.agents/rules/rules.yaml`, and the `default` one is what every contributor gets. But
no production caller ever selects a different one — `sync.ts:546` and
`project-launch.ts:108` both call `compileRulesForProject(cwd)` with no `preset`. So a
`review` preset defined here would compile for nobody. Mode-specific instruction has to
live in the content every agent already reads (a labeled section in `AGENTS.md`), not
behind a preset nothing selects.

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
