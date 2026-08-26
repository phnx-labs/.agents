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
Arguments: $ARGUMENTS
