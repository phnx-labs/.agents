---
kind: plan
title: Stop agents shipping UI they have never looked at
surface: internal
summary: An agent spent 57 minutes iterating on a UI mockup it had never rendered. Nothing caught it, because every evidence gate we own is shaped around pull requests.
---

# Stop agents shipping UI they have never looked at

An agent spent 57 minutes and 17 of your turns iterating on a UI mockup it had never once rendered. It wrote "quick tour of what you're looking at" about a browser window it had never seen. Nothing in the guardrail system noticed, because every evidence gate we own is shaped around pull requests — and this delivery was an HTML file `scp`'d to your Mac.

<div class="artifact-callout">
<strong>My first design was wrong and an adversarial review killed it.</strong> I proposed a PreToolUse guard that blocks <code>scp</code>/<code>open</code> of an unviewed artifact, and I told you it had "zero false positives." That was measured on <em>one</em> transcript. Replayed across all 66 sessions on this box it fires <strong>13 blocks / 1 allow — and 12 of the 13 land in the single most disciplined session in the corpus.</strong> The plan below is the design that survived review, not the one I opened with.
</div>

## Purpose

### Focus for review

1. **The seam moved.** The harm was not the `scp` — it was the *sentence* "quick tour of what you're looking at" written about an unseen render. Change B gates **the claim**, at Stop, where it cannot be routed around. Confirm you agree that is the right target.
2. **Change A is the cheap win.** Two one-line-class edits turn the *existing, already-trusted* Stop delivery gate on for this entire failure class. If you only take one thing, take this.
3. **The focus-steal reversal.** `plan-presentation` currently orders agents to "Open it proactively, every time" on your Mac. You said the opposite. I propose render-always, open-on-request.
4. **Two bugs found en route that are arguably bigger than the UI one** — the `stop_hook_active` bypass (section 6) and the fact that `ui-work-discipline` **is not in the rules preset, so its text never reaches any agent** (section 7). Say whether they ride along or get their own tickets.

### Intent

> "the agent is being so silly and so idiotic when it creates mockups or these plans, it never checks them. And it should not steal the user's focus."

Make it mechanically hard to describe a UI you have not looked at, and stop agents throwing windows onto your screen.

---

## The failure — session `0e34891f`, 2026-08-15

**57 minutes. 17 typed turns from you. 47 tool calls against 135 assistant messages** — it talked roughly three times more than it acted.

<figure class="artifact-figure artifact-figure-wide artifact-figure-diagram">
<svg class="artifact-diagram" width="920" height="340" viewBox="0 0 920 340" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Timeline showing a 19 minute 28 second window in which the agent shipped a UI mockup three times without ever rendering it">
  <title>The blind window — 19m 28s</title>
  <rect x="173" y="52" width="519" height="150" fill="#ef4444" fill-opacity="0.10" stroke="#ef4444" stroke-opacity="0.45" stroke-dasharray="4 3"/>
  <text x="432" y="44" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif" font-size="13" font-weight="700" fill="#ef4444">19m 28s shipped blind</text>
  <line x1="60" y1="150" x2="870" y2="150" stroke="currentColor" stroke-opacity="0.35" stroke-width="1.5"/>
  <text x="60"  y="176" text-anchor="middle" font-family="ui-monospace,monospace" font-size="11" fill="currentColor" fill-opacity="0.6">06:56</text>
  <text x="327" y="176" text-anchor="middle" font-family="ui-monospace,monospace" font-size="11" fill="currentColor" fill-opacity="0.6">07:06</text>
  <text x="594" y="176" text-anchor="middle" font-family="ui-monospace,monospace" font-size="11" fill="currentColor" fill-opacity="0.6">07:16</text>
  <text x="860" y="176" text-anchor="middle" font-family="ui-monospace,monospace" font-size="11" fill="currentColor" fill-opacity="0.6">07:26</text>
  <rect x="150" y="132" width="10" height="10" fill="#94a3b8"/>
  <rect x="573" y="132" width="10" height="10" fill="#94a3b8"/>
  <rect x="753" y="132" width="10" height="10" fill="#94a3b8"/>
  <text x="155" y="124" text-anchor="middle" font-family="ui-monospace,monospace" font-size="9" fill="currentColor" fill-opacity="0.55">wrote</text>
  <text x="578" y="124" text-anchor="middle" font-family="ui-monospace,monospace" font-size="9" fill="currentColor" fill-opacity="0.55">wrote</text>
  <text x="758" y="124" text-anchor="middle" font-family="ui-monospace,monospace" font-size="9" fill="currentColor" fill-opacity="0.55">wrote</text>
  <polygon points="173,88 181,104 165,104" fill="#ef4444"/>
  <polygon points="582,88 590,104 574,104" fill="#ef4444"/>
  <polygon points="592,88 600,104 584,104" fill="#ef4444"/>
  <text x="173" y="80" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif" font-size="10" font-weight="600" fill="#ef4444">SHIP</text>
  <text x="594" y="80" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif" font-size="10" font-weight="600" fill="#ef4444">SHIP x2</text>
  <circle cx="692" cy="150" r="6" fill="#3b82f6"/>
  <circle cx="764" cy="150" r="6" fill="#3b82f6"/>
  <circle cx="778" cy="150" r="6" fill="#3b82f6"/>
  <text x="692" y="128" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif" font-size="10" font-weight="700" fill="#3b82f6">first look</text>
  <polygon points="800,88 808,104 792,104" fill="#22c55e"/>
  <text x="826" y="80" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif" font-size="10" font-weight="600" fill="#22c55e">SHIP ok</text>
  <line x1="63"  y1="150" x2="63"  y2="212" stroke="#f59e0b" stroke-width="1.5"/>
  <line x1="249" y1="150" x2="249" y2="228" stroke="#f59e0b" stroke-width="1.5"/>
  <line x1="641" y1="150" x2="641" y2="252" stroke="#f59e0b" stroke-width="2.5"/>
  <circle cx="63"  cy="212" r="3.5" fill="#f59e0b"/>
  <circle cx="249" cy="228" r="3.5" fill="#f59e0b"/>
  <circle cx="641" cy="252" r="4.5" fill="#f59e0b"/>
  <text x="70"  y="216" font-family="ui-sans-serif,system-ui,sans-serif" font-size="11" fill="currentColor" fill-opacity="0.85">"show me what the new UI will look like… open it for me on zion"</text>
  <text x="256" y="232" font-family="ui-sans-serif,system-ui,sans-serif" font-size="11" fill="currentColor" fill-opacity="0.85">"quite a weak UI… those are not even the right logos"</text>
  <text x="300" y="272" font-family="ui-sans-serif,system-ui,sans-serif" font-size="12" font-weight="700" fill="#f59e0b">"Did you even look at this mock-up yourself?"</text>
  <rect x="60" y="300" width="10" height="10" fill="#94a3b8"/>
  <text x="76" y="309" font-family="ui-sans-serif,system-ui,sans-serif" font-size="11" fill="currentColor" fill-opacity="0.7">wrote the HTML</text>
  <polygon points="200,300 208,314 192,314" fill="#ef4444"/>
  <text x="214" y="309" font-family="ui-sans-serif,system-ui,sans-serif" font-size="11" fill="currentColor" fill-opacity="0.7">shipped to your Mac, unseen</text>
  <circle cx="430" cy="306" r="6" fill="#3b82f6"/>
  <text x="444" y="309" font-family="ui-sans-serif,system-ui,sans-serif" font-size="11" fill="currentColor" fill-opacity="0.7">agent looked at a render</text>
  <line x1="690" y1="300" x2="690" y2="312" stroke="#f59e0b" stroke-width="2.5"/>
  <text x="702" y="309" font-family="ui-sans-serif,system-ui,sans-serif" font-size="11" fill="currentColor" fill-opacity="0.7">your turn</text>
</svg>
<figcaption>Every red marker is a moment the agent put a UI in front of you that it had not rendered. The first blue dot — the first time it looked at its own work — lands 19m 28s after the first ship, and only after you asked it directly.</figcaption>
</figure>

| Time | Event |
| --- | --- |
| 06:56:06 | **You:** *"can you show me what the new UI will look like? …open it for me on zion"* |
| 06:59:40 | wrote `agi-ext-mockup.html` |
| **07:00:20** | **`scp` + `open` on zion — shipped blind** |
| 07:00:41 | Agent: *"It's open on zion — Quick tour of **what you're looking at**:"* then a paragraph describing a render it had never seen |
| 07:03:11 | **You:** *"quite a weak UI… The CL and CX, those are not even the right logos"* |
| 07:15:31 → 07:15:50 | wrote `fleet.html`, **shipped blind twice** (the first `open` failed; it retried without looking) |
| 07:17:54 | **You:** *"Did you even look at this mock-up yourself, open this in the website and take a screenshot?"* |
| 07:19:27 | Agent runs `echo "== headless browser options on this box =="` and loops over `chromium … brave-browser` **hunting for a binary by hand** |
| 07:19:48 | **First image read-back of its own render — 19m 28s after the first ship** |
| 07:22:16 → 07:23:16 | wrote `fleet2.html`, looked at it twice, *then* shipped. Correct, finally. |

## Root cause 1 — a delivered artifact is invisible unless it is a PR

Two independent places treat scratchpad-only work as "not a delivery":

```python
# hooks/stop/verify-delivery-chain.py:566
is_real_delivery = bool(pr_data) or (bool(repo_path) and bool(_deliverable_changed_files(repo_path, pr_data)))
```
```python
# hooks/stop/verify-work-state.py:283
if target and not target.startswith(("/tmp/", "/private/tmp/")):
```

No PR, no tracked file, everything under `/tmp/.../scratchpad/` — so `is_real_delivery` is `False`, `user_facing` is `False`, and the entire delivery gate is a no-op. **Measured: 0 Stop-gate messages in the whole 57-minute transcript.** A repo-wide grep confirms no guard in either layer fires on a visual file extension at all.

## Root cause 2 — the render capability was sitting right there, already configured

**Verified live, on both worker boxes, while writing this plan.** A bare `agents browser start --task X --url file://…` then `agents browser screenshot` renders headlessly on `yosemite-s0` and `yosemite-s1` with no `--profile` and no browser binary named — I ran it on each and looked at both PNGs (1467x901, headless Brave). **No config change is needed on s0 or s1; they already resolve to `brave-local`.** The agent simply never tried.

On `yosemite-s1`, the box it ran on the whole time:

```
brave-local   brave   Local headless Brave   cdp://127.0.0.1:9223   (default)
Default profile (this machine): brave-local
FOUND brave-browser -> /usr/bin/brave-browser
```

And the SessionStart hook injects this into **every** session on the fleet:

> Browser: a bare `agents browser start` on any machine uses THAT machine's configured profile — never pass --profile and never name a browser binary; the machine knows.

Three commands would have closed the loop. It hand-rolled a binary hunt instead — because **`ui-work-discipline.md` never names `agents browser`.** It names Vite, Storybook, and `/preview` routes, none of which exist for a one-off mockup. The rule pointed nowhere useful.

**The one real config gap is on `zion`, not the workers.** zion's default profile is `comet-local` — a *visible* browser. So the fleet-wide guidance "never pass `--profile`; the machine knows" produces a window in your face on the one machine you are sitting at. I hit this while rendering this plan and had to fall back to Chrome headless. Two fixes, both cheap: give zion a headless default profile, and change that guidance to "never pass `--profile` **on a worker**; on the interactive host, render headless."

## Root cause 3 — every Stop gate is one retry from a no-op

```bash
# hooks/stop/00-agent-verify-work-complete.sh:23-31
if [ "$stop_active" = "true" ]; then
  exit 0
fi
```

Identical at `plan-html-reminder.sh:45-46` and `no-permission-stop-guard.sh:42`. The harness sets `stop_hook_active: true` on the Stop event immediately following a blocked stop, and all three exit 0 **before evaluating any evidence**. An agent blocked once stops again with no new work and every gate passes. Loop protection is genuinely needed; unconditional `exit 0` is the wrong shape.

## Root cause 4 — the rules order the focus-steal

`plan-html-reminder.sh:208` literally prints this as remediation:

```
scp .agents/artifacts/$DATE/plan-<slug>.html <host>:/tmp/ && agents ssh <host> 'open /tmp/plan-<slug>.html'
```

Meanwhile `ui-work-discipline.md:7` bans focus theft for `agents computer` but says nothing about `open <file>` on your Mac.

---

## Proposed Changes

### A. Close the delivery hole — and key it on the artifact, **not** on a directory

At `verify-delivery-chain.py:566` and `verify-work-state.py:283`, treat this as a real delivery:

> **this session authored a visual artifact** (`.html`/`.png`/`.svg`/`.pdf`) **and it left the session** (`scp`/`rsync`/`agents share`/`agents ssh … open`/local `open`).

**No directory allowlist anywhere.** The `.agents/artifacts/yyyy-mm-dd/` layout is a convention agents follow inconsistently — they also write into a project's own `.agents/` subdir, into `/tmp` scratchpads, and into the repo under test. Any path-based rule inherits that inconsistency and silently misses the cases it did not enumerate. `verify-work-state.py:283`'s current `/tmp` exclusion is exactly that mistake in the other direction.

"Authored" must cover more than a `Write` tool call: a `> file.html` redirect, `artifacts render`, and `agents browser screenshot` all produce artifacts with no `Write` record. Coverage that misses those covers only hand-rolled HTML — the one path the rule already discourages.

This switches on the **existing, already-trusted** Stop delivery gate for the whole failure class — reusing its evidence machinery, its repeated-fire de-escalation (`00-agent-verify-work-complete.sh:70-117`), and its 20 s budget. It is a one-line-class change inside a gate that demonstrably fires (`gate_events`: `keep-moving` 137, `open-pr` 94, `delivery` 28).

### B. Gate the *claim*, not the transport — a Stop-time check

Fire only when the final message makes a **visual assertion** — a narrow token set in the same register as the existing `strong_parking` list (`00-agent-verify-work-complete.sh:801-807`): `you're looking at`, `quick tour of`, `on the left`, `the header shows`, `renders as`, `here's what you'll see`. Then require, in the goal suffix, an image `tool_result` whose **paired `tool_use.input.file_path` resolves**, occurring after the most recent authored visual artifact.

This targets the actual harm. It is bypass-irrelevant — an agent cannot route around describing a thing while describing it — has no compound-command hazard, and never touches Bash.

### C. PreToolUse nudge — `exit 0` with stdout, never `exit 2`

Modeled on `pre-tool-use/10-mq-read-nudge.py` ("Advisory only: it NEVER blocks"), once per artifact per session. You get the reminder at the moment of the ship with none of the deadlock in Risks.

### D. Rule repairs

- Name `agents browser start` / `navigate file://…` / `screenshot -o` as the first-line render method, ahead of Vite and Storybook.
- Invert the focus default: **render where you are running; `open` on the interactive host only when the user asked, and never before you have looked.**
- Soften `plan-presentation`'s "Open it proactively, every time" to render-always, open-on-request.

### E. Register the rule so its text actually ships

`ui-work-discipline` is **not in the `default` preset** in `rules/rules.yaml`, and `rules/README.md:48` states: *"A subrule not listed in a preset never renders."* The rule you rely on is not reaching agents. Separately, `~/.agents/rules/subrules/ui-work-discipline.md` shadows any system-layer file of that stem **wholesale**, so the guard must live under a distinct name or inside `plan-presentation/`.

## Public Interface

No new CLI surface. The changes are internal to hooks and rules.

| Surface | Change |
| --- | --- |
| Stop hook feedback | New gate message on a visual claim with no read-back, naming the `agents browser` remedy |
| PreToolUse stdout | Advisory nudge at ship time, once per artifact |
| `rules/rules.yaml` | `ui-work-discipline` added to the `default` preset |
| Agent-visible rule text | `ui-work-discipline.md` rewritten; `plan-presentation` amended |

## Validation

| Step | Check |
| --- | --- |
| Corpus replay | Replay any new predicate across **all 66 local transcripts**, not one. Target: 0 blocks in `c7d9f07e` (the disciplined session), block in `0e34891f` at 07:00:20 |
| Harness shape | Codex uses `custom_tool_call_output` + `input_image`, **not** `tool_result`/`image` — 398 rollouts, zero `tool_result`. Parse both, or fail open and say so in the header |
| Hook suites | `hooks/run_tests.sh`, `hooks/syntax_test.sh` (bash 3.2 gate) |
| Budget | p50 must stay near the 35 ms shim floor — shell `case` fast path first, python only on a real match |
| Live registration | `agents sync claude@all system` then `agents inspect hooks` |

## Risks

Every item below is a measured finding from the adversarial review, not a hypothetical.

| Risk | Evidence | Mitigation |
| --- | --- | --- |
| **False positives dominate** | Original design: 13 blocks / 1 allow across 66 transcripts; 12 in the most disciplined session | Dropped the blocking PreToolUse design (A/B/C instead) |
| **Blocks its own remediation** | The blocked command *contains* `agents browser start --url file://…` — the guard's advice sits inside the command it denies | Change C is advisory (`exit 0`) |
| **Duplicate side effects** | `gh pr comment …; agents feed post …; open …` — `exit 2` kills the line; the retry double-posts | Never `exit 2` on a trailing clause of a compound command |
| **The sanctioned path is uncovered** | `artifacts render` output has no `Write` record, so rule 5 skips it — coverage was hand-rolled HTML only, the path the rule already forbids | Widen "authored" to include `artifacts render` and `agents browser screenshot` |
| **Guard-vs-guard conflict** | `plan-html-reminder.sh:208` prints the exact `scp … && agents ssh … 'open …'` the guard would deny; hooks run concurrently so ordering cannot fix it | Amend that remediation text in the same change |
| **The read-back signal is path-blind** | The image `tool_result` carries no path; reading *your* pasted screenshot — which the rule mandates — clears the gate | Pair `tool_use_id` → `file_path` (Change B) |
| **Codex wedge** | Fail-closed on a harness with no image blocks = permanently unsatisfiable | Explicit documented fail-open, per `pr-description-reminder.sh:14-22` |

## Checklist

- [ ] A — scratchpad delivery hole at `verify-delivery-chain.py:566` + `verify-work-state.py:283`
- [ ] B — Stop-time visual-claim gate with paired `file_path` read-back
- [ ] C — advisory PreToolUse nudge (`exit 0`)
- [ ] D — rewrite `ui-work-discipline.md`; amend `plan-presentation` + its line 208 remediation
- [ ] E — add `ui-work-discipline` to the `default` preset; resolve the user-layer shadowing
- [ ] Corpus replay across all 66 transcripts before registering
- [ ] Decide: `stop_hook_active` bypass here or its own ticket
- [ ] Tests, CHANGELOG, PR, non-author review

## Tracking

| Item | Link |
| --- | --- |
| artifacts-cli schema deadlock | [phnx-labs/artifacts-cli#41](https://github.com/phnx-labs/artifacts-cli/issues/41) |
| `.agents/` out of the system repo | RUSH-2686 — dispatched to codex, branch `rush-2686-agents-path-policy` |
| This plan | RUSH ticket pending your go-ahead on scope |
