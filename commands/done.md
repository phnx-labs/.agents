---
description: Recap the session, then cleanly self-exit (SIGTERM the harness). For the ship gate (test/docs/PR/release) use /finish instead.
---

You are wrapping up this session. Context: $ARGUMENTS

`/done` means: **produce a recap, emit it as your message, then terminate this session yourself.**
It is the agent-side equivalent of the user typing `/exit` — but with a handoff recap first.

> **`/done` vs `/finish`** — `/done` *recaps and leaves*: it assumes the work is already delivered
> and you just want a clean handoff before the session ends. If the work is **not** actually finished
> — you're stalled at a blocker, a partial handoff, or untested code — use **`/finish`**, which drives
> the task to delivered (verify E2E, docs, commit, PR, optional release, close tickets) and does NOT
> exit. For draining a *queue* of tickets all the way to merged, that's `/code:loop`.

There is no `/exit` tool exposed to you — the only self-exit available is signalling the harness
process directly. That is deliberate and is the last step below.

## Step 0: Confirm the work is actually wrapped

`/done` assumes the work is delivered — before you recap and leave, make that true (this is also what the `verify-work-complete` Stop gate requires before a self-exit):

- **File follow-ups.** Out-of-scope ideas or issues you noticed → file them as tracked tickets now, with real context — not a one-line stub. Don't dangle them ("say the word"); do it, file it, or drop it.
- **Clean loose ends.** Commit and push any stray uncommitted work, remove worktrees and branches this session no longer needs, and confirm every ticket this session finished is closed with proof.

If any goal is untested or unfinished, this is a `/finish`, not a `/done` — go deliver it first.

## Step 1: Build the recap

Summarize the current state of work for handoff. Facts before hypotheses; ground every claim.

- **Situation** — what was the goal, and where did it end up? One short paragraph.
- **Completed** — concrete work done, with `file:line` / commit / PR / command-output evidence.
- **In progress** — anything started but not finished (be honest).
- **Blocked / open questions** — what genuinely needs the user (credentials, judgment, a click).
- **Next** — the single most useful next action.

Apply the `/recap` discipline:
- **Check before you list.** Anything you could verify or run yourself right now — do it, fold the
  answer in, don't list it as a "next step."
- **No wastebasket bullets.** Don't punt trivial loose ends or micro-decisions into "Next." Finish
  them, or turn a real fork into a crisp recommendation.
- Only keep items in **Next** that truly need the user's input, credentials, judgment, or a click
  you can't make.

Emit the recap as your assistant message **now** — it must be printed BEFORE the exit, because once
the harness dies nothing else you say will reach the user. The recap is the last thing they'll see.

## Step 2: Self-exit

After the recap is written, terminate the session as your final action. The Bash tool shell's parent
(`$PPID`) is the agent harness; sending it `SIGTERM` is the clean shutdown path — the harness flushes
the transcript, saves session state, and runs post-session hooks on its way out (unlike `SIGKILL`).

Run this as the LAST tool call of the turn (do not write any text after it):

```bash
HP=$PPID
HC=$(ps -o comm= -p "$HP" 2>/dev/null | tr -d ' ')
echo "self-exit: harness PID=$HP comm=$HC at $(date '+%H:%M:%S')"
case "$HC" in
  sshd|tmux*|init|systemd|login|bash|-bash|zsh|-zsh)
    echo "refusing self-exit: parent ($HC) is not an agent harness — aborting so we don't kill infra" ;;
  *)
    kill -TERM "$HP"
    echo "SIGTERM sent to $HP — if you can still read this, the harness ignored it" ;;
esac
```

The guard rejects obvious infrastructure parents (a bare shell, tmux, sshd, init/systemd) so `/done`
never tears down the wrong process; a real harness (`claude`, `codex`, `gemini`, `node`, etc.) is
anything else and gets the signal. If the guard refuses, report that the self-exit was skipped and
why — do not escalate to `SIGKILL` or walk further up the tree.
