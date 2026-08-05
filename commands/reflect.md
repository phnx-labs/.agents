---
description: Recall feedback and constraints before rewriting
---

You are reflecting on: $ARGUMENTS

Load the `/reflect` skill to recall all feedback from the current conversation before proceeding.

## When to Use

Before rewriting or revising work:
1. **Collect** — List every piece of feedback, correction, or constraint mentioned
2. **Identify** — Find the pattern or theme
3. **State** — Revise your approach based on the pattern
4. **Execute** — Apply the revised approach

## Preventing Iterative Drift

The most common failure mode: fixing the latest issue while regressing on earlier ones.

Example:
```
Feedback collected:
- "Don't use any CSS frameworks" (Turn 3)
- "Prefer semantic HTML" (Turn 5)
- "Data attributes for JS hooks" (Turn 8)
- "Accessibility matters" (Turn 12)

Pattern: Keep it simple, semantic, and accessible.
Revised approach: Plain HTML, data attributes, ARIA labels.
```

## Rules

- **Read the conversation** — Don't rely on memory of what was said
- **Every constraint matters** — Even offhand comments are requirements
- **Feedback is cumulative** — Apply ALL of it, not just the latest
- **State the pattern** — Don't just list; synthesize

Load the skill for the complete reflection methodology.
