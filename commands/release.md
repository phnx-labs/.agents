---
description: Publish a package/CLI/app to its registry — discover the repo's real release process, run tests, update the changelog, publish, tag, and verify it's live.
---

Invoke the `release` skill. Arguments: $ARGUMENTS

- No version given: analyze what's needed (current published version, commits since last tag) and suggest one.
- A version (`1.2.3`, `patch`, `minor`, `major`), a monorepo package path, and `--skip-tests`/`--skip-build`/`--force` are all accepted — see the skill for the full contract.
- Discovers the repo's actual release script (`scripts/release.sh`, npm scripts, monorepo packages) and runs it rather than reinventing it; scaffolds one only if none exists.
- Drives the full chain end to end: tests → version/changelog → publish/tag as the repo defines → verify the artifact is actually live (registry version, clean-room install, activated extension, or a health-endpoint `curl` — never just "the command exited 0").
- Refuses to double-release into a repo with its own serialized release train/lease — hands off to that instead.
