# Subagents

Named sub-agent definitions. One directory per subagent, written once here and materialized
into every subagents-capable agent's home in that agent's native format.

Most subagents are personal and belong in your user layer at `~/.agents/subagents/<name>/`,
not in the shipped defaults. The bar for shipping one here is that it is genuinely universal
across repos and harnesses.

## What ships here

| Subagent | Use when |
| --- | --- |
| [`code-reviewer`](./code-reviewer/AGENT.md) | A diff, branch, or PR needs an independent verdict. Adversarial twice over: it hunts the input that breaks the change, then tries to kill each of its own candidate findings (guard elsewhere / unreachable / sanctioned by the repo) and reports only survivors plus a count of what it filtered. Reads the ticket or plan for the requirement first, bounds what it reports to the diff and what the diff broke, and never edits, pushes, or merges. `code:review` spawns it by name. |

**Why this one is not packaged inside the `code` plugin.** A plugin's `agents/<name>.md` is
the Claude plugin format: `agents-cli` copies the plugin dir into each harness home, but only
a harness that parses plugin agent definitions registers it. The **native** subagent path each
harness actually reads (`~/.claude/agents/`, `~/.grok/agents/`, `~/.kimi-code/agents/`,
`~/.factory/droids/`, `~/.cursor/agents/`, …) is written from **this** directory via
`SUBAGENT_TARGETS`. Measured 2026-08-09 on yosemite-m1: with the plugin installed and its
`agents/code-reviewer.md` present on disk, every one of those native paths was empty. A
subagent that must work on Codex, Grok, Kimi, Cursor, and Droid lives here, not in a plugin.

## Adding one

Create `~/.agents/subagents/<name>/`, then sync:

```bash
agents sync claude@all      # materialize into every installed Claude
agents inspect user --subagents
```

## How it lands in each agent

One central definition, many native formats. `agents-cli` handles the translation from a
single registry entry (`SUBAGENT_TARGETS` in `apps/cli/src/lib/subagents-registry.ts`), so
support is uniform rather than per-agent special cases:

| Layout | Agents |
|---|---|
| One flat `<name><ext>` file | claude, codex, grok, droid, opencode, copilot, cursor, kiro, goose |
| A `<name>/` directory with one generated file | antigravity (`<name>/agent.md`) |
| The whole source directory copied, with renames | openclaw |
| Bespoke — two files plus a managed parent index | kimi |

If you add a subagent to the **system** layer, it ships to everyone. That is the bar: it must
be genuinely universal, and it needs a row in this README plus a `CHANGELOG.md` entry. When
in doubt, keep it in your user layer.
