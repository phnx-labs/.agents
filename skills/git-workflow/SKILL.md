---
name: git-workflow
description: "Run PR-bound work in an isolated git worktree instead of mutating the user's checkout. The full worktree lifecycle — create a branch under <repo>/.agents/worktrees/<slug>/ from the real default branch, implement and verify end-to-end inside it, open a PR, wait for review, then clean up after merge. Use whenever a task will produce a pull request, or when you need to create a branch/worktree. Triggers on: open a PR, create a worktree, PR-bound work, branch for a feature, ship a change as a PR."
argument-hint: "[task-slug]"
allowed-tools: Bash(git*), Bash(gh*)
user-invocable: true
---

# Agentic Git Workflow

PR-bound work runs in an **isolated worktree**, never in the user's checkout. The
behavioral invariants live in the always-on `truly-agentic-git-workflow` rule; this
skill is the procedure that backs them.

## Why a worktree (not a branch in place)

`checkout`, `switch`, `branch`, `reset` are on the `truly-agentic-git-workflow` deny list — fast,
irreversible, and the cause of real agent-driven data loss. `git worktree add` is the
**allowed** branch-creation path and it's isolated: it never touches the user's working
tree. So you get a fresh branch without `checkout`/`branch`.

Do **not** `checkout main` or `git pull` first — `pull` mutates the current checkout.
Refresh remote state with `git fetch` and base the worktree on `origin/<default-branch>`.

## 1. Create the worktree

**Slug:** kebab-case from the task (`fix-auth-refresh`); doubles as the branch name.
Resolve the default branch dynamically — never hardcode `main` (repos use `master`,
`trunk`, etc.).

```bash
REPO=$(git rev-parse --show-toplevel)
SLUG=fix-auth-refresh
WT="$REPO/.agents/worktrees/$SLUG"
git -C "$REPO" remote set-head origin --auto
BASE=$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
git -C "$REPO" fetch origin "$BASE"
git -C "$REPO" worktree add -b "$SLUG" "$WT" "origin/$BASE"
```

## 2. Work end-to-end inside `$WT`

Implement → test → verify the real flow (per F3) → commit → push — all
inside `$WT`. Don't bounce back to the primary checkout. The deny list still applies
here: no `reset` / `rebase` / `stash`.

```bash
# edit, then:
git -C "$WT" add -A
git -C "$WT" commit -m "…"
git -C "$WT" push -u origin "$SLUG"
```

## 3. Open the PR

```bash
gh -R <owner/repo> pr create --base "$BASE" --head "$SLUG" --title "…" --body "…"
```

**A user-visible change does not get review requested until its PR body carries a
picture**, per the `truly-agentic-git-workflow` rule. The user reviews the PR in GitHub,
not the diff, so a **screenshot or a short screen recording** of the outcome (rendered UI,
before/after, the passing test run, the `curl`'d response) is how they verify the feature
is real. Upload the asset; don't just describe it. A change with no visible surface
attaches the closest concrete artifact instead. Attach the **session transcript
confidentially**: on a private repo, a secret gist link only; on a public repo, omit it and
reference the local path. Never paste transcript text inline or onto a public repo.

```bash
# screenshot -> uploaded onto the PR (drag into the web UI, or:)
gh -R <owner/repo> pr comment <pr> --body "Verified end-to-end: ![result](<uploaded-image>)"
# short screen recording: upload the .mp4/.gif via the web UI comment box, or link an asset
gh -R <owner/repo> pr comment <pr> --body "Walkthrough: <uploaded-video-url>"
# confidential transcript, private repos only
gh gist create --secret "$AGENTS_SESSION_DIR/$SESSION_ID.jsonl"   # paste the URL into the PR
```

PR open is **not** "done" — but merging is autonomous on green. A reviewer that is
**not** the author reviews the diff and runs the real tests/CI. If
the review is clean **and** tests pass, rebase-merge and clean up without asking
(section 4). Only fall back to `AskUserQuestion` (request changes / iterate, inside the
same `$WT`) when the review finds problems, tests fail, or the merge conflicts. Don't
remove the worktree or delete the branch until merge.

## 4. Merge on green + clean up

Order matters: remove the worktree **first** so the branch is no longer checked
out, then let `gh` do the merge and delete both branches. This keeps cleanup off
the `truly-agentic-git-workflow` deny list — `git branch -D` is never invoked.

```bash
git -C "$REPO" worktree remove "$WT"                       # allowed; frees the branch
gh -R <owner/repo> pr merge "$SLUG" --rebase --delete-branch  # merge + delete remote & local branch
git -C "$REPO" fetch --prune                                # drop stale remote-tracking refs
```

**Rebase, not squash.** `--rebase` replays the PR's commits onto main so the
one-concept-per-commit history the `/code:commit` skill authored is preserved —
squashing throws away exactly the granular history those commits were written to
create. Squash (`--squash`) only for a throwaway-WIP series ("wip", "fix typo",
"address review") that should not land as individual commits.

`gh pr merge --delete-branch` handles branch deletion via the GitHub API and a
post-merge local prune, so no deny-listed `git branch` / `checkout` call is needed.

## Boundaries

- Worktrees live **only** under `<repo>/.agents/worktrees/`. Never elsewhere.
- Never dodge the `truly-agentic-git-workflow` deny list inside `$WT`.
- To locate the session transcript to attach, see the `sessions` skill. Attach it
  **confidentially** (secret gist link on private repos; local-path reference on
  public repos) — never inline, never onto a public repo. See the
  `truly-agentic-git-workflow` rule.
