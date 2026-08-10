---
description: Create an annotated git release tag and push it to origin. Pure git plumbing — never force, never re-points an existing tag.
---

Create and push an annotated release tag. Arguments (optional): $ARGUMENTS

## HARD LINE — A PUBLISHED TAG IS IMMUTABLE

This command only ever *creates a new tag and pushes it*. It never force-pushes, never deletes a tag, never moves an existing tag to a new commit, and never rewrites history. A tag that has been pushed is a permanent, shared reference — other people and CI may already point at it. Re-pointing it is the tag equivalent of a force-push to `main`.

**If the target tag already exists (locally or on `origin`), STOP and report. Do not clobber it.** The fix is a new version number, never an overwrite.

This command is the pure git-tag slice only. For a full package release — version bump, changelog, build, `npm`/CDN publish — use the `code:release` skill; it calls into this kind of tagging as its final step.

## Process

### 1. Orient

Run in parallel:
- `git rev-parse --show-toplevel` — repo root.
- `git symbolic-ref --short HEAD` — current branch.
- `git status --porcelain` — working tree state.
- `git tag --list --sort=-v:refname | head -10` — recent tags and their format (`v1.2.3` vs `1.2.3`).
- `git remote` — confirm `origin` exists.

### 2. Resolve the version

Determine the tag name, in priority order:

1. **`$ARGUMENTS`** — if it contains an explicit version (e.g. `v1.4.0`, `1.4.0`), use it. Match the existing tag format from step 1 (if existing tags are `vX.Y.Z`, normalize a bare `1.4.0` to `v1.4.0`).
2. **`CHANGELOG.md`** — if present, read the newest version heading (e.g. `## [0.2.0]`, `## 1.4.0`) and use it. This is the common case in this repo family.
3. **`package.json`** — if present, use its `version` field.
4. **Bump the last tag** — if none of the above, take the highest existing tag and propose the next patch bump. Never guess a major/minor bump silently.

Whatever the source, **state the resolved version and where it came from, then confirm with the user before tagging.** If you had to fall back to a bump (case 4), confirmation is mandatory.

### 3. Pre-flight checks (all must pass)

- **Tag must not already exist.** `git tag --list <version>` is empty AND `git ls-remote --tags origin refs/tags/<version>` is empty. If either is non-empty → STOP: "Tag `<version>` already exists. Pick a new version." Do not proceed.
- **Working tree clean.** `git status --porcelain` is empty. If dirty, warn and ask whether to tag the current `HEAD` anyway (the tag captures `HEAD`, not the dirty files) or stop. Default to stop.
- **On a sensible commit.** Report the branch and `HEAD` short SHA you are about to tag. If the branch is not the default branch (`main`/`master`), say so explicitly and confirm — release tags usually point at the default branch.
- **`origin` exists.** If not, stop and tell the user.

### 4. Pick the message

- If `$ARGUMENTS` includes a message after the version, use it.
- Else, if `CHANGELOG.md` has a body under the resolved version heading, use the first line / summary as the annotation.
- Else, default to `Release <version>`.

### 5. Create and push

```bash
git tag -a <version> -m "<message>"
git push origin <version>
```

- Annotated (`-a`) always — never a lightweight tag for a release.
- Push the single tag by name. Never `git push --tags` (that can push stray local tags you didn't intend).

If the push is rejected, report the exact error and stop — do not retry with `--force`.

### 6. Confirm

Report back with proof, not assertion:
- `git show <version> --stat --no-patch` — the tag object, tagger, message, and target commit.
- `git ls-remote --tags origin refs/tags/<version>` — confirm it landed on `origin`.

Quote both. "Pushed" without the remote ref showing the tag is not done.

## Safety rules (non-negotiable)

- **Never** force-push, `--force`, or `-f` anything.
- **Never** delete a tag (`git tag -d`, `git push origin :refs/tags/...`) unless the user explicitly asks in `$ARGUMENTS` and you confirm — and even then, never as an automatic step of this command.
- **Never** move or re-create an existing tag. Existing tag → stop, new version only.
- **Never** `git push --tags` (pushes unintended local tags). Push the one tag by name.
- **Never** rewrite history, rebase, reset, or amend to "make room" for a tag.
- **Never** skip the confirmation in step 2 when the version came from a bump.
- If any check is ambiguous or a command fails, STOP and report — do not assume success.
