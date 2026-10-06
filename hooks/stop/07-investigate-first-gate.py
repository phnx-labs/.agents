#!/usr/bin/env python3
"""investigate-first-gate — Stop hook, interactive Claude sessions only.

Blocks a reply to the owner that rests on no investigation tool call made since
their message, and (once per message) a reply that opened by conceding before any
evidence came back. Headless `claude -p` runs (CLAUDE_CODE_ENTRYPOINT=sdk-cli) are
machine prompts and are skipped. Claude Code has no cap on consecutive Stop blocks,
so this hook allows the stop after MAX_BLOCKS on one message.

Replaces 07-gather-before-reply.py, whose exit-0 advice was recorded only after the
reply was already shown. Exit 0 = allow; exit 2 = block, stderr goes to the agent.
"""
from __future__ import annotations

import json
import os
import re
import sys

MARKER = "[investigate-first-gate]"
MAX_BLOCKS = 3

# Tool calls that record or schedule work but gather no evidence.
BOOKKEEPING = {
    "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "ToolSearch",
    "ScheduleWakeup", "AskUserQuestion", "ExitPlanMode", "EnterPlanMode",
}

# Closed list of concession openers.
CONCEDE = re.compile(
    r"\b(?:you['\u2019]?re (?:absolutely |exactly |totally |completely )?(?:right|correct)"
    r"|you are (?:absolutely |exactly |totally |completely )?(?:right|correct)"
    r"|good catch|fair point|my mistake|i was wrong|i should(?: have|'ve)"
    r"|agreed\b|absolutely[.,!])",
    re.I,
)

QUOTES = "\"'`\u201c\u201d\u2018\u2019"


# What may precede a concession and still leave it the sentence's opener: list markers,
# emphasis, brackets, emoji, and a few filler words ("Yes, you're right", "Ah, good catch").
LEAD_IN = re.compile(
    r"^(?:[\W\d_]|(?:ah|oh|ok|okay|yes|yeah|yep|sorry|thanks|well|hmm|indeed|so|looks like|seems like)\b)*$",
    re.I,
)


def concession(text: str):
    """First concession that OPENS a sentence and is not quoted.

    A real opener reads "You're right. ...", "Yes, you're right", "- Good catch". A phrase
    merely mentioned (the "You're right" opener check) or inside a clause
    ("I said you're right too early") is not one.
    """
    for match in CONCEDE.finditer(text):
        before = text[:match.start()]
        after = text[match.end():match.end() + 1]
        if (before.rstrip() and before.rstrip()[-1] in QUOTES) or (after and after in QUOTES):
            continue
        sentence = re.split(r"[.!?:\n]", before)[-1]
        if LEAD_IN.match(sentence):
            return match
    return None


# User records the owner did not type.
SYNTHETIC = re.compile(
    r"^\s*(?:<(?:system-reminder|task-notification|local-command-stdout|local-command-stderr"
    r"|local-command-caveat|bash-stdout|bash-stderr)>|Base directory for this skill:"
    r"|[A-Za-z]+ hook feedback:|\[Request interrupted|Caveat: )"
)


def owner_typed(record: dict) -> bool:
    """A user record carrying text or an image the owner sent (slash commands and
    `!` shell inputs included: both are the owner speaking)."""
    if (record.get("type") != "user" or record.get("isMeta") or record.get("isSidechain")
            or record.get("isCompactSummary")):
        return False
    content = (record.get("message") or {}).get("content")
    if isinstance(content, str):
        return bool(content.strip()) and not SYNTHETIC.search(content)
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return False
        texts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        has_image = any(isinstance(b, dict) and b.get("type") == "image" for b in content)
        return has_image or any(t.strip() and not SYNTHETIC.search(t) for t in texts)
    return False


def own_feedback(record: dict) -> str:
    if record.get("type") != "user":
        return ""
    content = (record.get("message") or {}).get("content")
    if isinstance(content, str) and content.startswith("Stop hook feedback:") and MARKER in content:
        return content
    return ""


def main() -> int:
    if os.environ.get("CLAUDE_CODE_ENTRYPOINT") != "cli":
        return 0
    path = json.load(sys.stdin).get("transcript_path")
    if not path:
        print(f"{MARKER} no transcript_path in the Stop payload; cannot check, allowing.", file=sys.stderr)
        return 0
    records = []
    with open(path) as handle:
        for line in handle:
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue  # blank or half-written last line while the harness is still writing

    start = max((i for i, r in enumerate(records) if owner_typed(r)), default=-1)
    if start < 0:
        return 0
    turn = records[start + 1:]

    prior = [own_feedback(r) for r in turn]
    prior = [p for p in prior if p]
    if len(prior) >= MAX_BLOCKS:
        print(f"{MARKER} allowing this stop after {len(prior)} blocks on one message; "
              "the gate does not wedge sessions.", file=sys.stderr)
        return 0

    names: dict[str, str] = {}
    calls = 0
    opening: list[str] = []
    evidence = False
    for record in turn:
        content = (record.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if record.get("type") == "assistant" and kind == "text" and not evidence:
                opening.append(block.get("text", ""))
            elif record.get("type") == "assistant" and kind == "tool_use":
                names[block.get("id", "")] = block.get("name", "")
                if block.get("name") not in BOOKKEEPING:
                    calls += 1
            elif kind == "tool_result" and names.get(block.get("tool_use_id", "")) not in BOOKKEEPING:
                evidence = True

    if calls == 0:
        print(
            f"{MARKER} zero-tools: you replied to the owner without investigating. Nothing "
            "since their message was read, run, searched, or opened. Do not answer from "
            "context. Work out what the message needs (current code, live state, the PR, "
            "the session, the page), get it with tools, then answer from what you found. "
            "If they pushed back, check whether they are right before agreeing or disagreeing.",
            file=sys.stderr,
        )
        return 2

    already_flagged = any("agree-first" in p for p in prior)
    match = concession("\n".join(opening)[:600])
    if match and not already_flagged:
        print(
            f"{MARKER} agree-first: you opened with \"{match.group(0)}\" before any evidence "
            "came back. Agreement written before checking is a guess. Verify the claim now, "
            "then state in your reply what the evidence shows, including where the owner "
            "may be wrong or where your opener was premature.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
