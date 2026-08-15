#!/usr/bin/env python3
"""Order `gh pr list --state merged` rows by mergedAt, newest first.

`gh pr list` has no --sort and returns creation-date order, so the most recently
merged PR is not necessarily first: a long-lived PR that just landed gets pushed
out of the window by newer-created-but-earlier-merged ones. Verified against
agents-cli, where #2734 merged most recently and ranked third. For a section
whose entire job is "what just landed", that is the wrong order.

Reads the raw --json array on stdin, writes "- #N title" lines. argv[1] caps the
count. Any parse failure prints nothing and exits 0 — this feeds a SessionStart
brief, which must degrade rather than wedge.
"""
import json
import sys

try:
    rows = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if not isinstance(rows, list):
    sys.exit(0)

try:
    limit = int(sys.argv[1])
except (IndexError, ValueError):
    limit = 5

rows = [r for r in rows if isinstance(r, dict) and r.get("mergedAt")]
rows.sort(key=lambda r: r["mergedAt"], reverse=True)

for row in rows[:limit]:
    number = row.get("number")
    title = row.get("title") or ""
    if number is not None:
        sys.stdout.write("- #%s %s\n" % (number, title))
