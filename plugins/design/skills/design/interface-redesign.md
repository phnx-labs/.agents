# design:interface — redesign path

For redesigning screens, features, or flows that already exist. Load this after
`design-core.md` and `interface.md`; the workflow here replaces step 5 of the
interface loop.

## When this path applies

The user is unhappy with an existing screen, wants to improve it, or hands you a
screenshot and asks for a better version. The screen already exists; the job is
diagnosis and deliberate options — not immediate implementation.

## Step 1: Audit the current screen

If the user provided a screenshot, read it carefully. Study every element.

For the screen as a whole, work through:
1. What is the single most important action on this screen?
2. What is noise — elements that do not serve that action?
3. What is the information hierarchy? Does the visual weight match the importance?
4. Is anything unnecessarily complicated or duplicated?

Write down a specific diagnosis: name each problem by type — hierarchy, contrast,
density, copy, consistency — not just "it looks bad". Be precise.

Also check internal consistency before looking outward:
- Read `AGENTS.md` or `CLAUDE.md` for any declared design language.
- Scan neighboring screens in the repo for the patterns they use.
- Note discrepancies: "The main app uses pattern X but this screen uses Y instead."

## Step 2: BEFORE diagram (mandatory)

Draw the current screen accurately as ASCII art, then list the diagnosed problems
below it:

```
BEFORE: [Screen Name]
+------------------------------------------+
|  ...exact layout of current screen...   |
+------------------------------------------+

Problems:
- [hierarchy] ...
- [contrast] ...
- [density] ...
```

The BEFORE diagram must exist before any AFTER proposal is drawn. It is the
reference the comparison table is measured against.

## Step 3: AFTER proposals (exactly 2-3 options, mandatory)

Propose 2-3 distinct approaches. Each must represent a genuinely different design
philosophy — not minor color or spacing tweaks. For each option:

```
OPTION A: [Name] — [One-line philosophy]

+------------------------------------------+
|  ...complete screen layout...            |
+------------------------------------------+

Why this works:
- Solves [problem] by [approach]
- Feels [quality] because [reason]

Data needed: [what this option requires that may not exist today]
```

Every option must show the full screen. Realistic content — not "Lorem ipsum".

## Step 4: Comparison table (mandatory)

| Aspect | Option A | Option B | Option C |
|--------|----------|----------|----------|
| Solves main pain? | | | |
| Personality / warmth | | | |
| Implementation effort | Easy / Medium / Hard | | |
| Data requirements | | | |
| Risk | | | |

Fill every cell. A blank cell is not a valid answer.

## Step 5: STOP — wait for the user's pick

After presenting the BEFORE diagram, all options, and the comparison table: **stop**.
Do not implement. Do not pick an option. Do not begin writing code or HTML.

Wait for the user to:
- Pick one option, or
- Ask for modifications, or
- Request a hybrid.

If the user wants to combine elements from different options, sketch the hybrid as a
new ASCII diagram before proceeding to implementation.

## Constraints

- Every proposal must have a full ASCII diagram showing the complete screen.
- Do not propose more than 3 options or fewer than 2.
- Do not add features that were not asked for.
- Do not skip the BEFORE diagram.
- Do not discuss implementation details during the design phase.
- Do not start implementing until the user explicitly picks an option.
