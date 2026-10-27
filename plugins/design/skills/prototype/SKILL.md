---
name: prototype
description: "Create or refine screens, components, interactive prototypes, and user flows. Inspect existing patterns and interactions, then build and verify the relevant states."
argument-hint: "[existing URL, file, flow, or new prototype brief]"
user-invocable: true
---

# Screens and interactive prototypes

Create a new prototype or refine an existing screen, component, or flow. Resolve the
`design` skill from the current skill catalog and read `design-core.md` beside its
`SKILL.md` before step 1; it is part of this workflow, not optional background.
Supporting files resolve from the directory of the reference that owns them.

## Workflow

1. **Establish the task and baseline.** Identify the user's goal and whether the request
   is design-only or authorizes implementation. For an existing product, read its
   `DESIGN.md` (and `BRAND.md`), its component library, and the live pages closest to the
   new screen, then post a short preflight before any markup: the guideline sections
   read, the existing components the screen will be built from (file paths), and a
   capture of the nearest live page. No preflight, no prototype. Record the problem and
   the patterns worth retaining before proposing a change.
2. **Settle what the screen is.** Name the existing entity it shows, whose it is, and which
   states it covers (for example a catalog listing versus the copy someone added and is
   running). Check the product's requirements and `AGENTS.md` for anything the request
   conflicts with, and raise a conflict before drawing, not after.
3. **Map behavior.** Name the entry point, primary action, state transitions, feedback,
   and recovery. Include relevant validation, loading, empty, error, success, back/cancel,
   and keyboard/focus behavior, and the corner cases of the data (one item or fifty, one
   logo or ten, a long name). Decide what the prototype must demonstrate. Label any
   simulated data or behavior; do not imply a mock flow is connected to a real service,
   and do not invent counts, scores, benchmarks, or testimonials (`design-core.md` §7).
4. **Build from the product's own parts.** Reuse tokens, components, and marks from their
   source files; never redraw a logo or re-create a component by eye. When the product has
   a component library, prefer prototyping inside it (a scratch route, story, or
   browser-test harness). A standalone review page (the `artifacts` skill's hand-written
   HTML) is fine, but its marks and component markup come from those source files, with
   each reused part's path named in the preflight. Work in the existing stack when
   implementation is requested.
5. **Make the flow usable.** Wire controls to their outcomes, preserve context between
   states, support keyboard navigation, and expose useful feedback. Cover the relevant
   viewport sizes. Motion should communicate state and respect reduced-motion settings.
6. **Exercise, inspect, and get a second read.** Walk the primary path and relevant
   recovery path. Inspect screenshots at meaningful states. Record and review a short clip
   when motion, timing, or the sequence matters; compare the same path before and after a
   refinement. Run the `critique` skill's checkers. Before the owner sees it, have a
   non-author reviewer (the `artifact-critic` subagent or `design:critique` in a fresh
   agent) check the captures against the product's review checklist and the preflight;
   fix its blocking findings. Fix dead controls, unexpected focus changes, confusing
   transitions, and visual drift.
7. **Deliver the requested result.** Show the working prototype or changed live surface,
   summarize the behavior, and state simulations or unverified states. When the owner
   asked for a review of their feedback or a before/after, build the review page the
   `artifacts` skill describes ("Review pages"): their words first, the real before
   beside your after, the same numbered marks on both, one or two sentences per mark. Use the owning
   browser/computer/artifacts workflow and the repository's delivery process when code
   changes are authorized.

## Owner feedback

Keep a `requirements.md` beside the prototype. Restate each correction the owner gives
as a numbered, general rule ("every mark comes from its home component", not "fix the
Sentry logo"), play the list back before changing anything, then check every element of
the next version against the whole list, not only the latest item. The file outlives
context compaction; reread it at the start of each round.

Offer alternatives when a real tradeoff belongs to the user. A routine refinement does
not require two or three mockups and another approval before proceeding.

For reusable design-system changes use `design:system`; for standalone logos or icons
use `design:graphics`; for a read-only assessment use `design:critique`.
