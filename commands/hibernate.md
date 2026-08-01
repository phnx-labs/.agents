---
description: Hibernate until a future time, then wake THIS same session (full context, no transfer) to check on a long-running wait — approval, deploy, review, anything that takes hours to days.
---

You are putting the current session into hibernation. Argument: $ARGUMENTS

Use this when you are blocked on something slow and external — an approval that takes 1-7 business days, a deploy soaking, a review you can't hurry, a build on another machine — and there is genuinely nothing to do until it resolves. Instead of idling or handing the wait back to the user, you schedule your own wake-up, end the turn, and let the process exit. At the wake time a scheduled job resumes **this exact session** with your full context intact (no summary, no re-briefing) and drops you back in to check on it.

> **Why a launchd one-shot, not a routine.** The wake must resume the *actual* session so it reopens with full context. A `routines`-fired job spawns a *fresh* headless agent, and a fresh agent handed "run this command" for a session it has no memory of correctly refuses it as prompt injection — so the routine path cannot wake a hibernated session today. A launchd one-shot runs `agents run claude --resume` directly (no relay agent) — which resumes the *actual* session natively under the smart permission classifier (`--mode auto`, **never** `--dangerously-skip-permissions`) — and even catches up if the laptop was asleep at the wake time. (When `agents routines` gains native `--resume`, this switches to a one-line routine; until then, launchd.)

> **Prerequisite.** macOS, and `agents run claude` must be able to launch non-interactively — it drives the wake and manages claude auth itself. Concrete probe: `agents secrets exec claude.ai -- printenv CLAUDE_CODE_OAUTH_TOKEN` prints a token (same underlying auth `agents run` uses). For a logged-in Rush user it does. If it prompts or is empty, the wake can't authenticate — fix that first.

> **`/hibernate` vs `/done` vs `/finish`** — `/done` self-exits because the work is *delivered*. `/finish` refuses to stop and drives to delivery. `/hibernate` is for work that is *neither done nor blocked-forever*: it's waiting on wall-clock time. You come back and finish it yourself later — the user doesn't have to remember to ping you.

## Step 0 - Parse the argument

`$ARGUMENTS` is `<when> [reason]`:

- **`<when>`** — how long to hibernate. Accept human forms and convert to an absolute local wall-clock time:
  - relative: `8h`, `30h`, `5d`, `5 days`, `2 weeks`, `45m`
  - named: `next week`, `next Thursday 9am`, `tomorrow morning`
  - absolute: `2026-07-20 09:00`
- **`[reason]`** — free text: what you are waiting for. If omitted, infer it from the conversation (what blocked you). You MUST have a concrete reason — "check on X" where X is specific.

Compute the wake time and break it into calendar fields (launchd needs month/day/hour/minute):

```bash
WHEN='+30H'                                  # translate <when> to a `date -v` offset, or use an absolute date
read -r MON DAY HR MIN <<<"$(date -v$WHEN '+%-m %-d %-H %-M')"
WAKE_HUMAN="$(date -v$WHEN '+%a %b %-d, %-I:%M %p')"
echo "waking $WAKE_HUMAN  (month=$MON day=$DAY hour=$HR min=$MIN)"
```

Sanity-check: it must be in the future and match the user's intent. Echo it back in human terms ("waking Wednesday ~9am, in about 30 hours"). launchd catches up a missed calendar time when the machine wakes, so a laptop asleep at the exact minute still fires.

## Step 1 - Capture identity, cwd, and a durable wake note

Read these from the environment — do not guess them:

```bash
SID="$CLAUDE_CODE_SESSION_ID"                       # this session
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
CWD="$(pwd)"                                         # the resume must run from the ORIGINAL cwd
echo "session=$SID host=$HOST cwd=$CWD"
```

`claude --resume` finds the transcript under `projects/<cwd-hash>/`, so the wake must `cd "$CWD"` first. The transcript is local to `$HOST` — a hibernation scheduled here only wakes here. If `$CLAUDE_CODE_SESSION_ID` is empty, derive the id from the transcript filename in `CLAUDE_CONFIG_DIR/projects/<cwd-hash>/<id>.jsonl`; do not proceed without a real id.

Write a durable hibernation note — this is what the woken session reads first, so make it crisp and self-contained. **The note is re-entrant: create it fresh only on the FIRST hibernation; on a re-hibernation the note already exists and its `Wakes so far` / `Give up after` MUST be preserved (you incremented the count on wake) — never clobber them back to a template.**

```bash
mkdir -p ~/.rush/hibernate
NOTE=~/.rush/hibernate/"$SID".md
if [ -f "$NOTE" ]; then
  # Re-hibernation: keep the running count + deadline; just refresh the wake time.
  # (You already bumped "Wakes so far" per the on-wake checklist before calling /hibernate.)
  echo "existing note — preserving Wakes-so-far + deadline; update only the 'Waking at' line"
  # Edit just the "Waking at:" line in "$NOTE" to <WAKE_HUMAN>; leave everything else intact.
else
  cat > "$NOTE" <<EOF
# Hibernation note
- Session: $SID
- Hibernated at: $(date '+%Y-%m-%d %H:%M %Z')
- Waking at: <WAKE_HUMAN>
- Waiting for: <REASON — be specific>
- Give up after: <HARD DEADLINE — an absolute date past which re-hibernating is pointless, e.g. "2026-07-25; MS approval SLA is 7 business days">
- Wakes so far: 0   (cap: 6 — after this many pending-wakes, stop re-hibernating and escalate)

## On wake, do this
1. Increment "Wakes so far" in this note (edit the line) BEFORE deciding to re-hibernate.
2. Check whether <REASON> has resolved. Concrete check: <the exact command / inbox / URL / PR / API call to look at>.
3. If RESOLVED → continue the task from where you left off (your full transcript is loaded).
4. If STILL PENDING **and** before the give-up deadline **and** under the wake cap → run /hibernate again with a *longer* interval than last time (never re-hibernate shorter than the previous gap).
5. If PENDING but past the deadline OR at the wake cap → stop re-hibernating. Telegram Jeff with the status, then end the turn. Do not loop forever.
6. If it now needs Muqsit (his face/voice/identity, a decision, a payment) → Telegram Jeff, then hibernate or stop.

## Context I'll want
<2-4 lines: the task, the PR/ticket, the machine, whatever future-you needs to not re-derive it>
EOF
  echo "wrote fresh $NOTE"
fi
```

On the first hibernation, fill every `<...>` placeholder with real values before writing — the note is useless if it's a template.

## Step 2 - Compose the wake prompt

Short and quote-free; the detail lives in the note and your transcript:

```
WAKE FROM HIBERNATION. You scheduled this wake yourself via /hibernate to re-check a long-running wait. Read your hibernation note at <NOTE>, re-read your recent messages, then check on it. Resolved -> continue the task. Still pending -> /hibernate again with a longer backoff. Needs Muqsit -> Telegram Jeff. You own this wait; do not ask the user to remind you.
```

## Step 3 - Choose the wake transport, then schedule the launchd one-shot

**Pick the transport from the wait length — context-aware, not always the same:**

- **Short wait (< ~2h) from an interactive session → wake into a visible terminal tab.** You're likely still near the machine; a real tab (Ghostty → iTerm → Terminal.app) beats a silent background resume you'd never notice. Set `WAKE_VISIBLE=1`.
- **Long wait (≥ ~2h), or an away / headless / cron context → headless + Telegram.** A window popping open on an unattended machine hours or days later is worse than a notification. Set `WAKE_VISIBLE=0` (the default).

The wrapper honors `WAKE_VISIBLE` but **always keeps a headless floor**: if a visible tab is requested and no GUI terminal is installed, it resumes headless anyway and pings Muqsit. The wait must fire regardless of presentation — the terminal is just how it's shown, never a hard dependency.

Write two things: a tiny **inner resume script** (so terminal launchers exec a bare path — no nested-quote hell), and the **wrapper** that picks the transport and self-cleans. Plus the per-session launchd plist.

```bash
U=$(id -u)
GEN="$(date +%s)-$$"                       # unique per wake GENERATION — see the note below
LABEL="com.rush.hibernate.${SID}.${GEN}"
PLIST=~/Library/LaunchAgents/"$LABEL".plist
WRAP=~/.rush/hibernate/"${SID}.${GEN}".wake.sh
INNER=~/.rush/hibernate/"${SID}.${GEN}".resume.sh
LOG=~/.rush/hibernate/"$SID".wake.log       # shared per-session log (append) is fine
WAKE_VISIBLE=0   # 1 = try a visible terminal tab (short interactive waits); 0 = headless + Telegram

# Inner resume script: interactive TUI for a visible tab (--raw -i keeps it open),
# or headless -p when invoked with WAKE_HEADLESS=1 (the floor). Both resume the SAME
# session under the smart permission classifier. The interactive branch RUNS (not
# execs) so it can observe a resume that never starts: a terminal launcher
# (ghostty -e / osascript) returns 0 on window-launch, NOT on resume success, so the
# wrapper's opened=1 can't tell a live tab from a dead one — this in-tab rc check is
# the only place a failed visible wake is observable, and it pings rather than lose it.
cat > "$INNER" <<EOF
#!/bin/bash
cd "$CWD" 2>/dev/null || exit 1
_ping() { ssh muqsit@mac-mini "openclaw message send --channel telegram --account default --target 6078999250 --message '\$1'" >>"$LOG" 2>&1 || true; }
if [ "\${WAKE_HEADLESS:-0}" = "1" ]; then
  agents run claude --resume "$SID" --mode auto -p "<WAKE_PROMPT>"
else
  agents run claude --resume "$SID" --mode auto --raw -i "<WAKE_PROMPT>"
  RC=\$?
  [ \$RC -ne 0 ] && _ping "hibernate VISIBLE wake resume failed in-tab for session $SID (rc=\$RC) — see $LOG"
fi
EOF
chmod +x "$INNER"

cat > "$WRAP" <<EOF
#!/bin/bash
export PATH="$PATH"                       # launchd's env is minimal; bake the current PATH in
LOG="$LOG"; INNER="$INNER"
ping() { ssh muqsit@mac-mini "openclaw message send --channel telegram --account default --target 6078999250 --message '\$1'" >>"\$LOG" 2>&1 || true; }

# Visible-tab path: try Ghostty, then iTerm, then Terminal.app. opened=1 on first success.
opened=0
if [ "$WAKE_VISIBLE" = "1" ]; then
  if [ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]; then
    /Applications/Ghostty.app/Contents/MacOS/ghostty -e "\$INNER" >>"\$LOG" 2>&1 && opened=1
  elif [ -d /Applications/iTerm.app ]; then
    osascript -e "tell application \"iTerm\" to create window with default profile command \"\$INNER\"" >>"\$LOG" 2>&1 && opened=1
  elif [ -d /System/Applications/Utilities/Terminal.app ] || [ -d /Applications/Utilities/Terminal.app ]; then
    osascript -e "tell application \"Terminal\" to do script \"\$INNER\"" >>"\$LOG" 2>&1 && opened=1
  fi
fi

# Headless floor: not requested, or no GUI terminal available. The wait STILL fires.
if [ "\$opened" != "1" ]; then
  WAKE_HEADLESS=1 bash "\$INNER" >>"\$LOG" 2>&1
  RC=\$?
  [ "$WAKE_VISIBLE" = "1" ] && ping "hibernate woke HEADLESS (no GUI terminal) for session $SID — see \$LOG"
  [ \$RC -ne 0 ] && ping "hibernate wake FAILED for session $SID (rc=\$RC) — see \$LOG"
fi

# Self-clean THIS generation only (label/plist/wrap/inner are GEN-scoped, so a re-hibernation's
# newer generation is untouched). Order matters: remove files FIRST, then bootout — bootout
# kills this very process, so anything after it never runs.
rm -f "$PLIST" "$WRAP" "$INNER"
launchctl bootout gui/$U/"$LABEL"
EOF
chmod +x "$WRAP"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$WRAP</string></array>
  <key>StartCalendarInterval</key><dict>
    <key>Month</key><integer>$MON</integer><key>Day</key><integer>$DAY</integer>
    <key>Hour</key><integer>$HR</integer><key>Minute</key><integer>$MIN</integer>
  </dict>
  <key>RunAtLoad</key><false/>
</dict></plist>
EOF
chmod 600 "$PLIST"
launchctl bootstrap gui/$U "$PLIST"
```

Notes:
- **The `$GEN` nonce is load-bearing — do not key the label on the bare session id.** A re-hibernation is issued *from inside* the resumed `claude` process, which is running *inside the previous wake's wrapper* (the wrapper blocks on that `claude` call). If the new job reused the old label/paths, `launchctl bootstrap` would fail on the still-loaded old label, and the old wrapper's self-clean would then delete the new job's files and boot out the shared label — leaving nothing armed. The session would wake exactly once, ever, while Step 4 falsely reports the stale old job as "armed." A fresh `$GEN` per wake keeps generations independent so the loop survives.
- Substitute the real `<WAKE_PROMPT>` (Step 2) into the **inner** script — it appears twice (the headless `-p` branch and the interactive `--raw -i` branch); keep both in double quotes.
- **Visible tab uses an interactive resume** (`--raw -i`) so the TUI stays open for the user; the headless floor uses `-p` (prompt → auto-headless, prints and exits). Same session, same `--mode auto` either way. `--raw` spawns the agent directly in the tab (no tmux re-attach wrapper).
- **The visible branch RUNS the resume, it does not `exec` it — deliberately.** A terminal launcher (`ghostty -e`, `osascript`) exits 0 when the *window* opens, not when the *resume* succeeds, so the wrapper's `opened=1` cannot distinguish a live tab from one whose resume died on launch. Keeping the inner script as the tab's parent lets it check the resume's exit code and Telegram-ping on failure — closing the only seam where a visible wake could vanish silently. (Dismissing the woken tab with Ctrl-C exits 130, so a normal end can also ping — not just a genuine failure. We deliberately ping on *any* non-zero rather than whitelist clean-quit codes, because a real death can exit 130 too; erring toward a stray ping over a lost wait is the intended direction.)
- **Don't wake a session you're actively sitting in headlessly.** A headless `-p` resume of a session that's also live in a foreground TUI briefly double-attaches one transcript. For short interactive waits prefer `WAKE_VISIBLE=1` (a fresh tab is a clean second surface); the headless floor is for when no one's watching anyway.
- `--mode auto` lets the woken session act with the **smart permission classifier** — it auto-approves safe ops and still prompts/blocks on risky ones. **Never** `--mode skip` / `--dangerously-skip-permissions`: a persistent, auto-launched job must not carry a blanket permission bypass. The user issuing `/hibernate` is the authorization; `auto` keeps risky operations gated. (If a wake genuinely needs to run something the classifier would block, prefer a narrower allow-list over widening the mode.)
- `StartCalendarInterval` drops the year, so it fires on the next occurrence of that month/day — the wrapper boots the job out on first fire, so it runs exactly once.
- `agents run claude --resume` resumes the session natively and manages claude auth itself — no `agents secrets exec` wrapper, no `--dangerously-skip-permissions`, no routines daemon.

## Step 4 - Verify the job is armed

Do not claim you're hibernating until the job is loaded with the right fire time:

```bash
launchctl print gui/$(id -u)/"$LABEL" 2>/dev/null | grep -iE "state|StartCalendarInterval" -A4 | head
```

Confirm the label is loaded and the calendar fields match your wake time. If it's missing, fix it before ending the turn — a `/hibernate` that didn't arm is a silent data-loss of the whole wait.

## Step 5 - Hibernate (end the turn)

There is no self-kill tool, and you must not `kill` your own process mid-turn (it can truncate the transcript you're about to resume). Hibernating = **stop emitting tool calls and return a final message**:

- **Headless / auto / cron agent** (e.g. an OpenClaw agent, an `agents run` dispatch): ending the turn exits the process naturally — that *is* your self-exit. Nothing else to do.
- **Interactive terminal session**: ending the turn hands the prompt back; the window is yours to close. Say so plainly.

Final message shape:

```
Hibernating until <WAKE_HUMAN> (~<relative>). Waiting on: <reason>.
Wake job: <label> armed for <wake time> — verified loaded.
Wake transport: <a visible terminal tab | headless + Telegram> (per the short-vs-long rule in Step 3).
On wake I resume THIS session with full context and check on it myself — no ping needed.
[If interactive: safe to close this window.]
```

Then stop. Do not ask whether to proceed, do not offer alternatives, do not add a trailing question — you are hibernating.