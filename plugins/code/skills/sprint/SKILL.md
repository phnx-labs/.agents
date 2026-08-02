---
name: sprint
description: "Time-boxed multi-track parallel coding push. Opus planner builds the track distribution, user confirms, `agents teams` fans out the implementation, every track verifies with a real flow. Not Agile — no standups, no points, just one focused window where N independent surfaces get shipped in parallel instead of serially. Triggers on: 'sprint', 'parallel push', 'I have N hours, let's ship X+Y+Z', 'close all the open loops on A and B', 'tonight we ship', 'spin up teams to do A, B, C'."
argument-hint: "[goal — e.g. 'rush ship feature X + close linear-cli loops + fix agents-cli bug, 5h']"
allowed-tools: Bash(agents *), Bash(gh *), Bash(linear *), Bash(git status*), Bash(git log*), Bash(git diff*), Bash(ls*), Bash(fd*), Bash(rg*), Read(*), Write(*), Edit(*)
user-invocable: true
---

# code:sprint

> One focused window. Multiple independent tracks. Implementations in parallel via `agents teams`, integration and verification at the end. The word "sprint" is borrowed for the **shape** (time-boxed, intense) not the **ceremony** (no standups, no points, no retros).

This is a workflow skill, not a code generator. You — the orchestrator — execute the five phases below. Heavy work delegates to sub-agents and `agents teams`.

---

## When to invoke

Use sprint when **all** of these hold:

- A defined window (typically 2–8 hours).
- 3 or more independent surfaces that can land in parallel (different repos, different layers, different products).
- At least one surface has a definable verification path (real flow, not "tests pass").

Do **not** use sprint for:

- Single-surface bugs → use `/debug` or just edit directly.
- Read-only audits → use `/audit` or spawn `Agent(subagent_type: "Plan")` directly.
- Exploration ("what should we even build?") → use `/plan` or `Agent(subagent_type: "Plan", mode: "edit"=false)`.

---

## The five phases

### Phase 1 — Recon (orchestrator, ~3–5 min)

Goal: gather the raw inputs the planner needs. Do **not** plan yet.

Collect, in parallel via tool calls in the same response:

1. **Active sessions** — `agents sessions --active` (so you don't spawn duplicates).
2. **Open loops** for each surface mentioned in the goal:
   - For each repo: `git status`, `git log -10 --oneline`, list of recently modified directories.
   - For tickets: invoke `/issues` skill or `linear ls --status "in-progress,todo" --assignee me`.
   - For drafts/PRs: `gh pr list --author @me --state open` per repo, plus uncommitted branches.
3. **Recent sessions** for context — `agents sessions --last 20` filtered by the surfaces.
4. **Hard constraints** — time-box, deploy windows, anything in scope from the user prompt.

Dump everything into a `RECON.md` scratch (you can keep it in-memory — do NOT write a file unless the user explicitly asks). The dump is the planner's input.

### Phase 2 — Plan (Opus sub-agent, ~5–8 min wall-clock)

Spawn **one** Opus planner sub-agent. The planner returns a track distribution. You do NOT plan yourself — your weights are smaller. Use the **Opus planner prompt template** below.

```
Agent(
  subagent_type: "Plan",
  model: "opus",
  description: "Sprint plan: <one-line goal>",
  prompt: <Opus planner prompt template, filled with recon dump>
)
```

The planner must return:

- **Tracks** — 3 to 7. Each has: name (kebab-case), one-line goal, owned files/dirs, files NOT to touch, agent (claude or codex), success criteria, verification command, dependencies (`--after`).
- **Critical path** — longest sequential chain, with wall-clock minute estimate.
- **Integration risk** — which tracks touch shared deps, who owns them canonically.
- **Verification matrix** — per-track real flow to prove "done."

If the planner returns fewer than 3 tracks, the goal is too narrow for sprint — drop back to single-agent dispatch.

### Phase 3 — Confirm (checkpoint, ~30s–2min)

Present the track distribution plan concisely. Proceed with spawning `agents teams` on the default path.

Only use `AskUserQuestion` if the plan materially diverges from the user's original goal or if the user explicitly asked to approve each sprint. If the user asks to edit the plan, re-run Phase 2 with the corrections folded in.

### Phase 4 — Fan out (orchestrator + `agents teams`, ~2 min to spawn)

```bash
agents teams create <sprint-name>           # name = kebab of goal
```

Then one `add` per track, using the **teammate brief template** below. Mix agents: `claude` for code-heavy refactors and prose, `codex` for tight typed-implementation tracks. Sequence with `--after` per the planner's DAG.

```bash
agents teams add <sprint-name> claude "<filled brief>" --name <track-name>
agents teams add <sprint-name> codex  "<filled brief>" --name <track-name> --after <dep>
# ...
agents teams start <sprint-name> --watch
```

`--mode edit` is the default (the skill is for shipping, not auditing). Use `--mode plan` only if a track is research-only.

### Phase 5 — Land (orchestrator, remainder of window)

While teams run:

1. **Poll status** every 5–10 min via `agents teams status <sprint-name> --since <last-poll-ts>`. Never use `Monitor` or `ScheduleWakeup` — use `sleep N && agents teams status ... && echo "..."` per the harness convention.
2. **Unblock** — if a teammate stalls, read its log (`agents teams logs <sprint-name> <track>`), diagnose, and either inject a hint via a follow-up agent or remove+re-add the track with a sharper brief.
3. **Integrate** — when a track finishes, immediately run its verification command. If it passes, mark the track done. If it fails, push the failure back to the same teammate as a follow-up (do NOT silently fix it yourself — the agent needs to learn the boundary).
4. **Verify end-to-end** — once all tracks land, run the global verification: for Rush app changes, `/rqa`; for CLIs, real `--help` + golden-path invocation; for marketing pages, the live URL.
5. **Recap** — one short message: tracks landed (with commit/PR URLs), tracks deferred (and why), verification proof for each.

---

## Opus planner prompt template

Use verbatim. Fill the `{{ }}` slots.

```
You are the planner for a `code:sprint` push.

GOAL: {{ one-line goal from user }}

TIME BOX: {{ N hours }} ({{ end time in user's TZ }})

RECON DUMP (raw inputs, do not summarize back):
---
{{ paste recon outputs: active sessions, git status per repo, open tickets, recent PRs, recent sessions }}
---

YOUR JOB: Return a track distribution suitable for `agents teams`. Each track must be IMPLEMENTABLE IN PARALLEL by a separate agent with zero coordination after kickoff.

REQUIREMENTS:
- 3 to 7 tracks. If you can't find 3, say so and stop — sprint isn't the right shape.
- Each track owns explicit files/dirs. No two tracks own the same file.
- Each track has ONE verification command that proves "done" — a real flow, not "tests pass."
- Identify shared dependencies (e.g. a common types file, a config). Assign ONE canonical owner; everyone else imports.
- Sequence with `--after` only when truly blocking; default to parallel.

OUTPUT FORMAT (markdown, in this exact order):

## Tracks

### track-name (agent: claude|codex)
- **Goal:** one line
- **Owns:** file globs
- **Must NOT touch:** file globs owned by other tracks
- **Verification:** the literal command to run
- **After:** comma-separated track names or "none"
- **Why this agent:** one line

(Repeat for each track.)

## Critical path

Longest sequential chain with per-step wall-clock minute estimates. Total wall-clock minutes.

## Integration risk

Shared deps and their canonical owners. Anything that could collide.

## Verification matrix

| Track | Verification command | Proof artifact |
|---|---|---|

CONSTRAINTS:
- Every claim about file paths must be one you saw in the recon dump. Do NOT invent paths.
- Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.
```

---

## Teammate brief template

Use verbatim per track. Fill the `{{ }}` slots from the planner's output.

```
## Mission
{{ one-line sprint goal — same for every teammate }}

## Full sprint scope (so you have the big picture)
{{ bulleted list of ALL track names + their one-line goals }}

## Your assignment
{{ track goal — one or two sentences }}

## Boundary contract
- **You own:** {{ file globs }}
- **You must NOT touch:** {{ file globs owned by other tracks }}
- **Shared deps:** {{ canonical owner }} owns {{ files }}. You import, you don't edit.

## Pattern
{{ concrete code/command sketch the teammate should follow — inline, not "see file X" }}

## Success criteria
- {{ specific behaviour 1 }}
- {{ specific behaviour 2 }}
- The verification command `{{ command }}` exits 0 and shows {{ expected }}.

## Working agreement
- Commit your work in small logical commits. Push to a branch named `sprint/{{ sprint-name }}/{{ track-name }}`.
- If you finish early, do NOT pick up other tracks — message back with "DONE: <commit URL>".
- If you're blocked, do NOT silently expand scope — log the blocker and stop.

Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.
```

---

## Scratch directories — `.agents/scratch/` in the repo, never `/tmp`

Sprint work that needs a scratch space — mirror clones for history rewrites, intermediate render outputs, audit dumps, spec files for a filter-repo run — lives at `<repo>/.agents/scratch/<sprint-name>/`, gitignored. **Do not use `/tmp`.**

Why:
- `/tmp` is volatile (cleared on reboot, OS may purge mid-run) — work disappears between sessions.
- Project-local artifacts are co-located with the project, easy for the user to find and grep.
- The repo's existing `.agents/` (per project-level DotAgents convention) already has the shape (`.agents/plans/`, `.agents/worktrees/` are gitignored) — `.agents/scratch/` is the same pattern.

Add to the repo's `.gitignore` once per repo:

```
.agents/scratch/
```

Layout per sprint:

```
<repo>/.agents/scratch/<sprint-name>/
├── mirror.git/         # cloned --mirror for any history rewrite
├── spec/               # filter-repo specs, expression tables, mailmaps, blob lists
└── *.log               # run logs
```

For sprint artifacts that span multiple repos (audit reports, render outputs, recap docs), use `~/sprint-artifacts/<sprint-name>/` — outside any repo, but persistent across reboots and findable by the user.

## Anti-patterns

| Don't | Do |
|---|---|
| Skip Phase 2 ("I know what to do, just spawn teams") | Run the Opus planner. It catches the file-collision and ordering bugs you miss. |
| Stop for a permission gate in Phase 3 | Present the plan as a checkpoint, then spawn. Only ask if the plan materially diverges from the user's goal. |
| Fan out without boundary contracts | Two teammates editing the same file is the #1 sprint killer. |
| Disband mid-sprint to "restart" | Diagnose the blocking track, fix or remove THAT track. Other tracks keep running. |
| Mark a track done because the agent said "done" | Run the verification command. Quote its output. |
| Roll into a fresh sprint without recap | The recap is the input to the next session. Skip it and the next session loses context. |
| Use `Monitor`/`ScheduleWakeup` to poll | Use `sleep N && check && echo "..."` per harness convention. |
| Spawn a cheap model for the planner | Opus only. The planner is the load-bearing piece. |

---

## Verification checklist (Phase 5)

Before claiming the sprint shipped, every checkbox is true:

- [ ] Every track has a commit URL or a "deferred + reason" line.
- [ ] Every track's verification command ran and is quoted in the recap.
- [ ] For deploy tracks: the live URL was curled (or `rush http`-ed) and the response is quoted.
- [ ] Linear/GitHub tickets touched are updated (status, comment with PR URL).
- [ ] Open loops list in the recap shows what's still open and the smallest next step for each.
- [ ] No background shells left running (`agents sessions --active` checked).

---

## CLI surface

| Command | Purpose |
|---|---|
| `/code:sprint <goal>` | Run the full five-phase workflow. |
| `/code:sprint --resume <name>` | Pick up a sprint in progress (skip Phase 1–3, jump to Phase 5). |
| `/code:sprint --plan-only <goal>` | Run Phases 1–3, stop before fan-out. Output the team-spawn commands as a script. |

The skill itself is the playbook — these are the orchestrator-level invocations.

---

## Sibling references

- `agents teams` — the parallel execution primitive. See `~/.agents/plugins/agents/skills/teams/SKILL.md`.
- `/teams` command — long-form playbook with team templates.
- `parallel-teams` doc in AGENTS.md / CLAUDE.md — the boundary-contract discipline.
