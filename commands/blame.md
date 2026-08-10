---
description: Trace a product regression to the change — and the agent/session — that caused it. A feature that worked before and silently broke: find the culprit change, the removed/skipped test that let it through, and who did it. Read-only forensics, no side effects.
---

Blame a regression: $ARGUMENTS

A feature worked before and now silently doesn't, and it's hard to tell which agent's change caused it. Your job is **forensics, not repair**: find the change that broke it, the test or expectation that was removed/disabled so nothing caught it, and the agent/session responsible — then report. Make **no code changes** and cause **no side effects**.

## Step 1: Pin the expectation

- State the **expected** behavior (what the feature should do) and the **observed** behavior (what it does now) in one line each. If `$ARGUMENTS` is vague, read the code path (or reproduce) until "broken" is concrete — you cannot blame a regression you can't define.
- Find the **last known-good** point: when did it last work? (a user report, a passing CI run, a green deploy, a session that verified it). That bounds the search window. Anchor to the current tree first — `git fetch origin` — so you bisect against real history, not a stale checkout (see `research-discipline`).

## Step 2: Map the code path (read every hop)

- Trace the feature end to end (entry → logic → output) and list the files/functions on the path. Read every one and quote `file:line` — no lazy debugging (`research-discipline`).
- That suspect set is where the regression lives: either a change to one of these files, or a test that stopped guarding one.

## Step 3: Find the suspect changes on that path

For each suspect file, over the window from Step 1:

- `git log --oneline -- <path>` (widen to the merge window), then `git show <sha> -- <path>` on each candidate.
- Look for: a **behavior change** (logic altered, a branch removed, a default flipped, an early `return` added) or a **weakened/removed guard** (a validation deleted, an error now swallowed, a fallback that hides the failure — see the no-fallbacks rule). Quote the diff hunk that plausibly changed the observed behavior.

## Step 4: The tests — the real tell

The regression shipped because **no test caught it**. Find out why, in the same window:

- Hunt for tests **deleted, renamed away, `.skip`/`xit`/`it.only`'d, commented out, or with assertions weakened** on the affected path: `git log -p -- <testfile>`, and grep the diffs for `skip`, `xit`, `only`, `xdescribe`, `t.Skip`, `@pytest.mark.skip`, commented-out `expect`/`assert`.
- A test removed or disabled **in the same change window** as the behavior change is the smoking gun — quote its diff.
- If the behavior was **never** tested, say so plainly: that's a coverage gap, not a removed test — a different (and also reportable) failure.

## Step 5: Attribute — who, and which session

- `git blame` the culprit lines; `git show -s --format='%an <%ae> %cI' <sha>` for author + time; find the PR (`gh pr list --search <sha>` / the merge commit).
- Cross-reference the fleet: `agents sessions --since <window>` / `agents sessions "<topic>"` to find the session behind the change, then `agents sessions preview <id>` for its **task, PR, and what it was doing**. Name the agent + session, its stated task, and — crucially — **whether that PR flagged the test removal** or slipped it in silently. That is how you tell an honest tradeoff from an unnoticed regression.

## Step 6: Report — culprit + evidence, zero changes

A short verdict:

- **Regression** — expected vs observed (one line each).
- **Culprit change** — the commit/PR (link) and the `file:line` diff that broke it, quoted.
- **Why it slipped** — the test that was removed/skipped/weakened (quoted diff), or "never covered".
- **Who** — the agent + session (its task + `preview` link), and whether the loss was flagged in that PR.
- **Fix direction** — what to restore/re-enable and the test to add, as a **recommendation only**.

## Don'ts

- **Don't fix anything.** `/blame` is read-only forensics — no edits, no reverts, no re-enabling tests, no pushes, no deploys, no state-mutating test runs. Hand the verdict to `/debug` or `/next` for the actual repair.
- **Don't guess a culprit without the diff.** Every claim quotes a commit + `file:line` (`research-discipline`). "This file changed" is not blame — tie the change to the observed break **and** to the missing test.
- **Don't stop at the first suspicious commit.** Confirm it actually produces the observed behavior; a plausible-looking diff that doesn't is a false accusation.
