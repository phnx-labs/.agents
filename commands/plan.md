---
description: Plan like a staff engineer — live research, system diagrams, alternatives considered, render HTML
---

You are planning: $ARGUMENTS

## CRITICAL: Ground the Plan in Reality

Plans fail when they're based on assumptions instead of evidence. Before proposing anything:
0. **Search what previous agents did on this feature** — `agents sessions "<feature keywords>"`, then read the latest plan/PR on that surface. Extend it; do not silently revert it (the most common regression).
1. Research the live product and the current docs — not just search snippets
2. Read the actual code that will change
3. Create concrete artifacts (captures, mockups, diagrams, and a per-file diff of the change)
4. For medium+ work, get independent plans from a vendor-varied panel and adjudicate one
   merged plan against the code (Step 7)

## Quality bar — write it like a staff engineer

`artifacts check` requires a handful of headings and at least one figure. That is the
minimum that compiles. It is not a finished plan. Write the document a staff engineer
would put in front of another staff engineer.

A reviewer must be able to judge the plan without re-running the session:

- **Architecture as a system, not a box of labels.** Current and proposed architecture
  are proper system diagrams — follow the artifacts diagram recipe
  (`skills/artifacts/references/authoring.md`): named modules, arrows for calls / data
  / control, layers kept distinct (orchestration ≠ machine ≠ isolation; PID1 vs sidecar;
  config table vs image vs protocol). A table of filenames is not a diagram. One
  invented SVG next to empty headings is not done. Gold quality named the coupling
  points with `file:line` and drew the boot path, not a decorative topology.
- **Alternatives considered, always.** Every load-bearing choice lists the options,
  what each implies, and why this one wins. "A registry" is slop until it is "a config
  table in code" or "an OCI image per harness" or "a new protocol". A one-file bugfix
  may say "no alternatives — the existing helper already does this." Everything else
  gets the table. This is what made the Prix Cloud plan reviewable.
- **Corner cases with `file:line`.** Risks is not "this might be hard". Name the
  misconfig, the first-branch-wins trap, the leaked resource, the boot path that dies
  on a third-party image.
- **Adversarial review in the artifact.** For medium+ / architecture / product plans,
  run the independent panel (Step 7) **and put the findings in the HTML**
  (`## Adversarial review`: vendor, what they proposed, ADOPTED / REJECTED with
  `file:line`). Chat-only review evaporates. The gold session's user prompt was
  understand → review the plan → then fan out a team — the review is part of the
  plan, not a later chat.
- **Live evidence** of the current product or the competitors, when they exist — drive
  the real UI (`agents browser` / `agents computer`) and embed captures. A paragraph of
  remembered positioning is not a teardown.
- **External URLs** for every outside-world claim (API, pricing, a competitor's primitive,
  a current-year docs page). Uncited claims do not belong in the plan.
- **Extra `##` sections** between Intent/Purpose and Proposed Changes. Expected on a
  real plan: behavior first (the flows, each with today's gap), competitive teardown /
  field notes (from using the live product), proposed architecture (drawn, not only
  diffs), options considered, adversarial review, references. Keep the required
  headings; do not invent a second frontmatter schema. No slop nouns.

"No nice-to-haves" applies to the **build** (do not grow the feature). Thoroughness of
the **plan** — diagrams, alternatives, corner cases, review, citations — is the job.

Scale: a one-file bugfix can skip competitive teardown and the independent panel (still
state the alternative-considered one-liner). A platform, product, or architectural
change cannot.

## Step 1: Understand the Request

Before reading any code, clarify:

1. **What is the user asking for?** — Restate in your own words. If ambiguous, use `AskUserQuestion` with 2-3 interpretations.
2. **What is the goal?** — What problem does this solve? Who benefits?
3. **What is the scope?** — New feature, refactor, bug fix, or integration?
4. **What are the constraints?** — Time, dependencies, backwards compatibility?

## Step 2: Research the live world

**Do NOT skip this.** Your training data is stale. Web search finds the URLs; it is
not the research deliverable.

1. **Search with the current year** for current docs, APIs, pricing, and the products
   that already solve this. Then `WebFetch` the authoritative page and quote it.
2. **Drive the live thing.** When a current product, a competitor, or a docs site
   exists, open it with `agents browser` (or `agents computer` for native UI) and
   capture what you actually saw — the front-door primitive, the deploy/create flow,
   the missing lever. Field notes from using it beat a remembered pitch.
3. **Cite every outside-world claim** with a URL and year. Put the evidence in the
   rendered plan (a `## Competitive teardown`, `## References`, or `## Behavior first`
   section) — not only in chat.

If an API has changed or a better approach exists, the plan reflects the live docs,
not training memory.

## Step 3: Audit the Codebase

Now find what's relevant. Target your search — do NOT read everything.

**Search strategy:**
- Keywords in filenames: `fd auth`, `fd login`
- Keywords in content: `grep -r "authentication" src/`
- Project structure: `ls src/` or `ls app/`
- Similar features: How do existing features work?

**Identify and READ:**
- **Entry points** — Routes, controllers, handlers
- **Data layer** — Models, schemas, types
- **UI layer** — Components, screens (if applicable)
- **Shared logic** — Utilities, hooks, services
- **Tests** — Existing test patterns

**Output the relevant paths:**
```
Relevant paths identified:
- src/features/auth/login.tsx:1-85 (UI entry point)
- src/lib/auth.ts:20-60 (auth logic)
- src/types/auth.d.ts (types)
```

## Step 4: Read the Code

Read EVERY file identified above. For each:
1. Note file path and line numbers
2. Quote the relevant code
3. Understand how it connects to other files

**Do NOT guess. Do NOT speculate. Read code, then speak.**

The plan must be grounded in what the code actually does, not what you assume it does.

## Step 5: Inventory Existing Primitives

**Before designing anything new, catalog what already exists:**

- **UI Components** — buttons, modals, forms, layouts, cards already in the codebase
- **Design tokens** — colors, spacing, typography from tailwind config or design system
- **Utilities** — helpers, hooks, services that solve similar problems
- **Patterns** — how do similar features handle state, errors, loading, validation?

```
Existing primitives to reuse:
- components/ui/Button.tsx — primary, secondary, destructive variants
- components/ui/Modal.tsx — standard modal with close behavior
- hooks/useForm.ts — form state + validation
- lib/api.ts:fetchWithAuth() — authenticated API calls
```

**The default is REUSE, not invent.** If a component, pattern, or utility exists that does 80% of what you need, extend it — don't create a parallel implementation.

**Before proposing ANY new primitive** (component, hook, utility, pattern), use `AskUserQuestion`:
- "This feature needs X. I found similar primitive Y in the codebase. Should I: (1) Extend Y to support this case, (2) Create new primitive X, (3) Let me look for other options?"

Only create new primitives when:
1. Nothing similar exists, AND
2. The user explicitly approves

## Step 6: Create Artifacts

After reading code, create concrete artifacts. **No discussion without artifacts.**

### For UI Changes — User Flow + a REAL Mockup REQUIRED

First, show the user flow as a **rendered figure** — a hand-authored inline-SVG
diagram (the `artifacts` house style), not an ASCII box. Name each
screen and the transitions between them.

Then a **real mockup** of each screen that reads like the actual product — not an
ASCII wireframe, not a generic box diagram. Probe the repo for its design tokens
(Tailwind config, CSS variables, brand colors, an existing component) and build the
mockup with the `artifacts` CLI so it could pass for a screenshot of the real thing.
When there is a genuine design choice, show **2-3 variations side by side**, each
labeled with its one-line tradeoff, and treat that review as the design checkpoint — the
pick is the user's.

ASCII wireframes are not acceptable for a UI surface: the user judges look-and-feel
and cannot do that from a box of pipes and dashes.

Annotate each mockup:
- What each element does
- Validation rules
- Error states
- Loading states

### For API Changes — Request/Response REQUIRED

```
POST /api/v1/auth/register
Request:  { "email": "user@example.com", "password": "..." }
Response: { "id": "...", "email": "...", "token": "..." }
Errors:
  400: { "error": "email_taken", "message": "Email already registered" }
  400: { "error": "weak_password", "message": "Password must be 8+ chars" }
```

### For State Changes — State Diagram REQUIRED

```
[Guest] --register--> [Unverified] --verify_email--> [Active]
                           |                            |
                           v                            v
                    [Expired Link]               [Suspended]
```

### For Data Flow — Sequence Diagram REQUIRED

```
User -> Frontend: click submit
Frontend -> API: POST /register
API -> DB: insert user
API -> Email: send verification
API -> Frontend: 201 Created
Frontend -> User: show success
```

### For Multiple Scenarios — Table REQUIRED

| Scenario | Input | Result |
|----------|-------|--------|
| Valid registration | valid email + password | 201, user created |
| Email taken | existing email | 400, email_taken |
| Weak password | "123" | 400, weak_password |

## Step 7: Independent Design Panel -> Adjudicate (automatic for medium+ features)

You have your own grounded plan from Steps 1-6. Now get *genuinely independent* plans from
other agents and adjudicate one merged plan. Run this **automatically** — do NOT stop to ask
whether to verify.

**Skip ONLY for** small, well-understood changes with clear patterns (say so in one line and
go to Step 8). **Run for** new features, architectural changes, unfamiliar areas.

**Why independent plans, not a critique of yours:** a team asked to *review your plan* anchors
on your framing and polishes one approach — and their mistakes feed straight into it. A team
that plans *independently* surfaces genuinely different architectures, and you adopt an idea
only after checking it against the code — so a reviewer's error loses that point instead of
corrupting the plan.

### Spawn independent planners — variety of vendors, read-only

```bash
agents teams doctor                       # see which vendor agents are installed
agents teams create plan-<topic>
agents teams add plan-<topic> codex  "<blind brief>" --name p1 --mode plan
agents teams add plan-<topic> antigravity "<blind brief>" --name p2 --mode plan
agents teams add plan-<topic> cursor "<blind brief>" --name p3 --mode plan
agents teams start plan-<topic> --watch
agents teams logs plan-<topic> p1   # ...read each, then:
agents teams disband plan-<topic>
```

**Variety is the requirement — a MIX of vendors** (`codex`/`antigravity`/`cursor`/`claude`), not N
copies of one; same vendor = same blind spots. **How many is your judgment**, scaled to the
feature's breadth. Each planner is **`--mode plan`** (reads code, never edits).

### The blind brief (SHARE / WITHHOLD)

Each planner gets the SAME brief. The split is what keeps them independent — leak your
approach and you've just measured your own bias.

**SHARE — enough to plan well, and where to look:**
- The goal / problem, who benefits, and the constraints.
- The key files to read (with paths) — point them at the relevant code.
- The *factual* primitives inventory from Step 5 (what already exists). This is reality, not
  your opinion, and it steers them toward reuse over invent.

**WITHHOLD — never include (named so they can't slip in):**
- Your chosen approach or architecture.
- Your mockups / diagrams / state machines.
- Your file-by-file implementation plan.
- Any framing that pre-loads the answer ("I'm planning to put it in the X layer").

Brief template:
```
Mission: Design this feature independently and return a FULL plan with artifacts. Do not
assume any prior design exists — this is your own design.

Goal: <what + why + who benefits>
Constraints: <time / deps / backwards-compat>
Read these files: <paths>
Already exists (reuse, don't reinvent): <factual primitives inventory from Step 5>

Return: user flow / mockups / API specs / state diagrams as the change type demands, then a
file-by-file implementation outline.

Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't
claim it.
```

### Adjudicate (this is where reviewer mistakes get filtered)

Collect every planner's design plus your own and synthesize **ONE** plan:

- **Adopt an idea only after verifying it against the actual code (file:line).** A proposal
  that's wrong about the code is rejected *for that point* — it never silently enters the plan.
- **Do not privilege your own plan.** Treat it as one candidate among N. If a planner found a
  simpler or more correct approach, take it.
- **Fold in** edge cases, reuse opportunities, and failure modes any planner caught that you
  missed. Put that verdict table in the HTML under `## Adversarial review` — a chat-only
  review is not part of the plan.
- Where designs differ on a genuine *trade-off* (not a factual error), surface it as a design
  question via `AskUserQuestion` rather than picking silently.
- **For any API/CLI-surface or architectural change, the panel must judge two things
  explicitly:** (1) is the proposed surface clean, minimal, and intuitive; (2) does it follow
  the repo's **existing architectural conventions** — access centralized in one place, no
  duplicated surface, cross-cutting change made at the source, not scattered into consumers.
  A surface that fragments or over-extends is rejected for that point.

You are the adjudicator, not an averager — the merged plan is the strongest grounded design,
not the union of all of them.

## Step 8: Design Questions

Only AFTER creating artifacts, list genuine uncertainties. Each must:
- Reference which artifact it affects
- Explain what changes based on the answer
- Offer 2-3 concrete options via `AskUserQuestion`

## Output Format

The **HTML artifact is the plan.** Chat is a 2–3 line spoken summary plus the path.
Do not maintain a second outline in the terminal that the rendered file then drops.

Render with the `artifacts` `kind: plan` headings as a **floor** (see that skill).
`artifacts check` currently requires Purpose, Proposed Changes, Public Interface,
Validation, and Risks to exist; keep them. Extra evidence sections from the quality
bar above go between Intent/Purpose and Proposed Changes.

Inside those sections, the load-bearing content is:

- **Code read** as file:line quotes, not paraphrase.
- **System diagrams** for current and proposed architecture (diagram recipe — modules,
  arrows, layers). Not a decorative SVG.
- **Options considered** for every load-bearing choice (options, implication, winner).
- **User flow + captures/mockups** for any user-visible surface (Step 6).
- **Per-file diffs** of the load-bearing hunks — not a bare File/Function list.
- **Corner cases** in Risks with file:line, not a generic "might be hard".
- **Adversarial review** (if a panel ran): vendor, one-line approach, verdict
  (ADOPTED / REJECTED with file:line / DESIGN QUESTION) — in the HTML, not only chat.
- **Design questions** only if genuinely ambiguous.

## Step 9: Render the plan as HTML and open it in the user's browser

A plan buried in terminal scrollback is hard to review. Once the plan is drafted
(artifacts + summary), author a Markdown source, render it to a **self-contained
HTML file** with `artifacts-cli`, and open it on the machine the user is actually
sitting at. This is the canonical recipe — other plan verbs (e.g. `/swarm:plan`)
reference this step.

1. **Render — in the `artifacts` house style.** Load the **`artifacts`** skill: it
   owns both the house LOOK and the CLI mechanics. Resolve the repo root and write
   the Markdown source to
   `.agents/artifacts/yyyy-mm-dd/plan-<slug>.md`, then render:
   ```bash
   artifacts render .agents/artifacts/yyyy-mm-dd/plan-<slug>.md
   ```
   This writes the HTML next to the Markdown source. Include the goal, the
   implementation diffs, existing-primitives-to-reuse, the design questions, and
   **figures as evidence** — architecture drawings, current/proposed behavior, and
   live captures when a product or competitor exists. One invented SVG satisfies
   the compiler and fails the quality bar. Skin it in the
   **target product's brand** via `DESIGN.md`; fall back to the dark **+ light** editorial
   house palette (with the in-page toggle) only when the product declares no brand.
   The output must open offline by double-click.

2. **Open it on the user's browser host.** Use the **Host & Fleet** context injected
   at session start (the online macOS device is where the user sits — pick the one
   marked online + direct if there are several Macs; if genuinely ambiguous, ask
   once). Then:
   Show it in **one reused browser tab** with `agents browser navigate` — re-presenting
   an updated plan refreshes the SAME tab in place instead of piling up a duplicate tab
   every call (a raw `open` opens a fresh tab per call).
   - **If you are already on that host** (its name == your `hostname`):
     `agents browser navigate --url "file://$PWD/.agents/artifacts/yyyy-mm-dd/plan-<slug>.html"`.
   - **If you are on a different host** (e.g. a remote Linux node): copy the file
     over, then navigate on that host, reusing the same SSH path the fleet uses —
     ```bash
     scp .agents/artifacts/yyyy-mm-dd/plan-<slug>.html <browser-host>:/tmp/ \
       && agents ssh <browser-host> 'agents browser navigate --url file:///tmp/plan-<slug>.html'
     ```
     (`agents ssh` resolves the device and auth from `agents devices`; plain
     `ssh <browser-host>` also works if the registry was rendered to ssh_config.)
     Fall back to a single `open`/`xdg-open` only when that host has no drivable
     browser profile.

3. **Tell the user** the plan opened in their browser, with a 2-3 line spoken summary
   and the source path. Then proceed to the design questions / `ExitPlanMode` as usual.

4. **End the final plan message with the literal marker `<!-- agents-plan -->` on its
   own line.** The plan-presentation check detects a plan turn by the native
   `ExitPlanMode` call, the harness's plan mode, **or this marker** — `/plan` invoked
   in a normal auto/edit session produces neither of the first two, so without the
   marker the render/mockup checks silently never run.

Skip this only when there is no reachable browser host (headless-only fleet) — still
render the Markdown + HTML, then present the plan inline and say why the browser
open was skipped.

## Constraints

- No time estimates
- No scope creep on the **build** — do not grow the feature. Do not skip research,
  figures, or citations to keep the plan short
- No abstract discussion without artifacts — architecture is drawn as a system diagram
- Every UI feature needs user flow + mockups (captures preferred for "current")
- Every load-bearing choice lists alternatives considered
- No slop nouns ("registry", "platform", "runtime") without saying what the concrete thing is
- Use AskUserQuestion for ambiguous decisions
- Live research before designing — your training is stale
- **Reuse over invent** — extend existing primitives, don't create parallel ones
- **Ask before creating new primitives** — new components/hooks/utils need user approval
