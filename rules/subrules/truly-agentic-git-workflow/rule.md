# Truly Agentic Git Workflow

**The user's primary working tree is untouchable — on ANY branch. Every change
is a LINKED worktree + PR. Always.**

Never create, edit, or delete a tracked file, and never `git add`/`git commit`,
inside a repo's primary working tree — enforced by `main-branch-guard`
(PreToolUse) on the whole tree, not just the default branch. The only place an
agent writes is a linked worktree under `<repo>/.agents/worktrees/<slug>/`.
Non-git paths and gitignored paths are unaffected, and the user's own editor and
`!`-prefixed session commands are never blocked. `git switch` and `git checkout`
are both banned (`git-guard`) — switching the checkout in place strands the
user's tree.

Diagnose on the latest code, not your working-tree HEAD: `git fetch origin` +
`git rev-list --count HEAD..origin/<default>` before calling anything a bug or
opening a "fix" PR.

## Git ops

Reads (`status`, `diff`, `log`, `blame`, `show`, …), `fetch`, `clone`, `push`,
worktree ops, and `add`/`commit` off the default branch are yours. Destructive
and history-rewriting ops (`checkout`, `switch`, `branch`, `stash`, `reset`,
`rebase`, `cherry-pick`, `revert`, `clean`, `config` writes, force push) need
an explicit user ask — `git-guard` blocks them because they have destroyed
real work. On obstacles (conflict, lock file, unexpected state): resolve at
the source, never reset/clean as a shortcut.

## Worktree recipe

```
REPO=$(git rev-parse --show-toplevel)
git -C "$REPO" fetch origin
git -C "$REPO" remote set-head origin --auto
BASE=$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
git -C "$REPO" worktree add -b <slug> "$REPO/.agents/worktrees/<slug>" "origin/$BASE"
```

Fetch first — the guard denies an implicit or local-branch base, and a
remote-tracking base staler than `AGENTS_WORKTREE_FETCH_MAX_AGE_SEC` (default
900s). Never `git pull` the checkout. Do everything end-to-end inside the
worktree: implement → test → verify → commit → push → PR.

Multi-agent safety: create worktrees foreground (a backgrounded `worktree add`
races other agents' index writes); verify the checkout is complete before
building (`git -C "$WT" status --short | grep '^ D'` must be empty); commit
with an explicit pathspec (`git commit <path>`, never `add` + bare `commit`) so
a concurrent agent's staged files aren't swept in.

**Reclaim the worktree after the merge — it is a step, not an afterthought.**
`gh pr merge --delete-branch` removes the BRANCH and leaves the CHECKOUT on
disk. Nothing else ever removes it, so every merged PR used to leak a full
working tree: 581 worktrees / ~263 GB across this fleet, which took the release
box to 1.6 GiB free and wedged publishing (PHNX-3503, PHNX-3478). Merge first,
then reclaim:

```bash
gh pr merge <n> --rebase --delete-branch
git -C "$REPO" worktree remove "$WT"
```

`git worktree remove` without `--force` refuses a tree with uncommitted changes,
so it is safe to run the moment the merge returns. Leave the local branch ref
alone — you have no `git branch -d/-D` permission, by design, and the nightly
`worktree-sweep` routine reclaims stragglers and branch refs on every device.

## Open the PR with evidence attached

Run the feature, look at the real output, and attach that result — before
opening the PR. Only release PRs and pure doc edits need no run. The body leads
with a one-line what + type (`docs-only` / `refactor` / `test-only` when true),
then headings and short bullets — never a prose wall.

- A user-visible change ships a screenshot (both stills for a before/after);
  prefer a recording when a still can't carry the flow (`browser` skill for
  web, `agents pty` for terminal).
- A no-UI change still shows the run — the passing test output or `curl`'d
  response as an uploaded asset. Pasted source and hand-authored tables are not
  proof of a run. Genuinely no surface → declare it (refactor / test-only).
- Link the ticket and, if a plan was shared, the plan.

`gh` cannot upload images inline. Publish assets with
`agents artifacts share <file>` (Cloudflare R2, headless; set up once with
`agents artifacts setup` or `share join <baseUrl>`; `--expire 30d` bounds the
link) and embed `![caption](url)`. Fallbacks, in order: drag-drop in the web
UI; `gh pr comment` with the URL after the fact; a fleet-local `host:/path`
reference, named as such. Never commit a screenshot to the repo just to embed
it, and never publish a private or secret asset to a public URL.

Transcripts stay confidential: secret gist on a private repo
(`gh gist create --secret <id>.jsonl`), a local `<host>:<path>` reference on a
public one — never inline. The `pr-description-reminder` hook (PreToolUse)
nudges when a PR body carries no run result and no honest no-run declaration;
checkable declarations are verified against the branch's changed files.

## PR open is NOT done — drive review + merge yourself

Do not open the PR URL for the user or wait for them to click anything.
Authorization to do the work carries through to rebase-merge on green. Right
after `gh pr create`, two tracks in parallel:

1. Watch CI in the background with a finish-echo — run with
   `run_in_background: true`, never `Monitor`/`ScheduleWakeup`/`until` loops:

   ```
   (gh pr checks <pr> --watch --fail-fast; echo "CI settled rc=$? — next: non-author review, then merge on green")
   ```

2. Check the repo's automated reviewer: is one configured (a checked-in config,
   e.g. `.github/rush.yml` → verdicts as the `prix-cloud` comment), and is it
   alive on THIS PR (`gh pr view <n> --json reviews,comments`)? Configured and
   posting → wait for its verdict. Missing, silent, or down → spawn a
   non-author subagent review now; don't wait and don't hand the merge to the
   user.

Non-author review + green CI = rebase-merge without asking. Ask only when the
review finds problems, tests fail, or the merge conflicts. Don't remove the
worktree or branch before merge.

## Reconcile with rebase; never `reset --hard`; never stash

Commit instead of stashing (the `/code:commit` skill; small logical commits).
Uncommitted changes on `main` → move to a worktree/branch + WIP PR. Bring a
diverged branch up with `git pull --rebase` / `git rebase origin/<branch>` —
never `reset --hard`, which discards commits irrecoverably. `rebase` is blocked
on the agent's shell; hand it to the user via the `!` session prefix
(`!git -C <repo> rebase origin/<branch>`).
