---
name: critique
description: "Assess existing screens, graphics, design systems, and interactions against their own guidelines. Inspect evidence and return ranked findings with concrete fixes."
argument-hint: "[URL, app, file, screenshots, recording, or pages to compare]"
user-invocable: true
---

# Design critique

Assess the supplied surface without silently expanding a review into implementation.
Resolve the `design` skill through the current skill catalog and read `design-core.md`
beside its `SKILL.md`. The checker scripts belong to this critique skill's `scripts/`
directory; resolve their paths from this skill's actual installed location.

## Workflow

1. **Understand and observe.** Read the applicable design guidelines and open their
   visual examples. Inspect the target itself and representative peers for consistency.
   For interactive surfaces, follow the shared interaction preflight. Review supplied
   recordings; capture and inspect a short clip when sequence or timing matters. State
   what cannot be assessed from a screenshot or an unavailable surface.
2. **Check measurable properties.** Run `bun <critique-skill-dir>/scripts/check-contrast.ts
   --json '<actual foreground/background pairs>'` on real tokens or computed colors.
   Each pair has `fg`, `bg`, and `label` fields; add `large: true` only for large text. Run
   `bun <critique-skill-dir>/scripts/check-tells.ts <available-markup-file>` when markup
   is available. Use the browser's authenticated page when inspecting a live app; raw
   unauthenticated HTML may be a different surface. Treat style warnings as prompts to
   investigate, not automatic failures or permission to override the product's brand.
3. **Assess the user experience.** Check hierarchy, density, readability, alignment,
   asset consistency, component reuse, and copy against the task. For interactions,
   assess discoverability, keyboard/focus, feedback, state continuity, recovery, and
   relevant responsive/motion behavior. Compare pages or variants to identify drift.
4. **Report actionable findings.** Prioritize blockers to task completion and accessibility,
   then inconsistency and polish. Each finding names the page/element, observed behavior,
   evidence (capture, timestamp/action trace, computed result, or source line), impact,
   and a concrete fix. Separate observed facts from proposed changes and unverified claims.
5. **Route the next step.** Summarize the smallest useful correction. Use `design:system`
   for recurring rules, `design:graphics` for assets, or `design:prototype` for screens
   and flows when changes are authorized. Do not impose new standing design laws during
   a read-only review. Update existing guidance when that work is in scope.

Keep a small review in the response. For a substantial report, use the `artifacts` skill
and inspect its rendering. Share captures only within the user's authorized scope.
