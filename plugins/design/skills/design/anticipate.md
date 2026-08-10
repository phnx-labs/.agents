# design:anticipate — find the dead-end, propose the continuation

Shape a flow so the *next* thing the user is likely to want becomes the path of
least resistance. This mode diagnoses where a flow stops too early and proposes
the continuation — it does not implement anything.

## Load design-core first

Read `design-core.md`. Its precise-copy and restraint principles apply to any
proposed copy in the before/after; the anti-tells catalog (§8) applies to any
proposed screen text or UI chrome.

## When to use (vs neighbors)

- The user asks to improve a UX flow, command output, or screen transition and
  the question is "what happens after this?" → **anticipate** (this).
- The user wants a screen rebuilt right now → **`interface`**.
- The user wants an existing screen judged against the checklist → **`critique`**.

## The four dead-end smells

Look for these when scanning the current flow. Each is a signal that anticipatory
design is missing:

1. **Terminal success** — the action completes and the flow exits, but the user
   very likely has a related next action. Example: removing one duplicate
   version and exiting, ignoring that three more duplicates sit around.
2. **Silent partial work** — the flow does one of N related things and never
   surfaces the other N-1. Example: pruning one app's stale versions without
   mentioning another app's visible duplicates.
3. **Forced re-invocation** — the next step requires the user to retype or
   remember context the flow already has. Example: asking for a path after
   already listing the matching paths.
4. **Asymmetric confirms** — a destructive action gets a safety prompt, but its
   safe-but-tedious neighbors don't get offered. Example: confirming a delete
   but never asking "also delete the 3 related ones?".

## The loop

1. **Pin the flow.** Resolve a fuzzy target ("the prune thing") to a specific
   command, route, screen, or function before proceeding.
2. **Trace the flow end-to-end.** Read every file in the user-visible path — do
   not skip middle steps. CLI: flag parsing → branch → core action → output →
   exit. UI: mount → data load → render → interaction → transition. Annotate
   each step with what the user sees and what options exist; if you can't quote
   it from the code, you haven't read enough.
3. **Identify the dead-end.** Apply the four smells above. For each candidate,
   write one sentence: "The flow ends at X, but the user most likely wants Y,
   because Z." Pick the strongest "because." If nothing smells, say so and
   stop — this is not a license to add noise.
4. **Scan for an existing pattern to reuse.** Grep the codebase for neighbors
   that already solved a similar problem: cascading y/n prompts, "also found…"
   follow-ups, deferred actions offered after primary success, auto-scan on
   entry, smart defaults that pre-fill the likely answer. Reuse beats invention
   — name the pattern and cite file:line. If nothing fits, propose the smallest
   new pattern and flag it as new.
5. **Render before/after as ASCII.** The deliverable: two diagrams showing the
   full visible sequence from the user's perspective, not the code structure.
   Use the real command, real output text, real prompts — no placeholders. Show
   exit points explicitly (`[exit]`) and branches explicitly (`y` / `n`). If the
   cascade loops, draw the loop arrow. Keep each diagram under ~25 lines; longer
   means you're drawing too much.
6. **Write a one-paragraph rationale.** Which smell the before-diagram exhibits,
   what the user's likely next action was and why, which existing pattern the
   after-diagram reuses (file:line), one tradeoff to weigh, and whether you
   recommend shipping it.
7. **Stop. Do not implement.** The output is the proposal. Wait for the user to
   approve, redirect, or reject before touching code.

## Anti-patterns

- **Don't anticipate destructive actions.** "Also delete the repo?" after
  deleting a branch is dangerous, not helpful. Anticipation covers follow-ups
  the user would probably do anyway, not high-regret-cost ones.
- **Don't chain unrelated actions.** If the next action needs a different
  mental model, leave it for a separate invocation.
- **Don't add noise when the flow is already good.** A clean exit with low
  demand for more is a valid verdict: "nothing to change here."
- **Don't invent a new interaction when an existing one fits.** Reusing a
  cascade the user already understands beats a clever new widget.

## Output & delivery

- Two ASCII diagrams (before/after) plus the rationale paragraph, in chat —
  this mode has no HTML/SVG render step; it is a proposal, not a build.
- Offer to hand off to **`interface`** or **`prototype`** to implement, once
  the user picks.

## Mode checklist

- [ ] Flow pinned to a specific command/route/screen/function.
- [ ] Flow traced end-to-end from real code, not guessed.
- [ ] Exactly one dead-end smell identified, with a "because" sentence — or a
      stated verdict that nothing needs to change.
- [ ] Codebase scanned for an existing pattern to reuse before inventing one.
- [ ] Before/after ASCII uses real commands/output/prompts, under ~25 lines each.
- [ ] Rationale names the smell, the likely next action, the reused pattern
      (file:line), and one tradeoff.
- [ ] Stopped after the proposal — no implementation without user approval.
