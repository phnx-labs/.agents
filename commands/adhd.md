---
description: Explore a decision through bounded independent frames and a critical synthesis without taking external action
---

Run the ADHD decision workflow for: $ARGUMENTS

This command is a bounded problem-solving protocol, not a diagnostic or medical tool. It
creates a decision preview only: no repository mutation, job submission, board or mail
delivery, PR, deployment, credential access, or production action is permitted.

## 1. Frame the decision

Use `$ARGUMENTS` as the decision or problem. If it is empty, recover the active
conversation's most recent unresolved decision. If neither exists, ask one concise question
for the decision and stop.

State the decision owner, options already known, constraints, success criteria, harms to
avoid, evidence needed, and the latest time the decision matters. Read the relevant project
instructions and current source or authoritative documents before reasoning from them.

## 2. Generate independent frames

Create five materially different frames by default; use fewer only when the problem has
fewer distinct dimensions, and never exceed seven. Give every frame a distinct lens such as
user impact, system design, operational safety, economics, reversibility, or adversarial
failure. Each frame must identify evidence, a candidate action, assumptions, and a
falsification test.

Then perform a critical synthesis that actively looks for shared assumptions, omitted
stakeholders, irreversible outcomes, and evidence that would reverse the leading answer.
Rank the viable options against the stated criteria and record uncertainty instead of
manufacturing consensus.

## 3. Use the DevSub workflow only when it is real and authorized

If the active tool list exposes DevSub ADHD tools and the authenticated caller has the
required workflow scope, inspect their schemas and use only this sequence:

1. `adhd_ideate` to create the bounded frames.
2. `adhd_critique` for the independent critical pass.
3. `adhd_promote_preview` to create a reviewable preview artifact.

Never guess missing tool arguments, send raw prompts to an unapproved provider, bypass
authorization, or treat a tool invocation as approval. If the tools are absent or
unauthorized, run the reasoning locally, label the result `local draft`, and state that it
does not have DevSub's server-side independence or durable audit trail.

## 4. Return a decision preview

Return the decision statement, frames, critic findings, ranked recommendation, rejected
alternatives, assumptions, confidence, and the cheapest reversible experiment. Keep the
result at the approval boundary: the owner or the target project's normal workflow decides
whether it becomes a plan, Jobber work order, or implementation.
