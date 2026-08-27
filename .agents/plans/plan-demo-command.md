---
kind: plan
surface: cli
title: "/demo — the post-ship demonstration ritual"
summary: >
  Agents stop at "it's merged / shipped / released" and sit. Add a /demo command +
  work:demo skill that recovers the original intent, exercises the shipped thing in
  its real environment, puts before/after side by side, captures screenshots, and
  delivers a report — the recurring ask the owner types by hand after every landing.
status: draft
host: a fleet worker
session: " "
harness: agents-cli
agent: Claude
human: Muqsit
project: .agents-system
links:
  - https://github.com/phnx-labs/.agents-system (this repo)
---

## Focus for review

Five decisions worth your eyes before anyone builds this:

1. **Home + name.** Recommended: canonical skill in the **`work`** plugin
   (`work:demo`) with a top-level **`/demo`** alias — this satisfies *both*
   options you floated ("the work command **or** a top-level `/demo`") at once,
   and keeps the surface lean (no new plugin on an already 45%-dead command set).
   The alternative is a standalone `demo` plugin. **This is the one call I want
   from you.**
2. **Explicit command now, hook-nudge later.** Phase 1 is a command you (or an
   agent) invoke: `/demo`. Phase 2 (optional) teaches the `verify-work-complete`
   Stop hook to *suggest* a demo when it sees a ship-claim on a user-visible
   surface. Phase 1 ships clean and standalone; Phase 2 is a separate opt-in.
3. **Which environment counts as "real."** The skill demands the *installed /
   deployed* artifact — prod if deployed, else the pre-prod/staging box, else the
   installed binary — **never the dev build or the worktree**. Is "installed
   binary on a fleet box" a strong enough floor when there's no prod to hit?
4. **How hard is "side by side"?** Before/after of the *same* flow is always in
   scope. Comparing *alternative solutions* (the approaches considered) is only
   possible when the alternatives are cheap to run. The skill asks for before/after
   always, alternatives when feasible — not a hard requirement that stalls.
5. **Report format.** Reuse the `artifacts` skill (`kind: report`) so the output
   is a branded, self-contained HTML report delivered on your box + attached to the
   PR — same pipeline as the plans and recaps you already like.

## Purpose

Restating your ask, verbatim from this session:

> whenever we land a feature and the Agents ship that, they just sit there and say
> "Oh, it's merged or it's shipped or whatever, it's released." But they do not
> test it deeply in production or pre-production... they're supposed to take the
> context of the original intent and then even compare solutions, put things side
> by side, take screenshots, prepare a report, and analyze it.

This is not a one-off. Mining 100 days of your sessions, the **same post-ship ask
recurs in your own words** across at least five landings:

| Landing | Date | What you typed after "it's shipped" |
|---|---|---|
| A | 08-27 | **"Show me a demo.."** → *"how does it look side by side.. I thought we had a report too."* |
| B | 08-26 | *"test it quickly... on a worker box... and then **attach your screenshots in the PR**"* |
| C | 08-25 | *"Did we ship **all** the UI side changes??"* (completeness vs intent) |
| D | 08-25 | *"do the merge, do the release **and then test it as well**... create some more complex artifacts"* |
| E | 08-27 | *"Did we ship this?"* → the plan lived only in `/tmp` |

Every one is the same missing ritual: **the agent proved the code compiles and
merged, but never demonstrated the shipped thing works against what you actually
asked for.** `/demo` makes that ritual a first-class command so you stop typing it
by hand.

### Why the existing gate isn't enough

`hooks/stop/00-agent-verify-work-complete.sh` already blocks a *stop* that claims
"done" without evidence, and bans "builds / merges / proxies are not proof." But it
is a **negative gate on stopping** — it stops a bad stop; it does not *produce a
demonstration*. It has no notion of the *original intent*, no side-by-side, no
report, no delivery to your screen. `/demo` is the **positive** capstone the gate
implies: the artifact you asked for, not just permission to stop.

## Current architecture

How a landing flows today, and where it dead-ends:

<figure class="artifact-figure artifact-figure-diagram">
<svg viewBox="0 0 920 300" xmlns="http://www.w3.org/2000/svg" font-family="ui-sans-serif, system-ui, sans-serif" role="img" aria-label="Current landing flow dead-ends at 'it's shipped'">
  <rect x="10" y="120" width="150" height="60" rx="8" fill="#1b2a1b" stroke="#4a7a3a" stroke-width="1.5"/>
  <text x="85" y="146" fill="#cde8b8" font-size="13" text-anchor="middle">code:loop /</text>
  <text x="85" y="164" fill="#cde8b8" font-size="13" text-anchor="middle">work:dispatch</text>

  <rect x="200" y="120" width="150" height="60" rx="8" fill="#1b2333" stroke="#3a5a7a"/>
  <text x="275" y="146" fill="#b8d4e8" font-size="13" text-anchor="middle">PR merged</text>
  <text x="275" y="164" fill="#8fb3cc" font-size="11" text-anchor="middle">CI green + review</text>

  <rect x="390" y="120" width="150" height="60" rx="8" fill="#1b2333" stroke="#3a5a7a"/>
  <text x="465" y="146" fill="#b8d4e8" font-size="13" text-anchor="middle">released</text>
  <text x="465" y="164" fill="#8fb3cc" font-size="11" text-anchor="middle">npm / tag</text>

  <rect x="580" y="112" width="170" height="76" rx="8" fill="#3a1b1b" stroke="#a35050"/>
  <text x="665" y="140" fill="#f0b8b8" font-size="13" text-anchor="middle" font-weight="600">agent sits.</text>
  <text x="665" y="158" fill="#f0b8b8" font-size="12" text-anchor="middle">"it's shipped."</text>
  <text x="665" y="174" fill="#d89090" font-size="11" text-anchor="middle">no demo. no proof.</text>

  <rect x="580" y="230" width="330" height="52" rx="8" fill="#2a2410" stroke="#8a7a30" stroke-dasharray="5 4"/>
  <text x="745" y="252" fill="#e8d88f" font-size="12" text-anchor="middle">YOU type it by hand, every time:</text>
  <text x="745" y="270" fill="#c9b96a" font-size="12" text-anchor="middle" font-style="italic">"show me a demo.." · "side by side" · "did we ship all of it?"</text>

  <line x1="160" y1="150" x2="198" y2="150" stroke="#6a8a5a" stroke-width="2" marker-end="url(#a)"/>
  <line x1="350" y1="150" x2="388" y2="150" stroke="#5a7a9a" stroke-width="2" marker-end="url(#a)"/>
  <line x1="540" y1="150" x2="578" y2="150" stroke="#5a7a9a" stroke-width="2" marker-end="url(#a)"/>
  <line x1="665" y1="188" x2="665" y2="228" stroke="#8a7a30" stroke-width="2" stroke-dasharray="5 4" marker-end="url(#a)"/>
  <defs>
    <marker id="a" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#8a9a7a"/></marker>
  </defs>
</svg>
<figcaption>Today: the flow ends at a claim. The demonstration is outsourced to you.</figcaption>
</figure>

Proposed: `/demo` closes the loop — the agent runs the ritual the moment work lands,
and hands you the report instead of the other way around.

<figure class="artifact-figure artifact-figure-diagram">
<svg viewBox="0 0 920 340" xmlns="http://www.w3.org/2000/svg" font-family="ui-sans-serif, system-ui, sans-serif" role="img" aria-label="Proposed /demo ritual closing the loop">
  <rect x="10" y="150" width="130" height="54" rx="8" fill="#1b2333" stroke="#3a5a7a"/>
  <text x="75" y="182" fill="#b8d4e8" font-size="13" text-anchor="middle">shipped</text>

  <rect x="185" y="20" width="200" height="300" rx="10" fill="#12180f" stroke="#4a7a3a" stroke-width="1.5"/>
  <text x="285" y="44" fill="#a3e635" font-size="13" text-anchor="middle" font-weight="600">/demo</text>
  <g font-size="11.5">
    <rect x="200" y="58" width="170" height="34" rx="6" fill="#1b2a1b" stroke="#3a5a2a"/>
    <text x="285" y="79" fill="#cde8b8" text-anchor="middle">1 · recover intent</text>
    <rect x="200" y="100" width="170" height="34" rx="6" fill="#1b2a1b" stroke="#3a5a2a"/>
    <text x="285" y="121" fill="#cde8b8" text-anchor="middle">2 · pick real env</text>
    <rect x="200" y="142" width="170" height="34" rx="6" fill="#1b2a1b" stroke="#3a5a2a"/>
    <text x="285" y="163" fill="#cde8b8" text-anchor="middle">3 · drive + capture</text>
    <rect x="200" y="184" width="170" height="34" rx="6" fill="#1b2a1b" stroke="#3a5a2a"/>
    <text x="285" y="205" fill="#cde8b8" text-anchor="middle">4 · before / after</text>
    <rect x="200" y="226" width="170" height="34" rx="6" fill="#1b2a1b" stroke="#3a5a2a"/>
    <text x="285" y="247" fill="#cde8b8" text-anchor="middle">5 · analyze vs intent</text>
    <rect x="200" y="268" width="170" height="34" rx="6" fill="#1b2a1b" stroke="#3a5a2a"/>
    <text x="285" y="289" fill="#cde8b8" text-anchor="middle">6 · report</text>
  </g>

  <rect x="430" y="70" width="150" height="60" rx="8" fill="#1b2333" stroke="#3a5a7a"/>
  <text x="505" y="96" fill="#b8d4e8" font-size="12" text-anchor="middle">report on YOUR</text>
  <text x="505" y="114" fill="#b8d4e8" font-size="12" text-anchor="middle">your screen</text>

  <rect x="430" y="150" width="150" height="60" rx="8" fill="#1b2333" stroke="#3a5a7a"/>
  <text x="505" y="176" fill="#b8d4e8" font-size="12" text-anchor="middle">attached to</text>
  <text x="505" y="194" fill="#b8d4e8" font-size="12" text-anchor="middle">the PR</text>

  <rect x="430" y="230" width="150" height="60" rx="8" fill="#1b2333" stroke="#3a5a7a"/>
  <text x="505" y="256" fill="#b8d4e8" font-size="12" text-anchor="middle">honest gaps</text>
  <text x="505" y="274" fill="#8fb3cc" font-size="11" text-anchor="middle">→ filed as tickets</text>

  <rect x="640" y="150" width="150" height="60" rx="8" fill="#1b2a1b" stroke="#4a7a3a"/>
  <text x="715" y="176" fill="#cde8b8" font-size="13" text-anchor="middle" font-weight="600">you see it</text>
  <text x="715" y="194" fill="#a8c898" font-size="11" text-anchor="middle">without asking</text>

  <line x1="140" y1="177" x2="183" y2="177" stroke="#5a7a9a" stroke-width="2" marker-end="url(#b)"/>
  <line x1="385" y1="100" x2="428" y2="100" stroke="#5a7a5a" stroke-width="2" marker-end="url(#b)"/>
  <line x1="385" y1="180" x2="428" y2="180" stroke="#5a7a5a" stroke-width="2" marker-end="url(#b)"/>
  <line x1="385" y1="260" x2="428" y2="260" stroke="#5a7a5a" stroke-width="2" marker-end="url(#b)"/>
  <line x1="580" y1="180" x2="638" y2="180" stroke="#5a7a9a" stroke-width="2" marker-end="url(#b)"/>
  <defs>
    <marker id="b" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#8a9a7a"/></marker>
  </defs>
</svg>
<figcaption>Proposed: the agent runs the ritual and hands you the report — the loop closes on the agent's side.</figcaption>
</figure>

<p class="artifact-callout">The one call I need from you: <strong>home + name</strong>. My recommendation is <code>work:demo</code> (canonical skill) plus a top-level <code>/demo</code> alias — it satisfies both options you floated and adds zero new plugins. Everything else follows from that.</p>

## What the command actually does (behavior)

<figure class="artifact-figure artifact-behavior">
  <section data-state="current" data-evidence="mockup">
    <h4>Current — the agent sits at "it's shipped"</h4>
    <pre><code>◆ Recap
  We merged the change, filed the follow-up ticket, and released.
  Honest status / what's left:
   - PR merged (signed squash), worktree cleaned.
   - Report is on your screen but lives in /tmp — say the word and
     I'll publish it so it persists.
  Nothing outstanding on the delivery itself.

∗ Worked for 38m 34s

› Show me a demo..
  └ 2 skills available

∗ Envisioning…                                    ← it just sits here</code></pre>
    <p>Faithful reconstruction of a real landing this session: the agent delivered a solid status wrap-up — merged PR, filed ticket, honest "what's left" — then <em>stopped</em>. You had to type <strong>"Show me a demo.."</strong> and it sat at "Envisioning…". No demo was produced until asked. (Anonymized for this public repo; the live capture was shown on your screen.)</p>
  </section>
  <section data-state="proposed" data-evidence="mockup">
    <h4>Proposed — <code>/demo</code> produces the demonstration report</h4>
    <pre><code>$ /demo PHNX-3350
  recovered intent · ticket + this session's ask + PR #NNN
  env: installed `agents` on a fleet worker (not the dev build)
  drove: 3 flows · 6 screenshots · before/after captured
✓ intent delivered: 4/5 acceptance criteria
△ gap: macOS timeout nudge not yet wired → filed PHNX-XXXX
→ report on your screen · attached to PR · feed posted</code></pre>
    <p>A branded HTML report opens on your box: intent-vs-delivered table, before/after side by side, the captures, the measured delta, and the honest gaps filed as tickets.</p>
  </section>
</figure>

### The ritual — the instructions that go in the skill

This is the core of your question ("what instructions do we need to put there?").
The `work:demo` skill is these seven steps, in order:

1. **Recover the intent — don't trust the diff.** Pull the *original* ask: this
   session's opening request, the ticket's acceptance criteria, the PR description.
   Use `/recall` (`sessions:search`) to gather every relevant prior-session thread
   on the topic **without** reloading full transcripts. Restate what was asked in
   one paragraph. The bar is the *intent*, not "the code I wrote."
2. **Pick the real environment.** Demonstrate where it actually runs: **production
   if deployed; else the pre-prod/staging box; else the installed binary** on a
   fleet box. **Never the dev build or the worktree** — the verify hook already
   bans "builds/merges/proxies are not proof," and a demo of the dev build is the
   same lie. State which environment and why.
3. **Drive it end-to-end on the real surface — reach for the tools, hard.** You are
   not limited to the terminal. You have **`agents browser`** (open the web app,
   click through it, upload, screenshot) and **`agents computer`** (native desktop,
   element mode) — *use* them, don't describe what they'd show. The skill spells this
   out so no agent forgets it exists:
   - **Sign in as the user.** The fleet's interactive box already has a browser profile
     logged into the owner's services (the SessionStart host context names it) —
     `agents browser profiles logins --device <interactive-box>` lists which. Where a native login is needed, `agents computer`
     can select the owner's normal account and sign in. Demonstrate on the **real,
     logged-in account**, never a logged-out or throwaway session.
   - **Use REAL, representative inputs — never toy examples.** Upload / paste / feed
     the *kind of data the owner actually hits*: a real repo, a real transcript, a
     real file, a real prompt — not "hello world." A green screenshot on a toy input
     proves nothing. If the real input is sensitive, use a representative sample of
     the same shape and say so.
   - **Capture every meaningful step** — screenshot or record. Quoted output counts
     for non-visual surfaces.
4. **Put it side by side and quantify the delta.** Before vs after of the **same real
   input**, always — run the old behavior and the new behavior on identical,
   representative data and place the two captures adjacent. Then **measure**: how much
   better (a number, a latency, a token count, fewer steps), or honestly *none* if it
   didn't move. Alternatives considered vs the chosen one when they're cheap to run.
   This is the "compare solutions / side by side / see how much improvement" ask — the
   improvement must be **shown clearly**, not asserted.
5. **Analyze against the intent.** Did it deliver **every** part of the ask (the
   "did we ship *all* the UI changes??" completeness check)? Quote the measured
   improvement — a number, a latency, a token cost. Name what's still a gap and
   **file it as a ticket** rather than burying it.
6. **Build the report.** Reuse the `artifacts` skill (`kind: report`): hero
   side-by-side figure, the captures, an intent→delivered table, the measured
   delta, honest gaps. Concrete, not a slogan.
7. **Deliver it where you'll see it.** Render, inspect headlessly (both themes,
   desktop + mobile), then show it on the owner's interactive box in one reused
   tab, **attach the report + captures to the PR**, and post a feed milestone.
   Close with an honest status line that distinguishes *merged / released /
   installed / verified-in-prod* — never overclaim.

<p class="artifact-callout artifact-callout-warn">The heaviest reminder in the skill: <strong>you have <code>agents browser</code> and <code>agents computer</code> — open the real web app, sign in with the owner's normal account (the interactive box's profile is already logged in), and upload / drive <em>real, representative inputs</em>, not toy examples.</strong> Then compare before vs after on that same real input and <strong>show the improvement clearly</strong> — a measured delta, or an honest "no change." A demo on a logged-out toy example is theater, not proof.</p>

## Proposed Changes

New skill + command + top-level alias, then the three-places-agree bookkeeping. No
existing behavior changes — this is additive.

**`plugins/work/skills/demo/SKILL.md`** (new) — the seven-step ritual as operating
instructions, `allowed-tools` scoped to browser/computer/artifacts/recall:

```diff
+---
+name: demo
+description: Demonstrate landed work — recover the original intent, exercise the
+  shipped thing in its real environment, put before/after side by side, capture
+  screenshots, and deliver an analyzed report on the owner's screen + the PR.
+allowed-tools: Bash, Read, Write, Edit, WebFetch
+---
+# work:demo — prove it, don't just ship it
+... seven steps (recover intent → pick real env → drive+capture → side by side
+    → analyze vs intent → report → deliver) ...
```

**`plugins/work/commands/demo.md`** (new) → `/work:demo`, and **`commands/demo.md`**
(new) → top-level `/demo` alias that invokes the same skill (the `/recall`→`sessions:search`
precedent):

```diff
+---
+description: Demonstrate landed work — recover intent, exercise the shipped thing
+  in its real environment, before/after side by side, screenshots, analyzed report.
+argument-hint: "[<ticket|PR|session-id|what was shipped>]"
+---
+**`/demo` invokes the `work:demo` skill.** Arguments: $ARGUMENTS
```

**Three-places-agree + docs** (edits):

```diff
# plugins/work/.claude-plugin/plugin.json — bump description + version (0.4.0 → 0.5.0)
# plugins/README.md — work "Commands" count 2 → 3, add /demo row
# commands/README.md — add /demo alias row
# plugins/work/README.md — /demo as the delivery capstone after loop/dispatch
# CHANGELOG.md — work plugin minor: "/demo post-ship demonstration ritual"
```

## Public Interface

```text
/demo [<ticket|PR|session-id|"what was shipped">]
/work:demo <same>          # canonical; /demo is the top-level alias

# no arg → demo the work THIS session just landed (recover intent from the transcript)
# arg    → demo that ticket / PR / described landing
```

Flags kept minimal (surface-convention: intuitive over flag soup):

| Flag | Effect | Default |
|---|---|---|
| `--env <prod\|preprod\|installed>` | which environment to demonstrate against | auto-detect (prod if deployed, else installed) |
| `--device <name>` | run the demo on a specific fleet box | auto |
| `--no-report` | drive + capture + verbally summarize, skip the HTML report | report on |
| `--attach <pr>` | PR to attach the report/captures to | the session's owned PR |

`--help` ships a `setHelpSections` block: the seven-step playbook first, flags last.

## Plan

- [ ] **T1 — home decision** (blocks the rest): confirm `work:demo` + top-level `/demo` alias vs a standalone `demo` plugin.
- [ ] **T2 — skill**: `plugins/work/skills/demo/SKILL.md` — the seven-step ritual, with a `demo_test.sh` beside it (deterministic: fixture landing → asserts report has intent + before/after + gaps sections).
- [ ] **T3 — command**: `plugins/work/commands/demo.md` (`/work:demo`) + top-level `commands/demo.md` alias, both with `setHelpSections`.
- [ ] **T4 — three-places-agree**: update `plugins/work/.claude-plugin/plugin.json` description, `plugins/README.md` table (work count 2→3), `commands/README.md`; bump `CHANGELOG.md` (`work` minor). Run `claude plugin validate . --strict`.
- [ ] **T5 — wire references**: `plugins/work/README.md`, the `work:loop`/`work:dispatch` "not done at dispatched" lines point at `/demo` as the capstone; the top-level README "what should I run?" gets a row.
- [ ] **T6 — self-demo**: run `/demo` on THIS change (demo the demo), attach the report to the PR — the acceptance proof.

## Validation

- **Self-referential proof**: the PR that adds `/demo` is validated *by running
  `/demo` on itself* — recover this plan's intent, drive the installed command on a
  fleet box, before/after (agent-sits vs report-produced), report attached to the PR.
  If the command can't demo its own landing, it isn't done.
- `demo_test.sh` runs green next to the skill (real path, no mocks): a fixture
  landing in, a report with the required sections out.
- `claude plugin validate . --strict` passes; three-places-agree count holds.
- Rendered report inspected headlessly in both themes before it's shown.

## Risks

- **"Real environment" has no prod for a CLI change.** Most work here ships to npm,
  not a running service. Mitigation: the floor is the *installed binary on a fleet
  box* (`agents` at the released version, not `agents-dev`), driven for real — the
  same distinction `cli/CLAUDE.md` already draws. Flag in review if the skill ever
  lets a dev-build demo pass as shipped (`plugins/work/skills/demo/SKILL.md`).
- **Demo theater** — a green screenshot that proves nothing. Mitigation: step 5's
  completeness check is against the *recovered intent*, not the diff; the skill
  requires naming what was **not** demoed and why. A demo with no gap section and no
  measured delta is incomplete.
- **Surface bloat** on an already 45%-dead command set (your own usage report).
  Mitigation: no new plugin — `work:demo` + one alias; `/demo` earns its slot as a
  verbatim top-5 recurring ask, not a speculative feature.
- **Cost/time** — a full demo per landing is not free. Mitigation: `--no-report`
  for the quick path; the report is the default only because it's what you keep
  asking for.

## Tracking

- This plan: `.agents/plans/plan-demo-command.md` (committed with the feature).
- Ticket + PR links added here once the home decision (T1) is confirmed.
