---
name: resume
description: "Pick a whole PROJECT's work back up. Best-effort auto-detects the project from the CWD (GitHub repo + subdirectory → Linear project), reconstructs its in-flight work (live + interrupted sessions, open PRs, worktrees, open/doing tickets), presents it not-progressing-first, then OFFLOADS each item to a role=worker device — never the interactive/personal box. Not sessions:continue (one transcript) and not work:loop (the whole board). Triggers on: /work:resume, /resume, 'pick this project back up', 'resume the work on <project>', 'what was in flight here', 'get this project moving again'."
argument-hint: "[project name | empty = auto-detect from CWD | --all] [--here]"
allowed-tools: Bash(agents *), Bash(git *), Bash(gh *), Bash(linear *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Read(*), Task(*), AskUserQuestion(*)
user-invocable: true
---

# work:resume — pick a project's work back up

You sat back down at a project. Your job is to **re-establish what is in flight on it and get
the not-progressing work moving again** — without a human reconstructing state by hand, and
**without running the resumed work on the interactive/personal machine**.

Scope: `$ARGUMENTS` (empty = auto-detect the project from the CWD).

| This skill | Not this skill |
|---|---|
| One **project's** whole in-flight state, then resume it | `sessions:continue` — resume **one transcript** in this window |
| Reconstruct across sessions + PRs + worktrees + tickets | `work:dispatch` — route **one** item to an executor |
| **Offload** execution to workers | `work:loop` — drain the **whole board, every project** |
| Put crashed work back to *work* on the fleet | crash recovery that only reopened terminal windows is gone — see `/continue recover` |

## The compute rule (load-bearing — read first)

The session running `/work:resume` may be on the **personal laptop** (`role=personal`, marked
*never auto-place* because it freezes under load). So this skill **never runs the resumed
agent work "here."** The orchestrating session does only light, read-only reconstruction
(steps 1–3). Every actual resume in step 4 **offloads to a `role=worker` device**. The
placement engine already excludes the personal box: `agents devices pick` (what
`agents run --device auto` uses) returns a worker-only pool. Do not hand-pick devices and do
not fall back to local — a worker or a loud failure, never the laptop.

## 1. Identify the project — best-effort, from the CWD (no dedicated resolver needed)

An agent running this already has a CWD. Derive the project from what it gives you, in order,
stopping at the first confident match. `$ARGUMENTS` naming a project short-circuits the chain;
`--all` → every project that has in-flight work.

1. **Git anchor.** `git rev-parse --show-toplevel` (repo root) + `git remote get-url origin`
   → `owner/repo`; `git rev-parse --show-prefix` → the subdirectory (a monorepo/nested dir
   narrows which project).
2. **Defined-project fast path.** `agents projects status --path --json` (bare `--path`
   uses the cwd) auto-detects the project *containing* the cwd — repo-root or a bound
   subpath — and prints `{name, linear:{name,projectId}, root}`, so it hands you the project
   **and** its Linear binding in one call. Use it when `.name` is non-null; if it is `null`
   the cwd is in no defined project — fall through to step 3. (The session-start hooks
   resolve the same way via `agents projects for-cwd`; prefer `status --path` here because it
   ships in the current CLI and returns the binding inline. Both are best-effort — always
   tolerate a non-zero exit or a `null` name and fall through, never hard-depend on either.)
3. **Raw Linear match (fallback)** for an unregistered or deeply nested dir, or when step 2
   returned `null`: `linear projects --json` → best-effort match `owner/repo` + subdir against
   project name/key (`rush`→`Rush` matches by name; a repo whose name differs from its
   project, e.g. `agents-cli`→`AGI`, needs the binding, so step 2 wins when present). Fuzzy
   and best-effort — never assume a hard 1:1.
4. **Self-heal (optional).** When step 3 resolves a repo that had no binding, offer
   `agents projects add` / `agents projects link --linear` so the next resume hits the fast
   path.

Then pull the project's open/doing tickets fresh with `linear tasks --project <name>` (do not
rely only on the SessionStart injection — resume must work mid-session). **Ambiguity is
best-effort, not a stop:** name the most likely project and proceed; ask once only when
genuinely torn. **Fail loud only** when the CWD is not in a git repo *and* no project arg was
given — there is nothing to anchor on.

## 2. Reconstruct the in-flight state — read-only, in parallel

Gather from first-party sources (cheap, read-only subagents are ideal — do **not** relaunch
sessions just to see what they were doing):

| Source | How | Answers |
|---|---|---|
| Live sessions | `agents sessions --active` (scope to the project's repos) | what's running **now** — never duplicate it |
| Interrupted sessions | `agents sessions "<project/topic>"`, read the tail | mid-task threads that stalled |
| Open PRs | `gh pr list` on the project repo(s) | up for review / CI state |
| Local worktrees | `ls .agents/worktrees/` + `git -C <wt> status/log` | unlanded local work |
| Tickets | `linear tasks --project <name>` (or the `tickets` skill) | open/doing, the goal spine |

## 3. Present — not-progressing-first

One short table: **item · source · state · last touched · recommended next action**, ranked
**not-progressing-first** — idle-but-unfinished work is the highest-risk state (most likely
to be silently abandoned), so it ranks above the healthy running set, which collapses. This
is the read-only synthesis; no compute has been spawned yet.

## 4. Resume the work — on workers, never here

Hand each not-progressing item to a **`role=worker`** device. Compose the paths that already
do worker-only spawning; the orchestrating session only launches and monitors.

- **Many items / parallel:** compose `work:loop` **scoped to this one project** — it already
  does worker-only spawn + balanced rotation and drives each item to landed (engineering
  merges on green behind a non-author review). Spawn with **`--device auto`** (or an explicit
  worker pool via `agents teams --devices <workers>`); `devices pick` keeps the personal box
  out of the pool.
- **A single item:** `agents run --device auto` (single worker pick) or `work:dispatch` for a
  ticket with no session.
- **Monitor to landed from here.** Watch with a bounded check / `agents sessions --active`;
  never hold compute on the local machine.
- **`--here` (escape hatch, off by default):** continue one thread in this session via
  `sessions:continue` — **only** when this box is not `role=personal`. On the personal laptop
  it is refused with a one-line reason and the work is offloaded instead. Detect the local
  role via `agents devices list` (this machine's row) before honoring `--here`.

## 5. Not done at "resumed"

Drive each offloaded item to a landed result — merged PR, published outcome, completed task —
and update its ticket with proof. In flight is not done.

## Guardrails

- **Never run resumed compute on a `role=personal` box.** No local fallback in step 4 — a
  worker or a loud failure.
- Do not reopen terminal windows — the crash-window skill was removed. For crash recovery
  that finishes work headlessly, that's `sessions:continue recover`; this skill finishes the
  *work*, on workers.
- Do not duplicate a live session — check `agents sessions --active` first.
- Best-effort identification: proceed on the most likely project; don't stall on a fuzzy match.
- Reconstruction is read-only; spawning happens only in step 4, only on workers.
