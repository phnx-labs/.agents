# code plugin

Coding-workflow plugin. Sub-skills for the manager/router engineering loop: drain queues,
review PRs (or a whole repo) and merge, and learn a codebase well enough to leave it
better documented than you found it.

## Skills

| Skill | Use when |
| --- | --- |
| `code:loop` | A queue of work — one ticket, many tickets, a label, a markdown checklist, repo TODOs, or a single branch/PR to land — needs taking end-to-end: plan, code, test, review, rebase, fix CI, and merge. The top-level engineering loop composes the skills below and the `agents` CLI primitives. Publishing distributables is outside this plugin's scope. |
| `code:review` | Three modes on one skill. Default (no args): recap the session's goal, discover every PR it opened, review each with a sub-agent and act on the verdicts (merge / request-changes / close). Given PR number(s): a deep cold review of just those, with file:line grounding, an architecture rubric (reuse of primitives, cross-cutting at the source, no duplicate surfaces, doc-asserted invariants), and a security pass on risk-touching diffs. Given `repo` / a path / `--since`: a read-only whole-repo architecture-and-quality diagnostic — HTML report, ranked findings, never a merge verdict. |
| `code:learn` | A coding session just finished, or you need to learn a codebase cold. Learns the structure, entry points, architecture, and non-obvious invariants, then writes what a future agent would otherwise re-derive into the project's own `AGENTS.md` — the primary durable output. Secondarily routes a genuinely durable coding-*workflow* lesson (about the loop itself, not the project) to the right `code:*` skill. |
| `code:refactor` | The codebase has outgrown its own structure — two concepts that should be one, a horizontal layer four modules each reimplemented, a boundary never drawn, a cohesive core that should be its own package, a tree that no longer says where anything goes, a surface nobody can search. Builds a module dependency graph (god modules, cycles, extraction candidates, upward imports), measures which files agents actually read and edit (fleet session index, not just churn), censuses the public surface, and verifies the repo's own architecture claims against the code. Ranks seven architectural moves by `harm x exposure` (including whether a concept has the contract its job calls for — a family dispatched on by name across twenty files usually wants the provider pattern the repo already uses somewhere else), sequences them (cycles first, tree moves last), renders before/after figures with `artifacts` where every box and arrow is sourced from the graph JSON, and lands behavior-preserving PRs. Hygiene is the byproduct tier, not the job. Calls `code:review` Mode C for file-level passes instead of duplicating them. |
| `code:commit` | Split changes into the maximum number of small logical commits (one concept per commit) and push in the background. |
| `code:score` | Score how well a repository is structured for coding agents: multi-level `AGENTS.md` coverage and pointer quality, stale frontmatter, flat overloaded directories, god files, and deep unfocused trees. Produces ranked actions plus a visual Markdown-to-HTML report under the analyzed repo's dated artifact directory. |

## Self-contained commands

A full command prompt, not a skill invoker (same shape as `/code:commit`) — git
plumbing that belongs next to the coding loop, not in a separate plugin. (`/code:clean`
used to live here; it is now the `code:refactor` skill — see the table above.)

| Command | What it does |
| --- | --- |
| `/code:prune` | Deletes merged branches and worktrees locally and on `origin`, behind hard data-loss guards: never removes a worktree with uncommitted changes, a stash, unmerged commits, a lock, or a detached HEAD. Uses `git rev-list --count origin/$MAIN..HEAD == 0` as the load-bearing "nothing to lose" check (strictly stricter than `git branch --merged`), shows the plan, and asks before acting. |

## The reviewer it spawns

`code:review` spawns `subagent_type: "code-reviewer"`. That definition does **not** live in
this plugin — it ships from the repo's top-level
[`subagents/code-reviewer/`](../../subagents/code-reviewer/AGENT.md), which is the only path
that reaches every subagents-capable harness (Claude, Codex, Grok, Kimi, Cursor, Droid,
OpenCode, Copilot, Kiro, Goose, Antigravity, OpenClaw) through `SUBAGENT_TARGETS`. A plugin's
own `agents/` dir is the Claude plugin format and lands nowhere those harnesses read — see
[`plugins/AGENTS.md`](../AGENTS.md) for the measurement.

The standing rubric lives in the subagent, so this skill's per-PR brief carries only the
requirement, the context, and the canonical patterns. Change the rubric in one place.

## Where verify/ship/quality/release went

Earlier versions of this plugin had separate `code:verify`, `code:ship`, and `code:quality`
skills. They're gone, not renamed:

- **`code:verify`** — folded back into `code:loop` as an inline step. Verification is
  identifying the changed surfaces yourself and running each one's canonical test with
  quoted output — it never needed a dedicated skill call.
- **`code:ship`** — retired. Publishing and release orchestration are outside the code
  plugin's scope.
- **`code:quality`** — became `code:review`'s third mode (`repo` / a path / `--since`).
  The rubric was always the same one a PR review applies to a diff — reuse, cross-cutting
  at the source, no duplicate surfaces, doc-asserted invariants — just run over a whole
  scope instead of one PR's changes. The HTML report and its helper scripts moved to
  `code:review`'s skill directory.

## Primitives the loop uses directly

| Primitive | Use when |
|---|---|
| Inline edit | 1-2 files, < 15 min, no ambiguity. |
| `agents run <agent> "..." --mode edit --cwd <worktree>` | One surface, one agent, local. |
| `agents run --device auto` | Send to the automatic pool; named harnesses prefer a ready account, then lower live load. |
| `agents run --device <box>` | The work must run on a specific fleet box. |
| `agents run --lease` | Clear single-agent task on a disposable cloud box. |
| `agents teams` | 3+ independent surfaces; use boundary contracts and per-teammate worktrees. |
| `cloud:run` | Rush Cloud dispatch for clear, repo-bound tasks that should run away from the laptop. |

## The manager loop

1. New task arrives → pick the primitive directly (`agents run`, `agents teams`, `cloud:run`) and set up the worktree.
2. Agent runs.
3. Agent claims done → identify the changed surfaces and run each one's canonical test inline, quoting real output (F3's closing check — see `code:loop`).
4. PASS → `/code:review` the PR, then merge. FAIL → file the failing line back to the agent.
5. A distributable's repository-specific publish and live-verification process runs outside this plugin.

`/code:loop` drives steps 1-5 over a whole queue; the skills above are what it composes.
`/code:review repo` (or a path, or `--since <date>`) runs outside this loop — invoke it any
time as a read-only health snapshot (after landing a multi-commit branch, before opening a
PR, on a fresh checkout, or as a recurring sanity check). `/code:learn` runs *after* a
session — its primary output is the project's own `AGENTS.md`, updated so the next agent
doesn't re-derive what this one just learned.

## Conventions

- All sub-skills assume `agents-cli` is installed and on PATH.
- Sub-skills default to the `Plan` sub-agent type with `model: "sonnet"`; reserve `model: "opus"` only for genuinely load-bearing reasoning. Mix `claude`/`codex` for implementation tracks.
- Every sub-skill ends with a real verification step — no "code written = done."
- Worktrees live in `<repo>/.agents/worktrees/<slug>/` (F5: protect what you can't undo).
