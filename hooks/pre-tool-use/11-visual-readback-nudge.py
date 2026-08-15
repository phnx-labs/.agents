#!/usr/bin/env python3
"""Advisory reminder before a visual artifact leaves the session; never blocks."""
import hashlib
import json
import os
import re
import sys
import tempfile

VISUAL = re.compile(r"[^\s'\"|;&]+\.(?:html|png|jpe?g|svg|pdf)\b", re.I)
SHIP = re.compile(r"\b(?:scp|rsync|agents\s+share|open|xdg-open)\b|agents\s+ssh\b[^\n]*\bopen\b", re.I)


def main():
    try:
        payload = json.load(sys.stdin)
        inputs = payload.get("tool_input") or payload.get("toolInput") or {}
        command = str(inputs.get("command") or inputs.get("cmd") or "")
    except Exception:
        return
    if not SHIP.search(command):
        return
    match = VISUAL.search(command)
    if not match:
        return
    session = str(payload.get("session_id") or payload.get("sessionId") or os.getppid())
    key = hashlib.sha1(f"{session}:{match.group(0)}".encode()).hexdigest()
    directory = os.path.join(tempfile.gettempdir(), "agents-visual-readback-nudge")
    marker = os.path.join(directory, key)
    try:
        os.makedirs(directory, exist_ok=True)
        os.close(os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    except FileExistsError:
        return
    except OSError:
        pass
    note = (
        "[visual read-back] Before describing or delivering this visual artifact, render it "
        "headlessly with `agents browser start --url file://…`, capture it with "
        "`agents browser screenshot -o /tmp/<name>.png`, then read that path with "
        "`view_image`. This is advisory; the "
        "command will still run."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": note}}))


if __name__ == "__main__":
    main()
