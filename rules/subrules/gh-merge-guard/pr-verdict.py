#!/usr/bin/env python3
"""Shared PR verdict check used by merge-guard.sh and pr-merge-on-green.

A PR is merge-clearing when EITHER:
  - a GitHub review has state APPROVED, OR
  - an issue/PR comment body contains a whole-word APPROVE that is not a
    carried-from citation (the #2736 laundering pattern).

Stdin contract (kept identical to the python that used to be inlined in
merge-guard.sh): reviews JSON, then the line `---AGENTS-SPLIT---`, then
comments JSON. Prints `ok` or `missing`. Exit 0 on a successful parse so
merge-guard's `|| _verdict=ok` fail-open still means "python crashed", not
"no verdict".
"""
from __future__ import annotations

import json
import re
import sys

SPLIT = "---AGENTS-SPLIT---"

CARRIED = re.compile(
    r"\bcarried\s+(?:over\s+)?from\b|\bAPPROVE\s+(?:on|from)\s+#\d+",
    re.I,
)
APPROVE = re.compile(r"\bAPPROVE\b")


def has_verdict(reviews, comments) -> bool:
    if isinstance(reviews, list) and any(r.get("state") == "APPROVED" for r in reviews):
        return True
    if not isinstance(comments, list):
        return False
    for c in comments:
        body = c.get("body") or ""
        if not APPROVE.search(body):
            continue
        if CARRIED.search(body):
            continue
        return True
    return False


def verdict_from_stdin(raw: str) -> str:
    parts = raw.split(SPLIT)
    reviews = None
    comments = None
    try:
        reviews = json.loads(parts[0])
    except Exception:
        reviews = None
    if len(parts) > 1:
        try:
            comments = json.loads(parts[1])
        except Exception:
            comments = None
    if has_verdict(reviews, comments):
        return "ok"
    return "missing"


def main() -> int:
    raw = sys.stdin.read()
    sys.stdout.write(verdict_from_stdin(raw))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
