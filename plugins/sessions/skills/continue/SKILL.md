---
name: continue
description: "Resume previous agent work in this session — load a prior transcript (or a group of them), verify what actually landed, and finish the remaining work here. Reattach only when the session is genuinely still live and interactive. Also covers post-crash multi-session recovery (prefer finishing headlessly over resurrecting terminals). Triggers on: /continue, 'pick up where I left off', 'resume that session', 'continue the auth work', crash recovery that finishes work rather than reopening windows."
argument-hint: "[session-id | topic | empty] [--device <machine>] [recover]"
allowed-tools: Bash(agents sessions*), Bash(agents *), Bash(git *), Bash(gh *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Bash(sysctl *), Bash(uptime *), Read(*), Write(*), Edit(*), Task(*), AskUserQuestion(*)
user-invocable: true
---

# sessions:continue

Pick up where a previous session left off and **finish the work in this window**.

Typically invoked as `/continue <session-id>` (UUID or short prefix) — the form the
`agents sessions` picker emits when resuming across versions. Arguments may also be a
name, a topic, several ids, empty, or a recover-style crash sweep. A generated
cross-device handoff may append `--device <machine>`.

**Not** `sessions:restore` (that re-opens *other* sessions as Ghostty windows). This skill
keeps you in the current harness and drives the unfinished work to done.

## Modes

| Mode | When | What you do |
|---|---|---|
| **Single** (default) | One id, topic, or bare `/continue` | Load that session → verify state → continue here |
| **Group** | Several ids, a shared topic, or a team name | Load each (cheaply, in parallel), finish agent-doable work, hand off only what needs a human |
| **Recover** | Crash / reboot / pile of mid-task sessions, or the `recover` keyword | Find interrupted sessions, finish headlessly, one easy action for the rest |

`$ARGUMENTS` may contain the word `recover` (e.g. `/continue recover`) — treat that as recover
mode. Multiple bare ids or a clear multi-session ask → group mode.

## Parse an optional source machine

Before interpreting the selector, extract at most one trailing `--device <machine>`
pair from `$ARGUMENTS`. Remove that pair from the selector and retain
the machine as the transcript source. Reject a missing machine value, multiple source
flags, or extra text after the pair rather than guessing.

The source machine is a **read locator only**. It does not become this session's ID, host,
or execution target. If no source machine was supplied, use the normal fleet-aware
behavior below.

---

## Single mode (default)

### Step 0: Default to resuming in place — reattach only on a genuine live signal

**The common case is to resume in this window, not to reattach.** Most `/continue` calls
pick up a session that was *interrupted* — rate-limited, crashed, hit a context/usage
limit, or ran headless/background. That is **not** a live pane to return to. Do **not**
probe it with `focus`. Skip straight to Step 1: read its transcript, verify the state, and
continue the work **right here**.

Attempt reattach **only** when you have positive reason to believe the session is **still
running in an interactive terminal the user wants to jump back to** — e.g. the user says
it's still open, or you can see it live in a tmux pane / terminal tab (locally or on a
remote device). Reattaching then avoids spawning a redundant copy that abandons the
original. With no such signal, do not guess — go to Step 1. (If they ran `/continue` here,
they want the work continued here.)

1. **Resolve the session id (if one was given).**
   - Id (UUID or short prefix) → use it directly.
   - Topic / name / keyword → `agents sessions "<query>"` (add `--device <machine>` when a
     source machine was supplied). Multiple candidates → most recent, or ask once.
   - Nothing + live-session signal → attach picker in step 2.
   - Nothing + no signal → Step 1: load the most recent prior session and resume here
     (never open a focus picker on bare `/continue` with no live signal).

2. **Try to attach** (only after the live-signal check).
   - With id: `agents sessions focus <id> --attach-only` (append `--device <machine>` when
     the caller supplied a source machine).
   - No id but live signal: `agents sessions focus --attach-only` (picker; cancel → Step 1).
   - `--attach-only` means "join the live pane/tab or fail"; it never silently opens a new
     copy.
   - Preserve an explicit `--device` scope when the caller supplied one.

3. **Interpret the result.**
   - **Exit 0:** reattached. Tell the user which session, then **cleanly hand off** — do
     not keep chatting in this harness.
   - **Non-zero:** not attachable → transcript path below.

4. **Ambiguity.** If focus reports multiple canonical sessions, inspect with
   `agents sessions` or pass more of the UUID/tmux alias. Never choose an ambiguous alias
   suffix automatically.

### Step 1: Load the prior session

Default path whenever you did not reattach.

| Input | Command |
|------|---------|
| Session ID (UUID or displayed 8-character prefix) | `agents sessions preview <id>` |
| Session ID plus source machine | `agents sessions preview <id> --device <machine>` |
| Only a topic / name / keyword | `agents sessions "<query>"` → pick id → `agents sessions preview <id>` (+ `--device` when supplied) |
| Nothing | Most recent prior session from `agents sessions`; interactive picker only if you truly need one and have a TTY |

Default render is a concise summary (header, original prompt, tool groupings, final
response). Escalate to `agents sessions <id> --markdown` only when the preview leaves a
real gap. Narrow with `--include user,assistant` or `--last 5` if needed.

### Step 2: Assess current state

The transcript shows intent. Verify what landed.

- `git status`, `git log --oneline -20`, `git diff`
- Read the files the session touched
- TODOs, FIXMEs, half-edited functions, failing tests
- Tracker state via the `tickets` skill or the relevant tracker skill when an issue was referenced

Quote file:line evidence — do not paraphrase from memory.

### Step 3: Present and align

One short block:

- **Done:** what landed (paths)
- **Remaining:** unfinished or broken (specifics)
- **Drift:** what changed since the session ended
- **Next:** concrete next step

`AskUserQuestion` only if the next step is genuinely ambiguous. If obvious, state it and
start.

### Step 4: Continue working

Pick up exactly where things left off. Do not redo completed work. ACT → VERIFY → SHOW →
CONTINUE.

If the resumed work is already done, do not idle — run `/next` for the next related task
without re-deriving project context.

---

## Group mode

When `$ARGUMENTS` lists several sessions (ids, a shared topic, a team) and the intent is
**finish the work**, not reopen windows:

1. Resolve each id via `agents sessions` (parallel read-only subagents are fine for the
   *read* step).
2. Classify each: still live → reattach only on a genuine live signal; interrupted →
   continue here or headlessly; already done → skip.
3. Prefer finishing agent-doable work in this session (or with `agents teams` /
   `agents run`) over spawning a terminal per thread.
4. One recap table: id · topic · status · action taken · what still needs the user.

---

## Recover mode (`/continue recover`)

A crash, reboot, or pile of mid-task sessions left work in limbo. Finish what an agent can
finish; hand back only what truly needs the user. **Not** `sessions:restore` (windows).

Mindset (mechanics are yours):

- **Canonical lifecycle first.** `agents sessions resume <id-or-tmux-alias>` resolves
  owner, rechecks liveness, attaches an alive pane, then falls through to native resume.
  Use `focus --attach-only` only when recovery must refuse to start a continuation.
- **Don't resume what's already done.** Interrupted-mid-task only. `agents sessions` sees
  every version home; raw transcripts are append-only.
- **Read cheaply, in parallel.** Read-only subagents to understand sessions — do not
  relaunch them just to find out what they were doing.
- **Prefer finishing over resurrecting.** Reopening a swarm of interactive terminals is
  often what caused the crash. Drive mechanical work headlessly (you, subagents, or
  `agents teams`). Only human-in-the-loop threads come back live.
- **Do the legwork.** Resolve open questions yourself (did that PR merge?). When you must
  ask, ask specific framed questions — never "approve the plan?".
- **Hold irreversible / outward actions.** Push, merge, publish, deploy, secret export
  mid-flight need an explicit yes.
- **One easy handoff.** Clipboard a version-pinned resume command, or point at the resume
  picker — fewest keystrokes. Honor anything the user wants kept manual.

If the user wanted **windows back**, hand off to `sessions:restore` instead of finishing
here.

---

## Anti-patterns

- Do not ask "what were you working on?" — load the transcript first
- Do not dump raw transcript at the user — synthesize it
- Do not start coding before verifying prior work is still intact
- Do not `focus`/attach a rate-limited, crashed, or limit-hit session — read and continue here
- Do not spawn a new copy when the session is still live in tmux/Ghostty — reattach instead
- Do not drop a supplied `--device` locator then claim the remote transcript is missing
- Do not hand-traverse `~/.agents/versions/.../projects/` — use `agents sessions`
- Do not reopen a swarm of Ghostty windows under this skill — that is `sessions:restore`
