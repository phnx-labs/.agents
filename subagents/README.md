# Subagents

Named sub-agent definitions. One directory per subagent, written once here and materialized
into every subagents-capable agent's home in that agent's native format.

**This directory is empty in the system layer.** Subagents are personal by nature, so they
live in your user layer at `~/.agents/subagents/<name>/`, not in the shipped defaults. The
slot exists so `agents-cli` resolves the path consistently across all four layers.

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
