---
name: learn
description: "Learn the codebase a coding session just worked in, and write what a future agent would otherwise re-derive into that project's AGENTS.md — entry points, architecture, non-obvious invariants, how to navigate. The primary durable output of a coding session is the project's own memory file, not the code plugin. May also fold a genuinely durable coding-workflow lesson into a code:* skill via the top-level `learn` engine's filters, but that's secondary. Triggers on: 'learn this codebase', 'update AGENTS.md', 'what should future agents know about this repo', 'learn from this coding session', 'improve the code plugin', 'what should the engineering loop have done'."
argument-hint: "[empty = current session/repo | session-id | topic | path to a monorepo package]"
allowed-tools: Bash(agents *), Bash(git *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Read(*), Write(*), Edit(*), Task(*)
user-invocable: true
---

# code:learn

A coding session just finished (or you were asked to learn a codebase cold). The primary
durable output is not a lesson filed away in this plugin — it's the **project's own
AGENTS.md**, updated so the next agent to touch this repo doesn't re-derive what you just
learned by reading source and grepping around.

**Read `skills/docs/write-agents-md.md` first.** It is the engine for what makes an
AGENTS.md entry worth writing — the five things a good entry has, the two-tier
contract/intent split, what NOT to write, and the README/AGENTS.md pairing rule. This
skill does not repeat that; it adds the part that's specific to a just-finished coding
session: **what you actually discovered, and where it goes.**

## Step 1 — Learn the codebase

Before writing anything, make sure you actually know the thing well enough to document it
faithfully. Pull together, from what this session already touched plus a quick pass over
what it didn't:

- **Entry points** — where build/test/release/deploy actually run from (`scripts/*.sh`,
  root `package.json` scripts, a `Makefile`). If the session ran one, you already know it;
  if not, find it (`ls scripts/`, `jq '.scripts' package.json`).
- **Structure** — the top-level modules/packages and what each owns. For a monorepo,
  which package this session's work lived in and its boundary with siblings.
  `git diff --stat` against the session's changes is the fast map; `rg` for the
  surrounding module's existing conventions fills in the rest.
- **Architectural concepts** — the canonical layers this session had to route through or
  around (a middleware, a registry, a config loader, a store) — the things that would have
  saved time if they'd been named up front instead of discovered by reading source.
- **Non-obvious invariants** — anything that was always true across the paths this session
  touched, that isn't obvious from a function name alone: single-use tokens, cardinality
  rules, fail-closed/fail-open behavior, "these two call sites must converge."
- **Gotchas** — anything that cost real time to figure out: a footgun, a subtlety in how a
  test harness runs, a place two similar-looking things diverge.

If nothing durable surfaced — the session was routine, or the repo is already
well-documented — say so and stop. Writing an entry with no invariant, no rationale, and
no pointer a future agent couldn't grep in one shot is exactly the dead weight
`write-agents-md` warns against.

## Step 2 — Write it into the project's AGENTS.md

- **Root vs package.** Root `AGENTS.md` gets top-level guidelines, entry points, and
  pointers. A monorepo package this session actually worked in gets its own narrower
  `AGENTS.md` (create one if it's missing and the package is one agents will repeatedly
  re-read — not every directory qualifies; see `write-agents-md`'s "when a README is
  wrong" section for the same registry-shaped-directory test applied here).
- **Merge, don't overwrite.** Read the existing file first. Add or update the specific
  entries this session's discoveries bear on; leave the rest alone. If an existing entry
  is now stale (the invariant changed, the file moved), fix it in place rather than
  leaving a second, contradicting entry.
- **Cite file:symbol inside this repo, never a host-local or cross-repo path.** The next
  reader may be on a fresh clone.
- **Separate contract from intent.** A checkable invariant ("a token is single-use,
  enforced by `session.test.ts`") is a different trust tier from a principle ("prefer one
  pipeline with adapters"). Don't blur them.
- **No secrets, no host-specific paths, no machine-local state.** Nothing that only makes
  sense on the box this session happened to run on — a token, an absolute `/Users/...`
  path, a locally-installed tool version. AGENTS.md ships with the repo to every clone.
- **Registry-shaped directory the session touched (commands/, skills/, a plugins dir)?**
  Update the paired README catalog too, and check the what-must-stay-in-sync table is
  still accurate — that table is the highest-value entry in a maintenance AGENTS.md.
- **`AGENTS.md` is canonical; `CLAUDE.md`/`GEMINI.md` are symlinks.** Edit `AGENTS.md`
  only.

Commit the change in the same PR as the work that taught it, so the code and the note
that explains it land together and the note doesn't drift before anyone reads it.

## Step 3 — Optionally fold a coding-workflow lesson into a code:* skill

Not every lesson from a coding session is about *this repo* — some are about *how you ran
the loop*: a bad assumption `code:loop` made about rebasing, a review check that missed
something, a dispatch-shape heuristic that was wrong. Those still belong in the plugin,
but only when they clear the top-level `learn` engine's bar — **generalization,
recurrence, root cause, durability** — the same four filters as any other `learn` target.
This is secondary to Step 2: a session that only taught you something about the code
plugin and nothing about the project it worked in still writes nothing to AGENTS.md, and
that's fine — not every session has both kinds of lesson.

| The lesson is about… | Skill |
|---|---|
| Draining a queue, conflict-graph parallelism, rebasing, what "done" means | `code:loop` |
| Pre-merge review, whole-repo diagnostics, security pass, merge verdict | `code:review` |
| Splitting a working tree into logical commits | `code:commit` |
| Publishing / activating / confirming a distributable is live | Repository-specific release process (outside the code plugin) |

**Routing calls that aren't a code:\* skill either:**

- **A tool gotcha** (a CLI, an editor, git behavior) belongs in *that tool's* skill
  (`computer`, `browser`), not stuffed into a `code:*` skill.
- **A hard engineering principle** ("done means end-to-end", "no unverified claims") is a
  rule, not a skill — `rules/subrules/foundations.md` and its siblings.
- **A new code:\* skill** is justified only when a genuinely missing *verb* in the loop is
  the lesson. A one-off or a refinement to an existing verb is a section edit, not a new
  skill.

**Don't break the contracts.** `code:loop` calls `code:review` by name (see
`loop/SKILL.md` "Tools you compose"). An edit to a verb's *contract* — what `code:review`
returns, what a caller checks before it treats something as done — can ripple to its
callers. Before changing a skill's promised output or check, grep the other `code:*`
skills for references to it and keep the contract intact, or update every caller in the
same scoped change. Additive sections are safe; contract changes are not.

The rest — recall discipline, the four filters, the rejects-list, non-regression, verify-
then-ship — is the `learn` engine. Follow it for Step 3; it doesn't apply to Step 2, which
is a direct write of what you now know about the project, not a lesson about the loop.
