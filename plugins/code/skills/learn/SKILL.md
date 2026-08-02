---
name: learn
description: "Reflect on a coding-workflow session and improve the code plugin. Layers code-specific routing on the general `learn` engine — which code:* skill a lesson belongs to, when a missing verb justifies a new skill, and how to edit composing skills without breaking their contracts. Triggers on: 'learn from this coding session', 'improve the code plugin', 'update code:loop/verify/ship', 'what should the engineering loop have done'."
argument-hint: "[empty = current session | session-id | topic]"
allowed-tools: Bash(agents *), Bash(git *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Read(*), Write(*), Edit(*), Task(*)
user-invocable: true
---

# code:learn

Reflect on an engineering session and fold what you learned back into the `code` plugin — without overfitting or breaking what works.

**Read the `learn` skill first.** It is the engine: recall (grounded) → distill → four gates (generalization, recurrence, root cause, durability) → route → edit without downgrading → verify → ship. This skill does not repeat that. It adds the part that's specific to coding workflows: **where a coding lesson belongs.**

## The code plugin, as a map for routing

The plugin is the engineering loop, decomposed into verbs. A lesson about *how to do one of these better* belongs in that verb's skill:

| The lesson is about… | Skill |
|---|---|
| Draining a queue, conflict-graph parallelism, rebasing, what "done" means | `code:loop` |
| Scoping a single task, picking inline / agent / venue | `code:dispatch` |
| Proving end-to-end, which canonical test per changed surface | `code:verify` |
| Pre-merge review, security pass, merge verdict | `code:review` |
| Publishing / activating / confirming-live a distributable | `code:ship` |
| Time-boxed multi-track parallel push | `code:sprint` |
| Read-only code-health diagnostics | `code:quality` |
| Splitting a working tree into logical commits | `code:commit` |

## Routing calls that aren't a code:* skill

- **A tool gotcha** you hit while coding — a CLI, an editor, git behavior — belongs in *that tool's* skill (`computer`, `browser`, the `git` plugin), not stuffed into a `code:*` skill. Coding sessions surface tool lessons constantly; resist filing them under `code`.
- **A hard engineering principle** ("done means end-to-end", "no unverified claims") is a rule, not a skill — `rules/subrules/foundations.md` and its siblings. Skills are procedures; rules are constraints.
- **A new code:* skill** is justified only when a genuinely missing *verb* in the loop is the lesson — the way `code:ship` filled the gap after `merge`. A one-off, or a refinement to an existing verb, is a section edit, not a new skill. Apply the engine's bar: name the future situations first.

## Don't break the contracts

The `code:*` skills compose: `code:loop` calls `code:dispatch`, `code:verify`, `code:review`, `code:ship` by name (see `loop/SKILL.md` "Tools you compose"). So an edit to one verb's *contract* — what `code:verify` returns, what `code:ship` checks before it calls something shipped — can ripple to its callers. Before you change a skill's promised output or gate, grep the other `code:*` skills for references to it and keep the contract intact (or update every caller in the same scoped change). Additive sections are safe; contract changes are not — treat them like an API change.

The rest — the gates, the rejects-list, non-regression discipline, verify-then-ship — is the `learn` engine. Follow it.
