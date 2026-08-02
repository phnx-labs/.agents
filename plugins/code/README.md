# code plugin

Coding-workflow plugin. Sub-skills for the manager/router engineering loop: drain queues, verify end-to-end, review and merge, ship distributables to users, and learn from the session.

## Skills

| Skill | Use when |
| --- | --- |
| `code:loop` | A queue of work — one ticket, many tickets, a label, a markdown checklist, repo TODOs, or a single branch/PR to land — needs taking end-to-end: plan, code, test, review, rebase, fix CI, merge (and ship, for distributables). The top-level engineering loop; composes the skills below and the `agents` CLI primitives instead of reimplementing them. |
| `code:verify` | An agent claims work is done, or a branch / PR is ready. Identifies changed surfaces, runs the canonical `sandbox.sh test` for each, hits health endpoints on deploys, screenshots UI if rush/app touched. Returns PASS / FAIL with quoted evidence — the closing gate for F3. |
| `code:review` | CI is green on an open PR. A sub-agent (not the author) reviews the diff with file:line grounding and anti-overengineering guardrails, runs a security pass on risk-touching diffs, and posts a verdict — merge / request-changes / close-as-duplicate. |
| `code:ship` | A change is merged but the artifact is a **distributable** (VS Code extension, npm/cargo CLI, web app) — merge alone reaches nobody. Publishes, confirms the version is live on the public channel's API, activates it where it runs, verifies the real surface. "Published" ≠ "shipped"; "installed" ≠ "active". |
| `code:quality` | A read-only diagnostic across four orthogonal categories: **architecture & design** (inline auth where middleware exists, etc.), **code health** (`go vet`, `tsc`, `staticcheck`, `biome` — only if on PATH), **context quality** (docs vs code drift, doc-asserted invariants, identifier cross-reference), and **patterns** (parallel implementations by behavioral signature). Scope-flexible (`HEAD~1` default; `--commits N`, `--since`, `#PR`, path overrides). Emits an HTML report opened in the browser with per-finding clipboard actions (copy as `/code:loop` task, copy Linear ticket cmd, copy `file:line`). Never modifies code. |
| `code:learn` | A substantial session just finished and taught you something. Reflects on what was used and routes only the durable, generalizing lessons to the right `code:*` skill / rule / memory — the code-plugin layer on the top-level `learn` engine. Built to not overfit or break the composing skills' contracts. |

## Primitives the loop uses directly

| Primitive | Use when |
|---|---|
| Inline edit | 1-2 files, < 15 min, no ambiguity. |
| `agents run <agent> "..." --mode edit --cwd <worktree>` | One surface, one agent, local. |
| `agents run --device <box>` | The work must run on a specific fleet box. |
| `agents run --lease` | Clear single-agent task on a disposable cloud box. |
| `agents teams` | 3+ independent surfaces; use boundary contracts and per-teammate worktrees. |
| `cloud:run` | Rush Cloud dispatch for clear, repo-bound tasks that should run away from the laptop. |

## The manager loop

1. New task arrives → pick the primitive directly (`agents run`, `agents teams`, `cloud:run`) and set up the worktree.
2. Agent runs.
3. Agent claims done → `/verify <branch or PR>` runs the canonical tests and quotes evidence.
4. PASS → `/review` the PR, then merge. FAIL → file the failing line back to the agent.
5. Merged a **distributable** (extension / CLI / web app)? → `/ship` publishes, confirms it's live for users, activates and verifies it. Merge is the middle, not the end.

`/code:loop` drives steps 1-5 over a whole queue; the skills above are what it composes. `/quality` runs outside this loop — invoke it any time as a read-only health snapshot (after landing a multi-commit branch, before opening a PR, on a fresh checkout, or as a recurring sanity check). `/code:learn` runs *after* a session — fold what it taught you back into these skills.

## Conventions

- All sub-skills assume `agents-cli` is installed and on PATH.
- Sub-skills default to the `Plan` sub-agent type with `model: "sonnet"`; reserve `model: "opus"` only for genuinely load-bearing reasoning. Mix `claude`/`codex` for implementation tracks.
- Every sub-skill ends with a real verification step — no "code written = done." See `code:verify` for the canonical gate.
- Worktrees live in `<repo>/.agents/worktrees/<slug>/` (F5: protect what you can't undo).
