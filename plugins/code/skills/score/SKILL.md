---
name: score
description: "Score how well a codebase is structured for coding agents. Measures multi-level AGENTS.md coverage and architectural-pointer quality, flags missing or stale frontmatter, detects flat overloaded directories, god files, and deep unfocused trees, ranks the highest-value fixes, and renders a visual Markdown-to-HTML report with artifacts-cli. Read-only analysis: it never edits source, configuration, or AGENTS.md files. Triggers on: 'score this repo for agents', 'agent readiness', 'AGENTS.md coverage', 'is this codebase easy for agents', 'messy directory', 'flat lib directory'."
argument-hint: "[repo-path = cwd]"
allowed-tools: Bash(agents *), Bash(artifacts *), Bash(git *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(wc *), Bash(bun *), Bash(open *), Bash(xdg-open *), Bash(mkdir *), Read(*), Write(*), Edit(*)
user-invocable: true
---

# code:score

Evaluate how quickly a coding agent can recover the architecture of a repository and
choose the right place for a change. This is a read-only diagnostic: the only files it
writes are its Markdown, JSON, and rendered HTML outputs under the target repository's
dated `.agents/artifacts/` directory.

## Scope

Resolve `$ARGUMENTS` as a repository path; default to the current working directory.
Require a Git worktree so tracked files, ignored build products, and repository-relative
paths are unambiguous.

```bash
TARGET="${ARGUMENTS:-$PWD}"
TARGET=$(git -C "$TARGET" rev-parse --show-toplevel)
DATE=$(date +%F)
OUT="$TARGET/.agents/artifacts/$DATE"
mkdir -p "$OUT"
SKILL_DIR="$HOME/.agents/plugins/code/skills/score"
[ -d "$SKILL_DIR" ] || SKILL_DIR="$HOME/.agents/.system/plugins/code/skills/score"
```

## What the score means

The score has three explicit components. Never substitute vibes for these measurements.

1. **AGENTS.md coverage (45 points).** Every core module or library should have its own
   `AGENTS.md`, not merely inherit one from the repository root. A core directory is one
   with at least five direct source files or fifteen source files in its subtree. Ignore
   generated, vendor, dependency, fixture, and artifact directories.
2. **AGENTS.md quality (25 points).** An `AGENTS.md` is an architectural pointer: how
   modules talk, where responsibilities live, and the load-bearing invariants. It is not
   a procedural runbook. Reward architecture/location/invariant language; flag documents
   dominated by imperative steps. Require YAML frontmatter containing
   `last-updated: YYYY-MM-DD`; flag missing, invalid, or older-than-180-day dates.
3. **Directory organization (30 points).** Flag flat directories with at least 20 direct
   source files, god files at 800+ lines, and deep unfocused trees whose descendants extend
   at least four levels while the directory itself exposes many unrelated source files.
   These thresholds are signals to inspect, not automatic refactor instructions.

Run the deterministic census:

```bash
bun "$SKILL_DIR/score.ts" "$TARGET" "$OUT/code-score-data.json"
```

Read the JSON before writing conclusions. Quote its repository-relative paths and measured
counts exactly. Inspect the top offenders in source before accepting their ranked action;
drop false positives such as generated registries or deliberately flat public entry-point
directories.

## Ranked actions

Rank by impact, then evidence:

1. A core module with no local `AGENTS.md`.
2. A stale or instruction-heavy `AGENTS.md` covering a high-file-count module.
3. A flat overloaded directory, especially one that also contains god files.
4. A god file or deep unfocused tree not already covered by a higher-ranked directory move.

Every action names one directory or file, quotes its measured count, and states one
specific improvement. Do not prescribe a new module boundary without reading imports and
responsibilities; say “group by the domains already present” until that evidence exists.

## Visual report

Use the `artifacts` skill's report pipeline. Markdown remains the source of truth; never
hand-author or edit the generated HTML.

1. Check `agents artifacts --version`; if unavailable, check `artifacts --version`. If
   both are missing, run `bun add --global gh:phnx-labs/artifacts-cli`, then recheck.
2. Author `$OUT/code-score.md` with `kind: report`, a factual title, the overall score and
   three component scores in frontmatter `facts`, and these sections:
   - `## Summary` — score, scope, and the highest-priority finding.
   - `## AGENTS.md coverage` — an inline SVG tree/heatmap. Each core directory is a real
     path. Green = local pointer present and current; amber = present but stale/weak;
     red = missing. Include a text legend, so color is not the only encoding.
   - `## Directory organization` — an inline SVG horizontal bar chart of direct source
     file counts for the worst directories. Use one honest linear scale, label every bar
     with its exact count, and mark the 20-file review threshold.
   - `## Prioritized actions` — ranked, evidence-backed actions.
   - `## Method` — weights, thresholds, ignored directories, and the JSON evidence path.
3. Follow `skills/artifacts/references/authoring.md`: semantic SVG primitives, `viewBox`,
   `role="img"`, `aria-label`, accessible labels, and the repository's existing visual
   language. Do not use Mermaid, CDN libraries, or a table as the only visual.
4. Validate and render:

```bash
artifacts check "$OUT/code-score.md"
artifacts render "$OUT/code-score.md"
```

5. Inspect the HTML headlessly at desktop and mobile widths, in light and dark themes.
   Confirm both SVGs are visible, labels do not overlap, there is no horizontal page
   overflow, and the browser console is clean. Do not open the user's browser unless asked.

## Chat output

Print only the pointer plus the decision-useful summary:

```text
AGENT READINESS — <score>/100
Coverage <n>/45 · Context quality <n>/25 · Organization <n>/30

Top actions:
1. <path> — <quoted count and action>
2. <path> — <quoted count and action>
3. <path> — <quoted count and action>

Markdown: <absolute path>/code-score.md
HTML:     <absolute path>/code-score.html
```

Hard lines: never edit the target's source/configuration/AGENTS.md files; never call a
missing pointer “covered” because an ancestor has one; never call a dated file stale
without quoting its `last-updated` value; never recommend splitting a directory without
quoting its direct file count; never claim the visual is verified until it was inspected.
