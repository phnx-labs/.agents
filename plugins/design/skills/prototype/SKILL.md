---
name: prototype
description: "Create or refine screens, components, interactive prototypes, and user flows. Inspect existing patterns and interactions, then build and verify the relevant states."
argument-hint: "[existing URL, file, flow, or new prototype brief]"
user-invocable: true
---

# Screens and interactive prototypes

This skill owns the craft of prototyping. It never assumes a product's look: the product's
design system (its `DESIGN.md` or equivalent, tokens, components, marks, and assets) is
found in step 1 and followed from its source. Everything else a prototype needs is on
this page.

## What a prototype is

A prototype is held to this bar before anyone else sees it:

- **Every visible control works.** A button, tab, chip, link, menu, toggle, or card that
  looks clickable does something: it navigates, opens, changes state, or says why it
  cannot. Nothing is a picture of a control.
- **It is built from the product's own parts.** Tokens, components, and patterns come from
  the product's source files, and a control that exists in the product behaves the same
  way in the prototype (selection, hover, motion, keyboard).
- **Marks and images are the real files.** Every logo, app icon, avatar, and brand mark is
  the product's or vendor's published file, embedded from where the product keeps it.
  Never redraw a mark, never substitute a generic icon or a letter for a brand that has a
  mark, and never ship a placeholder image as finished.
- **Data is realistic and labeled.** Use real names and plausible content. Do not invent
  counts, ratings, benchmark scores, or testimonials; when a number is illustrative, say
  so on the page.
- **The hard cases are shown.** Empty, one, many (ten apps, fifty rows), long names,
  loading, error, and the narrow viewport each appear somewhere a reviewer can reach.
- **Anyone can use it.** Text meets contrast against its real background (4.5:1, or 3:1
  for large text), measured rather than guessed; meaning never rides on color alone;
  every control is reachable by keyboard with visible focus; motion honors reduced-motion.
- **Words are the product's.** Labels say what the action does, in the product's voice.
- **The owner can click it.** It opens on the owner's machine as a working page, not a
  screenshot or a description of one.

## Workflow

1. **Find the product's design system and show what you found.** Locate its design
   guidelines, tokens, component library, asset folders, and the live pages closest to the
   new screen; open those pages and capture them. Before any markup, post a short
   preflight: the guideline sections read, the components and marks the screen will reuse
   (with file paths), and the capture. No preflight, no prototype.
2. **Settle what the screen is.** Name the existing entity it shows, whose it is, and which
   states it covers (a template listing is not the instance a user created).
   Check the product's requirements and agent instructions for anything the request
   conflicts with, and raise it before drawing.
3. **Map behavior.** Entry point, primary action, state transitions, feedback, recovery,
   back/cancel, keyboard and focus, and the hard cases listed above. Decide what the
   prototype must demonstrate.
4. **Build.** When the product has a component library, prefer prototyping inside it (a
   scratch route, story, or browser-test harness). A standalone page (the `artifacts`
   skill's hand-written HTML) is fine when its tokens, component markup, and marks are
   taken from those source files. Work in the existing stack when implementation is
   requested. Motion communicates state and respects reduced-motion settings.
5. **Click through every control, then get a second read.** Script a walk that clicks each
   visible control and checks that something happened, with no console errors, at desktop
   and phone widths. Inspect the screenshots of each meaningful state; record a short clip
   when timing or sequence matters. Run `bun ../critique/scripts/check-contrast.ts --json
   '<pairs>'` on the real color pairs and `bun ../critique/scripts/check-tells.ts <file>` on
   the markup (paths relative to this skill's directory). Then have a
   non-author reviewer (the `artifact-critic` subagent, or `design:critique` in a fresh
   agent) check the captures against the product's own review checklist, the bar above,
   and your preflight. Fix every blocking finding before the owner sees it.
6. **Deliver.** Open the working prototype on the owner's machine, summarize the
   behavior, and state what is simulated or unverified. When the owner asked for a review
   of their feedback or a before/after, build the review page the `artifacts` skill
   describes ("Review pages"): their words first, the real before beside your after, the
   same numbered marks on both, one or two sentences per mark.

## Owner feedback

Keep a `requirements.md` beside the prototype. Restate each correction as a numbered,
general rule ("every mark comes from its source file", not "fix the logo on this card"), play
the list back before changing anything, then check every element of the next version
against the whole list, not only the latest item. Reread it at the start of each round;
it outlives context compaction.

Offer alternatives only when a real tradeoff belongs to the user. For reusable
design-system changes use `design:system`; for standalone logos or icons use
`design:graphics`; for a read-only assessment use `design:critique`.
