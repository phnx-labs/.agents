---
description: Identify and clean up technical debt, outdated code, and duplicates
---

You are cleaning up: $ARGUMENTS

Your goal is to identify cleanup opportunities, verify them, propose solutions,
and execute the cleanup.

## Scan

Search for cleanup opportunities in this priority order:

1. **Outdated** - Context files (AGENTS.md, README.md, CLAUDE.md) that don't
   match reality. Code paths that are stale but still referenced. These cause
   wrong decisions and bugs.

2. **Near-duplicates** - Two implementations of the same thing that have
   drifted apart. One gets updated, the other doesn't.

3. **Scattered sources of truth** - Same concept defined in multiple places.
   Constants, configs, type definitions that should be centralized.

4. **Complex patterns** - Overly complex code that can be simplified without
   changing behavior.

5. **Dead code** - Unused exports, unreachable paths, functions never called.
   Noise that obscures real code.

6. **Naming/organization** - Confusing names, illogical file organization,
   inconsistent conventions.

## Parallel Scan (Optional)

For large codebases (>50 files), parallelize the scan across areas:

1. Identify major areas: Frontend, Backend, Shared, Docs
2. Create a team with `agents teams create clean-<topic>`
3. Add one teammate per area with the priority list above
4. Start the team and collect findings
5. Synthesize cross-cutting concerns (duplicates spanning areas, scattered configs)

Skip this for small codebases — scan directly yourself.

## Verify

For each finding, verify it's actually an issue. Read the code. Confirm your
claim with evidence. Do not guess.

Evidence examples:
- "AGENTS.md says X but the code does Y"
- "functionA and functionB both implement sorting, but A handles nulls and B doesn't"
- "CONFIG_TIMEOUT is defined in config.go, utils.go, and constants.go"

If you cannot verify a finding, drop it.

## Propose and execute

For each verified finding, propose a concrete fix, then execute it unless it is genuinely ambiguous or risky. Explain what you changed and why. Do not stop for approval on obvious, safe cleanups.

Genuine reasons to pause and surface to the user:
- The finding touches a public API or user-facing behavior and you're unsure of intent.
- Removing code would break a consumer you cannot identify.
- The cleanup spans multiple ownership boundaries.

Everything else — doc drift fixes, dead-code removal, consolidating duplicate helpers, renaming for clarity — you execute directly.

## Output

### Summary
One paragraph. What areas need cleanup and the overall state.

### Completed
What you already fixed, with commit/PR links where applicable.

### Findings

Group by category in priority order. For each finding you acted on or parked:

#### Outdated
**[file or component name]**
- What: description of what's outdated
- Evidence: how you verified this
- Fix: what you changed or removed

#### Near-duplicates
**[the duplicate implementations]**
- What: the two or more implementations
- Evidence: how they've diverged
- Fix: which you kept, how you unified them

#### Scattered Sources of Truth
**[the concept]**
- Locations: where each definition lived
- Fix: where you centralized it, what you removed

#### Complex Patterns
**[file:function or component]**
- What: the complexity
- Fix: how you simplified it

#### Dead Code
**[file or export]**
- Evidence: why it was unreachable or unused
- Fix: removed

#### Naming/Organization
**[the issue]**
- Current: what it was called or where it lived
- Changed: better name or location

### Parked
Findings that genuinely need the user's input, credentials, judgment, or authorization. Include the smallest next step for each.
