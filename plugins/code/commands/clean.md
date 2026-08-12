---
description: Make a codebase legible to agents and land the cleanup — check the docs against the code, rank by where agents actually spend their reads, ship behavior-preserving PRs, record the trend.
---

Invoke the `code:clean` skill. Arguments: $ARGUMENTS

- Empty: the repo you're in (its dominant package in a monorepo — the skill says which it picked).
- A path (or several): scope the audit to those directories.
- `--scan-only`: produce the plan and the scorecard, open no PRs.
- `--execute`: skip the plan gate and land an already-approved plan.
- `--top N` (default 8) caps what gets fixed; `--days N` (default 90) sets the churn and agent-traffic window.

What it does: reads the repo's own docs as *claims* and checks each one against the code, measures which files agents actually read and edit (from the fleet session index, not just git churn), censuses the user-facing surface for undocumented/untested/orphan entries, then ranks findings by agent-cost across six defect classes — lying context, two homes for one concept, no obvious home, files too big to hold, dead weight that looks live, N ways to do one thing. Fixes land as behavior-preserving PRs, one concept each, and every run writes a scorecard so the legibility trend is visible as the codebase grows.

It calls `/code:review <scope>` for the file-level passes rather than duplicating them, and never mixes a bug fix into a cleanup PR.
