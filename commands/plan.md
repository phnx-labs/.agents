---
description: Plan with grounded design — research, read code, create artifacts, optionally get early review
---

You are planning: $ARGUMENTS

## CRITICAL: Ground the Plan in Reality

Plans fail when they're based on assumptions instead of evidence. Before proposing anything:
1. Research current best practices and APIs
2. Read the actual code that will change
3. Create concrete artifacts (mockups, diagrams)
4. For medium+ work, get independent plans from a vendor-varied panel and adjudicate one
   merged plan against the code (Step 7)

## Step 1: Understand the Request

Before reading any code, clarify:

1. **What is the user asking for?** — Restate in your own words. If ambiguous, use `AskUserQuestion` with 2-3 interpretations.
2. **What is the goal?** — What problem does this solve? Who benefits?
3. **What is the scope?** — New feature, refactor, bug fix, or integration?
4. **What are the constraints?** — Time, dependencies, backwards compatibility?

## Step 2: Research Current State-of-the-Art

**Do NOT skip this.** Your training data is stale. Before designing, web search for:

- Current best practices for this type of feature (anchor with current year)
- API documentation for any libraries or services involved
- Common pitfalls or anti-patterns others have hit
- Recent changes to frameworks or APIs the code uses

Examples:
- "Next.js 15 app router authentication patterns 2026"
- "Stripe subscription API best practices 2026"
- "React Server Components data fetching 2026"

Extract 2-3 key insights that should inform the design. If an API has changed or a better approach exists, the plan should reflect that.

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

### For UI Changes — User Flow + Mockups REQUIRED

First, show the user flow:
```
[Landing] --click "Sign Up"--> [Registration Form] --submit--> [Email Verification]
                                      |                              |
                                      v                              v
                               [Validation Error]            [Welcome Screen]
```

Then, ASCII mockup for each screen:
```
+----------------------------------+
| Logo                    [Login]  |
+----------------------------------+
|                                  |
|     Create your account          |
|                                  |
|  Email:    [                  ]  |
|  Password: [                  ]  |
|                                  |
|        [Create Account]          |
|                                  |
|  Already have an account? Login  |
+----------------------------------+
```

Annotate:
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
agents teams add plan-<topic> gemini "<blind brief>" --name p2 --mode plan
agents teams add plan-<topic> cursor "<blind brief>" --name p3 --mode plan
agents teams start plan-<topic> --watch
agents teams logs plan-<topic> p1   # ...read each, then:
agents teams disband plan-<topic>
```

**Variety is the requirement — a MIX of vendors** (`codex`/`gemini`/`cursor`/`claude`), not N
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
  missed.
- Where designs differ on a genuine *trade-off* (not a factual error), surface it as a design
  question via `AskUserQuestion` rather than picking silently.

You are the adjudicator, not an averager — the merged plan is the strongest grounded design,
not the union of all of them.

## Step 8: Design Questions

Only AFTER creating artifacts, list genuine uncertainties. Each must:
- Reference which artifact it affects
- Explain what changes based on the answer
- Offer 2-3 concrete options via `AskUserQuestion`

## Output Format

### Research
What you learned from web search. Key insights that inform the design.

### Codebase Audit
Files read with line numbers. How they connect.

### Existing Primitives
Components, hooks, utilities, patterns to reuse. What each provides.

### Feature: [Name]

**Code Read:** file:line quotes of relevant code

**User Flow:** (for UI features)
[Flow diagram showing screens and transitions]

**Artifacts:**
[Mockups, API specs, state diagrams — MANDATORY]

**Implementation:**
- File: path/to/file.ts
  - Function: existingFunction() — modify to add X
  - New function: newFunction() — does Y

**Design Questions:** (only if genuinely ambiguous)

### Independent Plans (if a panel was spawned)
For each independent planner: vendor, the approach it proposed in one line, and the verdict —
ADOPTED (what was taken), REJECTED (what was discarded *and why* — flag anything contradicted
by the code with file:line), or DESIGN QUESTION (a genuine trade-off surfaced to the user).
Note what the panel caught that your own plan missed.

### Summary

| Feature | Files Modified | New Functions | Complexity |
|---------|----------------|---------------|------------|
| ... | ... | ... | Low/Med/Hi |

## Step 9: Render the plan as HTML and open it in the user's browser

A plan buried in terminal scrollback is hard to review. Once the plan is drafted
(artifacts + summary), render it as a **self-contained HTML file** and open it on
the machine the user is actually sitting at. This is the canonical recipe — other
plan verbs (e.g. `/swarm:plan`) reference this step.

1. **Render — in the `plan-render` house style.** Load the **`plan-render`** skill and
   write one self-contained `.html` (inline CSS, no CDN) to `/tmp/plan-<slug>.html`,
   starting from its `template.html` (`example.html` is the gold reference). Include the
	   goal, the implementation table, existing-primitives-to-reuse, the design questions, and
	   **≥1 visual figure** (Dither Kit for quantitative charts; hand-authored inline SVG for
	   timeline / architecture / before-after diagrams — not mermaid). Skin it in the
	   **target product's brand** (design tokens → tailwind → logo);
   fall back to the dark **+ light** editorial house palette (with the in-page toggle) only
   when the product declares no brand. It must open offline by double-click.

2. **Open it on the user's browser host.** Use the **Host & Fleet** context injected
   at session start (the online macOS device is where the user sits — pick the one
   marked online + direct if there are several Macs; if genuinely ambiguous, ask
   once). Then:
   - **If you are already on that host** (its name == your `hostname`):
     `open /tmp/plan-<slug>.html` (macOS) / `xdg-open` (Linux).
   - **If you are on a different host** (e.g. a remote Linux node): copy the file
     over and open it there, reusing the same SSH path the fleet uses —
     ```bash
     scp /tmp/plan-<slug>.html <browser-host>:/tmp/ \
       && agents ssh <browser-host> 'open /tmp/plan-<slug>.html'
     ```
     (`agents ssh` resolves the device and auth from `agents devices`; plain
     `ssh <browser-host>` also works if the registry was rendered to ssh_config.)

3. **Tell the user** the plan opened in their browser, with a 2-3 line spoken summary
   and the temp path. Then proceed to the design questions / `ExitPlanMode` as usual.

Skip this only when there is no reachable browser host (headless-only fleet) — fall
back to presenting the plan inline and say why.

## Constraints

- No time estimates
- No "nice to have" additions
- No abstract discussion without artifacts
- Every UI feature needs user flow + mockups
- Use AskUserQuestion for ambiguous decisions
- Web search before designing — your training is stale
- **Reuse over invent** — extend existing primitives, don't create parallel ones
- **Ask before creating new primitives** — new components/hooks/utils need user approval
