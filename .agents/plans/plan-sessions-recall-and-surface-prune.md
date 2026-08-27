---
kind: plan
surface: cli
title: Stronger session recall + a measured prune of the command/skill surface
summary: >
  Two linked cleanups to the sessions subsystem, grounded in a 100-day, 14-device
  usage scan (24,283 sessions). (1) Ship a stronger `sessions:search` recall skill
  and fix what the session index leaves unsearchable — assistant reasoning is never
  indexed today. (2) Prune the command/skill surface the fleet measurably never
  uses, and fold `quality` into `refactor`.
status: shipped
links:
  - https://linear.app/phnx/issue/PHNX-3229
---

## Decisions (resolved 2026-08-27)

All four settled with the owner. This is now a build plan, not an open proposal.

1. **Prune / consolidate.** DELETE `code:prune`, `code:score`, `work:output` (0
   invocations across 24,283 sessions / 100 days / 14 devices, no live equivalent).
   KEEP `self:hibernate`. MERGE `fleet:mint-auth` **into** `fleet:onboard` — onboarding
   a device mints its auth in one flow; the standalone mint command is removed. FOLD
   `work:triage` into `/work:loop` (triage is a mode of draining a queue).
2. **Fold `quality` into `refactor`.** `/code:quality` is sourceless with 0 uses; its
   live equivalent is the global `simplify` skill. It becomes `/code:refactor`'s
   small-change mode: act on duplicate code, a bad abstraction, or a pattern that
   should exist but doesn't — never a report you do nothing with.
3. **Recall — both tracks in parallel.** Ship the `sessions:search` skill + script now
   (bridges the assistant-text gap by grepping transcripts) AND fix the index so
   assistant turns are natively searchable with snippets.
4. **`/recall` + drop dead doors.** `/recall` is the top-level door to `sessions:search`;
   the unused `sessions:finish/fork/insights` **command** doors are removed (behavior
   stays via the top-level aliases).

**Kept despite low counts** (valuable / auto-loading / measurement blind spot, not safe
to cut on count): the `design` plugin, `share:share`, `yc:workweave`, and every skill
whose "0" is a telemetry artifact (`mq`, `docs`, `cloud`, `monitors`, `learn`).

## Purpose

You asked for two things. First: a stronger search inside the `sessions` plugin — a
skill (plus a command and a top-level alias) that makes an agent pull *all relevant*
prior-session context on a topic, quickly, **without overloading context**, using
`agents sessions` but falling back to a script when it is flaky — and to verify what
the session index actually covers. Second: a complete report on which commands and
skills the fleet actually uses over ~100 days, since `agents insights` may not answer
it well. This plan carries both, because they share one root: **the session index is
half-blind, and that same blindness is why usage is hard to measure.**

## What we measured, and how much to trust it

A per-device scanner read every transcript active in the last 100 days out of each
box's `sessions.db`, and unioned three high-recall signals per resource: the
`<command-name>` marker in user turns, `Skill` tool-use blocks, and the
`session_resource_usage` ledger. It ran on 14 reachable devices and merged by session
id.

<div class="artifact-callout">
<strong>Coverage:</strong> 24,283 sessions scanned across 14 devices (the primary box 10,388 +
a second worker box 7,029 dominate); 2,540 distinct sessions invoked a `.system` resource.
Only one relayed laptop was unreachable.
<br><strong>Confidence is not uniform.</strong> A <em>command</em> is only ever run by
someone typing it, so a command's count is <strong>high-confidence</strong> — 0 means
genuinely never typed. A <em>skill</em> also auto-loads by description and is read by
its own command, and neither path emits a <code>Skill</code> tool-call — so a skill's
count <strong>undercounts</strong>, and a skill "0" is a question, not a verdict.
</div>

`agents insights` does not answer this: its `resource-mix` recipe reads `usage.db` and
only knows `kind: secret` (437 events) and `kind: browser` (4). It has **no per-command
or per-skill breakdown by name**. That gap is why this scan exists.

## Usage report — 100 days, 14 devices

<figure class="artifact-figure">
<svg viewBox="0 0 900 430" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Command usage by distinct sessions, 100 days">
  <text x="20" y="26" fill="#e8f0dd" font-size="15" font-family="ui-sans-serif,system-ui" font-weight="600">Commands — distinct sessions (top used vs zero)</text>
  <g transform="translate(150,50)" font-family="ui-monospace,monospace">
    <rect x="0" y="0" width="700" height="18" fill="#a3e635"/><text x="-8" y="14" text-anchor="end" fill="#cbd5c0" font-size="13">continue</text><text x="708" y="14" fill="#e8f0dd" font-size="12">531</text>
    <rect x="0" y="26" width="498" height="18" fill="#a3e635"/><text x="-8" y="40" text-anchor="end" fill="#cbd5c0" font-size="13">recap</text><text x="506" y="40" fill="#e8f0dd" font-size="12">269</text>
    <rect x="0" y="52" width="240" height="18" fill="#a3e635"/><text x="-8" y="66" text-anchor="end" fill="#cbd5c0" font-size="13">code:commit</text><text x="248" y="66" fill="#e8f0dd" font-size="12">63</text>
    <rect x="0" y="78" width="230" height="18" fill="#a3e635"/><text x="-8" y="92" text-anchor="end" fill="#cbd5c0" font-size="13">debug</text><text x="238" y="92" fill="#e8f0dd" font-size="12">58</text>
    <rect x="0" y="104" width="210" height="18" fill="#a3e635"/><text x="-8" y="118" text-anchor="end" fill="#cbd5c0" font-size="13">teams</text><text x="218" y="118" fill="#e8f0dd" font-size="12">48</text>
    <rect x="0" y="130" width="208" height="18" fill="#a3e635"/><text x="-8" y="144" text-anchor="end" fill="#cbd5c0" font-size="13">code:loop</text><text x="216" y="144" fill="#e8f0dd" font-size="12">47</text>
    <rect x="0" y="156" width="160" height="18" fill="#a3e635"/><text x="-8" y="170" text-anchor="end" fill="#cbd5c0" font-size="13">swarm:debug</text><text x="168" y="170" fill="#e8f0dd" font-size="12">28</text>
    <rect x="0" y="182" width="150" height="18" fill="#a3e635"/><text x="-8" y="196" text-anchor="end" fill="#cbd5c0" font-size="13">dispatch</text><text x="158" y="196" fill="#e8f0dd" font-size="12">25</text>
    <rect x="0" y="208" width="140" height="18" fill="#a3e635"/><text x="-8" y="222" text-anchor="end" fill="#cbd5c0" font-size="13">plan / visualize</text><text x="148" y="222" fill="#e8f0dd" font-size="12">23</text>
    <rect x="0" y="234" width="105" height="18" fill="#5b6f2a"/><text x="-8" y="248" text-anchor="end" fill="#cbd5c0" font-size="13">learn</text><text x="113" y="248" fill="#e8f0dd" font-size="12">16</text>
    <rect x="0" y="260" width="95" height="18" fill="#5b6f2a"/><text x="-8" y="274" text-anchor="end" fill="#cbd5c0" font-size="13">code:refactor</text><text x="103" y="274" fill="#e8f0dd" font-size="12">12</text>
    <rect x="0" y="292" width="4" height="18" fill="#7a2b2b"/><text x="-8" y="306" text-anchor="end" fill="#cbd5c0" font-size="13">code:prune</text><text x="14" y="306" fill="#e08a87" font-size="12">0</text>
    <rect x="0" y="318" width="4" height="18" fill="#7a2b2b"/><text x="-8" y="332" text-anchor="end" fill="#cbd5c0" font-size="13">code:score</text><text x="14" y="332" fill="#e08a87" font-size="12">0</text>
    <rect x="0" y="344" width="4" height="18" fill="#7a2b2b"/><text x="-8" y="358" text-anchor="end" fill="#cbd5c0" font-size="13">work:output / triage</text><text x="14" y="358" fill="#e08a87" font-size="12">0</text>
  </g>
  <text x="150" y="418" fill="#8a978a" font-size="11" font-family="ui-monospace,monospace">green = live · dark-green = long tail · red = 0 in 24,283 sessions</text>
</svg>
<figcaption>Command usage is steeply long-tailed: two commands (<code>continue</code>,
<code>recap</code>) carry most of it, a healthy middle exists, and a dozen sit at
exactly zero.</figcaption>
</figure>

**High-confidence dead commands** (0 invocations, both/only door):

| Command | Cmd sessions | Skill sessions | Resolved action |
|---|---|---|---|
| `code:prune` | 0 | (no skill) | **delete** |
| `code:score` | 0 | 0 | **delete** |
| `work:output` | 0 | (no skill) | **delete** |
| `fleet:mint-auth` | 1 | — | **merge into `fleet:onboard`** (one onboarding flow that mints auth) |
| `fleet:onboard` | 0 | (no skill) | **keep, absorb mint-auth** |
| `work:triage` | 0 | 0 | **fold into `/work:loop`** |
| `self:hibernate` | 0 | (no skill) | **keep** (owner call) |
| `share:share` | 0 | 1 | keep (valuable, near-zero) |
| `design:critique` / `design:design` | 0 / 0 | — / 1 | keep (auto-loads; blind-spot) |
| `yc:workweave` | 1 | 1 | keep, niche |

**Redundant alias doors** — behavior alive, plugin *command* door dead:

| Top-level door | Plugin door | Read |
|---|---|---|
| `/continue` = **531** | `sessions:continue` = 3 | top door wins; keep skill, drop nothing critical |
| `/finish` = 2 | `sessions:finish` = 0 | drop the redundant plugin command door |
| `/insights` = 2 | `sessions:insights` = 0 | drop the redundant plugin command door |
| (no top door) | `sessions:fork` = 0 | fork behavior itself unused — demote |

**The measurement blind spot — do NOT cut these on the count:**

`mq` (0), `docs` (0), `cloud` (0), `monitors` (0), `learn`-skill (0) all read as unused
*by skill-tool count*, but each is used via its CLI, an auto-load, or its command
(`/learn` ran 16 sessions and simply reads the `learn` skill). Cutting on this signal
would delete live capability. **The fix is telemetry, not deletion** — which is the
same index gap the recall track closes.

## Current architecture

How the session index and search work today, and where the two blind spots are.

<figure class="artifact-figure">
<svg viewBox="0 0 900 380" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Current session indexing and search data flow">
  <defs>
    <marker id="a" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#a3e635"/></marker>
    <marker id="b" markerWidth="9" markerHeight="9" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 Z" fill="#c0504d"/></marker>
  </defs>
  <rect x="20" y="150" width="150" height="70" rx="8" fill="#14181a" stroke="#3a4a2f" stroke-width="1.5"/><text x="34" y="180" fill="#e8f0dd" font-size="13" font-family="ui-sans-serif,system-ui" font-weight="600">transcript .jsonl</text><text x="34" y="200" fill="#9fb08f" font-size="11" font-family="ui-monospace,monospace">user + assistant + tools</text>
  <rect x="230" y="150" width="160" height="70" rx="8" fill="#14181a" stroke="#3a4a2f" stroke-width="1.5"/><text x="244" y="180" fill="#e8f0dd" font-size="13" font-family="ui-sans-serif,system-ui" font-weight="600">discover.ts</text><text x="244" y="200" fill="#9fb08f" font-size="11" font-family="ui-monospace,monospace">userTexts.join()</text>
  <rect x="470" y="60" width="180" height="80" rx="8" fill="#14181a" stroke="#3a4a2f" stroke-width="1.5"/><text x="484" y="90" fill="#e8f0dd" font-size="13" font-family="ui-sans-serif,system-ui" font-weight="600">session_text (FTS)</text><text x="484" y="110" fill="#9fb08f" font-size="11" font-family="ui-monospace,monospace">label·topic·project</text><text x="484" y="126" fill="#9fb08f" font-size="11" font-family="ui-monospace,monospace">content = USER turns</text>
  <rect x="470" y="230" width="180" height="80" rx="8" fill="#14181a" stroke="#3a4a2f" stroke-width="1.5"/><text x="484" y="260" fill="#e8f0dd" font-size="13" font-family="ui-sans-serif,system-ui" font-weight="600">tool_call_text (FTS)</text><text x="484" y="280" fill="#9fb08f" font-size="11" font-family="ui-monospace,monospace">tool·input·output</text><text x="484" y="296" fill="#9fb08f" font-size="11" font-family="ui-monospace,monospace">success out ≤ 1 KiB</text>
  <rect x="710" y="60" width="170" height="80" rx="8" fill="#14181a" stroke="#3a4a2f" stroke-width="1.5"/><text x="724" y="90" fill="#e8f0dd" font-size="13" font-family="ui-sans-serif,system-ui" font-weight="600">agents sessions «q»</text><text x="724" y="110" fill="#9fb08f" font-size="11" font-family="ui-monospace,monospace">ftsSearch → session_text</text><text x="724" y="126" fill="#9fb08f" font-size="11" font-family="ui-monospace,monospace">ONLY · no snippet</text>
  <path d="M170,185 L228,185" stroke="#a3e635" stroke-width="2" fill="none" marker-end="url(#a)"/>
  <path d="M390,175 C430,160 440,120 468,110" stroke="#a3e635" stroke-width="2" fill="none" marker-end="url(#a)"/>
  <path d="M390,195 C430,230 440,260 468,268" stroke="#a3e635" stroke-width="2" fill="none" marker-end="url(#a)"/>
  <path d="M650,100 L708,100" stroke="#a3e635" stroke-width="2" fill="none" marker-end="url(#a)"/>
  <path d="M300,150 C300,60 360,40 468,90" stroke="#c0504d" stroke-width="2" fill="none" stroke-dasharray="5 4" marker-end="url(#b)"/>
  <text x="150" y="54" fill="#e08a87" font-size="11" font-family="ui-monospace,monospace">assistant turns → DROPPED (discover.ts:3813)</text>
  <path d="M708,300 C690,330 680,150 706,120" stroke="#c0504d" stroke-width="2" fill="none" stroke-dasharray="5 4" marker-end="url(#b)"/>
  <text x="560" y="345" fill="#e08a87" font-size="11" font-family="ui-monospace,monospace">tool matches never reach the bare query (needs --include tools)</text>
</svg>
<figcaption>Two blind spots: assistant reasoning is never written to any index, and the
bare query reads only <code>session_text</code>, so tool activity and answers are
invisible to <code>agents sessions "…"</code>.</figcaption>
</figure>

Verified against the code and the live DB:

- `session_text.content` is only the **user turns** (`discover.ts:3798`); a 665-message
  session indexes 43 characters (its title). Assistant text is dropped at
  `discover.ts:3813`.
- The bare query hits **only** `session_text` via `ftsSearch` (`db.ts:3942`); tool
  activity lives in a separate `tool_call_text` reachable only with
  `--include tools --query` and is never unioned.
- Results are whole-session refs with **no snippet** (`db.ts:4032`) — so recall means
  dumping a transcript, the opposite of "without overloading context."
- `scan_ledger` has **no `extractor_version`** (`db.ts:163`), so improving the content
  extractor never re-indexes history — a fix needs a reindex lever.

## Proposed Changes

### Track A — `sessions:search` recall skill (ships now, cross-harness)

A skill plus a bundled `recall.py` that (1) **finds** candidates from both indexes,
(2) **recovers** assistant answers the index lacks by grepping the candidate
transcripts directly (the files hold every role), (3) **extracts** only ±N lines around
matches, capped, and (4) emits a compact digest — bounded output, context-safe. It
prefers `agents sessions --json` and falls back to direct SQLite when the CLI fans out
over the network and stalls.

```diff
# plugins/sessions/skills/search/SKILL.md  (new)
+---
+name: sessions:search
+description: Find ALL relevant prior-session context on a topic across the fleet —
+  ranked, snippet-level, context-bounded. Unions user turns, assistant answers
+  (via transcript grep), and tool activity; falls back to direct sqlite when the CLI is flaky.
+user-invocable: true
+---
+# Procedure: derive terms → layered query (content + tools) → transcript-grep for
+# assistant matches the index misses → extract capped snippets → synthesize a digest.
```

```diff
# plugins/sessions/commands/search.md  (new)  → routes to the skill
# commands/recall.md            (new)  → top-level /recall alias → sessions:search
```

### Track B — index the answers (agents-cli, parallel)

```diff
# cli/src/lib/session/discover.ts
- if (parsed.type !== 'assistant') return;   // assistant text discarded
+ // capture assistant text into a weighted column so answers are searchable
+ state.assistantTexts.push(extractAssistantText(parsed));
```

```diff
# cli/src/lib/session/db.ts — add a content extractor_version + reindex lever
+ scan_ledger.extractor_version INTEGER   // mirror TOOL_INDEX_VERSION so a better
+                                         // extractor re-indexes history, not just new files
+ // ftsSearch: emit snippet() so callers get context-sized hits, not whole sessions
```

### Track C — prune (this repo), gated on decisions 1–2

Delete the confirmed-dead command files + their README/manifest rows + CHANGELOG;
fold `quality` into `/code:refactor`; drop the redundant `sessions:*` command doors.

## Public Interface

| Surface | Change |
|---|---|
| `/sessions:search «query»` | **new** — ranked, snippet-level cross-session recall |
| `/recall «query»` | **new** top-level alias → `sessions:search` |
| `agents sessions "«q»"` | now finds sessions by **assistant answers** and returns snippets |
| `/code:refactor` | gains a "quality" small-change mode (duplicate code, bad abstraction, missing pattern) |
| `/code:prune`, `/code:score`, `/work:output` | **removed** |
| `/code:quality` | **removed** (already sourceless) — folded into `/code:refactor` |
| `/fleet:onboard` | **absorbs** the mint-token flow; `/fleet:mint-auth` **removed** |
| `/work:triage` | **removed** — folded into `/work:loop` |
| `sessions:finish/fork/insights` command doors | **removed** (behavior kept via top-level) |

<figure class="artifact-figure artifact-behavior">
  <section data-state="current" data-evidence="mockup">
    <h4>Today — <code>agents sessions "how did we fix the daemon race"</code></h4>
    <pre>$ agents sessions "how did we fix the daemon race" --all
(no results)

# the fix WAS discussed — but only in assistant turns,
# which no index contains. Recall fails.</pre>
  </section>
  <section data-state="proposed" data-evidence="mockup">
    <h4>Proposed — <code>/recall "how did we fix the daemon race"</code></h4>
    <pre>$ /recall "how did we fix the daemon race"
▸ 3 relevant sessions (100d, all devices)

sess-a1b2c3 · 2026-08-19 · agents-cli · why-matched: assistant
  "…the race was the ext watchdog rotate loop racing the
   daemon; fix = single scheduler, PR #1914…"    resume ▸
sess-d4e5f6 · 2026-08-11 · tool: git log #1914 touched daemon.ts
sess-7890ab · 2026-08-09 · user: "daemon keeps double-firing"
(3 sessions · 6 snippet lines · 0 full transcripts loaded)</pre>
  </section>
</figure>

## Plan

The task checklist is created in the harness and tracked against PHNX-3229.

## Validation

- **Recall skill:** on a known session whose answer lives only in an assistant turn
  (e.g. the daemon-race fix), `/recall` returns it in the top 3 with a snippet, loading
  0 full transcripts. Re-run the exact negative control from this investigation
  (`"rendering correctly now"`) and confirm it now resolves.
- **Index:** after the extractor bump, a mid-conversation assistant phrase matches via
  `agents sessions "…"`; `scan_ledger.extractor_version` forces a backfill on read.
- **Prune:** `agents inspect --commands` on a synced box no longer lists the removed
  commands; README/manifest counts match disk; the usage scan re-run shows no orphaned
  references.

## Risks

- **Deleting a low-confidence skill zero.** `mq`/`docs`/`cloud`/`monitors` read as 0 but
  are live via CLI/auto-load. Mitigation: the prune list contains **commands only**
  (high-confidence); no skill is deleted on count alone.
- **Reindex cost.** Adding `extractor_version` to `scan_ledger` re-extracts history on
  next read across the fleet. Mitigation: incremental via existing `parser_state`; bump
  once, warm via the daemon tick.
- **Transcript grep on huge sessions.** The skill's assistant-recovery reads candidate
  `.jsonl` files. Mitigation: cap candidates (top-K) and bytes; the DB narrows first.
- **Codex user turns ≥2000 chars are dropped from content** (`discover.ts:4996`), so a
  small class of sessions stays under-indexed even after Track B. Note, don't fix here.

## Tracking

- PHNX-3229 — Clean agents-cli repository root and consolidate project skills into system resources
- **Delivered (all merged):**
  - agents-cli #3184 — index assistant answers + `extractor_version` backfill + snippets (8 harnesses)
  - .system #407 — surface prune + folds (`quality→refactor`, `mint-auth→onboard`, `triage→loop`)
  - .system #408 — `/recall` + `sessions:search` skill + `recall.py`
- PHNX-3364 — follow-up: `snippet()` + per-harness assistant-text test coverage
- PHNX-3350 — carries the `timeout` platform-portability nudge (rides the shared unwrap)
