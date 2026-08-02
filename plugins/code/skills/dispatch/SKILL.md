---
name: dispatch
description: "Single-task router. Given a free-form task or RUSH-XXX ticket, scope it, pick a bucket (inline / single-agent / autodev / code:sprint) and venue (local laptop or Rush Cloud via `rush cloud run`), set up the workspace, brief the agent. Defaults to Rush Cloud for clear / well-scoped tasks (~80% of dispatches) and stays local for fuzzy / interactive work. The manager's entry point — call this when a new task arrives instead of guessing. Triggers on: 'dispatch this', 'delegate', 'kick off', 'spin up an agent for', 'route this', 'send this to the cloud'."
argument-hint: "[task description or RUSH-XXX]"
allowed-tools: Bash(agents *), Bash(rush cloud*), Bash(rush http*), Bash(gh *), Bash(linear *), Bash(git status*), Bash(git log*), Bash(git diff*), Bash(git worktree*), Bash(git fetch*), Bash(git push origin main:*), Bash(git rev-parse*), Bash(ls*), Bash(fd*), Bash(rg*), Read(*), Write(*), Edit(*)
user-invocable: true
---

# code:dispatch

> You (the manager in the user's chat) get a new task. This skill is the decision tree that picks the right delivery path and sets it up. It does NOT implement the task — implementation goes to the chosen dispatch target.

## When to invoke

The user hands you a task. Anything from a Linear ticket (`RUSH-123`) to a vague one-liner ("the login button is broken"). Run this skill first instead of jumping to `agents run` or editing yourself.

## The five steps

### Step 1 — Recover the contract

What is the task, in one sentence? If `$ARGUMENTS` matches `RUSH-\d+`, fetch the ticket body — invoke the `/issues` skill or run `linear issue <id>`. Quote the acceptance criterion verbatim. If the ask is ambiguous, ask **one** `AskUserQuestion` with concrete options. Do not guess scope.

### Step 2 — Triage scope

Read enough of the repo to classify. Run in parallel:

- `git status` — is the tree clean?
- `git log -5 --oneline` — recent work on this area?
- `rg -l <relevant-keyword>` — how many files are involved?
- If a ticket: read the description, any linked PRs.

Pick a **bucket** (scope) and a **venue** (where it runs):

**Bucket — what shape the work is:**

| Bucket | Signal |
|---|---|
| **Inline** | 1-2 file edits, < 15 min wall-clock, no ambiguity. Do it yourself; skip the rest of this skill. |
| **Single-agent** | One surface, one agent, clean scope. |
| **Autodev** | Clean RUSH-XXX with clear acceptance criterion — runs the autodev workflow (plan → implement → test → review → PR). |
| **Sprint** | 3+ independent surfaces, multi-hour window. Hand off to `code:sprint`. |

**Venue — local laptop or Rush Cloud:**

| Venue | Signal | Backend |
|---|---|---|
| **Local** | Fuzzy scope, interactive, you want to watch, ambiguity remains, or rapid iteration is critical. The user is watching too. | User's laptop, foreground or background |
| **Rush Cloud** | Clear scope, low ambiguity, single coherent ask, you can walk away. Default for ~80% of "very clear, well-scoped" tasks per the user's preference — less interactive, more efficient. | Phoenix K8s via `rush cloud run` — the native first-party CLI. (Do not use `agents cloud run --provider rush`; that's the multi-provider abstraction. Native `rush cloud` is the right interface for this codebase.) |

**Heuristic:** if the brief fits in three sentences and the agent shouldn't need to ask anything, dispatch to Rush Cloud. If the agent will likely need a "wait, which thing did you mean?" mid-flight, stay local.

**Constraints:**
- Inline is always venue-irrelevant (you do it).
- Sprint is **local only** for now — the `agents teams` orchestration runs on the laptop. Future: add `--cloud rush` per teammate.
- Autodev and Single-agent support both venues. Autodev on Rush Cloud uses `rush cloud run --workflow autodev`; the cloud pod runs the planner/implementer/tester/reviewer subagents natively.
- Rush Cloud requires the GitHub repo (`muqsitnawaz/agents` positional or `--repo`) and dispatches into a fresh branch on the remote — no local worktree needed. The cloud pod opens a PR per repo on completion.
- Rush Cloud modes are `plan, exec` (NOT `edit`). `agents run` modes are `plan, edit, full, skip`. Use the right vocabulary for the venue.

If you cannot place the task in a bucket, run Step 1 again — the contract was unclear.

### Step 3 — Present the dispatch plan

Build a one-paragraph plan:

```
Task: <one sentence>
Bucket: <inline | single-agent | autodev | sprint>
Venue: <local | rush-cloud>
Agent: <claude | codex | droid> (or N/A for inline)
Mode: <plan | edit | full>
Worktree: <repo>/.agents/worktrees/<slug>/  (local only — cloud uses remote branch)
Branch: <slug>  (cloud only — local infers from worktree)
Verifier: <who runs /verify after — me / autodev / sprint>
Ticket: <RUSH-XXX or "ad-hoc">
```

For inline-bucket tasks, skip the plan presentation and just do the work.

For other buckets, present the plan concisely, then proceed on the default path. Only use `AskUserQuestion` if the scope is genuinely ambiguous or the user explicitly asked to approve each dispatch. Do not include a "stop" option — the user can always interrupt.

### Step 4 — Set up the workspace

**Local venue** — worktrees live in `<repo>/.agents/worktrees/<slug>/` (F5: protect what you can't undo):

```bash
REPO=$(git rev-parse --show-toplevel)
SLUG=<short-kebab-from-task>
WT=$REPO/.agents/worktrees/$SLUG

git -C $REPO fetch origin
git -C $REPO remote set-head origin --auto
BASE=$(git -C $REPO symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
git -C $REPO worktree add -b $SLUG $WT origin/$BASE
```

**Rush Cloud venue** — no local worktree. The cloud pod clones the repo at HEAD and creates the branch on push:

```bash
SLUG=<short-kebab-from-task>
# Optional: pre-create the branch if you want to track it locally before dispatch
# git -C $REPO fetch origin main
# git -C $REPO push origin main:refs/heads/$SLUG  # remote branch pointing at main
```

Skip Step 4 entirely for inline tasks.

### Step 5 — Brief the agent

Every dispatch prompt MUST include:

1. **Mission** — one sentence: what the agent is shipping.
2. **Full scope** — files that change, files that don't, the why.
3. **Boundary contract** — for multi-agent dispatch only: "Owns: X. Must NOT touch: Y."
4. **Success criteria** — what proves it works (end-to-end, not "tests pass").
5. **Verification command** — the exact command you'll run to gate it.
6. **Evidence line (mandatory):** `Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.`

**Local single-agent:**
```bash
agents run claude --mode edit --cwd $WT "<brief>"
```

**Rush Cloud single-agent:**
```bash
rush cloud run claude muqsitnawaz/agents \
  --prompt "<brief>" \
  --mode exec
```
Positional args are `<AGENT> <OWNER/REPO>`. Add `--agents-repo muqsitnawaz/.agents` if the brief depends on a plugin/skill defined in the agents config repo (e.g. `code:verify`). For multi-repo dispatches, repeat `--repo owner/name`.

**Local autodev:**
```bash
agents run autodev --mode edit RUSH-XXX
```
Autodev handles its own briefing via the planner subagent — pass the bare ticket ID as the prompt.

**Rush Cloud autodev — DOES NOT WORK TODAY:**
```bash
# This fails in the cloud pod:
rush cloud run --workflow autodev muqsitnawaz/agents --prompt "RUSH-XXX" --mode exec
# → "Unknown agent: autodev. Available agents: claude, codex, gemini, ..."
```

The cloud pod's `agents-cli` (currently 1.16.0; latest is 1.20.0) does NOT discover project-local workflows from `.agents/workflows/`. The `--workflow autodev` flag translates inside the pod to `agents run --mode exec autodev "..."` which fails because the pod has never registered the workflow. Until cloud pods are upgraded to a workflow-aware agents-cli version that auto-discovers `.agents/workflows/`, autodev-on-cloud is broken.

**Workaround: use single-agent dispatch with the ticket body inlined.** The single cloud agent does the same plan→implement→test→review work in one process; you lose the four-subagent structure but gain a working dispatch.

```bash
rush cloud run claude muqsitnawaz/agents \
  --prompt "$(cat <<'EOF'
RUSH-XXX

<paste the Linear ticket body verbatim — title, description, acceptance criteria,
 affected files / vendors, scope rules ("MODIFY:" and "DO NOT touch:"), any comments
 that constrain scope. Always include the evidence-quote rule at the bottom.>
EOF
)" \
  --mode exec
```

**Two hard cloud gotchas (both lessons from the RUSH-983 dispatch on 2026-06-05):**

1. **No Linear creds in the pod.** Autodev's preflight `linear tasks` call fails. Inline the ticket body — never rely on the ticket ID alone.
2. **No project-local workflow registration.** `--workflow <name>` from `.agents/workflows/` is unknown in the pod. Use direct `claude` agent dispatch with an inline brief instead.

**Local autodev still works** — `agents run autodev --mode edit RUSH-XXX` on the laptop is fine because your local agents-cli has the workflow registered and your Keychain has the Linear key.

**Sprint:** invoke `code:sprint` skill directly — it has its own briefing template. Sprint is local-only.

For Rush Cloud dispatches, capture the returned execution ID. Reconnect from anywhere with:
- `rush cloud list` — all executions
- `rush cloud logs <id>` — live stream
- `rush cloud status <id>` — single execution detail
- `rush cloud message <id> "<follow-up>"` — steer in-flight or send follow-up to a needs-review run
- `rush cloud transcript <id>` — captured transcript

### Step 6 — Hand back to the user

Report in the chat:

**For local dispatches:**
- Worktree path
- Agent CLI + session id (if available — `agents sessions --active` lists it; `agents sessions focus <id> --attach-only` reattaches to a live session)
- Expected wall-clock minutes for the longest path
- The exact `/verify` invocation to run when the agent reports done

**For Rush Cloud dispatches:**
- Execution ID (from `rush cloud run` output)
- Repo (`muqsitnawaz/agents`)
- Reconnect command: `rush cloud logs <id>` (live) or `rush cloud status <id>` (single check)
- The exact `/verify` invocation to run when the cloud execution completes (PR URL appears in `rush cloud status`)

Then keep the conversation open. Do NOT propose to stop. Polling:
- Local: `agents teams status` or `agents sessions --active`; reattach to a live session with `agents sessions focus <id> --attach-only`
- Cloud: `rush cloud list` (all executions) or `rush cloud status <id>` (one)

Surface blockers to the user — don't wait silently.

## Don'ts

- Don't bypass the worktree for local dispatches. Every local PR-bound task lives in `.agents/worktrees/` (F5).
- Don't ship the brief without the evidence line — agents lie about what they read otherwise.
- Don't pick "sprint" for fewer than 3 tracks. Sprint coordination overhead eats its own gains below that.
- Don't combine "autodev" with a multi-surface task. Autodev assumes one ticket = one PR scope.
- Don't claim done from this skill. Done is a `/verify` decision.
- Don't default to local for a clear, well-scoped task. The user prefers Rush Cloud for ~80% of those — less interactive, more efficient.
- Don't dispatch to mac-mini. It's the user's personal box, not a `/dispatch` target. (Linear-label-driven async work goes through `/rdev`, which is a separate flow.)
- Don't use `agents cloud run --provider rush` — use `rush cloud run` (the native first-party CLI). `agents cloud` is the multi-provider abstraction; we only target Rush Cloud, so the native is cleaner.
- Don't use `--mode edit` with `rush cloud run` — Rush Cloud takes `plan, exec`. `edit` is `agents run` vocabulary.
- `rush cloud run --computer <name>` exists but it targets a *registered local computer* (e.g. your mac-mini if registered), NOT a Factory/Droid computer-use target. If the user has a computer registered and the task needs local-only resources, that's a legitimate path. Default Rush Cloud (no `--computer`) is the K8s pod.
