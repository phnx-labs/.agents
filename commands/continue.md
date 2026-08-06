---
description: Resume a previous task — reattach if it's still live, otherwise load context and continue
---

Resume previous work: $ARGUMENTS

You are picking up where a previous session left off. Typically called as `/continue <session-id>` (UUID or short prefix) — the invocation you see when resuming from the `agents sessions` picker across versions. The argument may also be a name, a topic, or empty. A generated cross-device handoff may append `--device <machine>` or its alias `--host <machine>`.

## Parse an optional source machine

Before interpreting the selector, extract at most one trailing `--device <machine>`
or `--host <machine>` pair from `$ARGUMENTS`. Remove that pair from the selector
and retain the machine as the transcript source. Reject a missing machine value,
multiple source flags, or extra text after the pair rather than guessing.

The source machine is a read locator only. It does not become this session's ID,
host, or execution target. If no source machine was supplied, use the normal
fleet-aware behavior below.

## Step 0: Reattach if the session is still live

The session you are resuming may already be running inside a tmux pane or terminal tab (locally or on a remote device such as `zion -> yosemite-*`). If it is, jump to the live surface instead of spawning a redundant copy that abandons the original.

1. **Resolve the session id (if one was given).**
   - If the user passed an id (UUID or short prefix), use it directly.
   - If they passed a topic/name/keyword, run `agents sessions "<query>"` to read the index and extract the id. When a source machine was supplied, add `--host <machine>` to that lookup. If the query returns multiple candidates, pick the most recent matching one or ask once.
   - If they passed nothing, skip to the attach picker in step 2.

2. **Try to attach.**
   - If you have an id: `agents sessions focus <id> --attach-only`. When the
     caller supplied a source machine, append `--host <machine>` so a short id
     or tmux alias is resolved only on its owning device.
   - If you have no id (the user typed bare `/continue`): `agents sessions focus --attach-only`. This opens the live-session picker; if the user cancels or no live session is chosen, fall through to Step 1.
   - `--attach-only` means "join the live pane/tab or fail"; it never silently opens a new copy.
   - Without a source-machine constraint, the command performs the cross-host
     sweep automatically. Preserve an explicit `--device` / `--host` scope when
     the caller supplied one.

3. **Interpret the result.**
   - **Exit code 0:** you are now attached to the live session. Tell the user which session you reattached to, then **cleanly hand off** — do not continue chatting in this harness. The user is interacting with the resumed session.
   - **Exit code non-zero:** the session is not attachable (dead, headless, plain terminal, ambiguous id, no tmux/Ghostty rail, or no TTY). Proceed to the transcript-recovery flow below.

4. **Resolve ambiguity.** If focus reports multiple canonical sessions, run
   `agents sessions` to inspect them or pass more of the UUID/tmux alias. Never
   choose an ambiguous alias suffix automatically.

## Step 1: Load the prior session

Use this only when Step 0 could not attach (session is not live in a reachable terminal).

Pick the loader based on what the user passed.

| Input | Command |
|------|---------|
| Session ID (UUID or short prefix) | `agents sessions <id>` |
| Session ID plus source machine | `agents sessions <id> --host <machine>` |
| Only a topic / name / keyword | `agents sessions "<query>"` to pick an ID, then `agents sessions <id>`; add `--host <machine>` to both commands when supplied |
| Nothing | `agents sessions` (interactive picker) — abort if no TTY and ask the user |

The default render is a concise summary: header, original prompt, tool-call groupings, final response. That's enough 90% of the time. Only escalate to `agents sessions <id> --markdown` if the summary leaves a real gap (e.g. you need a specific mid-session message). Narrow with `--include user,assistant` or `--last 5` if the full conversation is too long.

## Step 2: Assess current state

The transcript shows what the previous session *intended*. Verify what actually landed.

- `git status`, `git log --oneline -20`, `git diff` — what's committed, what's in flight
- Read the files the session touched and confirm the changes are still there
- Check for TODOs, FIXMEs, half-edited functions, failing tests
- If the session referenced an issue (Linear / GitHub / Jira / etc.), check its current state via `/tickets` or the relevant tracker skill

Quote file:line evidence when summarizing — don't paraphrase from memory.

## Step 3: Present and align

One short block:

- **Done:** what landed (with file paths)
- **Remaining:** what's unfinished or broken (with specifics)
- **Drift:** anything that changed since the session ended
- **Next:** concrete next step

Use `AskUserQuestion` only if the next step is genuinely ambiguous. If the path is obvious, just state it and start.

## Step 4: Continue working

Pick up exactly where things left off. Don't redo completed work. Follow ACT -> VERIFY -> SHOW -> CONTINUE.

## Anti-patterns

- Do not ask "what were you working on?" — load the transcript first
- Do not dump raw transcript output at the user — synthesize it
- Do not start coding before verifying the prior work is still intact
- Do not spawn a new resumed copy when the session is still live in tmux/Ghostty — reattach instead
- Do not drop a supplied `--device` / `--host` locator and then report that its remote transcript is missing
- Use the `agents sessions` CLI to load context — don't hand-traverse `~/.agents/versions/.../projects/`
