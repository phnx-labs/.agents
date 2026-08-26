# commands/ — maintenance contract

Humans start at [README.md](./README.md).

Each `.md` file here becomes one slash command named after the file. `plan.md` is `/plan`.
No manifest, no registration step: the filename **is** the command name.

## File format

```markdown
---
description: One line, imperative, shown in the command picker
---

You are doing X for: $ARGUMENTS

## The discipline
...
```

- `description` frontmatter is **required**. Without it the command has no picker entry.
- `$ARGUMENTS` is replaced with whatever the user typed after the command name. A command
  that ignores `$ARGUMENTS` silently discards the user's input — always consume it.
- Keep it to one methodology per command. If it needs scripts, reference files, or
  persistent context, it is a [skill](../skills/AGENTS.md), not a command.

## Adding or renaming a command

1. Write `commands/<name>.md` with `description` frontmatter.
2. Add a row to the table in [`README.md`](./README.md), in the right section, linked to the
   file. A command missing from the README is undiscoverable.
3. Add a `CHANGELOG.md` entry under the next version.

A rename is a delete plus an add: update the README row and check that no skill, plugin, or
rule still references the old `/name`. `grep -rn "/<oldname>"` from the repo root.

## Aliases point at the canonical definition

`/code:commit` is the canonical commit command — it lives in the `code` plugin. There is no
top-level `/commit` alias. The behavior stays in the plugin; do not fork it into any top-level
file. Top-level aliases like `/continue` → `/sessions:continue` follow the same pattern: the
thin file only routes, the behavior lives in the plugin skill.

## Namespacing

Plugin commands are namespaced `<plugin>:<command>` and live under
`plugins/<plugin>/commands/`, never here. This directory holds the unnamespaced top-level
set only.

## Do not block on the user

Commands that ask for permission before acting on their own verdict violate F1 of the
ruleset. `/code:review` merges on green; `/code:refactor` lands its reversible tier without asking; `/finish` drives the current task to delivered.
Reserve a question for genuine scope ambiguity. This has been fixed repo-wide once already —
do not reintroduce it.
