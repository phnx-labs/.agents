# git plugin

Pure git plumbing commands that aren't tied to code logic. Branch and worktree pruning, tag releases, anything that touches the git object store without caring about what's *in* the code.

The code-aware loop (`/code:commit` with code-organization heuristics, `/code:review` with a code-quality rubric, `/sprint` for multi-track pushes) lives in the [`code`](../code/) plugin — those are coding-workflow concerns that happen to talk to git. This plugin is the opposite: it doesn't reason about code at all.

## Requirements

- [`agents-cli`](https://github.com/phnx-labs/agents-cli) installed and on `$PATH`.
- At least one supported coding agent (Claude Code, Codex, Gemini, Cursor, OpenCode).
- `git` ≥ 2.20 (for `worktree` porcelain output).

## Commands

| Command | What it does |
| --- | --- |
| `/git:prune` | Deletes merged branches and worktrees locally and on `origin`, with hard data-loss guards: never removes a worktree that has uncommitted changes, stashes, unmerged commits, a lock, or detached HEAD. Always shows the plan and asks before acting. Uses `git rev-list --count origin/$MAIN..HEAD == 0` as the load-bearing "nothing to lose" check — strictly stricter than `git branch --merged`. |
| `/git:tag-release` | Creates an annotated git tag for a release and pushes it to `origin`. Resolves the version from `$ARGUMENTS`, else the newest `CHANGELOG.md` entry, else the last tag bumped — and always confirms before tagging. Pure git plumbing: only `git tag` and `git push <tag>`, never force, never deletes or moves an existing tag. For full package publishing (npm/CDN, changelog, build), use the `code:release` skill — this command is just the git-tag slice. |

Naming note: `/git:prune` is the canonical plugin-namespaced command — same logic, same guards as the now-removed top-level `/prune`.

## Safety bar

Both commands follow one hard line: **data loss / irreversibility is the only failure that matters**.

`/git:prune`: a worktree that lingers an extra day is a 5-second inconvenience; a worktree removed with unpushed commits or uncommitted edits is hours of irrecoverable work. It defaults to skipping any worktree where the safety probes can't return a definitive "nothing to lose," and never uses `--force` on branch deletes or worktree removes.

`/git:tag-release`: only ever *creates* a new tag and pushes it. It never force-pushes, never deletes or re-points an existing tag (a published tag is immutable), and never rewrites history. If the target tag already exists, it stops and reports rather than clobbering it.
