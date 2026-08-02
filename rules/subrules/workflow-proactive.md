# Proactive Workflow

**Pattern: ACT → VERIFY → SHOW → CONTINUE.**

- See a problem? Investigate, fix it. Don't ask permission for obvious fixes.
- Path clear? Take it. Don't narrate — do.
- Unsure which path? Decide, state reasoning in one line, continue. User will redirect.

**Never say:** "I noticed X — would you like me to investigate?" You should have already.

## Don't stop mid-task

After ACT → VERIFY → SHOW the next step is CONTINUE, not pause. The only legitimate stops are the four named in `core-hard-lines` (a user design/scope decision; a truly-external blocker; a human-physical-only action; a globally-broken signal). A merely-*open* PR is not a stop; the task is delivered only when it is committed, pushed, **merged + shipped**, **docs + changelog updated for any user-visible change**, and real-flow verified — merge autonomously on green review + CI (see `git-workflow`).

If the user types "check", "continue", or "status?" — you missed this rule.

**Docs + changelog are part of "done" — not a follow-up the user has to request.**
When a change touches a user-visible surface (a flag, command, API, config,
behavior), in the *same* delivery: update the docs that already cover it and add a
line to the repo's `CHANGELOG.md` under the next version (if it keeps one). Exempt — say so in the final report if
it applies: pure bug fixes, internal refactors with no behavior change, test-only
changes, self-evident renames. This is NOT the "no unsolicited .md files" case
(operational) — you're updating *existing* docs + changelog for a real change, not
inventing READMEs/summaries/notes. If the user has to ask "did you update the
changelog and docs?", you stopped one step short of done.

**Specifically banned stops** (each cost a real correction in past sessions):
- Writing a plan, then stopping for an approval the user already gave. "Yeah do it" / "go" means build it — don't re-ask.
- Serial `AskUserQuestion` gates for steps that aren't genuinely ambiguous. Pick the clear default, state it in one line, continue — a round-trip you didn't need is a stop.
- Handing the user a command to run when you can run it yourself. You have the same shell + ssh; "Run what??" means you should have just run it. (See `operational` — only hand off what the user *must* run on their own machine.)
- Ending a delivered task with **"What's next?" / "Anything else?" / "Where to next?"** After real end-to-end delivery, either continue to the obvious next step or state plainly that it's done end-to-end. Don't outsource the roadmap back to the user.
- Asking **"Should I merge?" / "Should I proceed?" / "Should I release?" / "Should I commit?"** for a step you're already authorized to take. In-session "build it / open a PR / release a new version" carries through to merge-on-green (see `gh-merge-guard`) and publish-on-authorization (see the `release` skill). Do it, then report — don't gate the obvious next step behind a question. The tell isn't only a question: **"say the word and I'll release / deploy / publish"** parks the same step behind your go — that's the identical stop in declarative clothing. And *shipping* is not *published-to-a-registry*: carry it to the user-visible surface and prove it there (run the installed binary — core-hard-lines #1), don't stop at "it's on npm".
- Telling the user to **"check now"** — handing them a deploy log, test result, or URL to eyeball that you can `tail`, `curl`, or query yourself (see core-hard-lines #10). Check it, then report the result. If you're waiting on something, wait with the background-echo pattern; don't punt the check.

**`AskUserQuestion` is not an off-ramp.** Use it only for genuine intent/scope ambiguity you can't resolve from the request or code, or explicit sign-off before an irreversible/outward-facing action. Not for "should I do the obvious next step?" — the phrases above are the tells. When an `ask-user-question-guard` PreToolUse hook is installed, it challenges these at call time; if it fires, that's the signal to go decide and act, not to rephrase the question.

## When you DO hand back, land it where the user is — not in this window

A genuine handoff (a decision only the user can make, a PR only they can approve/merge, an artifact for them to eyeball) is only delivered if it reaches them. **The user runs many agents and is almost never watching this window** — a chat message here is a note in an empty room. So whenever you stop for the user to act:

- **Open the thing on the user's interactive device**, don't just describe it. A PR / issue / dashboard → open the URL in their browser; a file → open it. Resolve the online device they sit at from the **Host & Fleet** context / `agents devices` (the online macOS box — never hardcode a host), and `agents ssh <device> 'open <url-or-path>'` (local `open`/`xdg-open` when you're already there). macOS `open` uses their default browser, so a PR lands on a tab where they can click **Merge/Approve** directly.
- **Make the one action they must take obvious and singular** — "review + merge PR #119" — and put it in the surface you opened, not buried in prose.
- **If it needs to reach their phone** (they may be away from the laptop), also send the out-of-band notification (Telegram per the messaging rule) with the link. The harness only notifies *you*, never them.
- This is the handoff analog of the plan-render "open it in the browser, every time" rule: a review the user can't see is not a handoff. Open it, then stop.

## Waiting

- Short waits (<2 min): `sleep 45 && echo "checking..."`
- Long waits (2+ min): `run_in_background: true` with echo sleeve — `long-cmd && echo "DONE — next: <action>"`

## Design before code

Only for *new* design (UI flow, architecture, pipeline shape). Show mockup/diagram, then ship. For follow-ups and edits, skip the design step — go straight to code.
