---
name: review
description: "Review session PRs, named PRs, or a repository. Independent evidence-based review and delivery for PR modes; read-only ranked findings for repo/path scans."
argument-hint: "[empty=session PRs | #PR [#PR...] | repo | <path> | --commits N | --since <date> | --branch] [--single|--team] [--security] [dry-run|no-merge]"
allowed-tools: Bash(gh *), Bash(git *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(wc *), Bash(jq *), Bash(agents *), Bash(go vet*), Bash(tsc*), Bash(staticcheck*), Bash(gocyclo*), Bash(biome*), Bash(shellcheck*), Bash(mcporter*), Bash(printenv*), Bash(sqlite3*), Bash(bun*), Bash(./*/scripts/sandbox.sh*), Bash(open*), Bash(xdg-open*), Bash(mkdir*), Bash(rush *), Read(*), Write(*), Edit(*), Agent(*)
user-invocable: true
---

# code:review

Review against the intended outcome and the repository's conventions. Findings need
quoted file/line evidence and a concrete failure or violated contract. Explain the
implication clearly; speculative style preferences and unrelated pre-existing defects
are not blockers for the change.

## Modes

| `$ARGUMENTS` | Scope and action |
|---|---|
| Empty | Discover this session's PRs, review them, and carry owned work through delivery in dependency order. |
| PR number(s) | Review those PRs against their requirement and act on the verdict within authorized ownership. |
| `repo`, path(s) | Read-only architecture and quality scan of tracked files in scope. |
| `--commits N`, `--since <date>`, `--branch` | Read-only scan of the selected changed-file scope. |

`dry-run` reports the proposed review/merge actions without posting, editing, merging,
or closing. `no-merge` performs review and may post findings but does not merge or close.
These modifiers apply to both PR modes. `--single` / `--team` select PR review dispatch;
`--security` requests the security pass; `formal-review` permits a formal changes-requested
review rather than a comment. Repo mode never changes code, opens tickets, or issues a
merge verdict; it may write its report in the authorized artifact workspace.

## Independent PR review

Resolve fresh PR heads, base branches, acceptance criteria, related tickets/plans, and
relevant existing work. In session mode, establish which PRs this session actually owns;
a shared GitHub author or recent timestamp alone does not prove ownership. For stacked
PRs, preserve dependency order and reassess the next head after its base changes.

Use the repository's configured non-author reviewer when it is working. Otherwise spawn
`code-reviewer`, whose canonical rubric is
[`subagents/code-reviewer/AGENT.md`](../../../../subagents/code-reviewer/AGENT.md).
On a harness without named subagents, give that same definition to an independent
review agent through the available dispatch mechanism; do not maintain a fallback rubric.
If independent review is unavailable, record the blocker rather than self-reviewing.

The brief carries the requirement, exact revision, relevant canonical patterns, and
scope. Reviewers read the actual diff and affected callers, tests, and sibling paths.
Scale parallel review to independent areas and risk using `run` or `teams`; the author
never supplies their own non-author verdict. A non-author verdict must be posted on the PR.

For security-sensitive changes, include a focused security pass. Trace untrusted input
to the sink and check existing controls before reporting a vulnerability; verify current
advisories against the actual affected dependency/version/path. Use a security skill
only when its described capability matches the job. A separate reviewer is useful when
security warrants independent attention; `--security` always includes this pass.

## Verdict and action

Use the canonical reviewer's verdict: READY TO MERGE, CHANGES REQUESTED, or BLOCKED.
Publish concrete findings on relevant diff lines where possible, with the overall verdict
and findings outside the diff in the review body. Preserve findings if inline posting
fails. [PR posting reference](pr-posting.md) documents the API format.

For owned work, fix findings, obtain the required updated review, and merge only when
required CI is green and the repository's non-author review requirements are satisfied.
A local test log does not replace required CI. Follow the repository's merge method;
never self-approve or bypass a guard. For someone else's active branch, coordinate fixes
instead of rewriting it unilaterally. A review-only request remains review-only.

Close a duplicate only when its complete intended result is already accounted for and
closing is within the authorized scope; overlapping files alone do not prove duplication.
Respect `dry-run` and `no-merge`. Check the resulting PR state, not merely command exit.
For distributables, continue through the canonical release and installed/live verification
when delivery is authorized; distinguish merged from shipped in the report.

## Read-only repository scan

Inspect architecture, code health, documented invariants, identifiers, and repeated
responsibilities where relevant. Existing helper scripts and their data contract are in
[scan-tools.md](scan-tools.md); select passes that can answer the scoped question.
Tool output is candidate evidence: a grep hit, missing local tool, or similar function
signature alone does not prove a defect. Validate findings, remove false positives,
and report skipped checks or incomplete coverage honestly.

Produce a readable, ranked report with evidence and practical fixes. Use the existing
interactive HTML renderer for larger scans; emphasize relationships visually when a
system map or comparison explains a finding better than a list. Follow `artifacts` and
`browser` for rendering, visual read-back, and delivery on the user's viewing device.
Keep findings as findings until execution is selected; clipboard actions are drafts,
not authorization to create tickets.

Report the important findings and the actual review/delivery stage with links to evidence.
For changed UI behavior, inspect the real surface using `browser` or `computer` before
claiming it works; a build or screenshot of source code is not behavioral evidence.
