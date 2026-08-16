---
name: bmad
description: "Produce a BMAD-style, evidence-backed work package without starting implementation. Triggers on: BMAD, BMM, requirements package, implementation-ready plan, product or architecture specification."
---

# BMAD work package

Use this capability when the user wants a request turned into a reviewable package that is
ready for later implementation. It ends at the approval boundary: do not mutate a
repository, create or submit a job, post or send a message, open a PR, deploy, or take a
production action.

## Build the package

1. Establish the goal, affected users or systems, constraints, and the decision that makes
   the package ready to build. If the goal is missing, ask one concise question.
2. Read the target project's agent instructions and authoritative specifications. Search for
   related code, plans, jobs, PRs, and reusable tools before proposing a new surface.
3. Separate verified facts, inferences, and unknowns. Cite the file, API, document, or live
   result behind each factual claim.
4. Produce: problem and desired outcome; scope and exclusions; current-state evidence;
   requirements and acceptance criteria; proposed flow, interfaces, data changes, and
   failures; ordered slices; dependencies; validation; rollout/rollback; risks; open
   decisions.

## Optional DevSub adapter

Use DevSub only if the active tool list exposes the BMAD workflow tools and the authenticated
caller has the required scope. Inspect the live schemas first, then use
`bmad_import_artifact`, `bmad_compile_work_order` for a preview only, and `bmad_status`.

Never guess a missing schema, bypass authorization, or represent a local document as a
durable artifact. When DevSub is unavailable or unauthorized, label the output `local draft`
and say it has not become a DevSub artifact or Jobber work order.

## Close

Return the package, evidence, unresolved decisions, and the smallest next action. A plan is
not approval to build: preserve the target project's authorization, Jobber, review, and
release gates.
