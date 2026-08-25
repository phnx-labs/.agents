---
description: Score how well a repository is structured for coding agents, then render an AGENTS.md coverage and directory-organization report.
---

Invoke the `code:score` skill. Arguments: $ARGUMENTS

- Empty: analyze the current repository.
- A repository path: analyze that repository without changing its source or configuration.
- Output: an agent-readiness score, ranked actions, and Markdown + rendered HTML under `<repo>/.agents/artifacts/<date>/`.
