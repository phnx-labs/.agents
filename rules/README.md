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
script, a `hooks.yaml` registering the guard, and a test. `gh-merge-guard`, `no-pr-footer`,
`plan-presentation`, and `truly-agentic-git-workflow` work this way.

## What the system layer ships

`foundations` renders first — the five principles (F1–F5) every other rule references by
name instead of restating. Then, in order: `research-discipline`, `fleet-delegation`,
`code-quality`, `testing-strict`, `truly-agentic-git-workflow`, `gh-merge-guard`,
`no-pr-footer`, `operational`, `conventions`, `agents-cli`, `parallel-teams`, `tech-stack`,
`plan-presentation`, `task-checklists`, `feed-status-posts`,
`remote-fleet-dispatch`.

Your own machine composes more than this — anything in `~/.agents/rules/subrules/` unions in
on top.

## Changing a rule

1. Edit `subrules/<name>.md`, or add a new one.
2. Add the name to the `default` preset in [`rules.yaml`](./rules.yaml) — **order matters**,
   it is the render order. A subrule not listed in a preset never renders.
3. Regenerate `AGENTS.md` and commit the regenerated file. Agents without native `@imports`
   get this compiled copy at sync time.
4. Add a `CHANGELOG.md` entry.

Rules to follow when writing one:

- **State each thing once.** `core-hard-lines` and `workflow-proactive` were removed for
  restating the same seven themes (one of them written eight separate times), which trains
  skimming and buries the load-bearing rule. Cite `F1`–`F5` instead of re-deriving them.
- **Ground it.** A rule earns its place with the concrete failure it prevents, quoted. Cost
  in hours, a verbatim bad output, a real incident.
- **A rule with a guard hook ships the guard, its `hooks.yaml`, and its test together.** A
  rule that only asks nicely is a suggestion.
- **Every line costs context on every agent, on every machine, forever.** Deleting a
  redundant paragraph is as valuable as adding a rule.

## Overriding on your machine

Put a same-named file in `~/.agents/rules/subrules/<name>.md` and it replaces the system one
wholesale. A new name unions in. This repo is a pull-only mirror — never edit it in place.
