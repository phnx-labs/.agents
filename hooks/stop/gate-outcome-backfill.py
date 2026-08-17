#!/usr/bin/env python3
"""Derive gate outcomes from the transcripts. OFFLINE — never on a hook path.

`gate_events` records that a gate fired. It cannot say whether firing was RIGHT.
That is the whole measurement gap: for the life of the table every row read
`blocked`, so no gate had a false-positive rate and no change to gate logic could
be shown to be an improvement.

This fills `gate_outcomes` by replaying what the agent did AFTER each block.

The headline field is `demand_satisfied`, and it is deliberately not
`followon_mutated`. Counting any follow-on activity would score an agent that
answers a bogus `keep-moving` by ticking one todo as a success — certifying the
exact false positives the metric exists to find. `demand_satisfied` keys on the
specific structured thing each gate demanded:

    open-pr      the session actually merged or closed a PR afterwards
    keep-moving  a task actually moved to completed afterwards
    handback     the script it wrote was actually executed afterwards
    delivery     a release/publish/verify command actually ran afterwards
    self-audit   no honest mechanical demand — see UNSCORED below
    swarm        no honest mechanical demand — see UNSCORED below

UNSCORED: `self-audit` demands "re-read the conversation and verify every goal",
and `swarm` demands "trigger the composed cross-track flow". Neither leaves a
signature a transcript scan can confirm — an agent can emit the right prose
without doing either. Rather than invent a proxy that would quietly inflate the
success rate, those rows get `demand_satisfied = 0` and are reported separately
as unscored. A metric that cannot measure something must say so.

No message text is written. `msg_sha256` is the join key back to the message
without storing it, the same trick `goal_boundaries.prompt_sha256` uses.

Read-only by default: prints what it would write. Pass --write to persist.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path

DB = Path(os.path.expanduser("~/.agents/.history/hooks/system.verify-work-complete/state.db"))
VERSIONS = Path(os.path.expanduser("~/.agents/.history/versions"))

FEEDBACK_PREFIX = "Stop hook feedback:"

# Anchors that identify which gate an injected block came from. These are
# substrings of the gate messages themselves, so they move if the messages do —
# a mismatch shows up as unmatched fires in the report rather than silently
# scoring zero.
GATE_MARKERS = {
    "open-pr": "pull request(s) that are still OPEN",
    "keep-moving": "STOP GATE (keep moving)",
    "handback": "STOP GATE (handback)",
    "delivery": "STOP GATE (delivery)",
    "self-audit": "you must verify before stopping",
    "swarm": "STOP GATE (swarm)",
}

CMD_POS = r"(?:^|[\n;&|]\s*|\$\(\s*)"
RE_MERGED = re.compile(CMD_POS + r"gh\s+pr\s+(?:merge|close)\b")
RE_RELEASE = re.compile(
    CMD_POS + r"(?:npm\s+publish|cargo\s+publish|vsce\s+publish|gh\s+release\s+create"
    r"|release\.sh|npm\s+(?:view|info)\b)"
)
RE_REPO_WRITE = re.compile(CMD_POS + r"git\s+(?:-C\s+\S+\s+)?(?:add|commit|push|merge)\b")
# The handback demand is "run the thing you just wrote to /tmp". An executable
# script is invoked BY PATH — `/tmp/deploy.sh --flag` — as often as through an
# interpreter, so requiring `bash /tmp/...` scores a satisfied fire as unmet.
# Measured: that narrower pattern reported handback at 100% unmet across 14
# fires, and the very first one inspected had run `/tmp/schedule-...-post.sh A`.
RE_RAN_TMP = re.compile(
    CMD_POS + r"(?:(?:bash|sh|zsh|python3?|node)\s+)?\S*/tmp/\S+\.(?:sh|py|js|mjs)\b"
)
WRITE_TOOLS = {"write", "edit", "multiedit", "notebookedit"}

UNSCORABLE = {"self-audit", "swarm"}


def _blocks(record):
    msg = record.get("message") if isinstance(record.get("message"), dict) else record
    content = msg.get("content") if isinstance(msg, dict) else None
    return content if isinstance(content, list) else []


def load_transcript(session_key: str):
    """Return the parsed records for a session, or None if no transcript exists."""
    if ":" not in session_key:
        return None
    harness, uid = session_key.split(":", 1)
    hits = glob.glob(str(VERSIONS / harness / "*/home/.claude/projects/*" / f"{uid}.jsonl"))
    if not hits:
        return None
    records = []
    try:
        with open(hits[0], errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except Exception:
                    continue
    except OSError:
        return None
    return records


def find_fires(records):
    """Injected gate blocks, in order: (index, gate_name, sha256 of the message that tripped it)."""
    fires = []
    last_text = ""
    for i, record in enumerate(records):
        msg = record.get("message") if isinstance(record.get("message"), dict) else record
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if record.get("type") == "assistant" or msg.get("role") == "assistant":
            text = " ".join(
                b.get("text", "") for b in _blocks(record)
                if isinstance(b, dict) and b.get("type") == "text"
            ).strip()
            if text:
                last_text = text
        if (record.get("type") == "user" and record.get("isMeta") is True
                and isinstance(content, str) and content.startswith(FEEDBACK_PREFIX)):
            gate = next((g for g, marker in GATE_MARKERS.items() if marker in content), None)
            if gate:
                digest = hashlib.sha256(last_text.encode("utf-8", "replace")).hexdigest()
                fires.append((i, gate, digest))
    return fires


def score_window(records, start, end, gate):
    """What the agent actually did between this block and the next one."""
    tools = 0
    mutated = False
    interjected = False
    satisfied = False
    for record in records[start + 1:end]:
        if (record.get("type") == "user" and not record.get("isMeta")
                and isinstance((record.get("message") or {}).get("content"), str)):
            interjected = True
        for block in _blocks(record):
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            tools += 1
            name = str(block.get("name") or "").lower()
            payload = block.get("input") or {}
            command = str(payload.get("command", ""))
            if name in WRITE_TOOLS or RE_REPO_WRITE.search(command):
                mutated = True
            if gate == "open-pr" and RE_MERGED.search(command):
                satisfied = True
            elif gate == "delivery" and RE_RELEASE.search(command):
                satisfied = True
            elif gate == "keep-moving" and name in ("taskupdate", "todowrite"):
                # the demand is a task actually moving, not merely being touched
                blob = json.dumps(payload)
                if '"completed"' in blob:
                    satisfied = True
            elif gate == "handback" and RE_RAN_TMP.search(command):
                satisfied = True
    return tools, mutated, interjected, satisfied


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="persist rows (default: report only)")
    parser.add_argument("--db", default=str(DB))
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.is_file():
        print(f"no state database at {db_path}", file=sys.stderr)
        return 1

    mode = "" if args.write else "?mode=ro"
    db = sqlite3.connect(f"file:{db_path}{mode}", uri=True)
    rows = db.execute(
        "SELECT id, session_key, gate_name FROM gate_events WHERE outcome='blocked' ORDER BY id"
    ).fetchall()

    by_session: dict[str, list] = {}
    for gate_event_id, session_key, gate_name in rows:
        by_session.setdefault(session_key, []).append((gate_event_id, gate_name))

    derived, no_transcript, unmatched = [], 0, 0
    now = int(time.time() * 1000)

    for session_key, events in by_session.items():
        records = load_transcript(session_key)
        if records is None:
            no_transcript += len(events)
            continue
        fires = find_fires(records)
        seen: dict[str, int] = {}
        for gate_event_id, gate_name in events:
            nth = seen.get(gate_name, 0)
            seen[gate_name] = nth + 1
            matching = [f for f in fires if f[1] == gate_name]
            if nth >= len(matching):
                unmatched += 1
                continue
            index, _, digest = matching[nth]
            later = [f[0] for f in fires if f[0] > index]
            end = later[0] if later else len(records)
            refired = 1 if any(f[1] == gate_name for f in fires if f[0] > index) else 0
            tools, mutated, interjected, satisfied = score_window(records, index, end, gate_name)
            if gate_name in UNSCORABLE:
                satisfied = False
            derived.append((gate_event_id, tools, int(mutated), int(satisfied),
                            refired, int(interjected), digest, now))

    if args.write:
        db.executemany(
            "INSERT OR REPLACE INTO gate_outcomes(gate_event_id,followon_tools,followon_mutated,"
            "demand_satisfied,refired,user_interjected,msg_sha256,derived_at_ms)"
            " VALUES(?,?,?,?,?,?,?,?)",
            derived,
        )
        db.commit()

    per_gate: dict[str, list[int]] = {}
    for gate_event_id, tools, mutated, satisfied, refired, interjected, _, _ in derived:
        gate = next(g for i, g in [(r[0], r[2]) for r in rows] if i == gate_event_id)
        bucket = per_gate.setdefault(gate, [0, 0, 0])
        bucket[0] += 1
        bucket[1] += satisfied
        bucket[2] += refired

    print(f"{'gate':<13} {'blocked':>8} {'satisfied':>10} {'refired':>8}   {'unmet':>8}")
    print("-" * 54)
    for gate in sorted(per_gate):
        total, satisfied, refired = per_gate[gate]
        if gate in UNSCORABLE:
            print(f"{gate:<13} {total:>8} {'—':>10} {refired:>8}   {'unscored':>8}")
            continue
        rate = 100.0 * (total - satisfied) / total if total else 0.0
        print(f"{gate:<13} {total:>8} {satisfied:>10} {refired:>8}   {rate:>7.1f}%")
    print("-" * 54)
    print(f"derived {len(derived)} outcome(s)"
          f"{' (written)' if args.write else ' (dry run — pass --write to persist)'}")
    if no_transcript:
        print(f"{no_transcript} fire(s) skipped: transcript pruned or on another machine")
    if unmatched:
        print(f"{unmatched} fire(s) skipped: no matching injection found in the transcript")
    print("'unmet' is NOT a false-positive rate. Every gate also accepts an ESCAPE —\n"
          "naming an external blocker, or handing off to a named owner — which this scan\n"
          "cannot detect, so a legitimately-escaped fire counts as unmet. Read it as an\n"
          "upper bound on wrongness, and the refired column as the harder signal.")
    print("self-audit and swarm are reported unscored on purpose: their demands "
          "(re-read and verify / trigger the composed flow) leave no signature a\n"
          "transcript scan can confirm, and a proxy would inflate the success rate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
