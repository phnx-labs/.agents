#!/usr/bin/env python3
"""Shared PR verdict check used by merge-guard.sh and pr-merge-on-green.

A PR is merge-clearing when EITHER:
  - a GitHub review has state APPROVED, OR
  - a whole-word APPROVE or APPROVED that is not a carried-from citation (the #2736
    laundering pattern) appears in the body of a COMMENTED review
    (`gh pr review --comment` — the fleet convention when self-approval is
    blocked) or an issue comment, POSTED BY SOMEONE OTHER THAN THE PR's AUTHOR.
    A CHANGES_REQUESTED or DISMISSED review body never clears the guard even if
    it contains the word APPROVE.

PHNX-3236: a real GitHub APPROVED review can never be self-authored (GitHub's
API rejects it), but a COMMENTED review body or an issue comment has no such
protection — every fleet agent shares one GitHub identity, so the PR's own
author could post "VERDICT: APPROVE" as a comment on their own PR and clear
the guard. `has_verdict` now takes the PR author's login and excludes any
review/comment authored by that same login from the body-approve check before
looking for the verdict text.

Stdin contract: three base64-encoded segments joined by the line
`---AGENTS-SPLIT---` — reviews JSON, comments JSON, PR author login. Encoding
each segment (rather than piping raw JSON with plain-text markers, the
original design) is load-bearing: a review or comment discussing this very
file — which happened live reviewing PHNX-3236 itself — can quote the marker
string verbatim in its OWN body, and a plain-text split has no way to tell a
quoted marker from a real one. Splitting on ANY occurrence corrupts the JSON
on both sides of it, both `reviews` and `comments` fail to parse, and a
genuine approval reads as "missing" (a live, reproduced false negative, not
a hypothetical one — see PHNX-3236 PR history). The base64 alphabet (RFC 4648)
contains no hyphen, so an encoded segment can never contain
`---AGENTS-SPLIT---` — the ambiguity is structurally impossible rather than
merely handled by careful split-direction bookkeeping. Prints `ok` or
`missing`. Exit 0 on a successful parse so merge-guard's `|| _verdict=ok`
fail-open still means "python crashed", not "no verdict".
"""
from __future__ import annotations

import base64
import json
import re
import sys

SPLIT = "---AGENTS-SPLIT---"

# `APPROVED` is both the natural English word and GitHub's own review state, and
# the block message itself says "Post a GitHub APPROVED review" -- so matching
# only the bare stem rejected the exact form it asked for. The optional D must
# be in the CARRIED filter too, or `APPROVED on #1234` walks straight past the
# laundering check that `APPROVE on #1234` is caught by (RUSH-3099).
CARRIED = re.compile(
    r"\bcarried\s+(?:over\s+)?from\b|\bAPPROVED?\s+(?:on|from)\s+#\d+",
    re.I,
)
APPROVE = re.compile(r"\bAPPROVED?\b")


def _b64_decode_text(segment: str) -> str:
    """Decode one base64 stdin segment to text. Empty/malformed input decodes
    to "" rather than raising — callers treat "" the same as "not provided"."""
    try:
        return base64.b64decode(segment.strip()).decode("utf-8", errors="replace")
    except Exception:
        return ""


def _b64_decode_json(segment: str):
    """Decode one base64 stdin segment as JSON. Returns None on any decode or
    parse failure — has_verdict already treats non-list reviews/comments as
    empty, so a corrupt segment degrades to "no verdict found" rather than
    crashing."""
    try:
        return json.loads(_b64_decode_text(segment))
    except Exception:
        return None


def _item_login(it: dict) -> str:
    """The item's author login. merge-guard.sh feeds REST API payloads
    (`gh api repos/.../pulls/.../reviews`, `.../issues/.../comments`), which key
    the author as `user.login`; pr-merge-on-green.sh feeds GraphQL-shaped
    payloads (`gh pr view --json reviews,comments`), which key it as
    `author.login` instead. Same data, two different `gh` surfaces — check
    both rather than requiring callers to normalize first."""
    user = it.get("user") or {}
    if user.get("login"):
        return user["login"]
    author = it.get("author") or {}
    return author.get("login") or ""


def _exclude_self_authored(items, pr_author: str):
    """Drop any review/comment whose author is the PR's own author. An empty
    login on either side never matches a real GitHub username, so this is a
    no-op (nothing excluded) when the caller could not resolve pr_author —
    the caller-side gate in merge-guard.sh/pr-merge-on-green.sh is what
    decides whether to run the whole verdict check at all in that case."""
    if not isinstance(items, list):
        return []
    author_cf = pr_author.strip().casefold()
    kept = []
    for it in items:
        login = _item_login(it).casefold()
        if login and author_cf and login == author_cf:
            continue
        kept.append(it)
    return kept


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


def has_verdict(reviews, comments, pr_author: str) -> bool:
    # PHNX-3236: exclude anything authored by the PR's own author FIRST, from
    # both reviews and comments, before checking state or body text. GitHub's
    # API does reject an attempt to submit a formal APPROVED review on your
    # own PR, so that specific case could never happen via normal `gh pr
    # review --approve` — but every fleet agent shares one GitHub identity,
    # and nothing stops that same identity from posting a COMMENTED review or
    # a plain issue comment on its own PR. Filtering reviews uniformly (rather
    # than only comments) is defense-in-depth against any path — an admin
    # override, a different bot with write access on the same PR — that could
    # otherwise produce a self-authored APPROVED review too.
    non_author_reviews = _exclude_self_authored(
        reviews if isinstance(reviews, list) else [], pr_author
    )
    non_author_comments = _exclude_self_authored(
        comments if isinstance(comments, list) else [], pr_author
    )
    # A GitHub review with state APPROVED clears it outright.
    if any(r.get("state") == "APPROVED" for r in non_author_reviews):
        return True
    # Fleet agents cannot `gh pr review --approve` (GitHub blocks approving
    # your own PR), so a non-author APPROVE arrives as a verdict in the BODY
    # of a COMMENTED review (`gh pr review --comment`) or an issue comment
    # (`gh pr comment`) — reading only issue comments silently ignored a
    # genuine review-body verdict and blocked the merge (RUSH-3080). Only
    # COMMENTED review bodies count: a CHANGES_REQUESTED or DISMISSED review
    # whose body happens to contain APPROVE must NOT clear the guard, or a
    # rejecting/stale review would launder itself into an approval.
    commented = [r for r in non_author_reviews if r.get("state") == "COMMENTED"]
    return _body_approves(commented) or _body_approves(non_author_comments)


def verdict_from_stdin(raw: str) -> str:
    # Three base64 segments joined by the plain-text marker. None of the
    # three can themselves contain "---AGENTS-SPLIT---" post-encoding (see
    # the module docstring), so an unbounded split on the marker always
    # yields exactly the three segments merge-guard.sh/pr-merge-on-green.sh
    # wrote, regardless of what any review or comment body quotes.
    parts = raw.split(SPLIT)
    reviews = _b64_decode_json(parts[0]) if len(parts) > 0 else None
    comments = _b64_decode_json(parts[1]) if len(parts) > 1 else None
    pr_author = _b64_decode_text(parts[2]).strip() if len(parts) > 2 else ""
    if has_verdict(reviews, comments, pr_author):
        return "ok"
    return "missing"


def main() -> int:
    raw = sys.stdin.read()
    sys.stdout.write(verdict_from_stdin(raw))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
