---
name: review
description: "Review PRs and repo health with one skill, three modes. Default: recap the session's goal, discover every PR it opened, and review/merge each in dependency order. Given PR number(s): a deep sub-agent review (not the author) with file:line grounding, an architecture rubric (reuse, cross-cutting-at-source, no duplicate surfaces, doc-asserted invariants), and a security pass on risk-touching diffs. Given `repo` / a path / `--since <date>`: a read-only whole-repo architecture-and-quality diagnostic (four orthogonal categories, HTML report, no merge verdict). Triggers on: 'review the PR', 'code review', 'review #N', 'before I merge', 'block this PR', 'security review', 'what's wrong with this branch', 'health check', 'parallel implementations', 'audit drift'."
argument-hint: "[empty=session PRs | #PR [#PR...] | repo | <path> | --commits N | --since <date> | --branch] [--single|--team] [--security] [dry-run|no-merge]"
allowed-tools: Bash(gh *), Bash(git *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(wc *), Bash(jq *), Bash(agents *), Bash(go vet*), Bash(tsc*), Bash(staticcheck*), Bash(gocyclo*), Bash(biome*), Bash(shellcheck*), Bash(mcporter*), Bash(printenv*), Bash(sqlite3*), Bash(bun*), Bash(./*/scripts/sandbox.sh*), Bash(open*), Bash(xdg-open*), Bash(mkdir*), Bash(rush *), Read(*), Write(*), Edit(*), Agent(*)
user-invocable: true
---

# code:review

> A PR is open, or a branch has been sitting a while, or you just want to know what's
> wrong with the repo. This skill is the one review surface for all three: it recaps a
> session and lands every PR it opened (default), it spawns a sub-agent to review one or
> more PRs cold with file:line grounding (given PR numbers), or it runs a read-only
> architecture-and-quality diagnostic over a whole repo or path (given `repo` / a path /
> `--since`). The author never grades their own paper — every PR mode spawns someone who
> did not write the code.

**When this skill is the default path:** right after `gh pr create`, check whether the
repo's automated code reviewer is configured and posting on this PR (see `gh-merge-guard`
/ `truly-agentic-git-workflow`). If the bot is working, wait for it — do not stack this
skill on top. If the bot is missing, silent, down, or the repo has none, run this skill
**immediately** so merge-on-green is not blocked. Never hand the merge to the user because
the automated reviewer is down.

## Anti-bias rule

If you (the orchestrator) opened the PR(s) in the current session — and most of the time
you did — you **must not** be the reviewer. Spawn a sub-agent. The whole point is fresh
eyes. This applies to every PR-touching mode below; the whole-repo mode has no PR to be
biased about.

## Scope resolution — pick the mode

`$ARGUMENTS` parses into one of three modes:

| Pattern | Mode | What happens |
|---|---|---|
| empty, or `dry-run` / `no-merge` alone | **Session PRs** (default) | Recap this session's goal, discover every PR it opened, review each, merge/request-changes/close in dependency order |
| one or more `#123` / `123` | **PR review** | Deep sub-agent review of exactly those PRs, cold |
| `repo`, a path (`src/`, `apps/api`), `--commits N`, `--since "<date>"`, or `--branch` | **Whole-repo scan** | Read-only architecture + code-health + context + patterns diagnostic, HTML report, no merge verdict |

`--single` / `--team` force the dispatch shape in PR review mode. `--security` forces the
deep security pass even when the diff doesn't obviously touch a risk surface. `dry-run` /
`no-merge` apply only to Session PRs mode (print the plan and stop / comment but never
merge).

---

## Mode A — Session PRs (default)

Recap what the session was trying to do, find every PR it opened, review each with the
shared reviewer engine (Mode B), and execute the verdicts in dependency order.

### A1. Recap — what was the session trying to do?

Reconstruct the session's intent before looking at any PR. No paraphrase, no invention.
Sources (use all that apply): the user's first substantive message in this conversation
(quote it verbatim), any plan the user confirmed (`ExitPlanMode` content, or an explicit
"let's do X, Y, Z"), Linear ticket(s) opened or referenced, an `agents teams` distribution
plan if one was used (boundary contracts name the goal per teammate).

```
Session goal: <one or two sentences, quoted or tightly paraphrased>
Confirmed by:  <message timestamp or "plan approved at <step>" or "linear PROJ-XXX">
Subgoals:
  - <subgoal 1>          → expected surface: <files/dirs>
```

If you can't ground the goal in something the user said in this session, STOP. Ask via
`AskUserQuestion` for the goal in one sentence before continuing — reviewing without a
goal is theater.

### A2. Discover the PRs this session opened

Run in parallel:

```bash
gh pr list --author "@me" --state open --limit 50 --json number,title,headRefName,baseRefName,createdAt,url,isDraft,mergeable,mergeStateStatus,statusCheckRollup
gh pr list --state open --limit 50 --search "in:title $(date -u +%Y-%m-%d)" --json number,title,headRefName,baseRefName,createdAt,url
git log --oneline --since="6 hours ago" --all
git branch -a --sort=-committerdate | head -40
```

Build a candidate set from: PRs whose `createdAt` is inside this session's window, PRs
whose head branch matches one this session created, PRs explicitly named in `$ARGUMENTS`
(these override auto-detect), PRs opened by an `agents teams` run started this session
(check `agents sessions --active`). If the result is empty, say so and stop — "No PRs
opened in this session to review."

### A3. Build the dependency graph (stacked PRs)

For each candidate PR record `{number, title, head, base, author, draft, ci_state,
mergeable, url}`. If PR B's `baseRefName` equals PR A's `headRefName`, B is **stacked on**
A (edge A → B); a chain must merge root-up. If multiple PRs share the default branch as
base, they're independent. Validate with `gh pr view <n> --json baseRefName,headRefName`
for each — don't trust a cached list older than a few minutes.

### A4. Present the recap + PR table

Print before spawning any reviewer, as a GitHub-flavored markdown table (not ASCII
box-drawing — it breaks on wide titles and doesn't render in the UI):

```markdown
Session goal: <quoted>
PRs opened this session: N

| PR    | Title                              | Base          | Head            | CI      | Mergeable | Notes               |
|-------|------------------------------------|---------------|-----------------|---------|-----------|---------------------|
| #412  | feat: add oauth refresh            | main          | auth-refresh    | green   | clean     |                     |
| #413  | feat: wire login UI                | auth-refresh  | login-ui        | pending | clean     | stacked on #412     |

Stack graph:
  main ← #412 ← #413     (merge order: 412, 413)
```

One row per PR, uniform column count, titles truncated to ~50 chars, single-line cells,
`—` for empty. Flag suspected duplicates or already-merged-elsewhere PRs in Notes —
confirm with `git rev-list --count <head>..origin/$BASE` before claiming it (see
Duplicate detection below).

### A5. Review each PR — the shared engine

For every candidate PR, run the **Mode B reviewer engine** (below), one sub-agent per PR,
all dispatched in a single message so they run concurrently. Pass two extra pieces of
context into each brief: the session goal (quoted) and this PR's stated purpose
(title/body, quoted) — the reviewer's brief gets a prepended **GOAL** check:

```
0. GOAL: Does this PR meet the stated session goal it was opened for? Quote the goal.
   Quote the diff lines that satisfy it. (YES / PARTIAL / NO)
```

Everything else in the brief (tests, evidence, docs, pattern reuse & architecture,
messiness, security) is unchanged from Mode B.

### A6. Show the verdict matrix

```
Verdicts:
  #412  SHIP             — auth refresh complete, CI green, replaces old middleware (deleted src/auth/legacy.go).
  #413  REQUEST_CHANGES  — 3 concrete asks (session token storage, missing error handling, dead import).

Merge plan (stack order):
  1. #412  → merge (rebase)
  2. #413  → after fixes land, re-review; do not merge yet
```

If any PR is REQUEST_CHANGES, the stack pauses at that point — do NOT merge anything
stacked on top of it. If `$ARGUMENTS` contains `dry-run`, print the plan and stop here.

### A7. Execute the verdicts, in stack order (base → tip)

**SHIP** — comment the safety case in 2-4 lines (goal met, evidence, cleanup, scope), then
`gh pr merge <N> --rebase --delete-branch` (rebase preserves per-commit history; squash
only for genuine throwaway-WIP commit series). For a stacked PR, after the base merges,
confirm the next PR's base auto-retargeted or run `gh pr edit <next> --base $BASE` and
wait for `mergeable` to go clean before merging it.

**REQUEST_CHANGES** — comment concrete `file:line — change — why` bullets, no prose
padding. Do not merge. Don't `gh pr review --request-changes` (notification noise) unless
`$ARGUMENTS` contains `formal-review` — a comment is enough.

**CLOSE_DUPLICATE** — quote the commit/PR that already has the work, comment, then
`gh pr close <N> --delete-branch`. If `$ARGUMENTS` contains `no-merge`, comment verdicts
but never merge (request-changes and close-as-duplicate still execute).

### Duplicate detection

A PR is a duplicate when one of these is true — verify with a command, never assert it:
1. **Already in default branch:** `git rev-list --count <head>..origin/$BASE` adds
   nothing beyond `<base>..origin/$BASE`, and `git diff origin/$BASE..<head> -- <files>`
   is empty/whitespace-only.
2. **Squashed-merged elsewhere:** `git log origin/$BASE --oneline --since="14 days ago" |
   grep -i "<keyword>"` finds the absorbing commit; confirm the diff overlap by hand.
3. **Open elsewhere:** another open PR touches a superset of the same files for the same
   goal — quote the PR number and the overlap.

If you can't get a definitive answer, the verdict is REQUEST_CHANGES with "needs human
triage: possible duplicate of <SHA/#>", never CLOSE_DUPLICATE on a guess.

### A8. Verify and report

Re-query in parallel: `gh pr list --state all --search "<the PR numbers>" --json
number,state,mergedAt,closedAt` and `git fetch --prune origin`. Report a final table — what
merged (with SHA), what got request-changes (with comment URL), what closed (with
duplicate reference), what failed. A failed merge/close is never silently skipped — print
the error and name which PR needs hand-resolution.

### Session-mode don'ts

Don't merge a REQUEST_CHANGES PR because it "looks mostly fine." Don't merge stacked PRs
out of order. Don't force-push, rebase, or amend the author's commits to "help" (F5) —
comment and let them act. Don't summarize each PR with prose ("Overall this is solid…") —
verdicts are terse, evidence is quoted. Don't stop after the recap — it's a checkpoint,
not an exit ramp, unless `$ARGUMENTS` contains `dry-run`. Don't fabricate a session goal —
ask in one sentence and continue.

---

## Mode B — PR review (one or more PR numbers)

The engine Session mode calls per-PR, and what you get when you name PR number(s)
directly: `/code:review #356` or `/code:review #412 #413`.

### B1. Resolve target(s) + load context

For each target, resolve into branch + base:

```bash
PR=356
gh pr view $PR --json number,title,headRefName,baseRefName,additions,deletions,files,body \
  > /tmp/code-review-$PR.json
BRANCH=$(jq -r .headRefName /tmp/code-review-$PR.json)
BASE=$(jq -r .baseRefName /tmp/code-review-$PR.json)
git fetch origin $BASE $BRANCH
git diff origin/$BASE...origin/$BRANCH --stat > /tmp/code-review-$PR.stat
git diff origin/$BASE...origin/$BRANCH --name-only > /tmp/code-review-$PR.files
```

Quote the title + body + stat in your response so the user can confirm scope before you
spend a sub-agent. Multiple targets resolve independently and review in parallel — no
ordering dependency unless one target's base is another target's head (treat that as a
stack: see Mode A's dependency-graph handling).

### B1b. Load the requirement — the ticket and the plan, before any reviewer spawns

A reviewer with no requirement can only grade the code against itself. Resolve what this
change was *supposed* to do and pass it into the brief:

```bash
# Ticket: from the branch name, PR title, or PR body (e.g. RUSH-2462, #412)
TICKET=$(grep -oE '[A-Z]{2,}-[0-9]+' <<<"$BRANCH $TITLE $BODY" | head -1)
[ -n "$TICKET" ] && linear tasks "$TICKET" 2>/dev/null   # or: gh issue view <n>
# Plan: committed alongside the code, or under the dated artifact layout
ls .agents/plans/plan-*.html .agents/artifacts/*/plan-*.md 2>/dev/null | tail -5
```

Quote the **acceptance criteria** verbatim into the brief (not a paraphrase, and not the
whole ticket). The reviewer answers conformance per criterion before it reviews anything
else. If no ticket and no plan exist, say so in one line and pass the PR body as the
requirement — never spawn a reviewer with nothing to review against.

### B2. Pick the dispatch shape

Auto-classify when no flag is set. Bias toward cheap.

| Signal | Shape | Model |
|---|---|---|
| ≤ 3 files changed, all docs (`*.md`) | Single | Sonnet |
| ≤ 10 files, ≤ 300 lines net, one surface | Single | Sonnet |
| > 10 files OR > 300 lines OR ≥ 3 surfaces touched | Team | Sonnet per teammate |
| Pure dependency bump / lockfile only | Single | Sonnet |
| Touches security / auth / billing surface | Single (or team) | Sonnet |

"Surface" = one of the project's top-level modules. Count distinct top-level surfaces
touched. State the decision before spawning: `Dispatch: single-agent (Sonnet) — 3 files,
173 lines, one surface (api), no auth/billing.` User override via `--single`/`--team`;
don't ask.

### B3. Pattern grounding (BEFORE spawning the reviewer)

The reviewer hates "follow existing patterns" without specifics — you prepare them. For
each new function / file / config block the diff adds, find the closest canonical
neighbor in the same surface and quote its file:line:

```bash
rg -n '^export (async )?function (router|register|GET|POST)' <surface>/src/
git ls-tree -r HEAD --name-only | rg "$(basename ${SOURCE_FILE} .ts)\.test\.ts" | head -5
```

Build a "patterns to compare against" list — 3-5 specific file:line citations max — and
pass it into the reviewer's brief verbatim. The reviewer checks REUSE of THESE, not
generic "code style."

### B4. Spawn the reviewer

**Single-agent** — one `Agent` call, `subagent_type: "code-reviewer"` (the repo ships that
subagent at `subagents/code-reviewer/AGENT.md`, materialized into every subagents-capable
harness; fall back to `"claude"` on a harness without subagent support), `model: "sonnet"`,
the brief below. The subagent already
carries the standing rubric — the hunt classes, the three-kill refutation pass, the
non-checks list, and the output shape — so the brief supplies only what is specific to
this PR: context, canonical patterns, and the session goal. B5 has both shapes: the short
brief when the subagent loaded, the full one when it did not. **Team** — cut the diff by
surface, one teammate per surface via `agents
teams add ... --mode plan` (read-only); each brief carries only that surface's diff +
pattern list, plus Mission / Full scope / Your assignment / Boundary contract / Success
criteria. The orchestrator collects each critique and synthesizes one verdict. Multiple
PR targets each get their own single-agent-or-team dispatch, all in one message.

### B4b. Security pass — its own agent, spawned alongside the reviewer

**Spawn it as a separate agent in the same message as the reviewer, not as a check folded
into that reviewer's brief.** Two reasons: it runs concurrently so it costs wall-clock
nothing, and a reviewer working a long correctness rubric reliably gives the security tail
the least attention. One cheap Sonnet agent whose only job is "does user input reach a
sink" finds more than check #6 of seven ever did.

Run it whenever changed files touch: HTTP/API routes, controllers, middleware · auth /
sessions / billing / IAM · DB queries, ORM raw SQL, query builders · HTML rendering,
share/preview pages · shell exec, `child_process`, `exec.Command`, `osascript` ·
native/IPC boundaries (Electron main↔renderer, extension content scripts) · infra
(Terraform, CDN/worker config, Dockerfile, K8s) · dependency/lockfile bumps · anything
that could carry a leaked secret. Also whenever `--security` is passed.

Skip it only for a diff that touches none of those (a docs edit, a pure rename) — say so
in one line rather than silently dropping it. For a security-heavy diff, widen to one
read-only `Explore` agent per relevant vulnerability class, all in one message.

**Hand off to a dedicated security skill when one is installed.** If the box has a
`security` or `audit` skill, invoke it scoped to this PR's changed-file list instead of
restating its rubric here — it owns the class taxonomy, the advisory cross-check, and the
false-positive catalogue, and two copies of that knowledge will drift. The table below is
the **self-contained fallback**: the system layer must work on a fresh install with nothing
else configured, so `code:review` never hard-depends on a skill that may be absent. Check
first, route if present, fall back if not.

| Class | Run when | Grep for |
|---|---|---|
| **SECRETS** | Always | `sk_live`, `ghp_`, `xoxb-`, `BEGIN PRIVATE KEY`, newly-tracked `.env*` |
| **INJECTION** | DB/query code changed | String interpolation near `.query()`/`SELECT`, raw-escape-hatch use |
| **AUTH** | Routes/middleware/auth changed | Endpoints with no auth middleware, skippable role checks, IDOR |
| **XSS** | HTML/user output changed | `innerHTML`/`dangerouslySetInnerHTML`, missing CSP |
| **SHELL** | Shell-exec touched | `sh -c` with concat, `exec` with user input, path traversal |
| **IPC / NATIVE** | Electron main/preload changed | `nodeIntegration: true`, `contextIsolation: false` |
| **INFRA** | CDN/Terraform/Dockerfile/K8s changed | SSRF in worker fetches, open redirects, `privileged: true` |
| **DEPS** | Lockfiles changed | `npm audit --json`; web-search current CVEs (training data is stale) |

**Filter false positives HARD — verify every CRITICAL/HIGH yourself** before it ships:
Stripe `pk_live`/`pk_test`, PostHog `phc_*`, anon JWTs, referrer-restricted `AIza...` keys,
and public `client_id`s are not leaks. "Missing auth" — check for router/app-level
middleware, not just the handler. "SQL injection" — check parameterization. "XSS via
innerHTML" — check whether the source is server-controlled. "CVE" — confirm your code
calls the vulnerable path and your version is in the affected range. Report only verified
findings; end with a **False positives filtered** line so they don't resurface.

### B5. The reviewer brief (fill brackets)

Two shapes, one source of truth. **When the `code-reviewer` subagent loaded** (the normal
case), send only the `CONTEXT` and `CANONICAL PATTERNS` blocks below, plus the `GOAL` line
in Session mode — everything from `WHAT YOU MUST CHECK` down already lives in
`subagents/code-reviewer/AGENT.md` and restating it is a second home for one rubric. **On a
harness without subagent support**, drop the whole thing in verbatim: that is what the
rest of this template is for. Either way the rubric changes in exactly one place — the
subagent — and this fallback copy tracks it.

```
You are reviewing PR #<N> on <owner/repo>. You did NOT write this code.
Your job is to find what's missing or wrong before this merges.

CONTEXT
  PR title:   <quote>
  PR body:    <quote first 500 chars>
  Diff stat:  <paste --stat output>
  Base:       <base ref>
  Files:      <paste --name-only output>
  Session goal (omit if not in Session mode): <quoted goal, or "N/A">

CANONICAL PATTERNS TO COMPARE AGAINST
  <Step B3 output: 3-5 specific file:line citations, 5-10 lines each, with line numbers>

WHAT YOU MUST CHECK (in this order, stop at first BLOCKER)

0. GOAL (only if a session goal was given) — does this PR meet it? Quote the goal
   and the diff lines that satisfy it. (YES / PARTIAL / NO)

1. Tests — is there a 1:1 test file for each new/modified source file? The codebase
   rule: test file = source file, 1:1. Name any missing test path.

2. End-to-end evidence — does the PR description include proof the changed flow runs?
   Real output: curl response, test log, screenshot, deploy URL — not "build passes."
   For UI changes, a screenshot is required. If missing, name what's missing.
   **Missing run evidence on a user-visible change is a BLOCKER, not a style nit** —
   same severity floor as a confirmed security finding. The fix is cheap (run it,
   capture it, attach it), so do not downgrade it to SHOULD to get to READY TO MERGE.

3. Docs — for each changed surface, is there a corresponding doc update? CHANGELOG.md
   entry, runbook section if ops behavior changed, README/AGENTS.md/CLAUDE.md if
   conventions changed. Name any missing doc path.

4. Pattern reuse & architecture — for each NEW function / config block, does it reuse
   the canonical pattern above, or invent a parallel one? Also check, for anything
   architecturally load-bearing in this diff:
     - Reuse of existing primitives (no re-implemented helper that already exists).
     - Cross-cutting logic added at the canonical source, not ad-hoc in a consumer
       (e.g. auth/validation/config-loading inlined where a middleware/validator/
       loader already exists in this surface).
     - No duplicate surface — a new file that duplicates a concern already split
       elsewhere in this directory.
     - Load-bearing seams honored — a caller goes through the registration factory /
       registry / store the surface already uses, not a fresh ad-hoc dispatch.
     - Doc-asserted invariants vs code — if a CLAUDE.md/AGENTS.md/README nearby
       asserts something is gone or must never happen ("X is gone", "never use X"),
       confirm the diff doesn't reintroduce it.
   Cite the existing pattern's file:line AND the new code's file:line, quote both.
   If the PR added a parallel implementation or broke an invariant: name it.

5. Messiness — did the diff make any of these worse? A function past 100 lines
   (warning, not BLOCKER); a switch/if-chain gaining an arm instead of a map; a new
   file under a directory that already splits the same concern across files. Quote
   before/after if found.

6. Security (ONLY if the diff touches a risk surface). Classify by vulnerability
   class (SECRETS, INJECTION, AUTH, XSS, SHELL, IPC, INFRA, DEPS). For each plausible
   issue: read the sink, trace whether user input reaches it, check for middleware /
   parameterization / escaping in between. Filter false positives HARD. Report only
   what you can prove reaches a real sink, file:line + quote. A confirmed CRITICAL/
   HIGH is a BLOCKER. If clean, say "security: clean".

OPTIONAL — code-health as supporting evidence, never the product. If go vet / tsc
--noEmit / staticcheck / biome are on PATH for a changed surface, you may run them and
cite a hit as extra evidence for a finding above — but a tool warning alone, with no
architectural or correctness story, is not a finding on its own.

NON-CHECKS — do NOT comment on these:
  - Style nits enforced by formatters (prettier, gofmt)
  - Naming preferences absent concrete confusion
  - Hypothetical future requirements ("what if we later need X?")
  - Test coverage for trivial guards or constants
  - "Add abstractions for flexibility"
  - Doc rewrites that don't add information

OUTPUT FORMAT — exactly this shape

## Verdict
READY TO MERGE | CHANGES REQUESTED | BLOCKED

## Evidence ran
<one line per E2E check quoted from the PR body>

## Findings
For each finding:

### <BLOCKER|SHOULD|NICE> — <one-line summary>
File: `path/to/file.ts:42-58`
Existing pattern (if relevant): `other/file.ts:100-110`

```ts
<quote the relevant 5-15 lines from the diff, with line numbers>
```

<2-3 sentences explaining the problem concretely. Propose the fix IF obvious. NO
speculation. If you can't prove it, drop the finding.>

Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.
```

### B6. Synthesize + post — findings land **on the lines**, not in a wall

Read the reviewer's output (merge per-surface critiques into one verdict for a team
review — BLOCKER count wins). Then post **one review** carrying inline comments, not a
single blob the author has to map back onto the diff themselves. Every finding already
carries `file:line`; that is exactly what anchors a comment.

Split the findings first:

- **Anchorable** — the cited line is on the **right side of this diff** (an added or
  context line in the PR's own hunks). Check against `git diff origin/$BASE...origin/$BRANCH`,
  which you already have from B1.
- **Not anchorable** — a finding about a file the diff never touched (an absent call site,
  an orphaned path, a missing test), or a line that exists only on the left side. These
  are real findings and often the most valuable ones; they go in the review **body**.

Post both in a single API call so the author gets one notification, not N:

```bash
jq -n --arg body "$(cat <synthesized>.md)" --arg sha "$(gh pr view $PR --json headRefOid -q .headRefOid)" \
  --slurpfile c <inline-comments>.json \
  '{body: $body, event: "COMMENT", commit_id: $sha, comments: $c[0]}' \
  | gh api repos/{owner}/{repo}/pulls/$PR/reviews --input -
```

`<inline-comments>.json` is a **single JSON array** — `$c[0]` takes that array, so a JSONL
file would silently post only its first line. Each element is `{"path": "...", "line": <n>,
"side": "RIGHT", "body": "**BLOCKER** — <one line>\n\n<why, and the fix>"}`; use
`start_line` with `line` for a range. Keep the inline body short — the defect and the fix.
The review body carries the verdict, the non-anchorable findings, and the `Filtered:` line.

When **nothing** is anchorable — a docs-only diff, or every finding sits outside the
hunks — skip the `comments` key entirely rather than sending `[]`, or just post the body
with `gh pr comment`. An empty array is a review with no content attached to it.

`event: "COMMENT"` deliberately: `REQUEST_CHANGES` blocks the PR and pages the author, so
reserve it for `$ARGUMENTS` containing `formal-review`. Never `APPROVE` your own work.

If the API call fails — a stale `commit_id` after a force-push, a line that moved, an
outdated position — do not silently drop the findings: fall back to the whole synthesized
report as one `gh pr comment <N> --body-file <synthesized>.md`, and say in the body that
inline anchoring failed and why.

### B7. Act on the verdict

| Verdict | Action |
|---|---|
| READY TO MERGE | `gh pr merge <N> --rebase` after CI is green and a non-author review is clear. Squash only for throwaway-WIP commit series. |
| CHANGES REQUESTED | Leave the comment. Iterate in the same worktree. Do NOT spawn a fresh review until changes land. |
| BLOCKED | Document the blocker, park the ticket in the tracker's blocked state with a concise comment, move on. Don't unilaterally close or revert. |

A red required check isn't automatically a code problem — read the **step-level**
conclusions before treating "CI failing" as CHANGES REQUESTED:
`gh api repos/<owner>/<repo>/actions/jobs/<id> --jq '.steps[] | "\(.conclusion)\t\(.name)"'`.
A dead `checkout`/`setup`/cache step on a self-hosted runner is infra — re-run
(`gh run rerun <run-id> --failed`), don't send a clean PR back for changes it doesn't need.

### When to skip Mode B

Tag-only / release PRs (no code change). PRs where the repo's automated reviewer is
**configured and has already posted** a clear verdict — don't duplicate it. PRs the user
explicitly said to ship unreviewed — state that you're skipping and why.

---

## Mode C — Whole-repo / path architecture & quality scan

Read-only. Never modifies code, never returns a merge verdict, never blocks anything.
Emits ranked findings with file:line, rendered as an HTML report. Fixes flow back through
`/code:loop` (one finding = one queue item) or a direct `/code:commit` for trivial cases.

Invoke when: landing a multi-commit branch before opening a PR, a fresh checkout of an
unfamiliar surface, a recurring drift check on the default branch, or "what's wrong with
this branch" / "any parallel implementations of X?". Mode C exists because the rubric is
the same one Mode B applies to a diff: reuse of existing primitives, cross-cutting logic
at the source, no duplicate surfaces, load-bearing seams honored, doc-asserted invariants
respected. Mode C runs that rubric over a whole repo or path instead of one PR's diff.

### C1. Scope resolution

| `$ARGUMENTS` pattern | Mode | Diff base |
|---|---|---|
| `--commits N` | last-N | `HEAD~N..HEAD` |
| `--since "<date>"` | since-window | commits since `<date>` |
| `--branch` | branch | `origin/$BASE...HEAD` |
| `repo` (no path) | corpus | every tracked file in the repo |
| `<path>` (one or more dirs/files) | corpus | every file under each path |

Corpus mode ignores the diff filter — it audits every file under the path, useful for a
fresh-eyes pass on an unfamiliar surface.

```bash
RUN_TS=$(date -u +"%Y-%m-%dT%H-%M-%S")
RUN_DIR="$(git rev-parse --show-toplevel)/.agents/artifacts/$RUN_TS-review"
mkdir -p "$RUN_DIR/findings"
SKILL_DIR="$(git rev-parse --show-toplevel)/.agents/plugins/code/skills/review"
```

`.agents/artifacts/` is the shared home for finished output products (tracked in git —
committed runs are a history of what was found and when). Naming is `<TS>-<skill>` so both
`ls -t` and lexical sort give chronological order alongside other skills writing there
(`audit`, `review`). Don't use `.agents/scratch/` — that's gitignored, mid-process-only.

```bash
# diff mode
git diff --name-only "$DIFF_BASE" > "$RUN_DIR/files.txt"
# corpus mode
git ls-files -- "${PATHS[@]}" > "$RUN_DIR/files.txt"
```

### C2. Findings JSON schema

Every pass emits a JSON array; the aggregator merges, the renderer reads.

```json
{
  "category": "architecture" | "code-health" | "context" | "patterns",
  "severity": "blocker" | "should" | "nice",
  "rule": "short one-line description (e.g. 'inline auth bypasses middleware')",
  "file": "relative/path/from/repo/root.ts",
  "line_start": 240,
  "line_end": 244,
  "snippet": "<5-15 lines verbatim of offending code>",
  "anchor_file": "relative/path/to/canonical.ts" | null,
  "anchor_line": 18 | null,
  "anchor_snippet": "<5-15 lines verbatim>" | null,
  "fix_one_line": "wrap handler in requireAuth()",
  "tool": "architecture-subagent" | "go-vet" | "tsc" | "invariants" | "identifiers" | "signatures" | "..."
}
```

Mandatory: `category`, `severity`, `rule`, `file`, `line_start`, `tool`. Anchor fields are
non-null only when the finding has a canonical counterpart.

### C3. Run inspections in parallel

Six independent passes, five pure bash + one Sonnet subagent. Each writes
`$RUN_DIR/findings/<pass>.json` independently — no shared state, no ordering.

```bash
bun "$SKILL_DIR/code-health.ts" "$RUN_DIR" > "$RUN_DIR/findings/code-health.json" &
bun "$SKILL_DIR/invariants.ts" "$RUN_DIR" > "$RUN_DIR/findings/invariants.json" &
bun "$SKILL_DIR/identifiers.ts" "$RUN_DIR" > "$RUN_DIR/findings/identifiers.json" &
bun "$SKILL_DIR/signatures.ts" "$RUN_DIR" > "$RUN_DIR/findings/signatures.json" &
```

- **Code health** (`code-health.ts`) — runs whichever of `go vet`, `tsc --noEmit`,
  `staticcheck`, `gocyclo -over 20`, `biome check`, `shellcheck` are on PATH for each
  surface in `files.txt`; findings from each tool's output. Missing tools are recorded to
  `$RUN_DIR/skipped.json` for the HTML footer. Never auto-installs.
- **Invariants** (`invariants.ts`) — parses every `CLAUDE.md`/`AGENTS.md`/`README.md` near
  the changed files for negative-assertion patterns (`X is gone`, `never use X`), re-greps
  the codebase for the asserted-absent token. Any hit = BLOCKER.
- **Identifiers** (`identifiers.ts`) — cross-references identifier classes against live
  sources of truth: `mcp__*` names against `mcporter list`, env vars against `printenv` /
  `agents secrets ls`, CLI flags in fenced code blocks against `<binary> --help`. A
  reference with no live counterpart = BLOCKER.
- **Patterns** (`signatures.ts`) — for each new top-level function, computes a shape
  signature (input types, output types, primary side-effect class) and clusters against an
  index of existing functions in the affected surfaces. Clusters of 2+ functions across 2+
  files in different modules = SHOULD finding. Ignores names, so `slugify`/`kebabCase`
  cluster when they should; divergent-contract `sanitize*` families don't all cluster.

**Architecture** (Sonnet subagent) — the same rubric Mode B applies to a diff, run over
the whole scope:

```
Agent(description: "Architecture pass for code:review repo mode", subagent_type: "claude",
      model: "sonnet", prompt: <brief below, filled>)
```

```
You are auditing CHANGED-OR-SCOPED code for STRUCTURAL anti-patterns. You are NOT a
linter, NOT a security reviewer. Find places where the code inlines logic that a
canonical layer already owns, or duplicates a primitive that already exists.

SCOPE: {{ comma-separated surfaces / paths }}
SURFACE CONVENTIONS: read each surface's CLAUDE.md and AGENTS.md
CANONICAL ANCHORS (extracted via rg): {{ list — e.g. api/src/middleware/auth.ts:18 }}
DIFF OR FILE LIST: {{ paste git diff --stat + diff, or the corpus file list }}

YOUR JOB — for each new or significant file, look for:
- Inline auth/authz where a middleware/decorator exists.
- Inline validation where a validator module exists.
- Direct DB / HTTP / FS calls in handlers where a repository/service layer exists.
- New route registered without using the surface's registration factory.
- Configuration read ad-hoc instead of through the surface's config loader.
- A new abstraction that duplicates an existing canonical one in THIS surface.
- if/switch chains for dispatch where a registry/map pattern is canonical.
- A load-bearing seam bypassed — a caller going around the store/registry the rest
  of the surface already uses.

For each finding, ONE JSON object per line (JSONL):
{"category":"architecture","severity":"blocker"|"should"|"nice","rule":"<one line>","file":"<rel path>","line_start":<n>,"line_end":<n>,"snippet":"<5-15 lines verbatim>","anchor_file":"<rel path or null>","anchor_line":<n or null>,"anchor_snippet":"<verbatim or null>","fix_one_line":"<one line>","tool":"architecture-subagent"}

NON-FINDINGS — do NOT emit: style nits, hypothetical futures, "add an abstraction for
flexibility" when none exists yet, trivial-guard test coverage, anything you can't tie to
a canonical anchor in THIS surface.

Output: JSONL to stdout. Empty output = no findings.
Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.
```

Capture the subagent's stdout, convert JSONL → JSON array, write to
`$RUN_DIR/findings/architecture.json`. `wait` for all five bash passes plus the subagent —
wall-clock is bounded by the slowest (usually the subagent).

### C4. Aggregate

```bash
bun "$SKILL_DIR/aggregate.ts" "$RUN_DIR/findings" > "$RUN_DIR/findings.json"
```

Merges all per-pass JSON, sorts by severity (blocker > should > nice) then file then
line_start, dedupes findings sharing `(file, line_start, rule)`.

### C5. Render & open

```bash
bun "$SKILL_DIR/render.ts" "$RUN_DIR/findings.json" "$RUN_DIR" > "$RUN_DIR/index.html"
case "$OSTYPE" in
  darwin*) open "$RUN_DIR/index.html" ;;
  linux*)  xdg-open "$RUN_DIR/index.html" ;;
  *)       echo "report at: $RUN_DIR/index.html" ;;
esac
```

Single-file, self-contained HTML (inline CSS + JS, no external deps). Sticky header (scope,
timestamp, totals, copy-pastable rerun command); filter chips (severity / category /
surface, multi-select, client-side); collapsible finding cards (rule, severity badge,
clickable `file:line`, quoted snippet, anchor when present, one-line fix); per-finding
actions — copy as `/code:loop` task, copy Linear ticket command, copy `file:line`; a
multi-select "create task batch" clipboard action; footer listing skipped checks and
missing-from-PATH tools. Scale: 0-20 findings all open by default; 21-100 only BLOCKERs
open; 100+ all collapsed with a "Show all" toggle.

### C6. Chat output

```
REPO REVIEW — scope: <mode> (<commit-or-range>)
Surfaces: <comma-separated>

  Category                Block  Should  Nice
  ─────────────────────  ─────  ──────  ────
  Architecture & Design      <n>     <n>   <n>
  Code Health                <n>     <n>   <n>
  Context Quality            <n>     <n>   <n>
  Patterns                   <n>     <n>   <n>

Top 3 blockers:
  1. <CAT>  <file>:<line>   ← <rule>

→ Full report: file://<absolute path to index.html> (opened in browser)
→ Rerun:       /code:review <same args>
```

Chat output is the pointer — totals table, three worst BLOCKERs, `file://` URL. Nothing
more; the rest lives in the browser.

### Mode C don'ts

Don't auto-install code-health tools — if missing from PATH, skip the sub-pass and note it
in the HTML footer (F1: act with what's available). Don't fan out via `agents teams` — this
is a sub-90-second diagnostic, teams are for multi-surface implementation. Don't include
Halstead / Maintainability Index thresholds — the skipped-checks footer explains why.
Don't return a merge/request-changes verdict or a non-zero exit — Mode C is read-only,
never a merge block. Don't modify code — the HTML report's clipboard actions are how fixes flow,
through `/code:loop` or `/code:commit`. Don't write to `/tmp` — output lands in
`<repo>/.agents/artifacts/<ts>-review/`.

---

## Hard lines this skill enforces, all modes

1. The author never reviews their own PR. Spawn a sub-agent.
2. Every finding cites file:line + quoted code. No paraphrase.
3. Pattern criticisms name the specific pattern by file:line. No generic "follow existing
   patterns."
4. The non-checks list is hard. Reviewers who add style/naming/speculative nits get
   re-prompted.
5. Default to Sonnet; a team only when the diff spans multiple surfaces. Never omit
   `model`.
6. Security findings are verified at the sink before they ship — no CRITICAL survives
   without a file:line quote and a traced path from user input.
7. Mode C never returns a merge verdict and never modifies code — findings only.
8. Never merge without one of: green CI, a quoted run, or explicit user override ("it
   looks correct" is not evidence).

**Web or native surface touched? Drive it, don't describe it.** Verification
of anything with a UI runs through `agents browser` (web, headless on your
machine) or `agents computer` (native, element mode) — screenshot, read back,
then claim. A verification claim with no drive of the real surface is a
proxy, not proof.
