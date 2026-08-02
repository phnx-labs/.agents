---
description: Recover interrupted sessions after a crash — find them, understand each, finish the agent-doable work, and make any handoff one easy action
---

Recover and triage interrupted work: $ARGUMENTS

A crash, reboot, or a pile of mid-task sessions has left work in limbo. Pick it back up — and make it genuinely easy for the user, not a list of homework.

The shape of the job: find the sessions that were actually interrupted, understand what each still needs, finish what an agent can finish, and hand back only what truly needs the user. Carry the right mindset; the mechanics are yours to work out.

- **Reattach to live sessions first.** A session may still be running inside a tmux pane or terminal tab locally or on a remote device. For each interrupted session, try `agents sessions focus <id> --attach-only` before doing anything else. On exit 0, hand off to the live session. Only on failure proceed to headless recovery.

- **Don't resume what's already done.** Plenty of sessions finished their last turn and have nothing left. Read enough to tell interrupted-mid-task from idle, and act only on the former. `agents sessions` finds and reads them across every version home (a plain `claude --resume` sees only one); the raw transcripts are append-only, so a crash doesn't corrupt them.

- **Read cheaply, in parallel.** Use read-only subagents to understand the sessions — don't relaunch them just to find out what they were doing.

- **Prefer finishing over resurrecting.** Reopening a swarm of interactive terminals is what tends to cause the crash in the first place. Most recoverable work is mechanical and can be driven to done headlessly — by you, by subagents, or fanned out with `agents teams`. Only threads that genuinely need a human in the loop should come back as a live session.

- **Do the legwork so the user barely has to decide.** Resolve everything you can resolve yourself — if a session's only open question is "did that PR merge?", go check and fold the answer in instead of asking. When you do need the user, ask specific, well-framed questions (this one has a merge conflict — rebase or drop?), never a blanket "approve the plan?". Effort on your side, a tap on theirs.

- **Hold irreversible and outward actions.** A push, merge, publish, deploy, or secret export a session was mid-way through needs an explicit yes — never auto-run it.

- **Make any handoff one easy action.** You generally can't spawn new interactive terminals yourself, so for the few sessions that must come back live, don't dump a list of commands to paste one by one. Put a ready-to-run, version-pinned resume command on the clipboard, or point at the resume picker if the user has one — whatever costs them the fewest keystrokes. Honor anything they ask to keep manual.
