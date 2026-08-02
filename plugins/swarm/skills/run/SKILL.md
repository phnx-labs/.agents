---
name: run
description: "Run any task across a swarm — the generic fan-out mode. Decompose an arbitrary goal into independent tracks, spawn a mixed team of parallel agents (claude/codex/antigravity), monitor to completion, and synthesize. The catch-all `/swarm:*` command for work that doesn't fit the specialized modes (plan/debug/test/qa). Use when a task is wide enough that one agent would serialize 4+ independent pieces of work. Triggers on: 'swarm run', 'fan this out', 'distribute this across agents', 'run this as a swarm', 'parallelize this task'."
argument-hint: "[task, goal, or scope to distribute across the swarm]"
allowed-tools: Bash(agents teams*), Bash(agents run*), Bash(agents sessions*), Bash(agents view*), Bash(git status*), Bash(git log*), Bash(git diff*), Bash(git show*), Bash(rg*), Bash(fd*), Bash(ls*), Read(*), Grep(*), Glob(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# swarm:run — fan an arbitrary task out, then synthesize

> Read `swarm:orchestrate` first for all fan-out mechanics (provider discovery, distribution plan, boundary contracts, the teammate-brief template, monitoring, synthesis). This skill is the **generic mode**: it applies that engine to any task, without the specialized framing that `/swarm:plan`, `/swarm:debug`, `/swarm:test`, and `/swarm:qa` add on top.

You are running as a swarm: **$ARGUMENTS**

This is the default when the work is genuinely multi-agent but doesn't match a specialized mode. If the task IS one of those, prefer the specialized command — it has the right phases and output baked in:

- Building something non-trivial → **`/swarm:plan`** (research + OpenSpec-grade proposal + blind independent planning).
- Proving a non-obvious root cause → **`/swarm:debug`** (trace the path, confirm blind on different providers).
- Widening test coverage → **`/swarm:test`** (split into areas, cover each, synthesize cross-cutting tests).
- Behavioral QA of a running app → **`/swarm:qa`** (multi-port instances, waves of browser agents, ship verdict).

If it doesn't fit those, run it here.

## 1. Scope — is this even a swarm task?

A swarm earns its cost only when there are **≥2 genuinely independent tracks** — pieces that can run at the same time without waiting on each other's output. Before anything else:

- Use `Agent` subagents (`subagent_type: "Explore"` / `"Plan"`, `model` set explicitly, never haiku) to scope the work and find the seams — do NOT spin up full agent CLIs just to grep.
- If you can't find ≥2 independent tracks, this is **not** a swarm task. Say so and drop to a single `agents run`, or just do it inline. Don't fan out one job into three agents that step on each other.
- If the task touches the state of the world (a library API, a framework capability, a pricing tier, a model id), **WebSearch with the current year** and fold the citation into each brief — your weights are stale.

## 2. Distribute — plan, gate, spawn

Follow `swarm:orchestrate` exactly:

1. **Discover providers** — `agents teams doctor` / `agents view --json`. Mix across the ones that are installed AND signed in; diversity across claude/codex/antigravity is the point. If only one is up, say so and proceed single-provider.
2. **Size by judgment** — no fixed table. Wide/gnarly/cross-cutting work gets more tracks; a narrow job gets one (or none). Spend agents where uncertainty is highest.
3. **Show the Swarm Distribution Plan** as a checkpoint, then create the team and proceed. Only stop for genuine scope/design ambiguity, not for a permission gate.
4. **`--mode plan`** for read-only tracks (research, audit, analysis); **`--mode edit`** only for tracks that change code. Isolate every edit-mode track so two tracks never write the same file.
5. Every `add` gets the full teammate brief (Mission / Full scope / Your assignment / Boundary contract / Pattern to apply / Success criteria), ending with the exact line:
   > `Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.`

## 3. Monitor → verify each track

- Poll with `agents teams status <slug> --since <last-ts>`; wait with `sleep N && agents teams status … && echo "…"` — never `Monitor`/`ScheduleWakeup`/`until` loops (they fail silently).
- Verify each track the moment it lands — run its literal verification command/flow. Failure goes back to the same teammate with a sharper brief, not silently absorbed by you.
- Don't infer failure from empty metadata — `files_modified: []` may just mean a different approach; grep for the real change.

## 4. Synthesize — don't concatenate

- Where tracks **agree**, that's likely true. Where they **diverge**, that's the real decision point — surface it plainly, each side cited to its teammate + file:line.
- For read-only swarms, fuse the strongest findings into one answer. For edit swarms, report what actually landed with proof (the real flow ran, not "code written").
- **Disband the team** when synthesis is done — never leave one running.

## Output

### Goal
What the swarm was asked to do, in one or two sentences.

### Tracks
Each track: agent/provider, mode, what it owned, and its outcome (with commit/PR URL for edit tracks, or the key finding for read-only tracks). file:line evidence, no paraphrase.

### Synthesis
The combined result. Call out where tracks converged (high confidence) and where they diverged (the decision point), each side cited.

### Verification
Per track: the real flow you ran and its result (quoted output for tests / health checks). No human-time estimates — wall-clock minutes, edit counts, or token cost only.

### Follow-ups
What's deferred and why. Confirm the team was disbanded.
