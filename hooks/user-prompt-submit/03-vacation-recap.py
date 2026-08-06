#!/usr/bin/env python3
"""
Detects a long gap since this session's last prompt and reminds the agent to open
with a quick back-from-vacation recap before addressing the new one — the user is
likely returning after time away, not continuing a live conversation.

State: one plain-content file per session, same convention as
notification/06-attention-sentinel.sh's attention dir:

  ~/.agents/.cache/state/last-user-prompt/<session_id>   (content: epoch seconds)

Machine-local, regenerable, never committed.

Threshold: AGENTS_VACATION_RECAP_THRESHOLD_SEC env var, default 7200 (2 hours).

Per-agent protocol — this is ADDITIVE, unlike the other user-prompt-submit hooks:
  claude           — plain stdout, no <user-prompt-submit-hook> wrapper. That wrapper
                      is used elsewhere in this dir to REPLACE the prompt (shortcut /
                      bang-command expansion); this hook must never touch or replace
                      the user's actual prompt, only add a reminder alongside it.
  codex/gemini/... — JSON with additionalContext; APPENDS (prompt untouched).
"""

import json
import os
import sys
import time

STATE_DIR = os.path.join(os.path.expanduser("~"), ".agents", ".cache", "state", "last-user-prompt")
DEFAULT_THRESHOLD_SEC = 7200
RETENTION_SEC = 30 * 86400  # prune session files untouched for 30+ days


def prune_stale(exclude_name):
    try:
        entries = os.listdir(STATE_DIR)
    except Exception:
        return
    now = time.time()
    for name in entries:
        if name == exclude_name:
            continue
        path = os.path.join(STATE_DIR, name)
        try:
            if now - os.path.getmtime(path) > RETENTION_SEC:
                os.remove(path)
        except Exception:
            continue


def human_duration(seconds):
    minutes = round(seconds / 60)
    if minutes < 60:
        return f"{minutes} minute{'s' if minutes != 1 else ''}"
    hours = round(seconds / 3600)
    if hours < 48:
        return f"{hours} hour{'s' if hours != 1 else ''}"
    days = round(seconds / 86400)
    return f"{days} day{'s' if days != 1 else ''}"


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    session_id = data.get("session_id") or data.get("sessionId") or ""
    if not session_id:
        sys.exit(0)

    try:
        threshold_sec = int(os.environ.get("AGENTS_VACATION_RECAP_THRESHOLD_SEC", DEFAULT_THRESHOLD_SEC))
    except ValueError:
        threshold_sec = DEFAULT_THRESHOLD_SEC

    try:
        os.makedirs(STATE_DIR, exist_ok=True)
    except Exception:
        sys.exit(0)

    prune_stale(exclude_name=session_id)

    state_path = os.path.join(STATE_DIR, session_id)
    now = time.time()

    prev = None
    try:
        with open(state_path) as f:
            prev = float(f.read().strip())
    except Exception:
        prev = None

    # Always record this prompt's time for next turn's gap check, best-effort.
    try:
        with open(state_path, "w") as f:
            f.write(str(now))
    except Exception:
        pass

    # First prompt this session (no prior timestamp) — nothing to recap yet.
    if prev is None:
        sys.exit(0)

    gap = now - prev
    if gap < threshold_sec:
        sys.exit(0)

    gap_human = human_duration(gap)
    reminder = (
        f"It's been {gap_human} since the last message in this session — the user is "
        "likely returning after time away, not continuing a live conversation. Before "
        "addressing the new prompt below, give a quick back-from-vacation recap in "
        "plain, simple language: (1) what the problem/task was, (2) what was actually "
        "accomplished, (3) what you're suggesting as the next step or what should keep "
        "going. A few lines, not a report — see the back-from-vacation summary under "
        "F4 in `foundations` for the fuller shape if useful. Then address the new prompt."
    )

    event = data.get("hook_event_name") or data.get("hookEventName") or "UserPromptSubmit"

    if os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("CLAUDECODE"):
        print(reminder)
        sys.exit(0)

    out = {
        "hookSpecificOutput": {
            "hookEventName": event,
            "additionalContext": reminder,
        }
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
