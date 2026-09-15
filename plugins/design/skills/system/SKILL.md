---
name: system
description: "Create or refine design systems: principles, tokens, components, interaction patterns, and living guidelines. Extend the existing system and verify it in real product use."
argument-hint: "[existing guidelines, repository, component library, or system brief]"
user-invocable: true
---

# Design systems

Create a system or improve an existing one. Resolve the `design` skill from the current
skill catalog and read `design-core.md` beside its `SKILL.md`. Resolve supporting files
relative to their owning reference directory.

## Workflow

1. **Inventory what exists.** Read the applicable guidelines, brand identity, tokens,
   themes, component APIs, and implementation. Open the rendered guidelines, Storybook,
   and representative product screens. Inspect component behavior as well as appearance.
   Distinguish documented rules, actual usage, and inconsistencies; retain proven patterns.
2. **Set the scope.** Identify which recurring product problem the change addresses.
   For refinement, extend the current source of truth and naming conventions. For a new
   system, derive principles and scales from the product's users, content, and interactions.
   Do not impose a universal ten-step palette or prescribed radius scale.
3. **Shape the foundations and patterns.** Cover the relevant color and semantic tokens,
   typography, spacing, layout/density, iconography, and motion. Specify component
   anatomy, variants, composition, and behavior: focus/keyboard, validation, disabled,
   loading, empty, error, and success where applicable. Explain when to use each pattern.
   Include responsive and theme behavior rather than limiting the system to swatches.
4. **Refine the canonical implementation.** Reuse component APIs and token aliases;
   change their owner instead of adding another theme or component library. When an
   intentional change affects consumers, identify them and show the migration. Keep
   exploratory alternatives distinct from adopted rules and implementation.
5. **Update living guidance.** Extend the existing documentation format and preview or
   Storybook. Create `DESIGN.md` only when the project lacks an appropriate source.
   Include representative composed screens and interactive states, not merely isolated
   buttons. Brand positioning and voice belong in existing brand guidance; revise or
   create `BRAND.md` only when brand identity is part of the request.
6. **Verify in context.** Exercise the affected components in representative product
   flows. Inspect the applicable sizes, themes, focus/keyboard paths, and error feedback.
   Measure contrast, review before/after captures, and use a reviewed clip for important
   motion or state transitions. Check that docs and implementation agree.

Deliver the updated system or clearly labeled proposal, the visible examples, and a
concise account of what changed and which consumers are affected. Follow the shared
worktree, artifact, and presentation guidance. For one screen or flow, use
`design:prototype`; for an icon or logo, use `design:graphics`.
