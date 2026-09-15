# code plugin

Assess code health, review changes, improve architecture, and preserve useful project
knowledge. Shared delivery and Git workflows live in the [work plugin](../work/README.md).

| Command | Capability | Source |
|---|---|---|
| `/code:review` | Review session/named PRs, or run a read-only repository diagnostic. | [Command](commands/review.md) · [Skill](skills/review/SKILL.md) |
| `/code:health` | Assess human maintainability and reduction opportunities; maintain component-root HEALTH.md and HEALTH.html. | [Command](commands/health.md) · [Skill](skills/health/SKILL.md) |
| `/code:refactor` | Check current code health, then simplify; `quality` scopes cleanup and `--scan-only` stays read-only. | [Command](commands/refactor.md) · [Skill](skills/refactor/SKILL.md) |
| `/code:learn` | Update durable, non-obvious project knowledge; refine existing workflow guidance when warranted. | [Command](commands/learn.md) · [Skill](skills/learn/SKILL.md) |

The independent review rubric lives in the portable
[`code-reviewer` definition](../../subagents/code-reviewer/AGENT.md), not a plugin-local copy.
On harnesses without named subagents, the review workflow supplies the same rubric to an
independent agent. Review, health, refactor, and learn have portable skills; commands
accelerate access. Use `work:commit` for cohesive commits and `work:loop` for delivery.

Optional Bun helpers support [repository scans](skills/review/scan-tools.md) and
[refactor measurements](skills/refactor/measurement-tools.md); incomplete tool coverage is
reported rather than treated as a clean result. The [PR posting reference](skills/review/pr-posting.md)
and [module comparison example](skills/refactor/reference-figure.md) load when needed.

Review and refactor share [TypeScript and Go guidance](skills/refactor/typescript-go.md)
for package boundaries, types, runtime behavior, library replacements, and meaningful
tests. The [measurement contract](skills/refactor/measurement-tools.md#comparable-code-health-measurements)
keeps source/test counts and duplicate-code candidates reproducible. Refactor proposals
show concrete before/after code and preserve the user's current feature decisions.

Health reports use only `kind`, `title`, `updated`, and `commit` frontmatter. The
[health skill](skills/health/SKILL.md) owns freshness, component-root output and human
maintainability criteria; existing measurements and language guidance are reused.
