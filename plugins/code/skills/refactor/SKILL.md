---
name: refactor
description: "Improve codebase structure with evidence-backed, behavior-preserving changes. Use for module boundaries, duplicated responsibilities, package extraction, public-surface cleanup, or quality mode during an existing change."
argument-hint: "[empty = this repo | <path> | quality | --scan-only | --top N | --days N | --depth N | --execute]"
allowed-tools: Bash(agents *), Bash(artifacts *), Bash(git *), Bash(gh *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Bash(sqlite3 *), Bash(bun *), Bash(wc *), Bash(sort *), Bash(uniq *), Read(*), Write(*), Edit(*), Task(*)
user-invocable: true
---

# code:refactor

Improve the structure so future changes are easier to understand and make correctly.
The result is a justified, behavior-preserving change with evidence of the improvement,
not a quota of deletions, abstractions, diagrams, or PRs.

## Scope

| `$ARGUMENTS` | Meaning |
|---|---|
| Empty | This repository; state the selected scope in a monorepo. |
| Path(s) | Only those areas and their necessary dependencies. |
| `quality` | Targeted cleanup within the current change, without a whole-repo scan. |
| `--scan-only` | Findings and proposed changes only; no implementation or tracker creation. |
| `--execute` | Execute an existing plan within its authorized scope. |
| `--top N` | Cap proposed moves; default 6, not a quota to fill. |
| `--days N`, `--depth N` | Measurement window (default 90 days) and graph granularity (default 2). |

Check current code, relevant tickets, open PRs, and active work before selecting changes.
Reuse existing work and coordinate overlapping modules. Explore without creating tickets;
claim or create tracking only when taking a selected change into execution.

## Architectural judgment

Understand the repository's intended boundaries and compare them with actual behavior.
Distinguish enforceable contracts, design intent, assumptions, and unverified claims.
A documentation error calls for a documentation correction; a behavior defect is separate
from a behavior-preserving refactor. Record incidental bugs as findings, not automatic tickets.

Consider merging duplicate responsibilities, extracting a shared layer, drawing a module
boundary, extracting a package/SDK, reorganizing a confusing tree, simplifying a public
surface, declaring a shared variant contract, or relocating architectural explanation.
Choose only moves supported by the actual maintenance problem.

Deduplicate decisions, not merely similar lines. Prefer extending an appropriate existing
home over inventing another. Extract a layer when it creates a useful boundary or unifies
one responsibility; do not force divergent variants into a provider interface. A switch
that constructs variants at one boundary can be correct. Repeated scattered dispatch may
justify a contract and registry, after examining actual variants and the repo's patterns.

Preserve useful per-symbol docs and point-of-use invariants. Move standalone architectural
narratives to an existing appropriate doc when that makes them easier to discover and
maintain; comment percentages and block lengths are discovery aids, never deletion targets.
In `quality` mode, make concrete cleanup relevant to the current change. Expand into a
structural plan only when the scope genuinely requires it.

## Evidence and visualization

Use [measurement-tools.md](measurement-tools.md) for the existing dependency graph,
agent-exposure, surface census, pattern, and comment scanners. Reuse `code:review` repo
mode for file-level diagnostics. Select relevant measurements and validate candidates
against actual code and consumers; static reachability does not prove absence of callers.
Report coverage limits and missing data rather than presenting partial scans as complete.

Make each significant structural change easy to inspect. Show current and proposed
relationships with meaningful notation, accurate labels, and clear arrow direction.
Keep unchanged elements visually comparable and distinguish observations from proposals.
Use the view that explains the decision: module dependencies, runtime flow, sequence,
or deployment boundaries. Cite the appropriate evidence rather than forcing every view
into an import graph. Numbers must agree with their source; proposals need a stated derivation.

Use `artifacts` for rendering guidance and `browser` for visual read-back and presentation
on the user's viewing device. [reference-figure.md](reference-figure.md) is an example of
module comparison, not a compulsory visual grammar. A diagram should clarify the change,
not require the reader to decode incidental LOC totals or implementation details.

The plan states the maintenance problem, goals and non-goals, selected changes, effects
on consumers, dependencies, and acceptance evidence. Rank by actual harm and exposure;
measurement scores support judgment. Proceed within authorized scope. Ask when the user's
priorities or desired outcomes determine a choice, not for every structural implementation.
`--scan-only` remains read-only even when an easy fix is found.

## Execution and proof

Use linked worktrees under `<repo>/.agents/worktrees/`; never edit the primary checkout.
Choose independently safe, reviewable increments; PR count follows the dependency and
verification boundaries. Resolve cycles and boundary dependencies before extracting a
package that would still depend on the old implementation. Sequence around active work.

Preserve observable behavior. Separate bug fixes from refactors, preserve required public
compatibility, and use a deprecation path for supported user-facing removals. Before
removing code, inspect runtime registration, generated callers, and known external consumers
as well as imports; missing static references alone are insufficient evidence.

Run the relevant canonical checks before and after the change, including original caller
paths when concepts merge. Documentation-only changes need verified claims and appropriate
checks, not a forced full suite. Recompute the relevant measurements after structural
changes and reconcile the proposed view with the actual result.

Use `code:loop` for owned delivery: independent review, required green CI, merge, and
repository-specific release/installed verification when applicable. Report the achieved
structural improvement and remaining limitations. Close tracking only with delivery proof.
