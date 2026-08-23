#!/usr/bin/env python3
"""Shared PR verdict check used by merge-guard.sh and pr-merge-on-green.

A PR is merge-clearing when EITHER:
  - a GitHub review has state APPROVED, OR
  - a whole-word APPROVE that is not a carried-from citation (the #2736
    laundering pattern) appears in the body of a COMMENTED review
    (`gh pr review --comment` — the fleet convention when self-approval is
    blocked) or an issue comment. A CHANGES_REQUESTED or DISMISSED review body
    never clears the guard even if it contains the word APPROVE.

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


def _body_approves(items) -> bool:
    """True if any item has a whole-word APPROVE body that is not a carried-from
    citation. Applies to both review bodies and issue-comment bodies."""
    if not isinstance(items, list):
        return False
    for it in items:
        body = it.get("body") or ""
        if not APPROVE.search(body):
            continue
        if CARRIED.search(body):
            continue
        return True
    return False


def has_verdict(reviews, comments) -> bool:
    # A GitHub review with state APPROVED clears it outright.
    if isinstance(reviews, list) and any(r.get("state") == "APPROVED" for r in reviews):
        return True
    # Fleet agents share one GitHub identity and cannot `gh pr review --approve`
    # (GitHub blocks approving your own PR), so a non-author APPROVE arrives as a
    # verdict in the BODY of a COMMENTED review (`gh pr review --comment`) or an
    # issue comment (`gh pr comment`) — reading only issue comments silently
    # ignored a genuine review-body verdict and blocked the merge (RUSH-3080).
    # Only COMMENTED review bodies count: a CHANGES_REQUESTED or DISMISSED review
    # whose body happens to contain APPROVE must NOT clear the guard, or a
    # rejecting/stale review would launder itself into an approval.
    commented = [r for r in reviews if r.get("state") == "COMMENTED"] if isinstance(reviews, list) else []
    return _body_approves(commented) or _body_approves(comments)


def verdict_from_stdin(raw: str) -> str:
    # Split on the FIRST marker only: merge-guard writes exactly one
    # `<reviews>\n---AGENTS-SPLIT---\n<comments>`, and a review or comment body
    # can legitimately quote the marker (e.g. a reviewer pasting pr-verdict.py's
    # own stdin contract). maxsplit=1 keeps all of the comments JSON — markers
    # and all — inside parts[1] so it still parses (RUSH-3080).
    parts = raw.split(SPLIT, 1)
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
