---
kind: plan
title: <plain, factual headline>
summary: <~3-line problem statement and intended outcome>
status: draft
tracking: "#<ticket>"
facts:
  - <key fact>
  - <key fact>
---

## Purpose

What is broken or needed, and what prompted this plan.

<section class="artifact-grid artifact-grid-3">
  <article class="artifact-stat">
    <span class="artifact-stat-value">N</span>
    <span class="artifact-stat-label">files touched</span>
  </article>
  <article class="artifact-stat">
    <span class="artifact-stat-value">N</span>
    <span class="artifact-stat-label">new helpers</span>
  </article>
  <article class="artifact-stat">
    <span class="artifact-stat-value">N</span>
    <span class="artifact-stat-label">tests added</span>
  </article>
</section>

## Proposed Changes

The proposed approach. Name concrete files and functions.

<figure class="artifact-figure artifact-figure-diagram artifact-figure-wide">
  <svg class="artifact-diagram" viewBox="0 0 900 250" role="img" aria-label="Architecture or flow diagram">
    <!-- Add interactive/animated SVG here -->
  </svg>
  <figcaption><b>Figure.</b> One-line description of what the figure shows.</figcaption>
</figure>

## Public Interface

```bash
# Commands, flags, or APIs this plan introduces
artifacts render .agents/artifacts/plans/plan-<slug>.md --format html
```

## Validation

| Check | Expected result |
| --- | --- |
| Frontmatter | Required metadata is present |
| HTML output | Renders in both themes and at mobile/desktop widths |
| Figures | SVG visible, animations/interactions work |

## Risks

| Risk | Mitigation |
| --- | --- |
| ... | ... |

<aside class="artifact-callout"><strong>Load-bearing takeaway:</strong> the one thing a reviewer must not miss.</aside>

## Tracking

- Ticket: <link>
- Next step: go / reshape
