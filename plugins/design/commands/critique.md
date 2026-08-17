---
description: Audit an existing design surface — a URL, local HTML file, screenshot, several pages of one site, or a running app — against the design plugin's rubric. Runs the deterministic checkers (WCAG contrast computed, never guessed; the anti-tells/offline/color-only-status linter), critiques real screenshots in both themes, diffs pages against the product's own brand tokens and against each other for drift, and returns ranked findings plus a paste-ready fix brief and standing design laws for the project's docs.
---

Invoke the `design` skill in its `critique` mode: read `design-core.md`, then follow `critique.md` beside it (including running `scripts/check-tells.ts` and `scripts/check-contrast.ts`). Target: $ARGUMENTS
