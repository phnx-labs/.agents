#!/usr/bin/env python3
"""Cross-session recall: rank candidate sessions from the local index, then
recover assistant answers the index does not cover by grepping each
candidate's own transcript file. Snippet-level, context-capped, stdlib only.

Two-phase design:
  1. FIND candidates by unioning session_text (bm25, holds user turns +
     title/topic/project) and tool_call_text (trigram, holds tool activity).
     This is what scales to hundreds of sessions without opening any file.
  2. RECOVER by opening only the top-K candidates' own transcript .jsonl and
     grepping every role (user, assistant, tool) for the same terms. This is
     what surfaces assistant answers, since the index never stores them.

Never reads more than --limit transcripts, and never emits more than
--snippets windows of +/-{context} lines per session, so output volume does
not scale with session size.
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timedelta, timezone

DB_PATH = os.path.expanduser("~/.agents/.history/sessions/sessions.db")

SINCE_RE = re.compile(r"^(\d+)([smhdw])$")
SINCE_UNITS = {"s": "seconds", "m": "minutes", "h": "hours", "d": "days", "w": "weeks"}

ROLE_LABELS = {"user": "user", "assistant": "assistant", "tool": "tool"}


def parse_args(argv):
    p = argparse.ArgumentParser(
        prog="recall.py",
        description="Rank prior sessions on a topic and pull capped, snippet-level context from them.",
    )
    p.add_argument("terms", nargs="+", help="search terms (ticket ids, filenames, symbols, keywords)")
    p.add_argument("--all", action="store_true", help="no-op placeholder for parity with `agents sessions --all`; recall.py already searches every project/device-local session by default")
    p.add_argument("--project", default=None, help="only sessions whose project name contains this (case-insensitive)")
    p.add_argument("--since", default=None, help="only sessions newer than this: 7d, 12h, 30m, 2w, or an ISO date")
    p.add_argument("--limit", type=int, default=8, help="max candidate sessions to open and grep (default: 8)")
    p.add_argument("--context", type=int, default=3, help="lines of context around each match (default: 3)")
    p.add_argument("--snippets", type=int, default=3, help="max snippet windows per session (default: 3)")
    p.add_argument("--json", action="store_true", help="emit JSON instead of the compact text digest")
    return p.parse_args(argv)


def parse_since(value):
    if not value:
        return None
    m = SINCE_RE.match(value.strip())
    if m:
        n, unit = m.groups()
        delta = timedelta(**{SINCE_UNITS[unit]: int(n)})
        return (datetime.now(timezone.utc) - delta).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    # fall back to treating it as an ISO date/timestamp already
    return value


def fts_quote(term):
    return '"' + term.replace('"', '""') + '"'


def open_db():
    uri = f"file:{DB_PATH}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


RRF_K = 60


def find_candidates(conn, terms, project, since, limit):
    """Union session_text (bm25) and tool_call_text (trigram) matches. The two
    tables' bm25 scores are not comparable (different tokenizers, different
    document stats), so candidates are fused by rank (reciprocal rank fusion)
    within each source rather than by raw score across sources."""
    match_query = " ".join(fts_quote(t) for t in terms)
    fused = {}  # session_id -> {"rrf": float, "via": set}

    def consider(session_id, rank, via):
        c = fused.setdefault(session_id, {"rrf": 0.0, "via": set()})
        c["rrf"] += 1.0 / (RRF_K + rank)
        c["via"].add(via)

    try:
        cur = conn.execute(
            "SELECT session_id, bm25(session_text) AS score FROM session_text "
            "WHERE session_text MATCH ? ORDER BY score LIMIT ?",
            (match_query, limit * 4),
        )
        for rank, row in enumerate(cur, start=1):
            consider(row["session_id"], rank, "user")
    except sqlite3.OperationalError:
        pass

    try:
        cur = conn.execute(
            "SELECT tc.session_id AS session_id, MIN(bm25(tool_call_text)) AS score "
            "FROM tool_call_text JOIN tool_calls tc ON tc.call_key = tool_call_text.call_key "
            "WHERE tool_call_text MATCH ? GROUP BY tc.session_id ORDER BY score LIMIT ?",
            (match_query, limit * 4),
        )
        for rank, row in enumerate(cur, start=1):
            consider(row["session_id"], rank, "tool")
    except sqlite3.OperationalError:
        pass

    if not fused:
        return []
    candidates = {sid: {"score": -c["rrf"], "via": c["via"]} for sid, c in fused.items()}

    placeholders = ",".join("?" for _ in candidates)
    filters = [f"id IN ({placeholders})"]
    params = list(candidates.keys())
    if project:
        filters.append("LOWER(project) LIKE ?")
        params.append(f"%{project.lower()}%")
    if since:
        filters.append("timestamp >= ?")
        params.append(since)

    rows = conn.execute(
        f"SELECT id, short_id, agent, project, timestamp, file_path, topic, label "
        f"FROM sessions WHERE {' AND '.join(filters)}",
        params,
    ).fetchall()

    merged = []
    for row in rows:
        c = candidates[row["id"]]
        merged.append({
            "id": row["id"],
            "shortId": row["short_id"],
            "agent": row["agent"],
            "project": row["project"],
            "timestamp": row["timestamp"],
            "filePath": row["file_path"],
            "topic": row["topic"] or row["label"] or "",
            "score": c["score"],
            "via": sorted(c["via"]),
        })
    merged.sort(key=lambda x: x["score"])
    return merged[:limit]


def resolve_transcript_path(file_path):
    real_home = os.path.expanduser("~")
    return file_path.replace("[HOME]", real_home)


def iter_text_events(obj):
    """Yield (role, text) for one transcript JSONL record. Best-effort across
    harnesses: tries the Claude Code envelope first, then a generic
    role+content-block walk that also covers Responses-API-shaped formats."""
    rtype = obj.get("type")

    if rtype == "queue-operation":
        content = obj.get("content")
        if isinstance(content, str) and content.strip():
            yield ("user", content)
        return

    msg = obj.get("message")
    role = None
    content = None
    if isinstance(msg, dict):
        role = msg.get("role")
        content = msg.get("content")
    elif "role" in obj:
        role = obj.get("role")
        content = obj.get("content")

    if role not in ("user", "assistant") or content is None:
        return

    if isinstance(content, str):
        text = content
        if role == "user" and (
            "<system-reminder>" in text
            or "<local-command-stdout>" in text
            or "<bash-input>" in text
        ):
            role = "tool"
        if text.strip():
            yield (role, text)
        return

    if not isinstance(content, list):
        return

    for block in content:
        if not isinstance(block, dict):
            continue
        btype = block.get("type")
        if btype in ("text", "output_text", "input_text"):
            text = block.get("text", "")
            if text.strip():
                yield (role, text)
        elif btype == "tool_use":
            name = block.get("name", "")
            try:
                inp = json.dumps(block.get("input", {}))[:2000]
            except TypeError:
                inp = str(block.get("input"))[:2000]
            yield ("tool", f"[tool_use {name}] {inp}")
        elif btype == "tool_result":
            out = block.get("content")
            if isinstance(out, list):
                out = "\n".join(
                    x.get("text", "") for x in out if isinstance(x, dict) and x.get("type") == "text"
                )
            if out:
                yield ("tool", str(out)[:4000])


def flatten_transcript(path):
    """Read the transcript once; return a flat list of (role, line_text)
    pairs, one entry per newline inside every extracted text block, in
    file order. This is the substrate --context windows are cut from."""
    lines = []
    try:
        with open(path, "r", errors="ignore") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    obj = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if not isinstance(obj, dict):
                    continue
                for role, text in iter_text_events(obj):
                    for line in text.split("\n"):
                        lines.append((role, line))
    except OSError:
        return None
    return lines


def grep_snippets(lines, terms, context, max_snippets):
    pattern = re.compile("|".join(re.escape(t) for t in terms), re.IGNORECASE)
    hit_idx = [i for i, (_, text) in enumerate(lines) if pattern.search(text)]
    if not hit_idx:
        return []

    windows = []
    for i in hit_idx:
        lo, hi = max(0, i - context), min(len(lines) - 1, i + context)
        if windows and lo <= windows[-1][1] + 1:
            windows[-1] = (windows[-1][0], hi, windows[-1][2] | {i})
        else:
            windows.append((lo, hi, {i}))
        if len(windows) >= max_snippets * 3:
            break

    snippets = []
    for lo, hi, hit_set in windows[:max_snippets]:
        window_lines = lines[lo:hi + 1]
        roles_hit = {lines[i][0] for i in hit_set}
        text = "\n".join(f"{role:>9}: {line}" for role, line in window_lines if line.strip())
        if text:
            snippets.append({"roles": sorted(roles_hit), "text": text})
    return snippets[:max_snippets]


def build_digest(candidates, terms, context, max_snippets):
    digest = []
    for c in candidates:
        path = resolve_transcript_path(c["filePath"])
        if not os.path.exists(path):
            continue
        lines = flatten_transcript(path)
        if not lines:
            continue
        snippets = grep_snippets(lines, terms, context, max_snippets)
        if not snippets:
            continue
        why = sorted({role for s in snippets for role in s["roles"]} | set(c["via"]))
        digest.append({
            "shortId": c["shortId"],
            "id": c["id"],
            "agent": c["agent"],
            "project": c["project"],
            "date": (c["timestamp"] or "")[:10],
            "topic": (c["topic"] or "")[:120],
            "why": why,
            "snippets": snippets,
            "resume": f"agents sessions resume {c['shortId']}",
        })
    return digest


def render_text(digest, terms):
    if not digest:
        print(f"No hits for: {' '.join(terms)}")
        return
    print(f"recall: {' '.join(terms)}  ({len(digest)} session(s))\n")
    for d in digest:
        print(f"[{d['shortId']}] {d['date']}  {d['project']}  (via: {', '.join(d['why'])})")
        if d["topic"]:
            print(f"  {d['topic']}")
        for s in d["snippets"]:
            for line in s["text"].splitlines():
                print(f"    {line}")
            print("    ---")
        print(f"  -> {d['resume']}\n")


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if not os.path.exists(DB_PATH):
        print(f"error: sessions index not found at {DB_PATH}", file=sys.stderr)
        return 1

    since = parse_since(args.since)
    conn = open_db()
    try:
        candidates = find_candidates(conn, args.terms, args.project, since, args.limit)
    finally:
        conn.close()

    digest = build_digest(candidates, args.terms, args.context, args.snippets)

    if args.json:
        print(json.dumps({"query": args.terms, "hits": digest}, indent=2))
    else:
        render_text(digest, args.terms)
    return 0 if digest else 3


if __name__ == "__main__":
    sys.exit(main())
