---
name: fork
description: "Fork a session into a NEW, independent same-harness sibling — the 'git branch' of sessions. Resolved across the fleet and seeded with a recap of the source (label, cwd, ticket, last state, changed files), so it works for a session on ANY device in ANY harness and picks up where the original left off. Where continue resumes the SAME thread, fork launches a new one. Triggers on: /sessions:fork, /fork, 'fork this session', 'branch this conversation', 'copy this session into a new one', 'explore an alternative direction without touching this thread', 'fork <id>'."
argument-hint: "[empty = fork THIS session | <session-id> | topic to resolve first]"
---

Fork a session: $ARGUMENTS

Branch a conversation into a NEW, independent session so you can explore an alternative
direction without touching the original. Where `/continue` resumes the *same* thread,
`/sessions:fork` launches a new same-harness sibling — the "git branch" of conversations.
Typically called as bare `/sessions:fork` (fork the CURRENT session) or
`/sessions:fork <id>` (fork a specific one).

The fork is **not** a transcript copy: `agents sessions fork` resolves the source across
the fleet, builds a **recap** of it (label, cwd, ticket, last state, changed files, and
the source id), and launches a same-harness sibling seeded with that recap. That is what
makes it work for a session on **any device** and in **any REPL harness** — the sibling
is handed plain text, so it never has to reach a transcript that may live on another box.
It costs the recap's tokens, not a full re-run, and the sibling can pull full history with
`/continue <source-id>` if it needs more.

## Step 0: Resolve which session to fork

- **Bare `/sessions:fork`** — fork THIS session. Its id is in the session-start context
  ("Your current session id is …"); use that.
- **`/sessions:fork <id>`** — fork that session (UUID or short prefix). The lookup is
  cross-fleet, so a remote id resolves.

Never guess an id — if `$ARGUMENTS` is a topic/name rather than an id, run
`agents sessions "<query>"` to resolve it first, or ask once.

## Step 1: Fork it where the user works

One command launches the sibling — resolve, recap, and launch are all inside
`agents sessions fork`. Pick placement by where the user is:

- **Local — the user is on THIS machine** (`$SSH_CONNECTION` is unset):
  `agents sessions fork <id> --terminal`
  `--terminal` (no value) detects the user's terminal from `agents sessions --active`
  (Ghostty / iTerm / tmux / VS Codium) and opens the sibling in a fresh tab there. Add
  `--name "<label>"` to name the branch.

- **Remote — the user connected from another box** (`$SSH_CONNECTION` is set):
  `agents sessions fork <id> --device <user-machine>`
  places the sibling on the user's box (interactive over the ssh link they are on).
  `--terminal` is local-only, so do not combine it with `--device`.

Fork works for every harness now — there is no claude-only gate and nothing to fake for a
non-Claude source.

## Step 2: Hand off

`agents sessions fork` takes over that terminal/tab with the new session, so once it
launches the fork is a separate conversation the user drives there. Tell the user which
session you forked and where it opened. The original session (this one) is untouched and
continues normally — do not keep working in the fork from here.

## Anti-patterns

- Don't hand-summarize the conversation to "seed" the fork — `agents sessions fork`
  builds the recap itself from the source's preview digest; that's the whole point.
- Don't try to "capture a new id and then resume it" — fork launches the sibling
  directly, there is no separate id to open.
- Don't open the fork on the agent's own box when the user is connected from elsewhere —
  resolve `$SSH_CONNECTION` and use `--device <user-machine>`.
- Don't pass `--terminal` together with `--device` — `--terminal` opens a local tab; use
  one or the other.
