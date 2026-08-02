---
description: Summarize the current situation — facts first, hypotheses with grounding
---

You are creating a recap of: $ARGUMENTS

Your goal is to summarize the current state of work for handoff or continuity.

## Gather Facts

Start by identifying what is objectively known:
- What was the original goal or problem?
- What concrete steps have been taken?
- What files were modified, created, or deleted?
- What tests were run and their results?
- What errors or unexpected behavior occurred?

Facts must be verifiable. File changes are facts. Test results are facts.
"It seems like X" is not a fact.

## Identify Open Questions

What remains unclear or unresolved?
- Bugs not yet root-caused
- Decisions not yet made
- External dependencies with unknown status
- Edge cases not yet tested

## Ground Hypotheses

If you have hypotheses about what's happening or what should happen next,
explicitly ground them in evidence:

BAD: "The bug is probably in the auth module"
GOOD: "The bug may be in auth module because: (1) error occurs after login,
(2) auth.ts:45 logs 'token expired' before the crash, (3) no errors in other modules"

Every hypothesis needs evidence. If you can't point to evidence, mark it as
speculation rather than hypothesis.

## Output

### Situation
What was the goal? What's the current state? One paragraph max.

### Completed
Bullet list of concrete work done. Include file paths where relevant.

### In Progress
What's currently being worked on but not finished.

### Blocked / Open Questions
What can't proceed without more information or decisions.

### Hypotheses
For anything uncertain, state the hypothesis and the evidence supporting it.
Format: "[Hypothesis]: [Evidence 1], [Evidence 2], ..."

### Recommended Next Steps
Concrete actions to take next. Prioritize by impact.

**HARD RULE 1 — Check before you list.** Do not list anything you could verify or execute yourself right now. Before writing a bullet, ask:

- "Can I check this myself?" → check it, fold the answer into the recap, don't list it.
- "Can I do this myself?" → do it first, then list what's left, not what you just completed.
- "Does this already exist?" → query the relevant system (your monitoring stack, issue tracker, repo, database, filesystem) before suggesting someone build it.

If a step reads like "go look at X" or "check if Y exists" — delete it and go look yourself before writing the recap.

**HARD RULE 2 — Spawn a team for multiple clear tasks.** If 2+ items remain that have clear requirements and are obviously actionable (switching a config, writing a dashboard panel, running an investigation script), do NOT list them for the user. Kick off an `agents teams` run — it's async, you're not blocked, and the work starts immediately.

Pattern:

```bash
agents teams create <topic-slug>
agents teams add <topic-slug> claude "Specific task 1 with full context" --name task1
agents teams add <topic-slug> codex "Specific task 2 with full context" --name task2
agents teams start <topic-slug>
```

Only keep items in "Recommended Next Steps" that genuinely need the user's input, credentials, judgment, or authorization (payments, public posts, destructive ops, ambiguous decisions). Everything else — spawn a team, mention the team name in the recap, move on.

"Top up credits on my logged-in browser" → user step. List it.
"Query the database to check X" → do it yourself. Don't list it.
"Build 3 dashboard panels + run a config sweep across N files + investigate a UUID" → spawn a team. Don't list it.

**No wastebasket bullets. Finish trivial loose ends yourself; make low-stakes decisions and note them, use `AskUserQuestion` only for genuine ambiguity.**

A "wastebasket bullet" is anything in Recommended Next Steps that (a) you could just execute, or (b) is a tiny decision you're punting instead of reasoning about and proposing options. Both waste the user's time. Before writing the recap, walk the entire session and close these out.

**Execute first, don't list:**

Anything mechanical that the session's work implies as finishing touches — do it, then land it in "Completed" with the concrete artifact (commit hash, closed issue ID, removed file, updated state). Examples of what this covers (non-exhaustive — the principle is the point, not the list):

- Uncommitted work in the tree (whether from this session or a parallel agent's session) → inspect the diff of every changed file, group related changes into logical commits by concern, then commit + push per the project's `/commit` command (conventional, <72 chars, single line, no co-author trailer). Another agent's uncommitted work is still yours to land — don't leave it dangling.
- Completed tickets that the session clearly finished → close them via `/tickets` (or the project's tracker skill / CLI directly). Post a short completion comment linking to the commit/PR.
- Satisfied TODOs or in-session task checklists → mark done in their source file.
- Stale branches, dead feature flags, leftover `.tmp` files that the session's work makes obsolete → remove them.
- Tests you wrote but didn't run → run them. Report counts.
- Builds/installs implied by code changes → run them, report the output version.

If it has a deterministic answer and you have the tools to execute it, you execute it. Period.

**Decide-or-delegate pattern for small choices:**

If an item reads like "Decide when to X", "Figure out whether Y", "Pick a name for Z" — that's you punting. Instead:

1. Reason from the conversation: propose a concrete recommendation + 1-2 alternatives.
2. Surface it via `AskUserQuestion` with clickable options (first option = your recommended default with "(Recommended)" suffix). Include a one-line rationale per option.
3. If the answer is genuinely unclear from context AND has medium+ blast radius, pause the recap and ask before finalizing. If it's low-stakes, make the call, note it briefly in the recap, and move on.

Never ship a recap with a bullet like "Decide X", "Consider Y", "Think about Z". Those are micro-decisions, not recommendations.

**Only these survive in Recommended Next Steps:**

- Actions requiring the user's credentials, judgment on strategy, personal accounts, or clicks you can't make (UI smoke tests, browser logins, physical devices, payments, public posts).
- External waits whose status you already verified (e.g. "PR #892 is open for review — awaiting human review").
- Ambiguous decisions where `AskUserQuestion` isn't enough because the context is too open (e.g. product direction, roadmap priority).

**Carveouts for auto-commit** (and only these):
- Files with potential secrets (`.env`, credential blobs, API keys, private keys) → flag, do not stage.
- Obviously `.gitignore`-worthy local files (IDE scratch files, OS metadata, local caches) → mention once, do not stage.
- Diffs you genuinely cannot make sense of after reading them → ask via `AskUserQuestion` ("this looks like it belongs to feature X, commit as Y?") rather than guessing.

The test: every bullet you're about to write in Recommended Next Steps — ask "did I try to execute this?" and "could I have posed this as an AskUserQuestion with 2-3 concrete options instead?" If either answer is yes, the bullet doesn't belong in the recap.
