---
name: health
description: "Assess code size and human maintainability, rank reduction opportunities, and share the HEALTH report as an owner-only artifacts page. Use for code-health assessments, size budgets, or a baseline before refactoring."
argument-hint: "[path(s) | empty = this repo]"
user-invocable: true
---

# code:health

Assess how much code and how many decisions a human must understand to change a component
safely. Produce a compact, evidence-backed baseline and practical reduction opportunities.
Health assesses; `code:refactor` implements. Do not change product code or create tickets
for findings. The report is shared, not committed.

## Inspect current code

Resolve the requested scope from repository instructions, manifests and actual component
boundaries. With no path, assess this repository; in a monorepo, select its major component
roots and state the scope rather than creating a report in every directory. Check existing
reports, open PRs and active ownership before work. Current user decisions govern retained
behavior; a size budget is not permission to delete a feature.

Find the prior baseline: the newest `~/.agents/artifacts/*/health-<repo>-<component>/HEALTH.md`
on this machine, else the page `artifacts share list --scope me --meta kind=health --meta
component=<repo>/<path> --list-json` returns (its `commit` metadata is the assessed revision;
open it with `browser`). A repository that still tracks a HEALTH.md at the component root has
an older one there. Read it as a prior assessment, never as current proof. Compare its assessed commit
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

Write HEALTH.md for each selected component in the `artifacts` skill's durable artifact
directory (`~/.agents/artifacts/<date>/health-<repo>-<component>/`), never in the repository,
and render HEALTH.html beside it. HEALTH.md is canonical; never hand-edit generated HTML.
Use exactly four frontmatter fields:

```yaml
---
kind: report
title: Component Health
updated: YYYY-MM-DD
commit: <full assessed source commit>
---
```

The `component` metadata below defines scope. `commit` is the source revision assessed. Disclose any assessed uncommitted changes in the body. Advance
`updated` and `commit` only after assessment, never just because HTML was rendered. State
partial coverage plainly; do not refresh stale findings as if they were checked.

Use Summary, Findings and Evidence sections: size versus budget and the human maintenance
burden first, ranked reductions next, reproducible measurements and verification limits
last. Keep it concise.

Open the Summary with a bird's-eye paragraph (what the component does, the shape problem in
one sentence), then a C4 container view (level 2) following the `artifacts` skill's
[diagram conventions](../../../../skills/artifacts/references/diagram-conventions.md): the
component's containers inside a dashed system boundary, the people and external systems
it talks to outside it, every arrow labeled with what flows and over what protocol, and a
legend. Draw it from the code you traced (routes, clients, database access), not from docs
or intent. Mark retired or unused paths with a dashed red outline, put a numbered marker
on each element a finding concerns with the same number as that finding, and caption the
figure with the assessed commit and anything omitted. A level-3 component view of the
largest container is worth adding when one file or module dominates it.

Use `artifacts` to validate and render, and `browser` to inspect the result. Then share it
owner-only under one stable slug per component, so each refresh is a new revision of the
same page and the owner finds it in the Rush console under Artifacts:

```bash
artifacts share HEALTH.md --visibility me --expire never \
  --slug health-<repo>-<component> \
  --meta kind=health --meta component=<repo>/<path> --meta commit=<sha>
```

Give the returned link in the reply and in the ticket or PR that asked for the assessment.
Do not commit HEALTH.md or HEALTH.html, open a report PR, or widen the visibility unless the
user asks in this conversation. Keep assessment and render review evidence in the body.
Report incomplete rendering or visual checks honestly.

When refactor uses this assessment in read-only `--scan-only` mode, return findings without
writing or sharing a report. A bounded `quality` change needs only
the relevant assessment, not a mandatory whole-component audit or new report. For full
structural work, refresh the baseline before relying on it and share the updated report
afterward with the actual measurements and remaining limitations.
