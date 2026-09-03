---
name: debug
description: "Debug end to end with swarm verification — clarify intent vs observed, check the feature's spec for the gap that let it slip, trace the data path, attribute regressions to the agent/session that caused them, have independent agents (different providers, blind) confirm the root cause, then close the loop with a viewable artifact, a ticket, and a dispatched fix. Use for any 'here's what I saw, here's what I expected' problem. Triggers on: 'debug', 'swarm debug', 'root cause', 'why is this happening', 'what was my intent vs what happened', 'confirm the bug', 'independent debug'."
argument-hint: "[symptom, error, screenshot, or 'intended X but got Y']"
allowed-tools: Bash(agents teams*), Bash(agents run*), Bash(agents sessions*), Bash(agents view*), Bash(rg*), Bash(fd*), Bash(ls*), Bash(git log*), Bash(git diff*), Bash(git show*), Read(*), Grep(*), Glob(*), Write(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# swarm:debug — from intent, to a confirmed root cause, to a dispatched fix

> Read `swarm:orchestrate` first for fan-out mechanics and the blinded-verification rule. This is the **debug loop**: pin what you *meant* against what *happened*, find the gap in the contract that let it slip, prove the root cause with independent agents, then close it out — artifact, ticket, dispatch. No fix ships until the cause is proven and independently confirmed.

You are debugging: **$ARGUMENTS**

The root cause is **not** where the error surfaces — it's where the incorrect behavior originates. No fallbacks, no "just in case" guards, no symptom patching — fix the root cause or fix nothing.

## 1. Intent vs observed — pin the delta before touching code

Separate **intent** from **observation** first; a root cause that doesn't explain the delta is the wrong root cause. If the report came with screenshots, logs, or a recording, read them (a `host:/path` clip is a real file — resolve and read it, don't treat it as literal text). State, one line each:

- **Intended** — what the user was trying to do.
- **Observed** — what actually happened: the exact surface, message, or state.
- **Delta** — the specific gap between them. This frames everything below.

If intent is genuinely ambiguous from the report plus the code, ask once. Otherwise infer it and proceed.

## 2. Check the spec — find the gap that let it slip

Before diagnosing, find the capability's contract and its tests. "Why did it slip" is a sharper question than "what broke," and its answer is half the fix:

- Locate the spec (a `docs/specifications.md`, a `spec.md`, the owning `AGENTS.md`) and the tests covering this path. Grep, then read.
- Record both:
  1. **Was this behavior specified and tested?** Quote the requirement / test (file:line), or state plainly that none exists.
  2. **If it was — why did it slip?** (the test asserts the wrong thing; the spec is silent on this edge; the path has no coverage). **If it wasn't** — the missing spec/test *is* part of the finding, not an afterthought.
- Decide whether the bug is a **regression**. If it is, invoke `/blame` as the read-only attribution primitive rather than duplicating its forensic steps. Record the culprit commit/PR and `file:line` diff, the removed/skipped/weakened test (or previously uncovered behavior), the change's author, the responsible agent + session from `agents sessions preview <id>`, and whether that PR flagged the loss or let it slip silently.

Need a full source-of-truth spec, not just the gap? That's `swarm:spec` — invoke it and come back. Here you only need the gap that explains the slip.

## 3. Investigate — trace the data path (no lazy debugging)

Read `AGENTS.md` / `CLAUDE.md` if present. Dissect the error/logs — file names, line numbers, stack traces, variable values are direct clues; extract everything.

Then trace the data path. If data flows A → B → C → D, **read all four files** and quote exact code (file:line) at each step. Skipping the middle is how you misdiagnose. Keep tracing backwards until you find where the behavior first goes wrong. Document your hypothesis before verifying.

If the bug could involve external behavior (a library version's quirk, an API contract, a runtime change), **WebSearch with the current year** and quote the authoritative source — don't guess from stale memory.

## 4. Verify — blinded, scaled to the bug, on the worker boxes

Fan out via `agents teams` (mechanics in `swarm:orchestrate`). First check who's available (`agents teams doctor` / `agents view --json`), then **mix different model providers** — the diversity is the whole point; two of the same model agreeing proves nothing. Dispatch verifiers to the worker boxes by default (`--device yosemite-s0,yosemite-s1`, or `--device auto`) to keep the interactive machine responsive.

**Scale the verifier count to the bug, by judgment** (not a fixed number):
- Trivial / single-file → 1 independent check, or skip the swarm and just prove it yourself.
- Normal cross-module bug → 2 verifiers on different providers.
- Gnarly, cross-stack, or high-stakes → 3+ verifiers on as many distinct providers as are signed in.

All verifiers run **`--mode plan`** (read-only).

Each verifier prompt MUST include:
1. **System context** — what the component does, its architecture.
2. **Observed symptoms** — the exact Observed behavior and Delta from step 1.
3. **Why it's problematic** — the UX/business impact, not just "it errors."
4. **Code paths to read** — specific files/dirs to investigate.
5. **The question** — "What is the root cause, and how would fixing it resolve these symptoms?"

Each verifier prompt MUST NOT include: your hypothesis, your proposed fix, leading questions, or any framing that biases toward a conclusion. Independent analysis only — confirmation isn't verification.

### Convergence
- **All agree** → high confidence, proceed.
- **Agree on area, differ on specifics** → read the disputed lines, determine who's right.
- **Fundamentally different** → your investigation missed something. Re-read the files the others flagged. Do NOT default back to your original hypothesis.

## 5. Resolve

Once the cause is verified, propose fixes — minimal, defensive, architectural — weigh tradeoffs, recommend one. Name the regression test that must exist so this can't recur, and (from step 2) the spec line that should have caught it.

## 6. Close the loop — artifact, ticket, dispatch

A confirmed root cause is the middle of the task, not the end. When this is a real problem you'll act on (not a throwaway diagnosis):

- **Render a viewable artifact.** Turn the finding (intent/observed/delta → evidence chain → root cause → spec gap → recommended fix) into a self-contained HTML doc and open it on the machine the user sits at — follow the `artifacts` skill for the LOOK and the `/plan` open-on-Mac transport. This is the surface the user reviews and reacts to.
- **Track the fix — don't reflexively cut a ticket.** If it's fixable now, fix it (or dispatch the fix — see below); otherwise check the board first and consolidate into an existing ticket, opening a new one only if the work is genuinely missing (see `conventions`). When you do open or enrich one, scope it to the fix: the delta, the root-cause file:line, the regression test to add, and the spec gap. Link the artifact.
- **Dispatch the build.** Once the fix is approved, dispatch it to the worker boxes — `agents run <profile> --device yosemite-s0` for a single fix, or `agents teams` for multi-surface work (see `swarm:orchestrate`). Don't hand-build it on the interactive machine.

For a quick throwaway diagnosis, stop at the confirmed root cause and say so.

## Output

### Intent vs observed
Intended / Observed / Delta — one line each.

### Bug
What's broken. Expected vs actual. UX impact.

### Spec & gap
Was it specified/tested (file:line, or "none") — and why it slipped. The regression test to add; the spec line that should have caught it.

### Evidence chain
File-by-file trace with exact quotes (file:line) at every hop.

### Root cause
The specific location and WHY it causes the bug. A small diagram from trigger → failure.

### Attribution
For a regression: culprit commit/PR, `file:line` diff, removed/skipped/weakened test or prior coverage gap, change author, responsible agent + session, and whether the PR flagged the loss or it slipped silently. Cite the `/blame` result. For a non-regression: "not applicable — no prior working behavior."

### Verification
What each verifier concluded and whether they converged. Note disagreements and how you resolved them with evidence (not majority vote).

### Fixes
Recommended fix first. For each: what changes, how it addresses the root cause, tradeoffs.

### Tests
The tests to run to confirm the fix, and the regression test to add (from Spec & gap) so this can't recur.

### Ticket & dispatch
The artifact path/link, the ticket id/URL (existing one enriched, or a new one only if genuinely missing), and where the fix was dispatched — or "throwaway diagnosis, not filed."
