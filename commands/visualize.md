---
description: Turn any concept, dataset, or finding into one self-contained branded HTML visual — infographic, explainer, status dashboard, data story, or comparison — rendered with artifacts-cli.
argument-hint: "<what to visualize>"
---

**`/visualize` routes to the `artifacts` skill with `kind: visual`.** The pipeline —
author Markdown, declare `kind: visual`, `artifacts check` + `artifacts render`, inspect
headlessly — is defined once in the skill; this command is the convenient door.

You are visualizing: $ARGUMENTS

Invoke the `artifacts` skill and follow its `kind: visual` section: one hero figure as the
visual spine of the page, `## Story` / optional `## Data` / `## Figure` structure, honest
scales and source labels on quantitative charts, self-contained branded light/dark HTML.

Follow its "When the artifact recommends" and "Evidence" rules: show each recommendation as
a mockup / before-after / demo rather than describing it, say why it matters, cite every
number to a primary source with a timeframe (raw-records appendix), and keep it digestible —
not a landing page. Verify every embedded capture by looking at the actual pixels, and settle
any live page fully before capturing it.

Arguments: $ARGUMENTS
