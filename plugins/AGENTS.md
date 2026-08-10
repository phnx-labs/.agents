# plugins/ — maintenance contract

Humans start at [README.md](./README.md).

A plugin is a namespaced bundle of commands and skills. The directory name is the namespace:
`plugins/code/commands/loop.md` is `/code:loop`.

## Three places must agree

A plugin directory alone does not ship. All three of these must list it, or it is installed
but invisible, or advertised but missing:

1. `plugins/<name>/` on disk, with `commands/` and (usually) `skills/`.
2. `plugins/<name>/.claude-plugin/plugin.json` — the plugin's own manifest. Every plugin here
   has one; a new plugin without one does not load.
3. [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) — the repo-level
   registry, with `name`, `source: ./plugins/<name>`, and a `description`.

All plugins currently agree across the three (count them when you add one). Keep it
that way: verify with `claude plugin validate . --strict` after touching either
manifest.

Then add a row to the table in [`README.md`](./README.md) and a `CHANGELOG.md` entry.

## Layout

```
plugins/<name>/
  README.md                      # required — what it is, and every command
  .claude-plugin/plugin.json     # required — the plugin manifest
  commands/<command>.md          # becomes /<name>:<command>
  skills/<skill>/SKILL.md        # skills the commands load
  agents/<subagent>.md           # a subagent the plugin's skills spawn
```

A plugin command follows the same rules as a top-level
[command](../commands/AGENTS.md): `description` frontmatter, `$ARGUMENTS` consumed. A plugin
skill follows [`skills/AGENTS.md`](../skills/AGENTS.md).

## Packaged subagents

A plugin ships a subagent as a **flat** `agents/<name>.md` — one file, `name:` +
`description:` frontmatter (`model:` and `color:` optional), discovered by
`discoverPluginAgentDefs` in `apps/cli/src/lib/plugins.ts`. That is a different layout
from the top-level [`subagents/`](../subagents/README.md) layer, which is a directory per
subagent; do not copy one shape into the other.

Ship one only when a skill in this plugin spawns it — a subagent nobody invokes is dead
weight in every install. Name it for the role, spawn it by that name from the skill, and
keep the standing rubric in the subagent so the skill's brief carries only per-run
context. The name collides with a same-named user-layer `~/.agents/subagents/<name>/`,
and the user layer wins, so a packaged subagent supersedes rather than merges: say so in
the plugin README and the CHANGELOG entry.

## The canonical definition lives in the plugin

`/code:commit` is the canonical commit command. There is no top-level `/commit` alias —
the behavior lives in the plugin skill exclusively. When you change it, change the plugin
skill and let any thin top-level aliases follow. Never fork logic into an alias.

## What belongs here vs in extras

This repo ships plugins that are lightweight and need no paid key: they must work on a fresh
install, on any OS, with nothing configured. A plugin that needs an API key, a heavy runtime,
or a paid service belongs in the opt-in `.agents-extras` bundle. Adding a key-gated
dependency to a plugin here breaks the default install for everyone.

## Renaming a plugin or command

The namespace is in the path, the manifest, the marketplace entry, the README table, and
every reference from rules and other skills. `grep -rn "<oldname>:" ` from the repo root
before you call a rename done — a stale `/code:dispatch`-style reference routes to nothing,
which is how the last removal left dangling links in three skills.
