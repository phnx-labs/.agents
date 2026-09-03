---
name: demo
description: "Demonstrate landed work instead of just claiming it shipped. Recover the ORIGINAL intent (not the diff), exercise the shipped thing in its REAL environment — the installed/deployed artifact, never the dev build — drive it on the real surface with `agents browser`/`agents computer` signed in as the owner on REAL representative inputs (never toy examples), put before/after side by side with a measured delta, then deliver an analyzed HTML report on the owner's screen and attach it to the PR. Triggers on: /demo, /work:demo, 'show me a demo', 'prove it works', 'test it in prod', 'how does it look side by side', 'did we ship all of it', 'demo what we just shipped', after any landing/merge/release."
argument-hint: "[empty = demo what THIS session just landed | <ticket|PR|session-id|what was shipped>]"
allowed-tools: Bash(agents *), Bash(gh *), Bash(git *), Bash(linear *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Bash(curl *), Bash(python3 *), Bash(artifacts *), Bash(scp *), Read(*), Write(*), Edit(*), Task(*), WebFetch(*)
user-invocable: true
---

# work:demo — prove it, don't just ship it

An agent that lands a feature and stops at *"it's merged / shipped / released"* has
done **half** the job. The code compiling and the PR merging is not a demonstration
that the thing the owner **asked for** actually works. `/demo` is the missing capstone:
you take the original intent, run the shipped thing against **real** inputs in its
**real** environment, put before and after side by side, and hand the owner a report —
so they never have to type *"show me a demo.."* themselves.

**The bar is the INTENT, not the diff.** "I wrote the code and it merged" is the thing
you are testing, not the proof. You are proving the owner got what they asked for.

## When this runs

- Right after you (or a teammate) land something user-visible — a feature, a fix, a
  release. Reach for it yourself the moment work lands; don't wait to be asked.
- When the owner says *"show me a demo"*, *"how does it look side by side"*, *"did we
  ship all of it"*, *"test it in prod"*.

## The argument

- **No argument** → demo what **THIS session** just landed. Recover the intent from the
  transcript (the opening ask), the ticket you worked, and the PR you merged.
- **An argument** (`PHNX-1234`, a PR URL, a session id, or a description) → demo that
  landing. Pull its intent from the ticket + PR + any prior session on the topic.

---

## Step 1 — Recover the intent (don't trust the diff)

Before touching the product, reconstruct **what was actually asked for**:

- **This session's opening request** — the owner's own words, verbatim.
- **The ticket** — its acceptance criteria, not its title. `linear issue <id>` /
  `gh issue view`.
- **The PR** — description + what it claims to do.
- **Every prior thread on the topic** — run `/recall` (`sessions:search`) so you pull
  ALL the context without reloading full transcripts:
  ```bash
  python3 ~/.agents/plugins/sessions/skills/search/recall.py --since 60d "<topic/ticket>"
  ```

Write the intent down in one paragraph. This is the yardstick every later step measures
against. If you can't state what was asked in one paragraph, you're not ready to demo.

## Step 2 — Pick the REAL environment

Demonstrate where the thing **actually runs for the owner**, in this order:

1. **Production**, if it's deployed to a running service — hit the live URL/endpoint.
2. **Pre-prod / staging**, if there's a staging environment — the box the work targeted.
3. **The installed / released artifact** — for a CLI or library with no service, the
   *released* binary on a real fleet box (`agents` at the published version), **not**
   `agents-dev`, **not** the worktree, **not** a local build.

**Never demo the dev build or the worktree and call it shipped.** A build, a merge, a
local proxy, a dev install — these are the exact things the `verify-work-complete` gate
already bans as "not proof." A demo of the dev build is the same lie in nicer clothes.
State which environment you chose and why in one line. If the released artifact isn't out
yet, say so and demo the strongest thing that IS live, flagged as such.

## Step 3 — Drive it on the real surface, signed in, on REAL inputs

**You are not limited to the terminal. Use your tools — hard.** This is where most demos
fail: the agent forgets it can actually open the product and drive it.

- **`agents browser`** — open the real web app, click through it, upload, fill forms,
  screenshot. Headless on your box; drive the owner's box with `--device <interactive-box>`.
- **`agents computer`** — the native desktop, element mode: real clicks on a real app.

**Sign in as the owner — use the real, logged-in account.**

- The fleet's **interactive box** already has a browser profile **logged into the
  owner's services** (the SessionStart host context names that box and its profile —
  don't hardcode a device). List what it's signed into before assuming you're logged
  out:
  ```bash
  agents browser profiles logins --device <interactive-box>
  ```
- Where a native login is needed, `agents computer` can select the owner's normal
  account and sign in. If a credential is needed, it's in `agents secrets` — inject it,
  don't stop.
- Demonstrate on the **real account**, never a logged-out or throwaway session. A demo
  behind a login wall you didn't cross proves nothing.

**Use REAL, representative inputs — never toy examples.**

- Upload / paste / feed the *kind of data the owner actually hits*: a real repo, a real
  transcript, a real document, a real prompt, a real dataset. Not "hello world," not a
  three-row fixture.
- If the genuine input is sensitive, use a representative sample **of the same shape and
  scale** and say so explicitly. Small toy inputs hide the exact failures a demo exists
  to catch.

**Capture every meaningful step** — `agents browser screenshot`, a short recording, or
quoted output for non-visual surfaces. These captures are the evidence in the report.

## Step 4 — Put it side by side, and measure the delta

The owner keeps asking for this specifically: *"how does it look side by side"*, *"see
how much improvement has been made."*

- **Before vs after, same real input.** Run the **old** behavior and the **new**
  behavior on **identical, representative** data and place the two captures adjacent.
  For a released CLI, the "before" is the prior version (`agents@<old>` vs the new one);
  for a web change, the old deploy vs the new.
- **Quantify it.** State how much better — a number, a latency, a token count, fewer
  clicks, fewer steps. If it didn't move, say so honestly; a demo that admits "no
  measurable change" is worth more than one that fakes an improvement.
- **Alternatives, when cheap.** If the work chose between approaches, show the chosen one
  against a runnable alternative. Don't stall on this if the alternative is expensive to
  stand up — before/after is the floor, alternatives are a bonus.

The improvement must be **shown clearly**, not asserted.

## Step 5 — Analyze against the intent (completeness)

Go back to the paragraph from Step 1 and check the work against it, not against the diff:

- **Did it deliver EVERY part of the ask?** This is the owner's recurring *"did we ship
  ALL the UI changes??"* check. Enumerate each acceptance criterion → delivered / partial
  / missing, each with its evidence (a capture, a quote).
- **What's still a gap?** Name it plainly rather than burying it in prose — a demo's
  honesty is measured by whether it surfaces what's *not* done. A gap you can close now
  doesn't need a ticket: fix it (or dispatch the fix). For one you can't, check the board
  and enrich an existing ticket, opening a new one only if the work is genuinely missing
  (see `conventions`); a gap you merely noticed goes in the owner update, not a fresh Todo.

## Step 6 — Build the report

Use the `artifacts` skill (`kind: report`) — the same pipeline behind the plans and
recaps the owner already likes. The report contains:

- A **hero side-by-side figure** — before/after on the real input.
- The **captures** from Step 3, inlined.
- An **intent → delivered** table (each criterion, status, evidence).
- The **measured delta** from Step 4.
- **Honest gaps**, with the ticket ids you filed.

```bash
ROOT=$(git rev-parse --show-toplevel); DATE=$(date +%F)
DIR="$ROOT/.agents/artifacts/$DATE"; mkdir -p "$DIR"
# author $DIR/demo-<slug>.md  (kind: report), then:
artifacts check "$DIR/demo-<slug>.md" && artifacts render "$DIR/demo-<slug>.md"
```

Concrete, not a slogan. Name real files, flags, numbers, error strings.

## Step 7 — Deliver it where the owner will see it

- **Inspect headlessly first** — both themes, desktop + mobile widths, no console errors.
- **Show it on the owner's interactive box** in one reused browser tab (the SessionStart
  host context names that box):
  ```bash
  scp "$DIR/demo-<slug>.html" <interactive-box>:/tmp/demo-<slug>.html
  agents browser navigate --device <interactive-box> --url file:///tmp/demo-<slug>.html
  ```
- **Attach the report + captures to the PR** (`gh pr comment <pr> --body-file` with the
  images, or a secret gist link) so the demonstration rides with the change.
- **Post a feed milestone** (`agents feed post "demo: <what> — <headline delta>"`).
- **Close with an honest status line** that distinguishes **merged / released /
  installed / verified-in-prod**. Never collapse them. "Merged" is not "shipped";
  "released" is not "verified in prod."

---

## Anti-patterns (each is a demo that proves nothing)

- **Demoing the dev build / worktree** and calling it shipped. Demo the released artifact.
- **Toy inputs.** "hello world" hides the failures a demo exists to catch. Real,
  representative data or a same-shape sample.
- **A logged-out session.** You have the owner's logged-in profile and `agents secrets` —
  sign in and demonstrate the real flow.
- **Asserting improvement without measuring it.** Put a number on it or admit there isn't
  one.
- **No gap section.** A demo with nothing marked partial/missing is almost always hiding
  something — re-check against the intent.
- **Describing instead of driving.** "This would show…" is not a demo. Open the surface,
  drive it, screenshot it.
- **Leaving the report in `/tmp`.** Durable output lives under `.agents/artifacts/<date>/`
  and rides the PR; `/tmp` vanishes.

---

Changing this skill? Read [`../../AGENTS.md`](../../AGENTS.md) and keep the top-level
`/demo` alias (`commands/demo.md`) and `/work:demo` command in sync.
