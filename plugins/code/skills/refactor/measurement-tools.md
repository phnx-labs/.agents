# Refactor measurement tooling

Resolve `SKILL_DIR` to this loaded skill directory. Run helpers from the target repository
worktree with Bun; they discover the repository from the current working directory.
Use an absolute `RUN_DIR` under `.agents/artifacts/<yyyy-mm-dd>/` in that worktree.
`SCOPE` is repo-relative; `DEPTH` defaults to 2 and `DAYS` to 90.

| Helper | Invocation | Output |
|---|---|---|
| Module graph | `bun "$SKILL_DIR/modules.ts" "$RUN_DIR" --scope "$SCOPE" --depth "$DEPTH"` | Modules, import edges, cycles, candidate boundaries/extractions, coverage caveats. |
| Exposure | `bun "$SKILL_DIR/exposure.ts" "$RUN_DIR" --scope "$SCOPE" --days "$DAYS"` | Churn, size, agent reads/edits when the session index is available. |
| Surface | `bun "$SKILL_DIR/surface.ts" "$RUN_DIR" --cli "$BIN"` | A bounded walk of the repository's installed CLI help. |
| Export surface | `bun "$SKILL_DIR/surface.ts" "$RUN_DIR" --exports` | Alternative when there is no CLI. |
| Patterns | `bun "$SKILL_DIR/patterns.ts" "$RUN_DIR" --scope "$SCOPE"` | Discriminator families, contracts/registries, repeated arms, capability-hole candidates. |
| Comments | `bun "$SKILL_DIR/comments.ts" "$RUN_DIR" --scope "$SCOPE" --depth "$DEPTH"` | Per-module comment composition and possible standalone narratives. |

Save selected outputs separately (`modules.json`, `exposure.json`, `surface.json`,
`patterns.json`, `comments.json`). Check each process and inspect coverage metadata.
Use `code:review` repo mode for existing file-level scanners instead of duplicating them.

Interpretation limits matter:

- Graph grouping follows path granularity; inferred layering may follow names. Inspect
  `meta.caveats`, unparsed files, and graph coverage before making architectural claims.
- Exposure reports `meta.degraded` when its session index is absent. Its score combines
  reads, edits, churn, and size; report inputs rather than treating the score as objective cost.
- A truncated help walk is partial coverage. An undocumented/unreferenced entry is an
  orphan candidate, not evidence that removing a public interface preserves compatibility.
- Pattern families can conflate different concepts using the same variable name. Inspect
  `arms_by_area` and `area_concentration`. Decide whether the variants actually share a
  contract; `same_contract: null` is deliberately unresolved by the scanner.
- A registry-construction switch may be legitimate. Existing contracts/registries bypassed
  elsewhere suggest a different fix from a missing abstraction.
- Comment ratios and essay sizes locate material for inspection. Keep per-symbol docs,
  point-of-use rationale, security invariants, and explanations whose best home is the code.

Use `claims.json` when a structured record helps: `{id, claim, source_file, source_line,
kind, check, result}`. Separate intended architecture from verified invariants; mark
unverifiable claims honestly. A ranking may use harm × exposure, but state assumptions
and select changes by the actual maintenance problem.

For a module comparison, source current nodes/edges/counts from `modules.json` and label
proposed changes as derived. Other diagrams need the evidence for their own semantics,
not fabricated import edges. See [reference-figure.md](reference-figure.md) for a module
comparison example; use the `artifacts` skill for current renderer mechanics.

After implementation, recompute the affected measures and compare them with the planned
change. A `scorecard.json` may record the scope, commit, date, relevant graph/surface/
exposure counts, and limitations. Preserve comparable inputs when showing trends;
report actual improvement rather than requiring every metric to decrease.
