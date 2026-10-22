# Rules

The standing instructions every agent gets as its memory file. This is the one directory in
this repo whose content is injected into **every agent's context on every machine** — the
highest-leverage and highest-cost thing here.

Layered with `~/.agents/rules/`: a same-named subrule in your user repo wins, new names union
in.

## Read this first if you are an agent editing this directory

> **`rules/AGENTS.md` is not a maintenance file.** It is the *composed ruleset* — the
> generated output that syncs into each agent as `CLAUDE.md`, `GEMINI.md`, `AGENTS.md`, or
> `.cursorrules`. `CLAUDE.md` and `GEMINI.md` here are symlinks to it.
>
> Every other directory in this repo keeps its maintenance contract in its own `AGENTS.md`.
> This one cannot: a maintenance note written into `rules/AGENTS.md` would be injected into
> every agent's prompt on the fleet. So the contract lives here in the README instead.

## Layout

| Path | What it is |
|---|---|
| [`rules.yaml`](./rules.yaml) | Declares the `default` preset and which subrules it includes, in render order |
| [`subrules/`](./subrules/) | The rule fragments — one file (or one directory, when the rule ships a guard hook) per rule |
| `AGENTS.md` | **Generated.** The composed ruleset. `CLAUDE.md` and `GEMINI.md` symlink to it |

A subrule that enforces itself is a directory, not a file: it holds `rule.md`, its guard
script, a `hooks.yaml` registering the guard, and a test. `gh-merge-guard`,
`parallel-teams`, `plan-presentation`, and `truly-agentic-git-workflow` work this way.

**Shadowing a directory-form subrule drops its guards.** A same-named flat file in a
higher layer wins the name, and `collectSubruleHooks` only folds hooks from the winning
copy, so the guard silently stops registering. To override the prose of a guard-bearing
rule, copy the whole directory (or leave the prose alone and let the system copy win).

## What the system layer ships

`foundations` renders first — the five principles (F1–F5) every other rule references by
name instead of restating. Then, in order: `research-discipline` (evidence),
`code-quality` (code, tests, skill restraint), `truly-agentic-git-workflow` (worktrees,
PRs, no footers), `gh-merge-guard`, `operational` (environment, credentials, owning tools,
output locations), `conventions` (existing work, tracker, checklists), `parallel-teams`
(delegation, remote dispatch, unattended verification), `feed-status-posts`,
`ui-work-discipline`, `plan-presentation`. The last is a thin route to the canonical
`swarm:plan` skill and carries its existing presentation guards, not a second
planning contract. Eleven subrules; a new rule is
almost always a sentence in one of these, not a twelfth file.

Your own machine composes more than this — anything in `~/.agents/rules/subrules/` unions in
on top.

## Changing a rule

1. Edit `subrules/<name>.md`, or add a new one.
2. Add the name to the `default` preset in [`rules.yaml`](./rules.yaml) — **order matters**,
   it is the render order. A subrule not listed in a preset never renders.
3. Regenerate `AGENTS.md` and commit the regenerated file: the fragments in preset order,
   trailing whitespace trimmed, joined by one blank line (what `composeRules` does at sync).
   Agents without native `@imports` get this compiled copy at sync time.
4. Add a `CHANGELOG.md` entry.

Rules to follow when writing one:

- **State each thing once.** `core-hard-lines` and `workflow-proactive` were removed for
  restating the same seven themes (one of them written eight separate times), which trains
  skimming and buries the load-bearing rule. Cite `F1`–`F5` instead of re-deriving them.
- **Ground the change.** Record motivating evidence in the PR. Keep the standing rule
  focused on the outcome and boundary, without repeating incident histories.
- **A rule with a guard hook ships the guard, its `hooks.yaml`, and its test together.** A
  rule that only asks nicely is a suggestion.
- **Every line costs context on every agent, on every machine, forever.** Deleting a
  redundant paragraph is as valuable as adding a rule.

## Overriding on your machine

Put a same-named file in `~/.agents/rules/subrules/<name>.md` and it replaces the system one
wholesale. A new name unions in. This repo is a pull-only mirror — never edit it in place.

**Never put a `rules.yaml` in `~/.agents/rules/`.** The preset comes from the first layer
whose `rules.yaml` defines it, user before system, so a user `rules.yaml` replaces this
preset wholesale: `subrules: []` there drops every system rule and leaves only your own
subrules (yosemite-m6 and mark-1 ran on Mission and Stack alone until 2026-10-22). Old
copies of system subrule names in `~/.agents/rules/subrules/` likewise shadow the current
ones.

## Checking what each machine loads

[`rules-check.sh`](./rules-check.sh) composes the user and system layers the way
`composeRules` does and compares the result with the rules file (agents-cli's
`capabilities.rules.file` under the agent's config dir) of every installed version on the
machine, without `agents sync`. It also names a version file that is a symlink and every
account copy that is a frozen file rather than a link to a version. It does not model extra
repos or a per-version `rulesPreset`; when `agents.yaml` sets either, it says so and `--apply`
rewrites nothing. `--apply` sets aside an untracked user `rules.yaml`, fast-forwards
`~/.agents` and `~/.agents/.system` when they are clean, and rewrites each version file that
differs. Across the fleet (`bash -s -- --apply` to repair):

```bash
for d in $(agents devices list --json | jq -r '.[].name'); do agents ssh "$d" 'bash -s' < rules/rules-check.sh; done
```
