---
name: review
description: "Pre-merge review of a PR by a sub-agent (not the author). Picks single-agent (Sonnet) or `agents teams` based on diff size + surface count; auto-detects but accepts override. Scans the diff for neighboring canonical patterns BEFORE spawning, then briefs the reviewer with file:line evidence demands. Reviewer focuses on missed tests, missing E2E proof / screenshots, missed docs, missed pattern reuse, increasing messiness, and — when the diff touches a risk surface — a security pass that classifies by vulnerability class and filters false positives hard. Every finding cites file:line + quoted code; no paraphrase. Triggers on: 'review the PR', 'code review', 'review #N', 'sub-agent review', 'before I merge', 'gate this PR', 'security review', 'check this for vulnerabilities'."
argument-hint: "[PR# | branch | worktree path] [--single|--team] [--haiku|--sonnet] [--security]"
allowed-tools: Bash(gh *), Bash(git diff*), Bash(git log*), Bash(git status*), Bash(git rev-parse*), Bash(git show*), Bash(git ls-tree*), Bash(git blame*), Bash(rg*), Bash(ls*), Bash(wc*), Bash(agents *), Read(*), Agent(*)
user-invocable: true
---

# code:review

> A PR is open. The author (a single agent — often you) wrote it AND tested it. That's not enough. This skill spawns a sub-agent who hasn't seen the work to review it cold, with strict evidence demands. Output: a PR comment + a merge/request-changes verdict. The author never grades their own paper.

## Anti-bias rule

If you (the orchestrator) opened this PR in the current session — and most of the time you did — you **must not** be the reviewer. Spawn a sub-agent. The whole point is fresh eyes.

## Step 1 — Resolve target + load context

`$ARGUMENTS` is `<target> [flags...]`. Parse:

- **Target**: PR number (`#356` or `356`), branch slug, or worktree path. Empty = current HEAD.
- **`--single`** / **`--team`**: force the dispatch shape.
- **`--haiku`** / **`--sonnet`**: force the model on a single-agent review. Default Sonnet.
- **`--security`**: force the deep security pass (Step 4b) even if the diff doesn't obviously touch a risk surface. Use before a launch, when auditing an unfamiliar contributor's PR, or when the change is small but sensitive.

Resolve into:

```bash
# PR number → branch
PR=356
gh pr view $PR --json number,title,headRefName,baseRefName,additions,deletions,files,body \
  > /tmp/code-review-$PR.json
BRANCH=$(jq -r .headRefName /tmp/code-review-$PR.json)
BASE=$(jq -r .baseRefName /tmp/code-review-$PR.json)

# Diff against base
git fetch origin $BASE $BRANCH
git diff origin/$BASE...origin/$BRANCH --stat > /tmp/code-review-$PR.stat
git diff origin/$BASE...origin/$BRANCH --name-only > /tmp/code-review-$PR.files
```

Quote the title + body + stat in your response so the user can confirm scope before you spend a sub-agent.

## Step 2 — Pick the dispatch shape

Auto-classify when no flag is set. The bias is toward cheap.

| Signal | Shape | Model |
|---|---|---|
| ≤ 3 files changed, all docs (`*.md`) | Single | Sonnet |
| ≤ 10 files, ≤ 300 lines net, one surface | Single | Sonnet |
| > 10 files OR > 300 lines OR ≥ 3 surfaces touched | Team | Sonnet per teammate |
| Pure dependency bump / lockfile only | Single | Sonnet |
| Touches security / auth / billing surface | Single (or team) | Sonnet |

"Surface" = one of the project's top-level modules (e.g. `app`, `api`, `web`, `cli`, `infra`, `docs`). Count distinct top-level surfaces touched.

State the shape decision before spawning:

```
Dispatch: single-agent (Sonnet)
Why: 3 files, 173 lines, one surface (api), no auth/billing.
```

User override happens via the `--single`/`--team`/`--sonnet` flags. Don't ask.

## Step 3 — Pattern grounding (BEFORE spawning the reviewer)

The reviewer hates "follow existing patterns" without specifics. So you (the orchestrator) prepare the specifics. For each new function / file / config block added by the diff, find the closest canonical neighbor in the same surface and quote its file:line.

Concrete probes:

```bash
# For a new shell helper / cron added under a deploy bootstrap script:
rg -nP '^(install -m \d+ -o root -g root /dev/stdin /usr/local/bin/|write_if_changed /etc/cron\.d/)' \
   <path>/deploy/bootstrap.sh

# For a new alert / config rule added to a deploy script:
rg -n 'name: "' <path>/scripts/deploy-*.ts

# For a new endpoint added under the API source tree:
rg -n '^export (async )?function (router|register|GET|POST)' <api>/src/

# For a new test file:
git ls-tree -r HEAD --name-only | rg "$(basename ${SOURCE_FILE} .ts)\.test\.ts" | head -5
```

Build a short "patterns to compare against" list — 3-5 specific file:line citations max — and pass it into the reviewer's brief verbatim. The reviewer should be checking REUSE of THESE, not generic "code style."

## Step 4 — Spawn the reviewer

### Single-agent path (Sonnet)

Spawn ONE `Agent` call with `subagent_type: "claude"` and `model: "sonnet"`. The prompt is structured as the brief below. **Critical**: end every reviewer prompt with the file:line grounding line (research discipline: no unverified claims).

### Team path (`agents teams`)

Cut the diff by surface. One teammate per surface. Each teammate's brief includes only THEIR surface's diff + only THEIR surface's pattern list. Coordinate with `agents teams add` + `--name <surface>`. Use `--mode plan` (read-only). The orchestrator collects each `critique.md` and synthesizes one verdict.

Every teammate brief needs: **Mission**, **Full scope** (so each has the big picture), **Your assignment** (files owned), **Boundary contract** (NOT to touch), **Pattern list** (Step 3 output for their surface), **Success criteria**.

## Step 4b — Security pass (when the diff touches a risk surface, or `--security`)

A quality review and a security review look at the same diff with different eyes. Run this pass when the changed files touch any risk surface below, or when `--security` is set. For a small diff, fold it into the single reviewer's brief as check #6. For a security-heavy diff (auth/billing/crypto/native, or `--security` on a multi-surface change), escalate: spawn one read-only `Explore` agent per relevant vulnerability class, in parallel, in a single message.

**Risk surfaces** (any touched file → run the pass): HTTP/API routes, controllers, middleware · auth / sessions / billing / IAM · DB queries, ORM raw SQL, query builders · HTML rendering, share/preview/embeddable pages · shell exec, `child_process`, `exec.Command`, `osascript` · native / IPC boundaries (Electron main↔renderer, extension content scripts) · infra (Terraform, CDN/worker config, Dockerfile, K8s) · dependency/lockfile bumps · anything that could carry a leaked secret (`*.env*`, `CLAUDE.md`, `docs/`, deploy scripts).

**Vulnerability classes — run the ones the changed surface warrants:**

| Class | Run when | Grep for |
|---|---|---|
| **SECRETS** | Always | `sk_live`, `ghp_`, `xoxb-`, `BEGIN PRIVATE KEY`, newly-tracked `.env*`, secrets in docs/`CLAUDE.md` |
| **INJECTION** | DB/query code changed | String interpolation near `.query()`/`.rpc()`/`SELECT`, raw-escape-hatch use, `$where`/`$ne` |
| **AUTH** | Routes/middleware/auth changed | Endpoints with no auth middleware, skippable role checks, IDOR (object access by user-controlled id without ownership check), JWT verification |
| **XSS** | HTML/user output changed | `innerHTML`/`dangerouslySetInnerHTML`, user input in templates, missing CSP / `X-Frame-Options` |
| **SHELL** | Shell-exec / `child_process` touched | `sh -c` with concat, `exec` with user input, path traversal via user-controlled paths |
| **IPC / NATIVE** | Electron main / preload changed | `nodeIntegration: true`, `contextIsolation: false`, `executeJavaScript` with user input, custom protocol handlers |
| **INFRA** | CDN/Terraform/Dockerfile/K8s changed | SSRF in worker fetches, open redirects, missing security headers, `privileged: true`, broad RBAC |
| **DEPS** | Lockfiles changed | `npm audit --json` / `go list -m all`; web-search "CVE \<package\> \<version\> 2026" for anything outside the boring set |

Each Explore agent reads the cited code, greps the patterns, and **web-searches current advisories** for the libraries in scope (the model's training data is stale on CVEs — always confirm against the live advisory). Agent report format: severity · `file:line` · quoted snippet · attack vector · confidence (medium/low MUST list disconfirming evidence) · one-line fix.

### Filter false positives HARD — this is the whole game

Security scans are mostly noise. **Verify every CRITICAL/HIGH yourself** (read the cited file, trace whether user input actually reaches the sink, check for middleware/parameterization/escaping in between) before it goes in the report. Discard these on sight unless you have evidence otherwise:

| Flagged as a leak | Why it usually isn't | The actually-secret one |
|---|---|---|
| Stripe `pk_live` / `pk_test` | Publishable keys ship to browsers by design | the `sk_`-prefixed live/test secret key |
| `phc_*` (PostHog) | Public ingest key, designed for client code | the personal API key |
| `eyJhbG...` anon JWT (Supabase/Firebase) | Anon key is public; RLS enforces auth | the service-role key |
| `AIza...` (Google) | Often a referrer-restricted Maps/YT key | check the restriction, not the format |
| App `client_id` | Public by design | the `client_secret` |

Other standing false positives: **"missing auth on endpoint"** → check for router/app-level `app.use(authMiddleware)`, not just the handler. **"SQL injection in `db.query(\`...${x}...\`)`"** → check whether `x` is validated upstream or the driver parameterizes. **"XSS via innerHTML"** → check whether the source is server-controlled, not user input. **"hardcoded password"** → test fixture / documented dev default ≠ production secret. **"dependency CVE"** → confirm your code actually calls the vulnerable path and your version is in the advisory's affected range; `npm audit` is loud on dev-only transitives.

Report only verified findings, sorted with the quality findings (BLOCKER → SHOULD → NICE; a confirmed CRITICAL/HIGH security issue is a BLOCKER). End with a **False positives filtered** line so the same flags don't resurface next review.

## Step 5 — The reviewer brief (drop this in verbatim)

```
You are reviewing PR #<N> on <owner/repo>. You did NOT write this code.
Your job is to find what's missing or wrong before this merges.

CONTEXT
  PR title:   <quote>
  PR body:    <quote first 500 chars>
  Diff stat:  <paste --stat output>
  Base:       <base ref>
  Files:      <paste --name-only output>

CANONICAL PATTERNS TO COMPARE AGAINST
  <Step 3 output: 3-5 specific "this is how the codebase does X" file:line citations.
   For each: paste 5-10 lines of the existing pattern, with line numbers.>

WHAT YOU MUST CHECK (in this order, stop at first BLOCKER)

1. Tests — is there a 1:1 test file for each new/modified source file?
   The codebase rule: test file = source file, 1:1.
   For each changed source path, verify the companion test exists and exercises
   the changed lines. If it doesn't: name the missing test path.

2. End-to-end evidence — does the PR description include proof the changed
   flow runs? Not "build passes." Real output: curl response, test log,
   screenshot, deploy URL. For UI changes, a screenshot is required.
   If missing: name what's missing.

3. Docs — for each changed surface, is there a corresponding doc update?
   - CHANGELOG.md entry if the surface has one
   - Runbook section if ops behavior changed (docs/ near the surface)
   - README / AGENTS.md / CLAUDE.md update if conventions changed
   If missing: name the missing doc path.

4. Pattern reuse — for each NEW function / config block added, does it reuse
   the canonical pattern listed above, or duplicate it / invent a parallel
   version? Cite the existing pattern's file:line AND the new code's file:line
   and quote both. If the PR added a parallel implementation: name it.

5. Messiness — did the diff make any of these worse?
   - A function that grew past 100 lines (size = warning, not BLOCKER)
   - A switch/if-chain with a new arm added instead of refactoring to a map
   - A new file under a directory that already has the same concern split across files
   If found: quote the before/after.

6. Security (ONLY if the diff touches a risk surface — routes, auth, queries,
   shell exec, native/IPC, infra, deps, or anything carrying a secret).
   Classify the changed code by vulnerability class (SECRETS, INJECTION, AUTH,
   XSS, SHELL, IPC, INFRA, DEPS). For each plausible issue: read the sink, trace
   whether user input actually reaches it, and check for middleware /
   parameterization / escaping in between. Filter false positives HARD — a
   publishable/anon/public key is not a leaked key; auth applied at the router
   level is not a missing check; a CVE you don't call is not a vulnerability.
   Report only what you can prove reaches a real sink, with file:line + quote.
   A confirmed CRITICAL/HIGH is a BLOCKER. If clean, say "security: clean".

NON-CHECKS — do NOT comment on these:
  - Style nits enforced by formatters (prettier, gofmt)
  - Naming preferences absent concrete confusion
  - Hypothetical future requirements
  - Test coverage for trivial guards or constants
  - "Add abstractions for flexibility"
  - Doc rewrites that don't add information

OUTPUT FORMAT — exactly this shape

## Verdict
READY TO MERGE | CHANGES REQUESTED | BLOCKED

## Evidence ran
<one line per E2E check: e.g. "bun test: passed (quote from PR body lines 12-15)">

## Findings
For each finding:

### <BLOCKER|SHOULD|NICE> — <one-line summary>
File: `path/to/file.ts:42-58`
Existing pattern (if relevant): `other/file.ts:100-110`

```ts
<quote the relevant 5-15 lines from the diff, with line numbers>
```

<2-3 sentences explaining the problem concretely. Propose the fix IF obvious.
NO speculation. NO "this might be." If you can't prove it, drop the finding.>

GROUNDING RULE — non-negotiable
  Every finding MUST cite file + line(s) + quote actual code.
  No paraphrase. If you cannot quote it from the diff or from a file you read,
  do not claim it.

Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.
```

## Step 6 — Synthesize + post

Read the reviewer's output. If it's a team review, merge per-surface critiques into one verdict (BLOCKER count wins).

Post one comment to the PR via `gh pr comment <N> --body-file <synthesized>.md`. The comment opens with the verdict, then findings sorted BLOCKER → SHOULD → NICE.

## Step 7 — Act on the verdict

| Verdict | Action |
|---|---|
| READY TO MERGE | `gh pr merge <N> --rebase` after CI is green and a non-author review is clear. Rebase preserves the PR's individual commits; squash only for throwaway-WIP commit series. Then close the worktree. |
| CHANGES REQUESTED | Leave the comment. Iterate inside the same worktree — additional commits, `git push`. Do NOT spawn a fresh review until changes land. |
| BLOCKED | Surface to the user via `AskUserQuestion`. In an unattended run (headless/cron, no interactive user), skip the question — state the BLOCKED verdict and its reasons in your output so the orchestrator can park the ticket and notify. Don't unilaterally close or revert. |

A red required check isn't automatically a code problem. Before you treat "CI failing" as CHANGES REQUESTED, read the **step-level** conclusions, not just the job's pass/fail — `gh api repos/<owner>/<repo>/actions/jobs/<id> --jq '.steps[] | "\(.conclusion)\t\(.name)"'`. Self-hosted runners flake: a job shows "fail" when only its `checkout`/`setup`/cache step died on a stale workspace, while the actual test step never ran. That's infra — fix the runner or re-run the failed jobs (`gh run rerun <run-id> --failed`), don't send a clean PR back for changes it doesn't need.

## When to skip this skill

- Tag-only / release PRs (no code change).
- PRs from external contributors where another review bot already gated.
- PRs you (the orchestrator) explicitly want to merge unreviewed and the user has said "ship it" — but state that you're skipping and why.

## Hard lines this skill enforces

1. The author never reviews their own PR. Spawn a sub-agent.
2. Every finding cites file:line + quoted code. No paraphrase.
3. Pattern criticisms name the specific pattern by file:line. No generic "follow existing patterns."
4. The 5 non-checks list is a HARD non-checks list. Reviewers who add nits get re-prompted.
5. Default to Sonnet; use a team only when the diff spans multiple surfaces. Never omit `model`.
6. Security findings are verified at the sink before they ship — no "CRITICAL" survives without a file:line quote and a traced path from user input. Public keys, router-level auth, and uncalled CVEs are filtered, not reported.
