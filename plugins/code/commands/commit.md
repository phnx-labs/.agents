---
description: Split changes into the maximum number of small logical commits (one concept per commit) and push in the background.
---

Commit and push. Arguments (optional): $ARGUMENTS

- Default: **maximum micro-commits** — one concept per commit, split as aggressively as the diff allows.
- Pass `squash` or `chunky` in $ARGUMENTS to fall back to coarser logical groups (old behavior — up to ~5 files per commit).
- Pass `no-verify` to skip git hooks.

## Style

Conventional commits: `<type>: <description>`

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `build`, `release`, `chore`

Match the voice of these examples — note how each names the **specific thing** changed, not just the category:

- feat: add jwt refresh token rotation on 401 responses
- fix: resolve null pointer in stripe payment webhook handler
- docs: add rate-limiting examples to api reference
- build: configure webpack tree-shaking for production bundle
- refactor: extract address validation into standalone validator
- fix: correct dst handling in user timezone formatter
- feat: stream server-sent events for real-time notification feed
- release: bump version to 1.2.0
- refactor: collapse three error-handling branches into single handler
- chore: remove unused lodash imports across auth module

Rules:

- Under 72 characters. Lowercase. Imperative mood. Single line only — no bodies, ever.
- No emojis. No scope prefix like `feat(api):` — just `feat:`.
- **Name the specific thing.** "feat: update auth" is rejected. "feat: add oauth refresh token rotation" is accepted.
- **NEVER add `Co-Authored-By:` lines.** Not for Claude, Claude Code, Codex, GPT, Anthropic, any AI tool, or any bot. The commit is authored by the user — period.
- No "Generated with Claude Code" or similar trailers.

## Process

> **The primary working tree is off-limits — on ANY branch.** If the target is the
> user's own checkout (the primary working tree), the `main-branch-guard` hook
> blocks `git add`/`git commit` regardless of which branch it is on, not just the
> default — by design (see the truly-agentic-git-workflow rule). Move the changes
> to a linked worktree and commit there (`git worktree add -b <slug>
> <repo>/.agents/worktrees/<slug> origin/<default>`), then open a PR. Don't try to
> work around the guard.

1. Run `git status` and `git diff` (staged + unstaged) in parallel.
2. If nothing to commit, say so and stop. Do not create an empty commit.
3. **Split the changes (default: maximum micro-commits).** Scan the diff and split into the smallest viable units. **One concept per commit** is the goal — err on the side of MORE commits, not fewer. A commit covers exactly one thing: one feature increment, one bug fix, one rename, one config tweak, one docs section. If two files could plausibly land in separate commits, they should. Unrelated changes (e.g. a hook config tweak + a new blog post + a bug fix) must NEVER share a commit. When `$ARGUMENTS` contains `squash` or `chunky`, fall back to the older "cluster what belongs together" heuristic instead.
4. **Split bias.** Default mode: any group with **more than 2 files** must justify staying together — the question is "why are these inseparable?", not "why split?". Always prefer splits like "implement X" + "wire X into Y" + "tests for X" + "docs for X" over one mega-commit. The only files that MUST stay together: a generated file + its generator input (schema + migration, proto + generated code, snapshot + test that produced it), and a `.gitignore` rule + the file it's ignoring. Everything else: split. In `squash`/`chunky` mode, the old 5-file threshold applies.
5. **Safety + hygiene checks** (run before any `git add`):
    - **Secrets:** `.env*`, `credentials.json`, `*.key`, `*.pem`, `id_rsa*`, `*.p12`, `*.keystore` → STOP, warn the user, propose adding to `.gitignore`. Don't commit.
    - **Binaries** (compiled output, not assets): `*.so`, `*.dylib`, `*.dll`, `*.exe`, `*.o`, `*.node`, `*.wasm`, archives (`*.zip`, `*.tar*`, `*.dmg`, `*.7z`), and anything `file <path>` reports as `Mach-O` / `ELF` / `data` → STOP. Default-assume it's a build artifact that escaped — unstage, propose `.gitignore` addition. Only proceed if the user confirms it's an intentional asset.
    - **Should-be-ignored paths** (not in any `.gitignore` yet): `.DS_Store`, editor swap (`*.swp`, `*~`, `.vscode/`, `.idea/`), build outputs (`dist/`, `build/`, `out/`, `.next/`, `target/`, `coverage/`), dep dirs (`node_modules/`, `.venv/`, `venv/`, `__pycache__/`, `*.pyc`), logs (`*.log`, `npm-debug.log*`), worktrees (`worktrees/`, `.agents/worktrees/`), local env (`.env.local`, `.env.*.local`) → propose adding to the nearest `.gitignore`, then exclude from this commit batch.
    - **Large files** (≥1 MB): flag and ask. If it's source, fine; if it's a binary asset, suggest Git LFS or external storage.
    - **Media** (`*.png`, `*.jpg`, `*.gif`, `*.webp`, `*.svg`, `*.pdf`, `*.mp4`, `*.mov`, `*.mp3`, `*.docx`): often legitimate (marketing, docs, fixtures). Don't auto-block — note in the summary if more than 5 are in one commit so the user can spot accidents.

    **Gitignore workflow.** When the check flags a file that should be ignored: find the closest existing `.gitignore` walking up from the file (or propose creating one at the repo root if none exists), append the minimum-specific pattern (broad rule like `.DS_Store` for noise files, dir-rule like `apps/web/dist/` for build outputs), confirm with `git check-ignore <path>`, and commit the `.gitignore` change FIRST as `chore: ignore <thing>` before the rest of the batch. Never `git rm --cached` without explicit user authorization — for already-tracked files, ask.
6. For each group (smallest/most-focused first):
    - `git add <files-in-group>` (explicit paths, never `-A`)
    - Write one conventional-commit message that names the specific thing. Single line.
    - `git commit -m "<message>"`
7. After all commits: single `git push` with `run_in_background: true`. Never block the conversation on the push.

## Splitting heuristics (default mode)

Default = **split aggressively**. These are the boundaries to cut along, in priority order:

- Different directories / modules → always separate commits.
- Different concerns in the same directory (e.g. auth refactor + new endpoint) → separate.
- Tests → separate `test:` commit from the source they cover. (Reverting source without losing tests is valuable.)
- Docs for a thing → separate `docs:` commit from the thing itself, unless the docs literally describe a single new API in the same file.
- Config / build changes → separate `build:` or `chore:` commit from feature code, even if they enable the feature.
- Formatting / lint-only changes → separate `chore:` commit, NEVER mixed with logic changes.
- Renames / moves → separate `refactor:` commit before the changes that depend on the new location.
- `.gitignore` additions → standalone `chore: ignore <thing>` commit, FIRST in the batch.
- Generated files (schema, migrations, proto output) → same commit as the source that generated them (this is the one "stay together" rule).
- Unrelated bug fixes → always separate, one per fix.

If a "split" would leave the repo in a broken state at any commit (e.g. tests reference a symbol that doesn't exist yet), reorder so the source lands first, then the test — but still as two commits. Don't merge them to dodge ordering.

If the entire diff is genuinely one indivisible thing (one file, one concept), one commit is fine. Don't fabricate groups — but also don't fabricate inseparability to avoid the work of splitting.

## Ignore when reasoning about the diff

`node_modules`, `dist`, `build`, `out`, `.git`, `*.lock`, `bun.lock`, `package-lock.json`, `*.vsix`

## Don'ts

- Don't lump unrelated changes into one commit.
- Don't write vague messages — name the specific thing that changed.
- Don't fabricate groups when the diff is genuinely one thing.
- Don't ask "should I commit?" — the slash command IS the ask.
- Don't verify build/tests pre-commit — that's the user's job.
- Don't use `--no-verify` unless `$ARGUMENTS` contains `no-verify`.
- Don't run push in the foreground. It always goes in the background.
- Don't commit binaries without asking — default-assume they're build artifacts that escaped.
- Don't use `git rm --cached` without explicit user authorization — propose `.gitignore` additions for untracked files instead.
- Don't default to fewer commits "because the changes are related" — relatedness is not the same as inseparability. Split unless the commit would actually break without its sibling.
