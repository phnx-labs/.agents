---
description: Restructure a codebase the way a principal engineer does — merge redundant concepts, extract shared layers, draw module boundaries, lift a core out into its own package, reorganize the tree, shrink an overgrown surface. Evidence-first, with before/after architecture figures, landed as behavior-preserving PRs.
---

Invoke the `code:refactor` skill. Arguments: $ARGUMENTS

- Empty: this repo (its dominant package in a monorepo — the skill says which it picked).
- A path (or several): scope the work to those directories.
- `--scan-only`: produce the plan and figures, open no PRs. `--execute`: land an already-approved plan.
- `--top N` (default 6) caps the moves; `--days N` (default 90) sets the churn/agent-traffic window; `--depth N` (default 2) sets module granularity for the dependency graph.

What it does: builds a module dependency graph (god modules, cycles, package-extraction candidates, upward imports), measures which files agents actually read and edit from the fleet session index, censuses the public surface, and reads the repo's docs as claims it then verifies against the code. It ranks six architectural moves — merge redundant concepts, extract the horizontal layer, draw the module boundary, lift a package/SDK out, reorganize the tree, shrink the surface — by `harm x exposure`, sequences them in dependency order (cycles first, tree moves last), and renders before/after architecture figures with `artifacts` where every box and arrow is sourced from the graph JSON. Reversible fixes land without asking; the structural moves are presented for the pick, then landed as behavior-preserving PRs.

Hygiene (dead code, doc drift, oversized files) is the byproduct tier, not the job. It calls `/code:review <scope>` for file-level defect passes instead of duplicating them.
