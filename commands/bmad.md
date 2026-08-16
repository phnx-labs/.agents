---
description: Turn a request into a BMAD-style, implementation-ready work package without starting the build
---

Run the BMAD planning workflow for: $ARGUMENTS

This is a planning and specification command. It produces a reviewable work package; it
does not modify a repository, create or submit a job, send mail, post to a board, open a
PR, deploy, or touch production.

## 1. Establish the brief

Use `$ARGUMENTS` as the request. If it is empty, recover the active conversation's most
recent concrete goal. If neither exists, ask one concise question for the goal and stop.

State the intended outcome, affected users or systems, constraints, and the decision that
will make the package ready to build. Read the target project's agent instructions and its
authoritative specification before proposing changes. Search for existing plans, jobs,
open PRs, and reusable tooling so the package extends current work rather than duplicating
it.

## 2. Build the package

Produce these sections, grounded in current source and documentation:

1. Problem and desired outcome.
2. In-scope and explicitly out-of-scope work.
3. Current-state evidence: relevant files, APIs, contracts, and existing work.
4. Requirements and acceptance criteria, including non-functional and safety boundaries.
5. Proposed flow, interfaces, data changes, and failure handling.
6. Ordered implementation slices, dependencies, validation, rollout, rollback, and open
   decisions.

Name the exact evidence for each factual claim. Separate verified facts, inferences, and
unknowns. Do not invent tool arguments, credentials, integrations, or current deployment
state.

## 3. Use the DevSub adapter only when it is real and authorized

If the active tool list exposes the DevSub BMAD tools and the authenticated caller has the
required workflow scope, inspect each tool's schema and use the adapter in this order:

1. `bmad_import_artifact` for a supplied BMAD artifact.
2. `bmad_compile_work_order` to produce a preview only.
3. `bmad_status` to record the resulting artifact state.

Never guess a missing schema or bypass an unavailable scope. If the adapter is absent or
unauthorized, still provide the local planning package, label it `local draft`, and state
that it has not become a durable DevSub artifact or Jobber work order.

## 4. Finish at the approval boundary

Return the complete package, the evidence used, the unresolved decisions, and the smallest
next action. Do not treat a plan as approval to implement. Preserve the target project's
normal authorization, Jobber, review, and release gates.
