---
description: Delete merged branches and worktrees locally and on origin, leaving only main.
---

Clean up merged branches and worktrees. Arguments (optional): $ARGUMENTS

## HARD LINE — DATA LOSS IS THE ONLY FAILURE THAT MATTERS

This command is allowed to be conservative. It is NOT allowed to lose work. A worktree that lingers for another day is a 5-second inconvenience. A worktree that gets removed with unpushed commits, uncommitted edits, or a stash is hours of lost work that may not be recoverable.

**Default to skip. Only remove when you have positive proof — a concrete git command and its zero/empty output — that nothing in the worktree could be lost.**

A worktree may be removed ONLY when ALL of these are true:

1. It is not the main worktree.
2. It is not `locked` (porcelain output).
3. It is not on a `detached` HEAD.
4. `git -C <path> status --porcelain` produces **empty output** (no modified/staged/untracked files).
5. `git -C <path> stash list` produces **empty output** (no stashed changes in this worktree).
6. `git -C <path> rev-list --count origin/$MAIN..HEAD` returns **exactly `0`** (every commit reachable from the worktree's HEAD is already in `origin/$MAIN`).

If any check is uncertain — command fails, output is ambiguous, you're not sure — **SKIP THE WORKTREE**. Never guess. Never assume. The cost of skipping is zero; the cost of being wrong is irreversible.

A `prunable` worktree (working directory already gone) is the one exception — there is nothing left to lose by definition. Run `git worktree prune` for it.

## Goal

Reach a state where:
- Locally: only `main` (or `master`) plus the current branch exist. Every other branch has been merged and is gone.
- On `origin`: same — no merged branches lingering.
- Worktrees: only the main worktree and any worktree still in active use remain. Worktrees on merged branches are removed; stale-admin (`prunable`) worktrees are pruned.
- Remotes: exactly one remote named `origin`. Warn if others exist; do not touch them.

## Process

### 1. Orient

Run in parallel:
- `git remote` — list remotes.
- `git branch -a` — list all local and remote-tracking branches.
- `git status` — confirm working tree is clean (warn but don't stop if it isn't).
- `git worktree list --porcelain` — list every worktree with its branch, lock state, and prunable flag.

**Detect main branch:** check whether `main` exists; fall back to `master`. Use that branch as the merge target throughout. Call it `$MAIN`.

**Detect origin:** if `origin` is absent, stop and tell the user. If extra remotes exist beyond `origin`, list them and warn — "I will only touch `origin`. Other remotes are untouched."

**Parse worktrees:** from the porcelain output, build one record per worktree with `{path, head, branch, locked, locked_reason, prunable, detached}`. The first record is the main worktree — keep it flagged so it is never a removal candidate.

### 2. Sync

```
git fetch --prune origin
```

This deletes remote-tracking refs for branches already gone on the server.

### 3. Discover merged branches

Run in parallel:

```bash
# Local branches already merged into $MAIN
git branch --merged origin/$MAIN
```

```bash
# Remote branches already merged into origin/$MAIN
git branch -r --merged origin/$MAIN
```

Filter out from both lists:
- `main`, `master`, `develop`, `HEAD`
- Any branch matching `origin/main`, `origin/master`, `origin/develop`, `origin/HEAD`
- **Any branch currently checked out in ANY worktree** (not just the main one). Use the `branch` field from each worktree record built in step 1 — every `refs/heads/<name>` value listed there is checked out somewhere and cannot be `-d`-deleted. This explicitly includes branches in locked worktrees and detached-HEAD worktrees (the latter have no branch field, so they don't contribute).

Call the resulting set `merged_local_branches`.

This filter prevents a real failure mode: a branch can satisfy "merged into origin/$MAIN" while still being checked out in a locked agent worktree. Deleting it would either fail noisily (`git branch -d`) or silently break the agent's worktree (`-D`, which we don't use). Filtering it out up front is cleaner than letting the delete fail at execute time.

### 3b. Classify worktrees

Walk every worktree record from step 1 EXCEPT the main worktree. For each, run the checks below **in order** and stop at the first one that matches. Use the exact commands shown — do not paraphrase, do not substitute "looks like" reasoning.

The block below is **pseudocode**. The bash snippets show the exact commands to run; the `if record.X` and `if probe returned Y` lines describe what to do with the output. Do not paste this block into a shell verbatim — execute the bash commands and apply the logic.

```
# === Cheap structural checks first — based on porcelain fields from step 1 ===

if record.locked:
    skip with reason: "locked: " + record.locked_reason
    next worktree
if record.prunable:
    add to to_prune (working dir is gone — nothing to lose)
    next worktree
if record.detached:
    skip with reason: "detached HEAD (no branch to compare)"
    next worktree

# === Data-loss probes — run against the live worktree ===
# If ANY probe command exits non-zero (e.g., not a git repo, permission denied),
# treat as UNCERTAIN and skip — never assume success.

#   Probe 1: uncommitted / untracked / staged changes
run:  git -C <path> status --porcelain
if command failed:                      skip with reason "status check failed"; next worktree
if output is non-empty:                 skip with reason "uncommitted changes: <first line of output>"; next worktree

#   Probe 2: stashed changes inside this worktree
run:  git -C <path> stash list
if command failed:                      skip with reason "stash check failed"; next worktree
if output is non-empty:                 skip with reason "stash present in this worktree"; next worktree

#   Probe 3: THE definitive "nothing-to-lose" check —
#   are all of this worktree's commits already in origin/$MAIN?
run:  git -C <path> rev-list --count origin/$MAIN..HEAD
if command failed:                      skip with reason "rev-list failed"; next worktree
if output is not exactly "0":           skip with reason "<N> commits not in origin/$MAIN (would be lost)"; next worktree

# All three probes passed. The worktree's branch is implicitly merged
# (every commit reachable from HEAD is in origin/$MAIN).
add to to_remove
```

Build three lists: `to_remove[]`, `to_prune[]`, `to_skip[]`. For each entry, record the path, branch (if any), HEAD SHA (short), and — for skipped entries — the exact reason string from above.

**The `rev-list --count origin/$MAIN..HEAD == 0` check is the load-bearing one.** It is strictly stricter than "branch appears in `git branch --merged`". It catches squash-merged branches as "not safe to remove" (because the original commits are not byte-identical in main), which is the conservative direction. Do not weaken it. Do not replace it with a branch-name lookup.

### 4. Show the plan — do NOT act yet

Print a clear summary:

```
Local branches to delete (merged into $MAIN):
  feature/oauth-refresh
  fix/payment-null

Remote branches to delete on origin (merged into $MAIN):
  origin/feature/oauth-refresh
  origin/fix/payment-null

Worktrees to remove (every commit already in origin/$MAIN — verified by rev-list):
  /Users/.../repo/.agents/worktrees/proj-846   [proj/846]                 HEAD a97ae4011  ahead=0  dirty=no  stashes=0
  /Users/.../repo.worktree-fix-733             [fix-733-foo]              HEAD dc89077c8  ahead=0  dirty=no  stashes=0

Worktrees to prune (working dir missing):
  /private/tmp/feature-ux-verify

Worktrees skipped (and why):
  /Users/.../.claude/worktrees/agent-a654c42614c0d4b4e — locked: claude agent (pid 20923)
  /Users/.../.agents/worktrees/cloud-exec-deploy        — detached HEAD (no branch to compare)
  /Users/.../.agents/worktrees/m1                       — uncommitted changes:  M src/cli/main.go
  /Users/.../.agents/worktrees/proj-849                 — 3 commits not in origin/main (would be lost)
  /Users/.../.agents/worktrees/b5-impl                  — stash present in this worktree

Nothing else will be touched.
```

Omit any section whose list is empty. If `merged_local_branches`, the merged remote list, `to_remove`, and `to_prune` are ALL empty, say "Nothing to clean up — already tidy." and stop.

### 5. Ask for confirmation

Use `AskUserQuestion` with two options:
- "Yes, delete them all"
- "Cancel"

Phrase the question with concrete counts: "Delete N branches and M worktrees (and prune P stale entries)?" — using the actual numbers from the plan. Do not proceed without an affirmative answer.

### 6. Execute

Order matters: a branch cannot be deleted while it is checked out in another worktree, so worktrees come first.

**6a. Remove worktrees on merged branches.** For each entry in `to_remove`:
```bash
git worktree remove <path>   # no --force — safe-fail leaves it for next run
```

**6b. Prune stale worktree admin files.** If `to_prune` is non-empty, or any `git worktree remove` succeeded:
```bash
git worktree prune
```

**6c. Delete local merged branches.** For each branch in `merged_local_branches`:
```bash
git branch -d <branch>   # safe delete — fails if unmerged, which should never happen here
```

**6d. Delete remote merged branches.** For each remote merged branch (strip the `origin/` prefix):
```bash
git push origin --delete <branch>
```

If any individual operation fails, log the error and continue with the rest. Do not abort the whole run on a single failure.

### 7. Final prune and report

Run in parallel:
```bash
git remote prune origin
git branch -a
git worktree list
```

Report what was deleted (branches), removed (worktrees), pruned (stale worktree admin), skipped (with reasons), and what (if anything) failed. Include the final branch list and final worktree list.

## Safety rules (non-negotiable)

- Never delete `main`, `master`, `develop`, or `HEAD` — locally or remotely.
- Never delete the currently checked-out branch.
- Never force-delete (`git branch -D`). Only `-d`. If `-d` would fail, skip and warn.
- Never push `--force` or `--force-with-lease`.
- Never touch remotes other than `origin` without explicit user instruction in `$ARGUMENTS`.
- Never delete a branch unless it appears in both the `--merged` output AND passes all filters above.
- Never `git worktree remove --force`. Plain `git worktree remove` only — if it refuses, skip and report. Git's own safety net is the last line of defense; do not disable it.
- Never remove a locked worktree, even if its branch is merged. The lock means something (usually a running agent) is actively using it.
- Never remove a worktree with uncommitted changes, untracked files, or a non-empty stash. Skip and report.
- Never remove a worktree where `git rev-list --count origin/$MAIN..HEAD` is non-zero, OR where that command exits non-zero. "I don't know" means skip.
- Never remove the main worktree (the one this command is running from).
- Never remove a detached-HEAD worktree. No branch means an ambiguous merged-check; the safe call is to leave it alone.
- Never substitute the data-loss probes (status, stash, rev-list) with a branch-name lookup or with "this looks merged to me." Run the commands. Read the output. Quote it in the plan.

## Don'ts

- Don't skip the confirmation step — even if `$ARGUMENTS` contains "yes" or "force".
- Don't rebase, reset, or modify any commit history.
- Don't delete branches that are not confirmed merged.
- Don't touch stashes, tags, or anything outside branches and worktrees.
- Don't run `git worktree prune` before the `git worktree remove` calls — ordering keeps the report honest.
- Don't try to "rescue" uncommitted changes by stashing or committing on behalf of the user. Skip the worktree and report it.
