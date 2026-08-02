---
name: quality
description: "Read-only code-health diagnostic. Four orthogonal categories — architecture & design (inline-auth-where-middleware-exists style anti-patterns, via Sonnet subagent), code health (`go vet`, `tsc --noEmit`, `staticcheck`, `biome`, `shellcheck` — only when on PATH; never installs), context quality (doc-asserted invariants, identifier cross-reference against live MCP/env/SQL/YAML/CLI universe), and patterns (parallel implementations clustered by behavioral signature, NOT token grep). Emits a self-contained HTML report opened in the browser with per-finding clipboard actions (copy as `/code:loop` task, copy Linear ticket cmd, copy `file:line`). Read-only — never modifies code; never blocks merges. Triggers on: 'quality', 'health check', 'code health', 'audit drift', 'doc drift', 'what's wrong with this branch', 'parallel implementations'."
argument-hint: "[empty | --commits N | --since <date> | --branch | #PR | <path>]"
allowed-tools: Bash(git diff*), Bash(git log*), Bash(git show*), Bash(git rev-parse*), Bash(git ls-files*), Bash(rg*), Bash(fd*), Bash(ls*), Bash(wc*), Bash(jq*), Bash(go vet*), Bash(tsc*), Bash(staticcheck*), Bash(gocyclo*), Bash(biome*), Bash(shellcheck*), Bash(mcporter*), Bash(printenv*), Bash(sqlite3*), Bash(bun*), Bash(./*/scripts/sandbox.sh*), Bash(open*), Bash(xdg-open*), Bash(mkdir*), Bash(rush *), Read(*), Write(*), Edit(*), Agent(*)
user-invocable: true
---

# code:quality

> A read-only diagnostic across four orthogonal axes. Emits an HTML report opened in the browser. Never fixes anything — fixes flow back through `/code:loop` (one finding = one queue item) or a direct `/commit` for trivial cases.

## When to invoke

- After landing a multi-commit branch and before opening a PR.
- On a fresh checkout of an unfamiliar surface.
- As a recurring sanity check on the default branch to surface drift.
- When the user asks "what's wrong with this branch" or "any parallel implementations of X?"

Skip when:
- You only want to gate a merge — that's `/code:verify`.
- You want to review a specific PR cold — that's `/code:review`.
- You want security analysis — that's `/audit`.

## Scope resolution (Phase 1)

`$ARGUMENTS` parses into one of:

| Pattern | Mode | Diff base |
|---|---|---|
| empty | last-commit | `HEAD~1..HEAD` |
| `--commits N` | last-N | `HEAD~N..HEAD` |
| `--since "<date>"` | since-window | commits since `<date>` |
| `--branch` | branch | `origin/$BASE...HEAD` |
| `#N` or `N` (PR) | pr | `origin/<base>...origin/<head>` |
| `<path>` (one or more dirs/files) | corpus | every file under each path — no diff filter |

The default is **last-commit**. Corpus mode is the only one that ignores the diff filter — it audits every file in the path, useful for a fresh-eyes pass on an unfamiliar surface.

After parsing, set:

```bash
RUN_TS=$(date -u +"%Y-%m-%dT%H-%M-%S")
RUN_DIR="$(git rev-parse --show-toplevel)/.agents/artifacts/$RUN_TS-quality"
mkdir -p "$RUN_DIR/findings"
SKILL_DIR="$(git rev-parse --show-toplevel)/.agents/plugins/code/skills/quality"
```

Note on the directory shape:
- `.agents/artifacts/` is the shared home for finished output products from any skill (HTML reports, generated docs, exports). It is tracked in git — committed runs serve as a history of what was found and when.
- Naming is `<TS>-<skill>` (timestamp first) so `ls -t` and lexical sort BOTH give chronological order, regardless of which skill produced the artifact. With multiple skills writing here (audit, review, quality), this interleaves them by time.
- Don't use `.agents/scratches/` for `/quality` output. Scratches is reserved for mid-process throwaway work (mirror clones, intermediate logs, spec files) and IS gitignored.

Then materialize the changed-file list:

```bash
# diff mode
git diff --name-only "$DIFF_BASE" > "$RUN_DIR/files.txt"
# corpus mode
git ls-files -- "${PATHS[@]}" > "$RUN_DIR/files.txt"
```

## Findings JSON schema

Every pass emits a JSON array of findings. The aggregator merges; the renderer reads.

```json
{
  "category": "architecture" | "code-health" | "context" | "patterns",
  "severity": "blocker" | "should" | "nice",
  "rule": "short one-line description (e.g. 'inline auth bypasses middleware')",
  "file": "relative/path/from/repo/root.ts",
  "line_start": 240,
  "line_end": 244,
  "snippet": "<5-15 lines verbatim of offending code>",
  "anchor_file": "relative/path/to/canonical.ts" | null,
  "anchor_line": 18 | null,
  "anchor_snippet": "<5-15 lines verbatim>" | null,
  "fix_one_line": "wrap handler in requireAuth()",
  "tool": "architecture-subagent" | "go-vet" | "tsc" | "invariants" | "identifiers" | "signatures" | "..."
}
```

Mandatory fields: `category`, `severity`, `rule`, `file`, `line_start`, `tool`. Anchor fields are non-null only when the finding has a canonical counterpart (architecture and patterns categories typically do; lint output usually doesn't).

## Phase 2 — Run inspections in parallel

Six independent passes run concurrently. Five are pure bash; one is a single Sonnet subagent. They write to `$RUN_DIR/findings/<pass>.json` independently — no shared state, no ordering.

### B. Code Health

```bash
bun "$SKILL_DIR/code-health.ts" "$RUN_DIR" > "$RUN_DIR/findings/code-health.json" &
```

The script iterates surfaces in `files.txt`, runs whichever of `go vet`, `tsc --noEmit`, `staticcheck`, `gocyclo -over 20`, `biome check`, `shellcheck` are on PATH for that surface, and emits findings from each tool's output. Tools missing from PATH are recorded in `$RUN_DIR/skipped.json` so the HTML footer can show what didn't run.

### C1. Invariants

```bash
bun "$SKILL_DIR/invariants.ts" "$RUN_DIR" > "$RUN_DIR/findings/invariants.json" &
```

Parses every `CLAUDE.md` / `AGENTS.md` / `README.md` in or near the changed files for negative-assertion patterns (`X is gone`, `there is no X`, `never use X`, `do NOT use X`), extracts the asserted-absent token, re-greps the codebase. Any hit = BLOCKER.

### C2. Identifiers

```bash
bun "$SKILL_DIR/identifiers.ts" "$RUN_DIR" > "$RUN_DIR/findings/identifiers.json" &
```

Cross-references identifier classes against live sources of truth — `mcp__*` tool names against `mcporter list`, env vars in shell/docs against `printenv` and `agents secrets ls`, CLI flags in markdown code fences against `<binary> --help`. A reference with no live counterpart = BLOCKER.

### D. Patterns (behavioral signatures)

```bash
bun "$SKILL_DIR/signatures.ts" "$RUN_DIR" > "$RUN_DIR/findings/signatures.json" &
```

For each new top-level function added in the diff, computes a small shape signature — `(input types, output types, primary side-effect class)` — and clusters against an index of existing functions in the affected surfaces. Clusters of 2+ functions across 2+ files in different modules = SHOULD finding. The signature ignores names, so `slugify` and `kebabCase` cluster when they should; same-name divergent-contract families like `sanitize*` don't all cluster.

### A. Architecture (Sonnet subagent)

```
Agent(
  description: "Architecture pass for /quality",
  subagent_type: "claude",
  model: "sonnet",
  prompt: <fill the brief below>
)
```

The brief (drop verbatim, fill `{{ }}` slots):

```
You are auditing changes for STRUCTURAL anti-patterns. You are NOT a linter,
NOT a security reviewer. Find places where the change inlines logic that a
canonical layer already owns.

CHANGED SURFACES: {{ comma-separated list }}
SURFACE CONVENTIONS: read each surface's CLAUDE.md and AGENTS.md
CANONICAL ANCHORS for each surface (extracted from rg):
{{ list — e.g. prix/api/src/middleware/auth.ts:18, prix/api/src/router.ts:12 }}

DIFF (against {{ base }}):
{{ paste git diff --stat + git diff }}

YOUR JOB
For each new file or significantly-changed file, look for these structural
anti-patterns:
- Inline auth/authz where a middleware/decorator exists.
- Inline validation where a validator module exists.
- Direct DB / HTTP / FS calls in handlers where a repository/service layer exists.
- Inline state mutation where a store/reducer exists.
- New route registered without using the surface's registration factory.
- Configuration read ad-hoc instead of through the surface's config loader.
- New abstraction added that duplicates an existing canonical one in THIS surface.
- if/switch chains for dispatch where a registry/map pattern is canonical.

For each finding, return ONE JSON object on its own line (JSONL format):
{"category":"architecture","severity":"blocker"|"should"|"nice","rule":"<one line>","file":"<rel path>","line_start":<n>,"line_end":<n>,"snippet":"<5-15 lines verbatim>","anchor_file":"<rel path or null>","anchor_line":<n or null>,"anchor_snippet":"<5-15 lines verbatim or null>","fix_one_line":"<one line>","tool":"architecture-subagent"}

NON-FINDINGS — do NOT emit:
- Style nits (formatting, naming preferences without concrete confusion).
- Hypothetical futures ("what if we later need X?").
- Suggestions to add an abstraction "for flexibility" when none exists yet.
- Test coverage of trivial guards.
- Anything you can't tie to a canonical anchor in THIS surface.

Output: JSONL to stdout (one JSON object per line). Empty output = no findings.

Return file:line quotes for every claim. Do NOT paraphrase. If you can't
quote it, don't claim it.
```

The orchestrator captures the subagent's stdout, converts JSONL → JSON array, writes to `$RUN_DIR/findings/architecture.json`.

### Awaiting completion

```bash
wait
```

All five bash passes run concurrently; the architecture subagent runs concurrently with them. Total wall-clock is gated by the slowest pass (usually architecture).

## Phase 3 — Aggregate

```bash
bun "$SKILL_DIR/aggregate.ts" "$RUN_DIR/findings" > "$RUN_DIR/findings.json"
```

The aggregator merges all per-pass JSON, sorts by `severity` (blocker > should > nice) then `file` then `line_start`, and dedupes findings that share `(file, line_start, rule)`.

## Phase 4 — Render & open

```bash
bun "$SKILL_DIR/render.ts" "$RUN_DIR/findings.json" "$RUN_DIR" > "$RUN_DIR/index.html"

case "$OSTYPE" in
  darwin*) open "$RUN_DIR/index.html" ;;
  linux*)  xdg-open "$RUN_DIR/index.html" ;;
  *)       echo "report at: $RUN_DIR/index.html" ;;
esac
```

The HTML is single-file, self-contained (inline CSS + JS), no external deps. Page features:

- Sticky header: scope, run timestamp, totals badges, copy-pastable rerun command.
- Filter chips: severity (BLOCKER / SHOULD / NICE), category (architecture / code-health / context / patterns), surface — all multi-select, instant client-side filter.
- Each finding is a collapsible card showing: rule, severity badge, `file:line` (clickable `vscode://file/...` link), quoted code snippet with line numbers, anchor (when present) with quoted code, one-line fix.
- Per-finding action row:
  - **Copy as /loop task** → clipboard a ready-made `/code:loop "Fix <rule> at <file:line>. Pattern: <anchor>. Approach: <fix>"`.
  - **Copy Linear ticket cmd** → clipboard a `linear issue create --title "<rule>" --description "..."`.
  - **Copy file:line** → clipboard the path for terminal jumping.
- Multi-select checkboxes + "Create task batch" at the top — clipboard a single brief enumerating all selected findings.
- Footer: explicitly skipped checks with one-line rationale, and the list of tools that were missing from PATH this run.

Scale-handling:
- 0–20 findings: all cards open by default.
- 21–100: only BLOCKERs open by default; SHOULD/NICE collapsed.
- 100+: all collapsed by default + a top "Show all" toggle.

## Phase 5 — Chat output

```
QUALITY REPORT — scope: <mode> (<commit-or-range>)
Surfaces: <comma-separated>

  Category                Block  Should  Nice
  ─────────────────────  ─────  ──────  ────
  Architecture & Design      <n>     <n>   <n>
  Code Health                <n>     <n>   <n>
  Context Quality            <n>     <n>   <n>
  Patterns                   <n>     <n>   <n>

Top 3 blockers:
  1. <CAT>  <file>:<line>   ← <rule>
  2. ...
  3. ...

→ Full report: file://<absolute path to index.html> (opened in browser)
→ Rerun:       /quality <same args>
```

Chat output is the pointer — totals table, three worst BLOCKERs, file:// URL. Nothing more. The rest lives in the browser.

## Severity rules (consistent across categories)

- **BLOCKER**: a real bug, a violated doc-asserted invariant, a hallucinated identifier, an inline structural anti-pattern that contradicts a canonical layer in the same surface, a compiler / type-checker error.
- **SHOULD**: contradicts a stated convention; parallel implementation candidate; tool warning.
- **NICE**: tool info-level output; minor style mismatch the surface's own CLAUDE.md endorses.

When in doubt, drop the finding entirely. Noise erodes adoption faster than missed findings.

## Don'ts

- Don't auto-install Tier 2 tools (`staticcheck`, `gocyclo`, `biome`). If they're not on PATH, the sub-pass is skipped and noted in the HTML footer. Per F1, never prompt the user to install — act with what's available.
- Don't fan out via `agents teams`. This skill is a sub-90-second diagnostic; teams are for multi-surface implementation work.
- Don't include Halstead / Maintainability Index / function-line thresholds. The skipped-checks footer lists these and why.
- Don't gate merges or return non-zero exit. `/code:verify` is the merge gate; `/quality` is a read-only diagnostic.
- Don't modify code. The HTML report's "Copy as /loop task" buttons are how fixes flow — through `/code:loop` or `/commit`, not through this skill.
- Don't write to `/tmp`. Output products land in `<repo>/.agents/artifacts/<ts>-quality/` (timestamp first, tracked in git); mid-process scratch goes in `<repo>/.agents/scratches/` (gitignored).
- Don't include the architecture-subagent's prompt in any other category's reasoning. Each pass is independent.
