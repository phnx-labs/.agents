---
kind: report
title: Clearer rules, less repeated instruction
summary: Preserve judgment, useful visuals, and verified delivery while reducing repeated procedures.
status: In review
project: Agent instructions
repository: phnx-labs/.agents
branch: refine/clear-expectations
harness: Codex
agent: Codex
human: Owner
host: worker
session: resumed-session
date: "2026-09-06"
links:
  - https://linear.app/getrush/issue/PHNX-3882
---

## Summary

The standing rules state expected outcomes and boundaries. Portable skills own task-specific guidance; supporting references hold occasional tool mechanics. `/plan` and `/dispatch` remain available.

<section class="artifact-grid artifact-grid-2">
<article class="artifact-panel"><h3>Before</h3><p>Repeated workflows across rules, commands, and skills.</p><p>Approval gates contradicted autonomy. Incidental-ticket mandates expanded scope. Merge evidence appeared as alternatives.</p></article>
<article class="artifact-panel"><h3>After</h3><p>Rules define outcomes. Commands route to skills. References hold detailed mechanics.</p><p>Respect authorized scope. Ask for product choices. Require both passing checks and independent review.</p></article>
</section>

## Findings

| Area | Refined expectation |
| --- | --- |
| Visuals | Make behavior understandable with purposeful diagrams, mockups, or captures; inspect the rendered result. |
| Planning | Explain the problem, goals/non-goals, behavior, and success checks. Respect plan-only requests. |
| Dispatch | Discover existing work, assign a capable executor, and own the verified result. |
| Tracking | Draft locally during planning; commit tracking at execution. Do not automatically file incidental findings. |
| Code workflows | Cohesive commits, independent review, useful refactoring evidence, and concise durable learning. |
| Safety | Preserve worktrees, review independence, credentials, confidential transcripts, and the active desktop. |

## Evidence

- [x] Recover existing work and confirm open-PR ownership.
- [x] Review system rules, personal overrides, and code-plugin changes.
- [x] Compose system and layered personal rules; preserve four empty overrides.
- [x] Run the Linear guard: 26 checks pass.
- [x] Validate plugin manifests in strict mode.
- [x] Independent review clears both repositories. Full hook suite: 46/47 pass; the owner-allowlist fixture also fails on unchanged base.
- [ ] Merge both PRs and verify installed resources across reachable fleet devices.

<div class="artifact-callout">The shorter instructions preserve concrete safety boundaries. Independent review is complete; merge and fleet installation are pending. The unrelated owner-allowlist test failure is reproduced on unchanged base.</div>

## Tracking

[PHNX-3882](https://linear.app/getrush/issue/PHNX-3882) tracks related planning improvements. Its broader product-spec work remains outside this refinement.
