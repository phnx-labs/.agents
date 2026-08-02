---
description: Recap the session's goal, list every PR it opened, review each in parallel with anti-overengineering guardrails, then merge / request-changes / close-as-duplicate per verdict.
---

Review the PRs this session produced and decide what ships. Arguments (optional): $ARGUMENTS

- Default: review every PR opened in this session, score against the session's stated goal, act on the verdicts (merge / request changes / close).
- Pass an explicit PR list (e.g. `#412 #413 #414`) in $ARGUMENTS to review only those PRs instead of auto-detecting.
- Pass `dry-run` to print the plan and stop — no comments, no merges, no closes.
- Pass `no-merge` to comment verdicts but never merge (request-changes and close-as-duplicate still execute).

## Do not merge without evidence the thing actually runs

A PR that "looks correct" is not the same as a PR that has been demonstrated to work. Before merging, you must have at least one of:

1. A green CI run on the PR's head SHA (`gh pr checks <pr> --watch=false` shows all required checks passing).
2. A quoted command + output from this session showing the changed code path executing end-to-end (curl response, test run, screenshot, log line — quoted, not paraphrased).
3. An explicit user override for an exceptional case (e.g. the PR is blocked by an external dependency and the user said "ship it" verbatim). "It looks good" does not.

If you have none of those, the verdict is **request-changes**, not merge. State the missing evidence in the PR comment.

See F1–F5 (`rules/subrules/foundations.md`) and the `git-workflow` skill for the full merge-on-green policy.

## No overreview, no overengineering pressure

The review subagents you spawn are NOT here to find every possible improvement. They are here to answer **five questions** and stop:

1. **Goal:** Does this PR meet the stated session goal it was opened for? (Quote the goal. Quote the diff lines that satisfy it.)
2. **Evidence:** Is there proof the changed path actually runs? (CI green, test output, curl response, screenshot — quote it.)
3. **Quality:** Is the code reasonable? (No dead branches, no obvious bugs, no copy-paste duplication.) "Reasonable" is the bar — not "perfect."
4. **Cleanup:** Does the PR remove what it replaces, or does it leave the old thing alongside the new thing? Parallel implementations are a defect.
5. **Scope:** Did the PR stay in its lane, or did it sprawl into unrelated refactors / renames / formatting passes?

That is the entire rubric. Things subagents must NOT comment on:

- Style nits already enforced by lint/format (the linter is the source of truth — don't relitigate).
- Hypothetical future requirements ("what if we later want…?"). YAGNI applies to reviews too.
- Naming preferences absent a concrete confusion the name causes.
- Test coverage for trivial guards / constants — only flag missing tests where the code path has real branching or state risk.
- Suggestions to add abstractions, helpers, factories, interfaces, base classes "for flexibility." Three similar lines is fine.
- Documentation suggestions unless the PR introduces a user-facing surface that has no docs at all.

The output of each subagent is a **terse verdict** with file:line evidence, not an essay.

## Process

### 1. Recap — what was the session trying to do?

Reconstruct the session's intent before looking at any PR. The recap must be grounded — no paraphrase, no invention.

Sources (use all that apply):

- The user's first substantive message in this conversation — quote the goal verbatim.
- Any plan that was confirmed (look for `ExitPlanMode` content, or a "let's do X, Y, Z" the user explicitly approved).
- Linear ticket(s) opened or referenced — `gh issue view` / linear context from the session-start hook.
- `agents teams` distribution plan if one was used (boundary contracts name the goal per teammate).

Present the recap as:

```
Session goal: <one or two sentences, quoted or tightly paraphrased>
Confirmed by:  <message timestamp or "plan approved at <step>" or "linear PROJ-XXX">
Subgoals:
  - <subgoal 1>          → expected surface: <files/dirs>
  - <subgoal 2>          → expected surface: <files/dirs>
```

If you can't ground the goal in something the user said in this session, STOP. Ask via `AskUserQuestion` for the goal in one sentence before continuing. Reviewing without a goal is theater.

### 2. Discover the PRs this session opened

Run in parallel:

```bash
gh pr list --author "@me" --state open --limit 50 --json number,title,headRefName,baseRefName,createdAt,url,isDraft,mergeable,mergeStateStatus,statusCheckRollup
gh pr list --state open --limit 50 --search "in:title $(date -u +%Y-%m-%d)" --json number,title,headRefName,baseRefName,createdAt,url
git log --oneline --since="6 hours ago" --all
git branch -a --sort=-committerdate | head -40
```

Build a candidate set from:

- PRs whose `createdAt` is inside this session's window.
- PRs whose head branch matches a branch this session created (cross-check against `git reflog` + recent branches).
- PRs explicitly named in `$ARGUMENTS` (these override the auto-detect — review exactly that set).
- PRs opened by an `agents teams` run started in this session (check `agents sessions --active` for live teammates, or `agents sessions focus <id>` to reattach to a live session).

If the result is empty, say so and stop — "No PRs opened in this session to review."

### 3. Build the dependency graph (detect stacked PRs)

For each candidate PR, record `{number, title, head, base, author, draft, ci_state, mergeable, url}`. Then construct the stack graph:

- If PR B's `baseRefName` equals PR A's `headRefName`, B is **stacked on** A. Draw an edge A → B.
- If multiple PRs share the same base (e.g., the default branch), they are **independent** — flat list, no edges.
- A chain A → B → C must merge in order A, then B, then C. After A merges, B's base auto-retargets (or needs `gh pr edit <B> --base $BASE` + a rebase, where `$BASE` is the default branch). Document that.

Validate the graph with `gh pr view <n> --json baseRefName,headRefName` for each PR — don't trust the cached list if it's older than a few minutes.

### 4. Present the recap + PR table

Print before launching any subagent. **Use a GitHub-flavored markdown table — not ASCII box-drawing characters.** Box-drawing forces manual column alignment and breaks the moment a title is wider than the placeholder. Markdown tables auto-size, render correctly in Claude Code's UI, and stay readable when the agent's underlying terminal lacks fancy Unicode width support.

```markdown
Session goal: <quoted>

PRs opened this session: N

| PR    | Title                              | Base          | Head            | CI      | Mergeable | Notes               |
|-------|------------------------------------|---------------|-----------------|---------|-----------|---------------------|
| #412  | feat: add oauth refresh            | main          | auth-refresh    | green   | clean     |                     |
| #413  | feat: wire login UI                | auth-refresh  | login-ui        | pending | clean     | stacked on #412     |
| #414  | test: add login flow e2e           | login-ui      | login-e2e       | —       | unknown   | possible duplicate? |

Stack graph:
  main ← #412 ← #413 ← #414     (merge order: 412, 413, 414)

Independents: none.
```

Rules for the table:

- **One row per PR.** Never split a single PR's fields across multiple lines — column counts must be uniform (markdown tables fail silently if a row has fewer/more `|` than the header).
- **Truncate the Title column to ~50 chars max** with an ellipsis if needed — long titles wreck readability even in markdown tables. The PR number is the unambiguous identifier.
- **Keep cell content single-line.** No embedded newlines, no nested tables, no `<br>`.
- **Use the Notes column** for duplicate flags, "stacked on #X", "draft", "conflicts" — not extra rows.
- Empty cells use `—` (em dash) or blank, not `N/A` or `null`.

Flag any PR that looks like a **duplicate** or **already-merged-elsewhere** in the Notes column — confirm with `git rev-list --count <head>..origin/$BASE` and `git log origin/$BASE --grep "<title>"` (where `$BASE` is the default branch) before claiming it.

### 5. Spawn one review subagent per PR — in parallel

Use the `Agent` tool. **One subagent per PR, all dispatched in a single message** so they run concurrently. Always set `model` explicitly — `"sonnet"` is the default, reserve `"opus"` only for genuinely load-bearing reasoning (auth, billing, migrations). Never let it default.

Each subagent gets this brief — fill in the bracketed parts:

```
Mission: Review PR #<N> and return a terse verdict.

Session goal (the WHY this PR exists): "<quoted session goal>"
This PR's stated purpose (from title/body): "<quoted>"
Stacked context: <"depends on #X" | "independent">

Read these:
  - The PR diff:    gh pr diff <N>
  - The PR body:    gh pr view <N> --json title,body,headRefName,baseRefName,statusCheckRollup
  - CI status:      gh pr checks <N>
  - Touched files in full (not just the diff) for any non-trivial change: <list paths from the diff>

Answer EXACTLY these five questions, in this order, with file:line evidence quoted from the diff:

1. GOAL: Does this PR meet the stated session goal it was opened for? Quote the goal. Quote the diff lines that satisfy it. (YES / PARTIAL / NO)
2. EVIDENCE: Is there proof the changed path actually runs? Quote the CI rollup, test output, or any command output from the PR description. (YES / MISSING)
3. QUALITY: Any concrete bugs, dead branches, or obvious defects? Quote file:line for each. ("clean" is a valid answer.)
4. CLEANUP: Does this PR remove what it replaces, or leave parallel implementations? If there's a sibling old path still in the tree, quote it. (CLEAN / DUPLICATES <path>)
5. SCOPE: Did the PR stay in its lane, or sprawl? List any files changed that are outside the stated purpose. (TIGHT / SPRAWL: <files>)

Then give ONE verdict:
  - SHIP — all five answers are good. State why this is safe to merge in ONE sentence.
  - REQUEST_CHANGES — list 1-5 bullet points, each with file:line and the exact change needed. No prose around them.
  - CLOSE_DUPLICATE — the work is already in the default branch (quote the commit) or another open PR (quote the #).

Do NOT propose abstractions, renames, doc additions, test additions for trivial code, naming preferences, or "what if later." Do NOT relitigate lint/format. The bar is "reasonable and meets the goal," not "perfect."

Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.
```

After all subagents return, aggregate the verdicts.

### 6. Show the verdict matrix

```
Verdicts:
  #412  SHIP             — auth refresh complete, CI green, replaces old middleware (deleted src/auth/legacy.go).
  #413  REQUEST_CHANGES  — 3 concrete asks (login-ui session token storage location, missing error handling on refresh, dead import).
  #414  CLOSE_DUPLICATE  — e2e covered by existing tests/login.e2e.ts (commit a97ae40 in main).

Merge plan (stack order):
  1. #412  → merge (rebase)
  2. #413  → after fixes land, re-review; do not merge yet
  3. #414  → close as duplicate of a97ae40
```

If any PR is REQUEST_CHANGES, the stack pauses at that point — do NOT merge anything stacked on top of it.

### 7. Execute the verdicts

Order matters. Do these in sequence per PR; PRs across the stack are processed in stack order (base → tip). If `$ARGUMENTS` contains `dry-run`, print the plan and stop instead.

**7a. SHIP verdict — comment + merge.**

Post a single approval comment that states the safety case in 2-4 lines max — what was checked, the evidence (quoted CI line or curl response), and the cleanup confirmation. Example:

```bash
gh pr comment <N> --body "$(cat <<'EOF'
Reviewed against session goal: <one-line goal>.

Safe to merge:
- Meets goal: <one-line, file:line>
- Evidence: CI green on <SHA> (<check names>) / <curl output if applicable>
- Cleanup: removed <old thing> at <file:line>
- Scope: stayed within <surface>
EOF
)"
```

Then merge. Strategy by default: **rebase** — replay the PR's commits onto the default branch so the granular per-commit history is preserved (this matches the `code:commit` micro-commit philosophy; squashing would throw away exactly the one-concept-per-commit history those commits were authored to create). Only squash when a PR's commits are genuine throwaway WIP ("wip", "fix typo", "address review") that should not land individually. Use `--auto` only if CI is still running.

```bash
gh pr merge <N> --rebase --delete-branch
# squash ONLY when the commits are throwaway WIP, not clean logical units:
# gh pr merge <N> --squash --delete-branch
```

For stacked PRs: after merging the base, the next PR's base auto-retargets on GitHub if it was set to the previous head — but if your tooling didn't enable that, run `gh pr edit <next> --base $BASE` (where `$BASE` is the default branch) and confirm `mergeStateStatus` becomes `clean` before merging the next one.

**7b. REQUEST_CHANGES verdict — comment with concrete asks.**

Bullet points, each `file:line — exact change — why`. No prose, no padding, no "great work overall." Example:

```bash
gh pr comment <N> --body "$(cat <<'EOF'
Blocking, in order:

- app/src/auth/login.tsx:42 — store session token via `setSession()` from auth/session.ts, not `localStorage.setItem('token', ...)`. Plaintext-token-in-localStorage was the bug fixed in PR #401 — this reintroduces it.
- app/src/auth/refresh.ts:18 — the `if (!res.ok)` branch returns without logging; the original handler in auth/legacy.go:88 emits a structured error. Add the same.
- app/src/auth/refresh.ts:3 — `import { unused } from './helpers'` is dead; remove.

Not blocking — leave for follow-up if you want:
- (nothing)
EOF
)"
```

Do NOT auto-request review from the user via `gh pr review --request-changes` unless `$ARGUMENTS` contains `formal-review` — a comment is enough and avoids notification noise. The subagent that produced the verdict is the source of truth; the comment is the artifact.

**7c. CLOSE_DUPLICATE verdict — comment + close.**

Quote the commit or PR that already contains the work, then close.

```bash
gh pr comment <N> --body "Closing as duplicate — this work is already in the default branch as <SHA> (\"<commit subject>\") merged at <date>. The diff between this branch and the default branch is empty modulo whitespace: \`git diff origin/$BASE..<head>\` returns 0 substantive changes."
gh pr close <N> --delete-branch
```

If the duplicate is **another open PR** rather than already-merged work, link both ways:

```bash
gh pr comment <N> --body "Closing in favor of #<other>, which covers the same change and is further along. Continuing the conversation there."
gh pr comment <other> --body "Folded in scope from #<N> (closed)."
gh pr close <N> --delete-branch
```

### 8. Verify and report

After execution, re-query state in parallel:

```bash
gh pr list --state all --search "<the PR numbers we acted on>" --json number,state,mergedAt,closedAt
git fetch --prune origin
```

Report a final table — what merged, what got requested-changes, what closed, what (if anything) failed. For each merge, quote the merge commit SHA. For each request-changes, link the comment URL. For each close, quote the duplicate reference.

If any merge or close failed, do NOT silently move on — print the error, leave the PR in whatever state GitHub returned, and tell the user which one needs hand-resolution.

## Stacked-PR specifics

A stack is a chain `main ← A ← B ← C`. The rules:

- **Review order: leaf-down or root-up — your choice.** Either works; subagents run in parallel anyway. The verdicts come back independent.
- **Merge order: strictly root-up.** A before B before C. Never merge a child before its parent — that creates phantom commits in the child's diff and confuses subsequent reviews.
- **If the base verdict is REQUEST_CHANGES, every PR stacked on top is also blocked.** Mark them `BLOCKED — waiting on #<base>` and do not merge them, even if their own verdict was SHIP.
- **After merging A, retarget B's base to the default branch** if GitHub didn't do it automatically: `gh pr edit <B> --base $BASE`. Then re-check `mergeable` before merging B.
- **If B has merge conflicts after A lands**, do NOT rebase/force-push on the author's behalf without explicit user approval (F5 — protect what you can't undo). Comment on B explaining the conflict and stop the chain.

## Duplicate detection

A PR is a duplicate when one of these is true — verify with a command before claiming it:

1. **Already in default branch:** `git rev-list --count <head>..origin/$BASE` returns the same count as `git rev-list --count <base>..origin/$BASE` (i.e., the head adds nothing). Also confirm with `git diff origin/$BASE..<head> -- <files-changed>` returning empty/whitespace-only.
2. **Squashed-merged elsewhere:** the PR's commit messages or diff are subsumed by a recent default-branch commit. Find it: `git log origin/$BASE --oneline --since="14 days ago" | grep -i "<keyword from PR title>"`. Confirm the diff overlap by hand.
3. **Open elsewhere:** another open PR touches a strict superset of the same files for the same goal. Quote the PR number and the file overlap.

If you cannot run one of these commands and get a definitive answer, the verdict is NOT `CLOSE_DUPLICATE` — fall back to `REQUEST_CHANGES` with "needs human triage: possible duplicate of <SHA/#>".

## Don'ts

- Don't merge a PR whose verdict is REQUEST_CHANGES because it "looks mostly fine." The whole point of the verdict is to stop you.
- Don't merge without one of: green CI, a quoted run, or explicit user override. "I read the diff and it looks correct" is not evidence.
- Don't post review comments that demand abstractions, naming changes, or speculative future-proofing — those are noise that delay merges. The subagent rubric forbids them; the reviewer (you) does too.
- Don't merge stacked PRs out of order.
- Don't force-push, rebase the author's branch, or amend their commits to "help" — that's destructive (F5). Comment and let the author act.
- Don't auto-request formal review (`gh pr review --request-changes`) unless `$ARGUMENTS` contains `formal-review` — a comment is the lighter touch and doesn't ping reviewers redundantly.
- Don't summarize each PR with prose like "Overall this is a solid change that…". Verdicts are terse. Evidence is quoted. That's the whole document.
- Don't propose to stop after the recap. The recap is a checkpoint, not an exit ramp. Continue to the verdict matrix unless `$ARGUMENTS` contains `dry-run`.
- Don't fabricate a session goal because you can't find one. Ask the user in one sentence and continue.
