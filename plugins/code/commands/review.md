---
description: Review PRs or a whole repo. Default recaps the session and lands every PR it opened; given PR number(s) reviews those cold; given `repo`/a path/`--since` runs a read-only architecture-and-quality scan.
---

Invoke the `code:review` skill. Arguments: $ARGUMENTS

- Empty (or `dry-run` / `no-merge`): review every PR opened in this session, act on the verdicts (merge / request changes / close).
- `#412` or `#412 #413 #414`: deep sub-agent review of exactly those PRs.
- `repo`, a path, `--since "<date>"`, or `--branch`: read-only whole-repo architecture + code-health + context + patterns diagnostic — HTML report, no merge verdict.
