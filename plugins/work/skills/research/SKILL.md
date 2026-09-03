---
name: research
description: "Answer a hard research question by fanning it out across DISTINCT search modalities, each blind to the others, then synthesizing one sourced artifact. Codex agents run aggressive web search; Grok agents mine X/Twitter community chatter (its privileged data); Antigravity works Google; Perplexity runs a broad browser-driven Deep Research report; the Claude fleet deep-reads and synthesizes. Multi-modal because no single engine sees everything — a company's funding is in a press release, its reputation is in X replies, its moat is in a founder's blog. Triggers on: /work:research, 'research X across sources', 'deep research on', 'market/competitive/landscape research', 'what's the real story on <company/topic>', 'pull everything on', 'multi-source research'."
argument-hint: "<research question or topic> [--depth quick|standard|deep] [--out <path>]"
allowed-tools: Bash(agents *), Bash(git *), Bash(gh *), Bash(linear *), Bash(rush *), Bash(rg *), Bash(ls *), Bash(cat *), Bash(jq *), Read(*), Write(*), Task(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# work:research — one question, many engines, one sourced answer

You were handed a research question. Your job is to **get the real, cited answer** — not one
model's guess. No single search engine sees the whole picture: funding rounds live in press
releases and SEC filings, reputation and traction live in X/Twitter replies, technical moat
lives in a founder's blog or a HN thread, and adoption numbers surface in Perplexity's broad
crawl. So you **fan the question out across distinct engines that each see a different slice**,
run them in parallel, then reconcile their findings into one artifact where every claim carries
a source. One engine is a rumor; three independent engines that agree is a fact.

Question / topic: `$ARGUMENTS`.

| This skill | Not this skill |
|---|---|
| A **question** answered from many live engines, synthesized + cited | `sessions:search` — search your own past transcripts |
| Fan out across Codex / Grok / Antigravity / Perplexity / Claude | `browser` alone — one engine, one tab, by hand |
| Produces a durable sourced report | `work:dispatch` — routes one unit of work to an executor |

## The core rule (load-bearing — read first)

**Diversity beats depth from one source.** Do NOT just ask Claude (or any one model) harder.
Spawn engines that have access the others lack, prompt each for the slice it is best at, and
keep them **blind to each other** so they don't converge on the same first-page results. Then
**cross-check**: a number only one engine reports is a lead to verify, not a finding. Every
claim in the final report cites where it came from — an unsourced number is a defect.

## 1. Frame the question — angles + a target shape

Turn the topic into **3–6 concrete sub-questions** (the angles you actually need answered), and
decide the output shape up front (a table of companies with funding/investors/customers? a
narrative with a claims list? a comparison matrix?). Pick `--depth` if the caller didn't:
`quick` (one round, ~3 engines), `standard` (default: all engines, one verify pass), `deep`
(loop-until-dry: keep spawning finders until two rounds add nothing new, then a completeness
critic pass). Ground once in any local context (`AGENTS.md`, a prior `docs/research/*`) so you
don't re-derive what's already known.

## 2. Fan out across engines — parallel, blind, each to its strength

Spawn these **concurrently** (one message, multiple dispatches). Give each the sub-questions and
ask for **structured findings with source URLs**, not prose. Route by what each engine sees best:

| Engine | How to run it | Best at |
|---|---|---|
| **Codex** | `agents run codex "<web-search brief>" --device auto` | Aggressive multi-query **web search** — docs, filings, press, GitHub, changelogs. Ask for many queries, not one. |
| **Grok** | `agents run grok "<X/community brief>" --device auto` | **X/Twitter** community chatter — who's shipping, sentiment, real-user complaints, launch reactions. Its privileged data; nothing else sees it. |
| **Antigravity** | `agents run antigravity "<Google brief>" --device auto` | **Google** search integration — the broad web index, news, forums. |
| **Perplexity** | **Browser-driven Deep Research** — see §3 | A single **broad, cited report** that goes wider than a targeted crawl. Use it for the "everything on X" sweep. |
| **Claude fleet** | `agents run claude "<deep-read brief>"` or the `rabbit-hole` subagent | **Deep reading + synthesis** — follow a lead all the way down, read the actual page, resolve conflicts. |

Not every question needs all five. A pure market-map leans Codex + Perplexity; a
reputation/sentiment question leans Grok; a technical-moat question leans Claude deep-read + HN.
Pick the engines whose slice the question actually needs, but **always use at least three** so no
single engine's blind spot becomes the answer's blind spot.

## 3. Perplexity (and Grok) Deep Research — the correct browser recipe

Deep Research is a **dedicated mode**, NOT the Computer / Control-browser / Orchestrator mode.
Driving it wrong (submitting the question through computer-use) produces nothing usable. Do this:

1. `agents browser start --profile <perplexity-or-grok-profile> --task research --url <site>`
   (a signed-in profile from the injected browser list — never guess `default`).
2. **Open a new tab / new thread**, then click the **Search** control's caret to open its
   dropdown and select **"Deep research"** (the telescope / "In-depth reports, files, and apps"
   option — the same dropdown carries Search · Deep research · Learn step by step · Control
   browser; you want **Deep research**, not Control browser).
3. Type the **broad** brief (Perplexity's job is width — give it the whole question, not one
   angle) and submit.
4. **Monitor to completion** — Deep Research takes minutes and runs asynchronously. Poll the tab
   (`agents browser screenshot` / `refs`) on a bounded loop; do not declare done while it's still
   "researching."
5. **Export** the finished report (PDF / markdown / the cited sources) and save it into the run's
   artifact dir. Capture the **source list** — that's the cross-check ammunition for §4.

If the tool is **blocked on credits or a paywall**, that is a genuine owner blocker: post it
(`agents feed post "<ask>" --blocked`) and continue with the other engines — never silently drop
it and never fake a result. (This is exactly how a Perplexity run stalled unnoticed before.)

## 4. Reconcile — cross-check, dedup, and verify before you believe anything

Collect every engine's structured findings and **merge on the entity/claim**, not by trusting one
source. For each claim:

- **Agreed by ≥2 independent engines** → high confidence, cite both.
- **Only one engine** → a **lead**, not a fact. Send a Claude deep-read to open the actual source
  and confirm or kill it. Guessing a number to fill a cell is a fabrication, not research.
- **Conflicting** (two funding totals, two customer counts) → surface the conflict with both
  sources; pick the more authoritative (filing > press > blog > tweet) and say why.

On `--depth deep`, run a **completeness critic**: "what angle did no engine cover, what claim is
still single-sourced, what source did nobody actually open?" — its answers are the next round.

## 5. Deliver — one sourced artifact, durable

Synthesize into the target shape from §1, then **write it where it survives the session** (per the
project's durable-artifacts rule): promote a keepable result to `docs/research/<YYYY-MM-DD>-<slug>/`
(tracked), rendering an `index.html` via the `artifacts` skill when it's worth showing visually,
with the raw per-engine outputs beside it. Every claim cites its source; a confidence column marks
single- vs multi-sourced. Put the rendered result on the owner's screen
(`agents browser navigate --url file://<path>`), and `share` it if it's meant to leave the machine.

## Anti-patterns

- **Asking one model harder instead of many models each.** The whole point is orthogonal access —
  Grok sees X, Codex sees the web, Perplexity goes broad. One engine repeated is not "multi-source."
- **Perplexity/Grok Deep Research via Computer/Control-browser mode.** Wrong mode → no usable
  output. Use the **Search → Deep research** dropdown, new tab, then monitor to completion.
- **Trusting a single-sourced number.** One engine's claim is a lead; verify it or mark it
  low-confidence. Never launder a guess into a cited-looking cell.
- **Declaring a browser Deep Research done while it's still running**, or silently dropping it when
  it's blocked on credits. Monitor to completion; park a real blocker on the feed.
- **Leaving the answer in `/tmp` or scrollback.** A research result worth having is worth promoting
  to `docs/research/` where the next agent finds it.
- **Serial engines.** Fan out in one message; a research sweep that runs engines one-at-a-time
  wastes the fleet.

## Compose map

- Engines → the `run` skill (`agents run codex|grok|antigravity|claude`) and `teams` for a wider fan-out.
- Browser Deep Research → the `browser` skill; signed-in profiles + `secrets` for gated sources.
- Deep single-lead reading → the `rabbit-hole` subagent (via `Task`) or a Claude `agents run`.
- Render + publish → the `artifacts` skill (HTML) and `share` (shareable link).
- A blocker only the owner can clear (credits, a login) → `agents feed post "<ask>" --blocked`.
