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

`/commit` is a thin alias of the `code` plugin's `/code:commit`. The behavior lives in the
plugin; the alias file only routes to it. Do not fork the logic into the alias — change the
plugin skill and let the alias follow.

## Namespacing

Plugin commands are namespaced `<plugin>:<command>` and live under
`plugins/<plugin>/commands/`, never here. This directory holds the unnamespaced top-level
set only.

## Do not gate on the user

Commands that ask for permission before acting on their own verdict violate F1 of the
ruleset. `/code:review` merges on green; `/clean` executes its cleanup; `/finish` drives to done.
Reserve a question for genuine scope ambiguity. This has been fixed repo-wide once already —
do not reintroduce it.
