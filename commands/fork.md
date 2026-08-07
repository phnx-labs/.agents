---
description: Fork this conversation into a new, independent session and open it where you work
---

Fork a session: $ARGUMENTS

Branch a conversation into a NEW, independent session and open it in a fresh terminal, so you can explore an alternative direction without touching the original. Where `/continue` resumes the *same* thread, `/fork` copies it under a new id — the "git branch" of conversations. Typically called as bare `/fork` (fork the CURRENT session) or `/fork <id>` (fork a specific one).

This is cheap: a fork is a file copy of the transcript so far, not a re-run — it costs no tokens, and the new session carries the full context natively.

## Step 0: Resolve which session to fork

- **Bare `/fork`** — fork THIS session. Its id is in the session-start context ("Your current session id is …"); use that. The current harness is the one you are running in.
- **`/fork <id>`** — fork that session (UUID or short prefix). Resolve its harness from `agents sessions preview <id> --json` if you need it; the lookup includes remote devices.

Never guess an id — if `$ARGUMENTS` is a topic/name rather than an id, run `agents sessions "<query>"` to resolve it first, or ask once.

## Step 1: Create the branch

Check whether the session's harness supports a native fork copy (Claude today):

- **Forkable →** `agents sessions fork <id>`. It prints `Forked <src> -> <new-short-id>`. Capture the new id — that is what you open next. (Add `--name "<label>"` to name the branch.)
- **Not forkable →** there is no native copy for that harness yet. Don't fake one. Branch by hand instead: open a fresh agent of the same harness (Step 2) and seed it with `/continue <original-id>` as its first message. The original stays put; the new session loads its context.

## Step 2: Open the fork where the user works

Open the new session in a real terminal tab, in the program the user actually works in (Ghostty / iTerm / tmux / VS Codium — auto-detected from their live sessions).

- **Local — the user is on THIS machine** (`$SSH_CONNECTION` is unset): 
  `agents run <agent> --resume <new-id> --terminal`
  `--terminal` (no value) detects the user's terminal from `agents sessions --active` and opens a tab there.

- **Remote — the user connected from another box** (`$SSH_CONNECTION` is set): run
  `agents sessions resume <new-id> --host <source-machine>` from the terminal where
  the user is working. Here `--host` scopes identity lookup to the machine that owns
  the fork; the CLI attaches a live pane or routes native resume there. Do not choose
  the harness, version, or tmux target in this command.

For the non-forkable branch, use the same open commands but with no `--resume`; type `/continue <original-id>` into the new session once it is ready.

## Step 3: Hand off

Tell the user which session you forked and where it opened (`Forked <src> -> <new-id>, opened in <program> on <machine>`). The fork is a separate conversation now — do not keep working in it from here; the user drives it in the new tab. The original session (this one) is untouched and continues normally.

## Anti-patterns

- Don't re-run or re-summarize the conversation to "seed" the fork — `agents sessions fork` copies the transcript natively; that's the whole point.
- Don't open the fork on the agent's own box when the user is connected from elsewhere — resolve `$SSH_CONNECTION` and open on THEIR machine.
- Don't pass `--host` to `agents run --terminal`; use the canonical `agents sessions resume <id> --host <source-machine>` lifecycle path.
- Don't silently succeed on a non-forkable harness — say a native copy isn't supported and take the `/continue` branch explicitly.
