# Diagnose a flow's next step

Read `design-core.md` beside this file. Use this reference to understand a dead end or
missing continuation; use `design:prototype` when creating or refining the flow.

1. Identify the user's goal and the concrete entry point. Inspect the relevant source
   and exercise the actual flow using the shared interaction preflight. A code path
   alone does not prove what the user sees or can do.
2. Look for lost context, unclear completion, missing recovery, or a related next action
   that requires repeating work. State the observed problem and evidence. A useful clean
   exit is valid; do not invent follow-up actions merely to extend the flow.
3. Inspect neighboring flows for a pattern to reuse. Propose the smallest change that
   helps the user continue or recover. Keep unrelated or destructive actions separate.
4. Show current and proposed behavior with the form that best explains it: an annotated
   capture, a compact flow diagram, or a working prototype. Label proposal versus observed
   behavior. Include the action, feedback, next state, and relevant exit/recovery paths.
5. Explain the benefit and any tradeoff. An advisory request ends with the assessment.
   When implementation is already authorized, continue through `design:prototype`; ask
   only when a consequential unresolved choice belongs to the user.
