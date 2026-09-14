# code plugin

Coding workflows for delivering changes, reviewing code, improving architecture, and
preserving useful project knowledge. Repository policies own merge and release requirements.

| Command | Capability | Source |
|---|---|---|
| `/code:loop` | Deliver one item or a queue; coordinate ownership, verification, review, and release. | [Command](commands/loop.md) · [Skill](skills/loop/SKILL.md) |
| `/code:review` | Review session/named PRs, or run a read-only repository diagnostic. | [Command](commands/review.md) · [Skill](skills/review/SKILL.md) |
| `/code:refactor` | Behavior-preserving structural improvements; `quality` scopes cleanup to a current change. | [Command](commands/refactor.md) · [Skill](skills/refactor/SKILL.md) |
| `/code:learn` | Update durable, non-obvious project knowledge; refine existing workflow guidance when warranted. | [Command](commands/learn.md) · [Skill](skills/learn/SKILL.md) |
| `/code:commit` | Commit and push cohesive changes under repository conventions. | [Command](commands/commit.md) |

The independent review rubric lives in the portable
[`code-reviewer` definition](../../subagents/code-reviewer/AGENT.md), not a plugin-local copy.
On harnesses without named subagents, the review workflow supplies the same rubric to an
independent agent. Commands accelerate access; loop, review, refactor, and learn also
have standalone skills. Commit currently remains command-only on harnesses without commands.

Optional Bun helpers support [repository scans](skills/review/scan-tools.md) and
[refactor measurements](skills/refactor/measurement-tools.md); incomplete tool coverage is
reported rather than treated as a clean result. The [PR posting reference](skills/review/pr-posting.md)
and [module comparison example](skills/refactor/reference-figure.md) load when needed.

Review and refactor share [TypeScript and Go guidance](skills/refactor/typescript-go.md)
for package boundaries, types, runtime behavior, library replacements, and meaningful
tests. The [measurement contract](skills/refactor/measurement-tools.md#comparable-code-health-measurements)
keeps source/test counts and duplicate-code candidates reproducible. Refactor proposals
show concrete before/after code and preserve the user's current feature decisions.
