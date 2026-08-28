---
name: orchestrate
description: "Fan a task out across a swarm of parallel coding agents via `agents teams` — the engine behind every /swarm:* command. Build a distribution plan with boundary contracts, spawn a mixed team (claude/codex/antigravity), monitor, and synthesize. Use whenever a task is wide enough that one agent would serialize 4+ independent edits, or when you want independent agents to verify a conclusion instead of trusting one. Triggers on: 'swarm', 'fan out', 'spin up a team', 'parallel agents', 'distribute this', 'independent verification'."
argument-hint: "[task, plan, or question to distribute across the swarm]"
allowed-tools: Bash(agents teams*), Bash(agents run*), Bash(agents sessions*), Bash(git status*), Bash(git log*), Bash(git diff*), Bash(rg*), Bash(fd*), Bash(ls*), Read(*), Grep(*), Glob(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# swarm:orchestrate — the fan-out engine

> Distribute and execute a task across parallel agents. This is the shared engine every `/swarm:*` command builds on. `/swarm` and `/swarm:run` are the generic mode; the specialized modes (`/swarm:plan`, `/swarm:spec`, `/swarm:debug`) read this skill for the **mechanics**, then layer their own phases and output format on top. It has no command of its own — invoke it through those surfaces.

You are the **orchestrator**. Agents execute; you architect. Bad architecture = bad execution. Your job is to decompose, set boundaries, spawn, monitor, and synthesize — never to single-thread work that could run in parallel.

## The runtime: `agents teams`, not Swarm MCP

The old Swarmify MCP (`mcp__Swarm__spawn`, `npm @swarmify/agents-cli`) is **deprecated and gone**. All fan-out now goes through the `agents teams` CLI. If you have never used it, run `agents teams --help` and `agents teams doctor` (lists which agent CLIs are installed) first.

```bash
agents teams create <slug>                                   # one team per task; slug = kebab of the goal
agents teams add <slug> kimi   "<brief>" --name <role>       # one add per track — substitute from `agents view`
agents teams add <slug> codex  "<brief>" --name <role> --after <dep>   # DAG dependency
agents teams start <slug> --watch                            # drains the DAG, parallel where it can
agents teams status <slug> --since <iso-ts>                  # delta poll
agents teams logs <slug> <role>                              # read one teammate
agents teams disband <slug>                                  # tear down when synthesis is done
```

- **Mix agents** when available (`claude`, `codex`, `antigravity`, `cursor`, `opencode`) — different models have different blind spots. That diversity is the entire point of a swarm; never spawn three of the same model to "verify" each other.
- **`--mode plan`** (read-only) for research, audit, planning, verification. For a track that changes code, prefer **`--mode auto`** over plain `edit` — teammates run headless, and `edit` alone can stall waiting on an approval prompt nobody is there to answer; `auto` clears safe operations on its own through each harness's native auto-approval (Claude/Copilot's smart classifier, Codex's never-prompt `approval_policy=never`, Droid's high-auto). Reach for plain `edit` only when a human is actively watching that teammate's session.
- **Steer cost per track** with `--model cheap|default|best|ultra` on `teams add` — a stable tier that resolves per harness+version to a supported model (cheap for grunt tracks, best/ultra for the hard one). See `agents models <agent>` for the resolved map.
- **Never** leave a team running. Disband when done.

## Pick the swarm — discover who's available, then size by judgment

Two decisions, both yours as the orchestrator, before you write the distribution plan:

**Which providers** — never assume a CLI is installed and logged in. Probe first:

```bash
agents teams doctor          # JSON: which agent CLIs are installed (claude/codex/antigravity/cursor/opencode)
agents view --json           # installed versions + signed-in status per agent
```

Mix across the ones that come back **available and signed-in**. If only one provider is up, say so and proceed single-provider rather than spawning blind.

> Caveat: doctor's `signedIn` is read from installed config, not a live call — stale
> auth (droid especially) can report signed-in and still 401 at spawn. Before a
> load-bearing run, smoke-test the provider:
> `agents run <agent> --mode skip --timeout 1m "Reply with exactly OK"`.

**How many** — there is **no fixed sizing table**. You are a capable orchestrator; size the swarm to the task's complexity by judgment: one agent for a narrow, single-surface job; more for wide, cross-cutting, or gnarly work where independent angles pay off. Scale the *verification* depth the same way — a trivial claim needs one check, a load-bearing cross-stack conclusion needs several. Spend agents where uncertainty is highest, not uniformly. Every other `/swarm:*` skill defers to this rule instead of hardcoding counts.

## Exploration uses Claude subagents, not the swarm

For exploration, investigation, or scoping *before* you can write a distribution plan, use the `Task`/`Agent` tool with `subagent_type: "Explore"` or `"Plan"` — fast, in-process, read-only. Reserve `agents teams` for **parallel execution of known, well-defined work**. Spawning a full agent CLI just to grep is waste.

When you do spawn `Agent` subagents, set `model` explicitly — `"sonnet"` for breadth, `"opus"` for depth, **never `"haiku"`, never omit it**. Every investigation brief ends with the exact line:

> `Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.`

## Web-search first — your weights are stale

Before architecting anything that touches the state of the world — a library's current API, a framework capability, a pricing tier, a SOTA approach, a model id — **WebSearch with the current year in the query**, then `WebFetch` the authoritative source. Do not distribute a plan built on remembered facts. Fold the citations into the brief you hand each teammate so they don't re-derive (or contradict) them. This matters most for `/swarm:plan` and `/swarm:spec`, but applies anywhere a track depends on an external truth.

## Pre-spawn integration discovery (surgical, not exhaustive)

Agents execute precise targets; they do not explore. Before the distribution plan, you find the seams:

1. **Grep for integration points** — where similar features store config, define types, register routes. (`rg "UserConfig" → pkg/config/user.go`.)
2. **Read only the pattern-defining files** — the structs/interfaces/conventions a teammate must extend rather than reinvent.
3. **Put concrete paths in the brief**, never vague instructions:
   - BAD: "Store the local-model config somewhere."
   - GOOD: "Add `UseLocalModel bool` to the `UserConfig` struct in `harness/config/user.go:15`."
4. **Name each seam and the command that exercises it.** Where track A will call what track B builds (a CLI it shells out to, a route it hits, a symbol it imports), write down the exact contract (`imsg calls: agents mission-control digest --phone`) and the one command that proves the two halves connect. This list is not just for the briefs — it is the **post-merge integration checklist** you must run before the swarm is done (see Post-completion). No seam recorded now = no way to verify the composed feature later.

## Distribution plan — REQUIRED before any spawn

Show the distribution plan as a concise checkpoint, then proceed on the default path. Only stop for genuine scope/design ambiguity, not to ask permission. Fanning out the wrong plan wastes a wall-clock window, so make the plan concrete enough that it can be executed without re-asking.

```
## Swarm Distribution Plan

### Goal
[one or two sentences — what we're building / proving / cleaning]

### Track: <kebab-name>  (agent: claude|codex|antigravity, mode: plan|edit)
- Goal: [specific deliverable, 1–2 sentences]
- Owns: [exact files/globs this track may modify]
- Must NOT touch: [files owned by other tracks]
- Verification: [the literal command/flow that proves this track is done]
- After: [comma-separated track names, or "none"]

### Track: ... (repeat, 2–7 tracks)

### Boundary contracts
- [How work is divided so no two tracks write the same file]
- [Shared deps → ONE canonical owner; everyone else imports]
- [Sequencing: who must finish before whom, and why]

Ready to spawn? (yes / edit / no)
```

If A must wait on B's *output to even start*, the cut is wrong — re-slice, or sequence with `--after`. If you can't find ≥2 genuinely independent tracks, this isn't a swarm task: drop to a single `agents run` or just do it inline.

## Teammate brief template — every `add` gets all of it

```
## Mission
[why — the business/technical goal the whole swarm serves]

## Full scope
[ALL tracks across ALL agents, so this teammate sees the big picture]

## Your assignment
[the specific files/task THIS track owns]

## Boundary contract
- You OWN (may modify): [explicit list]
- You must NOT touch: [explicit list — owned by other tracks]
- Shared deps: [how to handle imports/types you don't own]

## Pattern to apply
[exact code pattern / file:line anchors / web-search citations — concrete]

## Success criteria
[how this track knows it is done — the real flow, not "tests pass"]

## Feed/notify (verbatim)
Post to the feed at IMPORTANT milestones only, never per step. Use a plain agents feed post --title "<short subject>" at start and at PR-opened (record-only). On final delivery — PR merged, or the composed work runs end-to-end — add --level important so it reaches the owner (deprecated alias: agents notify). If you hit a real blocker, use agents feed post --blocked instead (never combined with --level). Do NOT narrate every step.

## Completion contract (edit-mode, verbatim)
Your task is complete only when your PR is merged, or you have handed it off by naming who/what now owns it. If you are waiting on CI or review, keep waiting with a background watch — do not stop.

Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.
```

## Monitor → synthesize

1. **Poll** with `agents teams status <slug> --since <last-ts>`. Wait with `sleep N && agents teams status … && echo "…"` — never `Monitor`/`ScheduleWakeup`/`until` loops (they fail silently).
2. **Unblock** a stalled track: read its log, diagnose, inject a follow-up hint or `remove`+`add` with a sharper brief. Don't silently finish its work yourself — the boundary is the lesson.
3. **Verify each track** the moment it lands — run its verification command. Failure goes back to the same teammate.
4. **Don't assume failure from empty metadata.** `files_modified: []` may mean a different approach — grep for the actual change before concluding a track failed.
5. **Synthesize, don't concatenate.** Where tracks AGREE, that's likely true. Where they DIVERGE, that's the real decision point — surface it plainly with each side cited to its teammate + file:line. For brainstorm/plan modes, fuse the strongest ideas; for edit modes, report what landed with proof.
6. **Post at boundaries, not per step.** As orchestrator, record one plain `agents feed post` when you spawn the swarm and one when it completes. Reach the owner only at delivery — the composed cross-track flow ran end-to-end — with `agents feed post --level important` (deprecated alias: `agents notify`), or when a teammate is blocked and needs the owner, with `agents feed post --blocked` (never `--level` together with `--blocked`). This is the record-vs-deliver split from `feed-status-posts.md`.

## Independent verification = blinded

When the swarm's job is to *check* a conclusion (debug root cause, plan soundness, an analysis), give each verifier the **context and the question but NOT your hypothesis or proposed answer**. Two agents agreeing with you because you told them the answer proves nothing. You want independent convergence, not confirmation bias. Different model providers per verifier.

## Post-completion (edit-mode swarms)

- **Run the integration checklist FIRST — this is what "done" means for a swarm.** Every track's PR merging green does **not** mean the composed feature works: each teammate's tests and reviewer only saw its own half, so the seam between tracks (track A calls what track B built) is the one thing nobody verified — and it's exactly where the feature breaks. Take the seam list from Pre-spawn integration discovery and **run each seam's command against where the feature actually executes** (the running daemon / installed binary / deployed service — merged to `main` is not deployed), then **quote the real output**. A caller/callee mismatch (`imsg` shells out to `agents mission-control digest`; the digest track shipped `mission-control-digest`) passes every per-track check and dies here. If a seam can't be exercised, call that hop **unverified** — never fold it into "done end-to-end".
- Verify each track's real flow (F3: "done" = the verified user-visible outcome, not "code written").
- Run the relevant test suite; report pass/fail with quoted output.
- Disband the team.
- Recap: what each track shipped (commit/PR URLs), **the composed-flow verification with its quoted output**, what's deferred/unverified and why, verification proof per track. A table of green checkmarks is a report of merges, not proof of a working feature. No human-time estimates — wall-clock minutes, edit counts, or token cost only.
