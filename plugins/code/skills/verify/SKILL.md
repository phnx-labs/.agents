---
name: verify
description: "End-to-end gate. Given a branch / PR # / worktree path, identify what changed, run the canonical sandbox.sh test for each affected surface, hit health endpoints on deploys, screenshot UI if rush/app touched. Returns PASS or FAIL with file:line evidence and quoted command output. The closing gate for 'done means end-to-end' (F3) — call this before telling the user work is complete. Triggers on: 'verify', 'did it actually work', 'gate this', 'E2E check', 'test the PR'."
argument-hint: "[branch | PR# | worktree path | empty for current]"
allowed-tools: Bash(agents *), Bash(gh *), Bash(git diff*), Bash(git log*), Bash(git status*), Bash(git rev-parse*), Bash(git show*), Bash(rush *), Bash(./*/scripts/sandbox.sh*), Bash(./scripts/*), Bash(curl *), Bash(jq *), Read(*), Bash(rg*), Bash(fd*), Bash(ls*)
user-invocable: true
---

# code:verify

> The user (or you) just shipped a change. Before claiming done, prove it works end-to-end. This skill identifies the changed surfaces, picks the right canonical test for each, runs them on the right host, and reports with quoted evidence.

This is the closing gate for F3 — "done means end-to-end." Code compiling is not done. Unit tests passing is not done. A real flow producing real output, quoted in this response, is done.

## When to invoke

- An agent just claimed work is finished.
- A PR is open and the user wants to know if it ships.
- You finished an inline edit and need to gate before reporting back.
- The user asks "did it actually work?"

## Step 1 — Resolve the target

`$ARGUMENTS` is one of:

- A branch slug (`fix-auth-refresh`) — `ref = origin/$ARGUMENTS` (fetch first).
- A PR number (`#347` or `347`) — resolve via `gh pr view <n> --json headRefName` → branch slug.
- A worktree path (`/path/to/wt`) — `ref = HEAD` inside that worktree.
- Empty — current directory's HEAD.

Set:
- `$BASE` — the default branch: `$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')`.
- `$REF` — the ref to diff against `origin/$BASE`.
- `$CWD` — the working directory to run tests in (worktree path or current).

## Step 2 — Diff and classify

```bash
git diff origin/$BASE...$REF --name-only > /tmp/verify-changed.txt
```

Classify changed files into surfaces. Each surface owns a canonical test command:

| Surface (path glob) | Canonical test | Source of truth |
|---|---|---|
| `rush/app/**` | `./rush/app/scripts/sandbox.sh test` | CLAUDE.md "Canonical project tests" table |
| `rush/cli/**` | `./rush/cli/scripts/sandbox.sh test` | CLAUDE.md "Canonical project tests" table |
| `prix/api/**` | `./prix/api/scripts/sandbox.sh test` | CLAUDE.md "Canonical project tests" table |
| `harness/**` | `./harness/scripts/sandbox.sh test` | CLAUDE.md "Canonical project tests" table |
| `rush/web/**` | `cd rush/web && bun run build && bun test` | rush/web has no sandbox.sh — verify locally |
| `prix/web/**` | `cd prix/web && bun run build` | prix/web (Vercel) — build is the gate |
| `infra/**` | `wrangler deploy --dry-run` in the affected worker | infra/CLAUDE.md |
| `agents/**` (YAML) | `rush build <agent-dir>` | rush/docs/commands.md |
| `*.md` only | Skip — docs don't ship code | n/a |

If a surface has no canonical test (e.g. a new module), run `go test ./...` (Go) or `bun test` (TS) inside that module directory and quote the result.

## Step 3 — Run the canonical tests

Run all affected sandbox commands. Per CLAUDE.md crabbox section, `sandbox.sh` runs on a remote Hetzner box — first one pays ~60s warmup, the rest run warm. So if multiple surfaces are touched, parallelize them — but quote each one's output separately.

For each test:
1. Run it.
2. Capture stdout/stderr.
3. Extract PASS / FAIL from the exit code AND from the visible output (some tests exit 0 even when they should fail — check the actual log).
4. Quote the final 10–20 lines of output verbatim in your response.

```bash
./rush/app/scripts/sandbox.sh test 2>&1 | tail -50
```

## Step 4 — API contract checks

If the diff touched any HTTP route (`prix/api/src/**/*.ts` files defining endpoints, or `prix/api/src/router.ts`), hit each affected endpoint:

```bash
rush http GET /api/v1/<changed-endpoint>
rush http POST /api/v1/<changed-endpoint> -d '<plausible-body>'
```

Per CLAUDE.md "Authenticated API Calls", `rush http` injects session tokens — never `curl` with manual tokens.

Quote the response body and status. A 200 with the expected shape passes. A 4xx/5xx fails.

## Step 5 — UI smoke (rush/app only)

If `rush/app/src/**` changed and the change is visible UI:

```bash
cd /Users/muqsit/src/github.com/muqsitnawaz/agents/rush/app
bun run dev > /tmp/rush-dev.log 2>&1 &
sleep 5
agents browser start --profile rush-local --task verify-$REF
agents browser screenshot
```

Quote what the screenshot shows. If it matches the user-flow you'd expect, pass. If anything looks wrong, fail.

Per CLAUDE.md "Testing Rush App Features in Dev Mode" — don't pre-launch Chrome. Use `agents browser` with the `rush-local` profile.

## Step 6 — Health check on deployed services

If the diff was deployed during this verification (or as part of the dispatch), hit the health endpoint:

```bash
curl -sS https://api.prix.dev/health    # or rush http GET /health
```

Per F3: a deploy command finishing is NOT proof. Only a 200 OK response from a real curl is proof.

## Step 7 — Report

Output exactly this shape:

```
VERDICT: PASS | FAIL | UNVERIFIED

Surfaces tested:
- <surface> → <result> (quote last 5 lines of output)
- ...

Surfaces NOT verified (and why):
- <surface> → <reason>

Next action:
- If PASS: <merge | hand to user for review>
- If FAIL: <the failing line, the file:line cause, and the proposed fix>
- If UNVERIFIED: <what's missing — a sandbox host, a flag, a credential — and how to unblock>
```

Every claim needs proof. Quote the lines. Do not paraphrase. UNVERIFIED is the correct verdict when you cannot prove it works — never inflate it to PASS.

## Don'ts

- Don't claim PASS without quoting evidence.
- Don't skip the canonical sandbox.sh for the surface — `bun test` in `rush/app/` does not equal `sandbox.sh test` (the wrappers handle hermetic deps and remote execution).
- Don't run sandbox.sh on the laptop unless the surface is small — per CLAUDE.md "Remote Execution (Crabbox)", heavy work goes to a Hetzner box.
- Don't curl with manual tokens — use `rush http`.
- Don't claim done when a UI changed and you didn't screenshot it.
