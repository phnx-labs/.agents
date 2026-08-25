---
name: plan
description: "Plan a feature with swarm verification — research hard, produce mock-ups for any UI/flow, draft a behavior-first change proposal, then have independent agents plan the same thing blind and reconcile. Use before building anything non-trivial. Triggers on: 'swarm plan', '/swarm plan', 'plan with verification', 'change proposal', 'plan and check the approach'."
argument-hint: "[feature or change to plan]"
allowed-tools: Bash(agents teams*), Bash(agents run*), Bash(agents browser*), Bash(agents computer*), Bash(rg*), Bash(fd*), Bash(ls*), Bash(git log*), Bash(git diff*), Read(*), Grep(*), Glob(*), Write(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# swarm:plan — plan, mock up, then have the swarm try to break the plan

> Read the `swarm:orchestrate` skill first for the fan-out mechanics (team creation, briefs, blinded verification, monitoring). This skill is the **plan mode** layered on top: research deeply, **draw what the user will see**, produce a behavior-first change proposal, and validate it against independent agents who plan the same feature blind.

You are planning: **$ARGUMENTS**

The deliverable is not a paragraph of intentions — it is a **rigorous, behavior-first change proposal** plus **concrete mock-ups** for any surface a human will look at: a precise statement of the delta, the tasks to get there, the visual/UX shape, and the behavior it leaves behind. Then de-risk it by having the swarm independently arrive at their own plans and reconciling.

**plan vs spec:** this skill is the *delta* (what we will build). `/swarm:spec` is the durable *is* (what the capability already guarantees) for other agents/humans so they do not invent wrong behavior.

## 1. Understand (read, don't guess)

Read `AGENTS.md` / `CLAUDE.md` if present. Grep for keywords related to the task, then **read** the files that own the patterns — trace the data flow end to end, identify every touch point and dependency. Explore with `Agent(subagent_type: "Explore")` for breadth; read the load-bearing files yourself.

## 2. Research the live world (search finds URLs; driving is the deliverable)

Your weights are stale. Before proposing an approach that touches any external truth — a library's current API, a framework capability, a service's limits, a pricing tier, the current SOTA pattern, a model id — **WebSearch with the current year**, then `WebFetch` the authoritative doc and quote it. When a live product or competitor exists, open it (`agents browser` / `agents computer`) and embed captures; a remembered pitch is not a teardown. A plan built on remembered facts is a plan built on sand. Cite every external claim with a URL (and year) **in the rendered plan**, not only in chat. If three approaches exist in the wild, search — and open — all three before picking.

## 3. Find existing abstractions before proposing new code

For every piece of new code you're about to propose, ask:
- Is there an existing function that already does most of this?
- Can I extend an abstraction instead of inventing one?
- Can this be a one-line change in one place instead of new logic in many?

**Prefer extending existing code over writing new. Prefer one change in one place over many changes in many.**

## 4. Mock-ups first (load-bearing — not optional for UI/flow work)

**Lead with what the user will see.** A plan without mock-ups for a visual or multi-step
flow is unfinished — the swarm and the builder will invent different UIs.

For any change that touches a screen, CLI interactive flow, dashboard, dialog, empty
state, error state, or multi-step user journey:

1. **User flow** — numbered steps from intent → done (happy path + the 1–2 failure paths
   that matter).
2. **Real mock-ups** of **every** distinct screen/state (not just the hero) — built to
   read like the actual product (probe the repo for its tokens/brand), not ASCII
   wireframes and not generic box diagrams. Label primary actions, empty states, and
   error copy with the target product's real labels, never placeholder lorem.
3. **Before / after** when replacing an existing surface — stills side by side, not a
   prose diff of "we'll improve the layout".
4. Put the mock-ups **in the proposal and in the HTML review artifact**. For a
   user-visible surface the artifact must carry the current/proposed behavior figure
   in the `artifact-behavior` markup (`data-state="current|proposed"`,
   `data-evidence="capture|mockup"`) — that markup is what `artifacts check` and the
   plan-presentation check actually verify; fenced ASCII does **not** satisfy it. Do
   not leave mock-ups only in chat.
5. **End the final plan message with the literal marker `<!-- agents-plan -->` on its
   own line** — it is how the plan-presentation check recognizes a plan turn when this
   skill runs outside the harness's native plan mode.

If the change is pure library/backend with **no** user-visible surface, say so explicitly
under Design (`no UI surface`) and skip mock-ups — do not invent a fake screen.

## 5. Draft the change proposal

Structure the plan as a change proposal, not prose: the delta to build, the tasks to get there, and the visible shape it leaves behind.

- **`proposal.md`** — Why (the problem / user value), What changes (the delta in plain terms), Impact (what this touches), and **Mock-ups / flows** (section 4) when applicable.
- **`tasks.md`** — the ordered, checkable task list to execute the change. Each task names the file(s) it edits. This is exactly what a swarm or a `/code:loop` would drain.
- **Delta spec** — the behavior the system will have *after* this change: the new contract, endpoints, types, or UX, written as the source-of-truth spec a future change would diff against.

## 6. Verify — the swarm plans it blind

Fan out via `agents teams` (mechanics in `swarm:orchestrate`). Check who's signed in (`agents teams doctor` / `agents view --json`), then spawn 1–2 verifiers on **different** providers than yourself (codex, antigravity, …) — count by judgment, more for a wide or high-stakes plan. **`--mode plan`** (read-only).

Give each verifier: the feature description, the relevant context (key files, how the system works, your web-search citations). Do **NOT** share your proposed approach — ask them to independently produce their own plan. (Blinded verification per `swarm:orchestrate`.)

Compare:
- Did they identify the same touch points and files?
- Same scope, or did one find work you missed?
- Did they catch edge cases you missed?
- Is their approach simpler or more robust than yours?

Where approaches diverge significantly, that divergence is the real decision — evaluate which is better or fuse the strengths. Don't default to your own draft just because it's yours.

## Output

### Goal
One sentence. What are we building?

### Approach
A short paragraph: the high-level strategy and why it beats the alternatives you researched.

### Research
External facts that shaped the plan, each with a source URL (and year). State-of-the-world claims live here, verified — not in your memory.

### Verification
The independent plans the swarm produced. Where they agreed (high confidence), where they diverged (the real decisions), and why you chose the final approach. Cite each finding to its teammate.

### Design & mock-ups
Required whenever there is a user-visible surface (section 4): user flow + real
captures/mock-ups of every state + before/after when replacing UI. Architecture
is a staff-engineer **system diagram** (modules, arrows, layers — follow the
artifacts diagram recipe), not a decorative SVG; current and proposed when the
shape changes. Extra evidence (flows with today's gap, live field notes,
proposed architecture, alternatives, panel findings, cited URLs) belongs in
the HTML between Intent/Purpose and Proposed Changes — as content, not as a
second heading checklist. If no UI: one line `no UI surface`.

### Proposal (`proposal.md`)
Why / What changes / Impact / mock-ups.

### Tasks (`tasks.md`)
Ordered, checkable, each naming its file(s). Drainable by `/code:loop` or fanned out via `agents teams`.

### Delta spec
The contract the system holds after the change — the source of truth a future change diffs against.

### Edge cases
Enumerated with `file:line`, each with how the plan handles it — misconfig,
leaked resource, boot path that dies. Not "this might be hard".

### Testing
Scenarios to cover — happy path and the edges that matter.

### Review artifact (HTML)
After the proposal is written, author a Markdown source under `.agents/artifacts/yyyy-mm-dd/`,
render it to a self-contained HTML file with `artifacts-cli`, and open it on the machine
the user sits at — follow the **`artifacts`** skill for the LOOK (house structure,
product-brand theming, light/dark toggle, figures as evidence — architecture
drawings, current/proposed behavior, live captures when a product or competitor
exists; one invented SVG is the compiler floor, not the bar) and the
`/plan` command's Step 9 for the open-on-Mac transport, using the injected **Host &
Fleet** context to pick and reach the browser host. Don't duplicate the recipe; reuse it.

## Constraints

No human-time estimates (wall-clock minutes / edit counts / token cost only). No
scope creep on the **build**. Thoroughness of the **plan** (system diagrams,
alternatives considered, corner cases, adversarial review in the HTML, citations)
is not a nice-to-have. No slop nouns. No backwards-compat planning unless asked.
Do exactly what was asked — no feature creep.
