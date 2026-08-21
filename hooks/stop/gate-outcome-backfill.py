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
    delivery     UNSCORED - it fires on five different demands and no single
                 signature can confirm them (see UNSCORABLE below)
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
# Each gate matches on any of its anchors: the legacy "STOP GATE (...)" prefix
# for transcripts written before the message rewrite, plus a phrase present in
# the current message text.
GATE_MARKERS = {
    "open-pr": ("pull request(s) that are still OPEN",),
    "keep-moving": ("STOP GATE (keep moving)", "your task list still has"),
    "handback": ("STOP GATE (handback)", "you wrote a runnable script"),
    "delivery": ("STOP GATE (delivery)", "close out the delivery"),
    "self-audit": ("you must verify before stopping",),
    "swarm": ("STOP GATE (swarm)", "edit-mode swarm and are claiming"),
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
# The open-PR gate documents four legitimate resolutions, not one
# (00-agent-verify-work-complete.sh:479-495): merge it, get a non-author review
# then merge, hand it to a NAMED owner, or name an external blocker plus a durable
# process. A session that correctly hands a PR off never touches it again — by
# design — so counting only `gh pr merge` scores that as unmet.
WATCHER_TOOLS = {"schedulewakeup", "monitor"}
RE_HANDOFF = re.compile(
    r"\b(?:handed off|handing (?:it|this|the pr) (?:off|to)|owns? (?:this|the) pr"
    r"|takes over from here|pr-merge-on-green|will merge on green)\b", re.I
)

# Gates whose demand leaves no signature a transcript scan can confirm.
#
# `delivery` is here after review, not by original design, and the reason matters:
# STOP GATE (delivery) fires on ANY of five independent conditions
# (verify-delivery-chain.py:625-635) — an open Linear ticket, open related
# tickets, missing docs/CHANGELOG, an unreleased shippable change, or missing
# outcome evidence. A release-command detector can only ever see the fourth.
# Sampled a real fire: its demand was "RUSH-2476 [Todo] still needs state + proof",
# which no release regex can ever satisfy, so the agent was scored unmet no matter
# what it did. Reporting 83.9% unmet from a detector blind to 4 of 5 demands is the
# exact failure this file warns about — a narrow detector making a working gate
# look broken. Unscored until each demand shape can be detected on its own.
UNSCORABLE = {"self-audit", "swarm", "delivery"}

# A recorded fire and its transcript injection are the same event, so their
# timestamps should agree closely. Anything further apart is a pairing failure,
# not a slow write.
PAIR_TOLERANCE_MS = 5 * 60 * 1000


# Claude Code delivers several harness artifacts as `type: "user"` with a plain
# string body — PTY echoes, background-task notifications, slash-command echoes.
# Counting those as a human stepping in put this field at 88% of all windows,
# which is not credible. Match the wrappers and exclude them.
RE_HARNESS_TURN = re.compile(
    r"</?(?:bash-input|bash-stdout|bash-stderr|task-notification|command-message"
    r"|command-name|command-args|local-command-stdout|system-reminder)\b"
)


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


def _record_ms(record):
    """Epoch ms for a transcript record, or None if it carries no timestamp."""
    stamp = record.get("timestamp")
    if not isinstance(stamp, str):
        return None
    try:
        from datetime import datetime
        return int(datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp() * 1000)
    except Exception:
        return None


def find_fires(records):
    """Injected gate blocks, in order: (index, gate_name, sha256, epoch_ms|None)."""
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
            gate = next((g for g, markers in GATE_MARKERS.items() if any(m in content for m in markers)), None)
            if gate:
                digest = hashlib.sha256(last_text.encode("utf-8", "replace")).hexdigest()
                fires.append((i, gate, digest, _record_ms(record)))
    return fires


def _completed_ids(payload):
    """Ids (or contents) of todo entries this TodoWrite call marks completed."""
    ids = set()
    for item in (payload.get("todos") or payload.get("items") or []):
        if isinstance(item, dict) and str(item.get("status") or "") == "completed":
            ids.add(str(item.get("id") or item.get("content") or ""))
    return ids


def _todo_baseline(records, start):
    """Which todos were ALREADY completed as of the last TodoWrite before the gate."""
    for i in range(start, -1, -1):
        for block in _blocks(records[i]):
            if (isinstance(block, dict) and block.get("type") == "tool_use"
                    and str(block.get("name") or "").lower() == "todowrite"):
                return _completed_ids(block.get("input") or {})
    return set()


def score_window(records, start, end, gate):
    """What the agent actually did between this block and the next one."""
    tools = 0
    handoff = False
    mutated = False
    interjected = False
    satisfied = False
    baseline = _todo_baseline(records, start)
    for record in records[start + 1:end]:
        if record.get("type") == "user" and not record.get("isMeta"):
            body = (record.get("message") or {}).get("content")
            if isinstance(body, str) and body.strip() and not RE_HARNESS_TURN.search(body):
                interjected = True
        for block in _blocks(record):
            if isinstance(block, dict) and block.get("type") == "text" and gate == "open-pr":
                if RE_HANDOFF.search(str(block.get("text") or "")):
                    handoff = True
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            tools += 1
            name = str(block.get("name") or "").lower()
            payload = block.get("input") or {}
            command = str(payload.get("command", ""))
            if name in WRITE_TOOLS or RE_REPO_WRITE.search(command):
                mutated = True
            if gate == "open-pr" and (RE_MERGED.search(command)
                                      or name in WATCHER_TOOLS):
                satisfied = True
            elif gate == "delivery" and RE_RELEASE.search(command):
                satisfied = True
            elif gate == "keep-moving" and name == "taskupdate":
                # Read the status FIELD. '"completed"' anywhere in the dumped
                # payload also matches a task whose *content* says "completed"
                # while its status is in_progress.
                if str(payload.get("status") or "") == "completed":
                    satisfied = True
            elif gate == "keep-moving" and name == "todowrite":
                # TodoWrite re-emits the whole list, so a completed entry proves
                # nothing on its own — it may have been completed before the gate
                # fired. Only an id that was NOT already complete going in counts.
                if _completed_ids(payload) - baseline:
                    satisfied = True
            elif gate == "handback" and RE_RAN_TMP.search(command):
                satisfied = True
    if gate == "open-pr" and handoff:
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
        "SELECT id, session_key, gate_name, created_at_ms FROM gate_events"
        " WHERE outcome='blocked' ORDER BY id"
    ).fetchall()

    by_session: dict[str, list] = {}
    for gate_event_id, session_key, gate_name, created_at_ms in rows:
        by_session.setdefault(session_key, []).append((gate_event_id, gate_name, created_at_ms))

    derived, no_transcript, unmatched, mispaired = [], 0, 0, 0
    now = int(time.time() * 1000)

    for session_key, events in by_session.items():
        used: set[int] = set()
        events.sort(key=lambda e: (e[2] or 0, e[0]))
        records = load_transcript(session_key)
        if records is None:
            no_transcript += len(events)
            continue
        fires = find_fires(records)
        for gate_event_id, gate_name, created_at_ms in events:
            matching = [f for f in fires if f[1] == gate_name]
            if not matching:
                unmatched += 1
                continue
            # Pair on the row's OWN timestamp, not on ordinal position. Ordinal
            # pairing only guards the case where the DB has MORE rows than the
            # transcript has markers; the opposite — a transcript carrying older
            # occurrences than gate recording existed for — silently paired rows
            # to windows hours away from the real one. Measured on two live
            # sessions: DB rows at 22:29-22:47 were being scored against
            # occurrences at 08:07-10:04, entirely different work.
            # Pair on the row's OWN timestamp, and CONSUME the fire so two rows
            # can never share one window. The hook records a fire even when the
            # harness never injects the block, so a session routinely holds more
            # rows than markers (measured: 17 keep-moving rows against 8
            # injections on one session). Nearest-match alone then attaches every
            # orphan row to whichever real fire is closest, and scores it against
            # a window that answered a different block.
            index = digest = None
            if created_at_ms:
                free = [f for f in matching
                        if f[3] is not None and f[0] not in used
                        and abs(f[3] - created_at_ms) <= PAIR_TOLERANCE_MS]
                if free:
                    best = min(free, key=lambda f: abs(f[3] - created_at_ms))
                    index, digest = best[0], best[2]
                    used.add(best[0])
            if index is None:
                # No timestamp to validate against, or no unused injection inside
                # the tolerance. Either way there is nothing to score honestly, so
                # skip and count it. There is deliberately no ordinal fallback:
                # positional pairing is the silent mis-pair this block exists to
                # prevent, and reinstating it "just for older transcripts" is the
                # fallback the repo rules forbid.
                mispaired += 1
                continue
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
    if mispaired:
        print(f"{mispaired} fire(s) skipped: no unused injection within "
              f"{PAIR_TOLERANCE_MS // 60000}min of the recorded fire time — "
              "scoring these would use the wrong slice of the conversation")
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
