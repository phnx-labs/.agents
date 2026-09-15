---
name: prototype
description: "Create or refine screens, components, interactive prototypes, and user flows. Inspect existing patterns and interactions, then build and verify the relevant states."
argument-hint: "[existing URL, file, flow, or new prototype brief]"
user-invocable: true
---

# Screens and interactive prototypes

Create a new prototype or refine an existing screen, component, or flow. Resolve the
`design` skill from the current skill catalog and read `design-core.md` beside its
`SKILL.md`. Supporting files resolve from the directory of the reference that owns them.

## Workflow

1. **Establish the task and baseline.** Identify the user's goal and whether the request
   is design-only or authorizes implementation. For an existing product, inspect its
   guidelines, components, and live flow using the shared preflight. Record the problem
   and the patterns worth retaining before proposing a change.
2. **Map behavior.** Name the entry point, primary action, state transitions, feedback,
   and recovery. Include relevant validation, loading, empty, error, success, back/cancel,
   and keyboard/focus behavior. Decide what the prototype must demonstrate. Label any
   simulated data or behavior; do not imply a mock flow is connected to a real service.
3. **Refine the smallest useful surface.** Reuse tokens and components. Work in the
   existing stack when implementation is requested; do not replace an app with a parallel
   static mockup. For a standalone prototype, choose a simple editable implementation
   that actually supports the required interactions. HTML/CSS/JavaScript is suitable;
   real routing, state management, and existing project tools are allowed when needed.
4. **Make the flow usable.** Wire controls to their outcomes, preserve context between
   states, support keyboard navigation, and expose useful feedback. Cover the relevant
   viewport sizes. Motion should communicate state and respect reduced-motion settings.
5. **Exercise and inspect.** Walk the primary path and relevant recovery path. Inspect
   screenshots at meaningful states. Record and review a short clip when motion, timing,
   or the sequence matters; compare the same path before and after a refinement. Fix
   dead controls, unexpected focus changes, confusing transitions, and visual drift.
6. **Deliver the requested result.** Show the working prototype or changed live surface,
   summarize the behavior, and state simulations or unverified states. Use the owning
   browser/computer/artifacts workflow and the repository's delivery process when code
   changes are authorized.

Offer alternatives when a real tradeoff belongs to the user. A routine refinement does
not require two or three mockups and another approval before proceeding.

For reusable design-system changes use `design:system`; for standalone logos or icons
use `design:graphics`; for a read-only assessment use `design:critique`.
