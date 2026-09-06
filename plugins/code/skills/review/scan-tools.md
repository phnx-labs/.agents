# Repository scan tooling

Resolve `SKILL_DIR` to the directory containing the loaded review skill. Run helpers
from the target repository worktree: they resolve repository paths from the current
working directory. `RUN_DIR` is an absolute artifact directory under that worktree's
`.agents/artifacts/<yyyy-mm-dd>/`; keep intermediate or sensitive data in the repository's
appropriate scratch/private location.

Create `RUN_DIR/files.txt` containing repo-relative tracked paths, one per line.
Choose scope from `git ls-files -- <paths>`, the branch's three-dot diff against its base,
`HEAD~N..HEAD`, or files changed by commits in the requested `--since` window.
Create `RUN_DIR/findings/` for selected pass outputs. Helpers require Bun.

| Helper | Invocation | Candidate evidence |
|---|---|---|
| Code health | `bun "$SKILL_DIR/code-health.ts" "$RUN_DIR"` | Available compiler/linter output; missing checks recorded in `skipped.json`. |
| Invariants | `bun "$SKILL_DIR/invariants.ts" "$RUN_DIR"` | Negative assertions in nearby docs and references to the named tokens. |
| Identifiers | `bun "$SKILL_DIR/identifiers.ts" "$RUN_DIR"` | MCP names and documented CLI flags against locally available interfaces. |
| Signatures | `bun "$SKILL_DIR/signatures.ts" "$RUN_DIR"` | Similar function shapes that may duplicate a responsibility. |

Redirect each selected helper's stdout to a distinct `findings/<pass>.json`. Independent
passes can run concurrently, but check every process completion and output. A missing
runtime/tool or unsupported source area is an explicit coverage limit; do not auto-install
a suite merely for this diagnostic. The code-health helper recognizes a limited set of
project layouts: inspect its surface detection before claiming it checked another repo.

Add an architecture inspection of the scoped code and canonical patterns. An independent
agent may inspect a bounded area. Look for bypassed ownership, duplicated responsibilities,
and caller/registry gaps; report specific consequences, not arbitrary layering taste.

All findings use the shared schema (JSON array per pass):

```json
[
  {
    "category": "architecture",
    "severity": "should",
    "rule": "Specific finding",
    "file": "src/example.ts",
    "line_start": 42,
    "line_end": 45,
    "snippet": "Verbatim evidence",
    "anchor_file": null,
    "anchor_line": null,
    "anchor_snippet": null,
    "fix_one_line": "Concrete proposed fix",
    "tool": "architecture-review"
  }
]
```

Categories: `architecture`, `code-health`, `context`, `patterns`. Severities:
`blocker`, `should`, `nice`; in repo mode these rank findings, not merge decisions.
`category`, `severity`, `rule`, `file`, `line_start`, and `tool` are required.
Validate candidates and correct severity before publishing. A scanner assigning
`blocker` does not establish a defect by itself. Populate anchor fields when comparing
to a real canonical implementation.

```bash
bun "$SKILL_DIR/aggregate.ts" "$RUN_DIR/findings" > "$RUN_DIR/findings.json"
bun "$SKILL_DIR/render.ts" "$RUN_DIR/findings.json" "$RUN_DIR" > "$RUN_DIR/index.html"
```

The aggregator deduplicates `(category, file, line_start, rule)` and sorts by severity and location.
The renderer produces self-contained HTML with filters, evidence cards, and clipboard
exports. Clipboard task/Linear commands are drafts only. Inspect the HTML and deliver it
through the configured browser on the user's viewing device; local `open` on a worker
is not delivery. Refer to the `artifacts` and `browser` skills for those mechanics.
