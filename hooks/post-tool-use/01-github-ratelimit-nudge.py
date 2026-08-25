#!/usr/bin/env python3
"""Advisory nudge AFTER a GitHub call comes back rate-limited; never blocks.

The failure this targets: an agent hits a GitHub rate limit and then sits idle
waiting for the reset, or parks the work on a background agent to retry "once the
limit resets" — instead of switching to a path that isn't limited right now. The
logged-in browser on the local device reads and posts as the user with no API
cost; the authenticated REST API (`gh api`) is 5000/hour when the wall was the
60/hour unauthenticated path.

PostToolUse on the shell tool (matcher Bash): it sees the command and its output.
When the output shows a GitHub rate-limit signal, it prints a short additionalContext
note and exits 0 — advisory, fails open. Fires at most once per session.

Kept deliberately tight so it does not distract:
  - Only when the OUTPUT actually says rate-limited (not preemptively on every gh
    call). If nothing rate-limited, this returns before parsing.
  - Only in a GitHub context (command or output mentions gh / github).
  - One note per session.
"""
import hashlib
import json
import os
import re
import sys
import tempfile

# The tool output actually reported a rate limit. GitHub's real wording for the
# primary limit ("API rate limit exceeded"), the secondary/abuse limit, and the
# raw header signal are all covered.
RATELIMIT = re.compile(
    r"(?:API rate limit exceeded|secondary rate limit|abuse detection|"
    r"rate limit|was submitted too quickly|Retry-After|"
    r"x-ratelimit-remaining['\"]?\s*[:=]\s*['\"]?0\b)",
    re.I,
)
# A GitHub context — so a rate limit from some other API never misfires this.
GITHUB = re.compile(r"(?:\bgh\b|github\.com|githubusercontent|api\.github)", re.I)


def stringify(value):
    if isinstance(value, str):
        return value
    try:
        return json.dumps(value)
    except Exception:
        return str(value)


def main():
    raw = sys.stdin.read()
    if not RATELIMIT.search(raw):  # cheap gate: nothing rate-limited -> nothing to say
        return
    try:
        payload = json.loads(raw)
    except Exception:
        return

    inputs = payload.get("tool_input") or payload.get("toolInput") or {}
    command = str(inputs.get("command") or inputs.get("cmd") or "")
    response = payload.get("tool_response")
    if response is None:
        response = payload.get("toolResponse")
    output = stringify(response)

    # The rate-limit signal must be in the OUTPUT, not just the typed command
    # (e.g. a `grep 'rate limit'` should not trip it).
    if not RATELIMIT.search(output):
        return
    if not GITHUB.search(command + " " + output):
        return

    session = str(payload.get("session_id") or payload.get("sessionId") or os.getppid())
    key = hashlib.sha1(f"github-ratelimit:{session}".encode()).hexdigest()
    directory = os.path.join(tempfile.gettempdir(), "agents-github-ratelimit-nudge")
    marker = os.path.join(directory, key)
    try:
        os.makedirs(directory, exist_ok=True)
        os.close(os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    except FileExistsError:
        return
    except OSError:
        pass

    note = (
        "[github rate-limited] Don't sit idle waiting for the reset or hand it to a background "
        "agent to retry later. Do it now another way: the logged-in browser on this device "
        "(`agents browser`), or the authenticated REST API (`gh api`)."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": note}}))


if __name__ == "__main__":
    main()
