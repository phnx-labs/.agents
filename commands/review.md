---
description: Alias for /code:review — session PRs by default, PR number(s) for a cold review, or repo/path for a read-only architecture-and-quality scan.
---

**`/review` is an alias of `/code:review`.** There is one review skill, defined once in the
`code` plugin; this is the convenience short name.

Apply the full `/code:review` procedure to `$ARGUMENTS`. In brief, three modes:

- **Default (empty)** — recap the session's goal, discover every PR it opened, review each
  in parallel against a shared rubric (tests / evidence / docs / pattern reuse &
  architecture / messiness / security), then act on the verdicts (merge / request-changes
  / close-as-duplicate). Stack-aware: respects PR dependency/merge order. `dry-run` prints
  the plan and stops; `no-merge` comments verdicts but never merges.
- **`#412`** or **`#412 #413`** — deep sub-agent review of exactly those PRs, cold, with
  the same rubric plus a security pass on risk-touching diffs.
- **`repo`, a path, or `--since "<date>"`** — read-only architecture + code-health +
  context + patterns diagnostic over the whole scope. Emits an HTML report with ranked
  findings; never a merge verdict, never modifies code.

**Never merge without evidence the changed path runs** — green CI on the head SHA
(`gh pr checks <pr>`), a quoted command+output, or explicit user approval. Otherwise the
verdict is request-changes. **No over-review.** The rubric is fixed and stops there — no
style or speculative feedback.

The canonical, authoritative definition (all three modes, the reviewer brief, the security
pass, and the whole-repo diagnostic) lives at the `code:review` skill
(`plugins/code/skills/review/SKILL.md`). Make behavior changes **there**, not here — this
file and `plugins/code/commands/review.md` only forward.
