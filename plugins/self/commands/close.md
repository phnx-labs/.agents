---
description: Cleanly self-terminate THIS session — SIGTERM the harness, with an infra-parent guard. The low-level exit primitive; for a recap-then-exit use /done, for the ship gate use /finish.
---

Self-close the current session. Optional context: $ARGUMENTS

`/self:close` is the **exit primitive**: it ends *this* agent's own session by signalling
the harness process, nothing more. It does NOT recap, verify work, or clean up — if you want
those first, that is `/done` (recap → close) or `/finish` (drive to delivered, no exit).

There is no `/exit` tool. The only self-exit is signalling the harness directly: the Bash
tool's shell has the harness as its parent (`$PPID`), and `SIGTERM` is the clean path — the
harness flushes the transcript, saves session state, and runs post-session hooks on the way
out (unlike `SIGKILL`).

## Before you close

Emit any final line to the user **now** — once the harness dies, nothing else you say
reaches them. If `$ARGUMENTS` names a reason, state it in one short line first.

Do not `/self:close` mid-task to dodge work: if the session is unfinished, that is `/finish`,
not this. Use `/self:close` only when the work is genuinely wrapped (or you were asked to end
the session).

## Close — two steps, run as the LAST two tool calls of the turn

**Step 1 — guard (read-only).** Confirm the parent really is an agent harness, not
infrastructure, so you never tear down a shell / tmux / sshd:

```bash
ps -o comm= -p $PPID
```

If that prints a bare shell or infra process — `sshd`, `tmux`/`tmux: server`, `init`,
`systemd`, `login`, `bash`, `-bash`, `zsh`, `-zsh`, `sh`, `-sh`, `fish` — **stop**: report
that self-close was skipped because the parent (`<comm>`) is not a harness, and do not signal
anything. A real harness (`claude`, `codex`, `gemini`, `node`, `bun`, `droid`, `grok`, …) is
anything else.

**Step 2 — signal the harness.** Only if the guard passed, run **exactly** this (this exact
form is what the `self` permission group allowlists, so it runs without a prompt in auto mode):

```bash
kill -TERM $PPID
```

Do not write any text after Step 2 — it is the last action of the session. If you can still
read after it, the harness ignored the signal; report that and stop (do NOT escalate to
`SIGKILL` or walk up to another pid).
