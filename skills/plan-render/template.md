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
  <svg class="artifact-diagram" viewBox="0 0 900 220" role="img" aria-label="Before and after flow">
    <rect x="40" y="60" width="240" height="100" rx="8" fill="#16120a" stroke="#f59e0b" stroke-width="1.5" />
    <text x="160" y="105" text-anchor="middle" fill="#c8c8c8" font-family="Inter, system-ui, sans-serif" font-size="16">Before</text>
    <text x="160" y="130" text-anchor="middle" fill="#f59e0b" font-family="JetBrains Mono, monospace" font-size="12">current path</text>
    <line x1="300" y1="110" x2="420" y2="110" stroke="#38bdf8" stroke-width="2" stroke-dasharray="3 3" opacity="0.7" />
    <text x="360" y="98" text-anchor="middle" fill="#38bdf8" font-family="JetBrains Mono, monospace" font-size="11">fix</text>
    <rect x="440" y="60" width="240" height="100" rx="8" fill="#0f160a" stroke="#a3e635" stroke-width="1.5" />
    <text x="560" y="105" text-anchor="middle" fill="#c8c8c8" font-family="Inter, system-ui, sans-serif" font-size="16">After</text>
    <text x="560" y="130" text-anchor="middle" fill="#a3e635" font-family="JetBrains Mono, monospace" font-size="12">desired path</text>
  </svg>
  <figcaption><b>Figure.</b> Replace this with the real architecture / before-after for this plan. Empty SVG shells fail validation.</figcaption>
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
