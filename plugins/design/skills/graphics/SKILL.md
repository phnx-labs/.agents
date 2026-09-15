---
name: graphics
description: "Create or refine logos, icons, favicons, and other graphic assets. Inspect the existing visual language, edit the appropriate source, and verify the result at its actual usage sizes."
argument-hint: "[existing asset, icon family, logo, or graphics brief]"
user-invocable: true
---

# Graphics

Create an asset or refine an existing one. Resolve the `design` skill from the current
skill catalog and read `design-core.md` beside its `SKILL.md`. Supporting files resolve
from the directory of their owning reference.

## Workflow

1. **Inspect the context.** Open the current asset and its uses visually. Read the
   product's brand/design guidance and inspect neighboring assets. Establish purpose,
   required formats, dimensions, backgrounds, and usage sizes from the actual consumers.
2. **Identify the visual language.** For an icon family, inspect grid/viewBox, stroke
   weight, caps/joins, corner treatment, filled versus outlined construction, optical
   alignment, and detail at small sizes. For logos, inspect proportions, typography,
   clear space, variants, and behavior on light/dark backgrounds. Preserve these unless
   the requested change deliberately revises them.
3. **Choose and edit the source.** Reuse the existing icon library or editable master.
   SVG is useful for vector assets; HTML is useful for typographic compositions; use the
   available image capability for requested raster generation or editing. Do not rebuild
   a reusable existing asset as a disconnected substitute. Label concept alternatives
   separately from the adopted asset, and ask only for a consequential direction choice.
4. **Check actual use.** Render at the intended sizes and backgrounds, including the
   smallest relevant size. Inspect alignment, legibility, clipping, padding, transparency,
   and consistency with the asset family. For icons used as controls, inspect their
   surrounding hit target, focus/selected/disabled states, and accessible name in context.
   An isolated SVG cannot establish that the control is usable.
5. **Export and verify.** Keep the editable master and produce the formats/sizes the
   consumer requires. Open the exports, compare before/after, and confirm they render
   correctly without missing fonts or linked assets. A placeholder is not a finished
   raster image; state the missing deliverable if the required capability is unavailable.

Deliver the master and verified exports or the updated library asset, with a brief
explanation of what changed. Use the shared delivery guidance. System-wide rules belong
in `design:system`; interactive screens and flows belong in `design:prototype`.
