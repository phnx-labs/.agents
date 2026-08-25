#!/usr/bin/env python3
"""Stop hook: refuse a from-context reply.

The failure this catches (measured in session 3f42a8d1, RUSH-3033): the user
pushes back on a design decision and the agent's first move is "you're exactly
right" with no search and no reflection. It answered off the context already in
its window instead of gathering what the question needed.

At the reply event (Stop), read the session file. If the agent made no tool call
and used no skill since the user's last message, it gathered nothing this turn.
Print a directive to go gather context; per hooks/AGENTS.md the stdout of an
exit-0 hook is injected into the model's context. Advisory only: this never
blocks and fails open, so a parse error can never wedge a session.

Keep this small. If it grows phrase catalogs it has gone wrong.
"""
from __future__ import annotations

import json
import sys


def is_user_message(record: dict) -> bool:
    """A message the user actually typed.

    A typed user turn is `type: "user"` with STRING content. A tool result is
    also `type: "user"` but its content is a LIST of tool_result blocks, so it is
    not the user speaking. A message queued mid-turn arrives as its own record
    with string content. (Record shapes verified against a live transcript.)
    """
    if record.get("type") == "user":
        content = (record.get("message") or {}).get("content")
        if isinstance(content, str):
            return True
    if record.get("type") == "queue-operation" and isinstance(record.get("content"), str):
        return True
    return False


def is_context_gathering(record: dict) -> bool:
    """Did the agent make a tool call (a skill invocation is one) this record?

    Covers the Claude shape (a content list carrying a tool_use block) and the
    function-call shape other harnesses record, so the check is not Claude-only.
    """
    content = (record.get("message") or {}).get("content")
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_use" for b in content):
            return True
    if record.get("type") in ("function_call", "custom_tool_call", "command_execution"):
        return True
    return False


GUIDANCE = (
    "You are about to reply without having gathered any new context this turn. "
    "Since the user's last message you have not read a file, run anything, or "
    "used a skill. Do not answer from the context you already have. Work out what "
    "answering this properly requires, then go get it: read the relevant code and "
    "files, use any skill that fits, check the real state, weigh the tradeoffs and "
    "downsides. When the user pushes back or asserts something, do not just agree "
    "or disagree, find out whether it holds and what it costs first. Then reply "
    "from what you found."
)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        transcript_path = payload.get("transcript_path") or payload.get("transcriptPath") or ""
        with open(transcript_path) as handle:
            records = [json.loads(line) for line in handle if line.strip()]
    except Exception:
        return 0  # advisory hook: fail open, never wedge a session

    last_user = -1
    for index, record in enumerate(records):
        if isinstance(record, dict) and is_user_message(record):
            last_user = index
    if last_user < 0:
        return 0

    for record in records[last_user + 1:]:
        if isinstance(record, dict) and is_context_gathering(record):
            return 0  # the agent gathered something; let the reply through

    print(GUIDANCE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
