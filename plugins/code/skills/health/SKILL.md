---
name: health
description: "Assess code size and human maintainability, rank reduction opportunities, and maintain HEALTH.md with rendered HEALTH.html. Use for code-health assessments, size budgets, or a baseline before refactoring."
argument-hint: "[path(s) | empty = this repo]"
user-invocable: true
---

# code:health

Assess how much code and how many decisions a human must understand to change a component
safely. Produce a compact, evidence-backed baseline and practical reduction opportunities.
Health assesses; `code:refactor` implements. Do not change product code or create tickets
for findings. Follow repository worktree, review, and delivery rules for report changes.

## Inspect current code

Resolve the requested scope from repository instructions, manifests and actual component
boundaries. With no path, assess this repository; in a monorepo, select its major component
roots and state the scope rather than creating a report in every directory. Check existing
reports, open PRs and active ownership before work. Current user decisions govern retained
behavior; a size budget is not permission to delete a feature.

Read HEALTH.md as a prior assessment, never as current proof. Compare its assessed commit
with current source and inspect the relevant changes, including shared code and dependency
changes outside the component. Report-only changes do not require a full reassessment.
If the report or commit is missing or unavailable, establish a fresh baseline. Even when
the commit matches, revalidate the code and assumptions behind the findings being used.

## Evaluate human maintenance burden

Use the existing [measurement contract and helpers](../refactor/measurement-tools.md)
and [review scanners](../review/scan-tools.md); do not build another scanner framework.
Resolve helper paths against those references, and run them from the target worktree.
Record counting commands, tools, exclusions and limitations in the report body.

Lead with maintained production LOC and any user-agreed budget. Count tests, comments,
generated code and vendor material separately using the shared counting contract. Include
internally maintained helpers and scripts; moving code into another package is not a
reduction. Reconcile shared code once when reporting a combined budget. Do not invent a
universal LOC target or an overall health score. Agent read/edit counts are discovery aids,
not measures of human maintainability.

Trace representative flows and identify responsibilities, repeated decisions, indirection,
and the files a human must inspect for a typical change. Rank a small set of opportunities:
unnecessary scope to remove, behavior to consolidate in its existing owner, and custom
machinery that the standard library or stable libraries can replace. Reuse the
[library evaluation guidance](../refactor/typescript-go.md#replacing-custom-code-with-a-library)
across languages; prefer already-used helpers, frameworks and SDKs. Verify candidate
libraries against current primary documentation and representative behavior before claiming
equivalence. Include adapter code and dependency costs in the tradeoff.

For each recommendation, cite current code and consumers, show what disappears and what
remains, and estimate net reduction after replacement code. Distinguish confirmed findings
from uninspected candidates. Preserve readable formatting and required guarantees; shorter
files, compressed code and displaced complexity do not establish improvement. Keep
correctness and verification gaps visible without turning health into a bug-list-only review.

## Write the baseline

Write HEALTH.md at each selected component root and render HEALTH.html beside it.
HEALTH.md is canonical; never hand-edit generated HTML. Use exactly four frontmatter fields:

```yaml
---
kind: report
title: Component Health
updated: YYYY-MM-DD
commit: <full assessed source commit>
---
```

The location defines scope. `commit` is the source revision assessed, not the later commit
that adds the report. Disclose any assessed uncommitted changes in the body. Advance
`updated` and `commit` only after assessment, never just because HTML was rendered. State
partial coverage plainly; do not refresh stale findings as if they were checked.

Use Summary, Findings and Evidence sections: size versus budget and the human maintenance
burden first, ranked reductions next, reproducible measurements and verification limits
last. Keep it concise and use diagrams where they explain relationships. Use `artifacts`
to validate and render, and `browser` to inspect the result. These component-root outputs
are intentional repository documentation, so use a linked worktree and the repository's
PR flow rather than the default external artifact directory. Keep assessment and render
review evidence in the body or PR, not extra frontmatter or a separate metadata file.
Report incomplete rendering or visual checks honestly; do not publish externally by default.

When refactor uses this assessment in read-only `--scan-only` mode, return findings without
writing tracked HEALTH files or opening a report PR. A bounded `quality` change needs only
the relevant assessment, not a mandatory whole-component audit or new report. For full
structural work, refresh the baseline before relying on it and update both HEALTH files
afterward with the actual measurements and remaining limitations.
