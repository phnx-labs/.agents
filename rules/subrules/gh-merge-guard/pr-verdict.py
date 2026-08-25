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

Stdin contract (kept as close as possible to the python that used to be
inlined in merge-guard.sh): reviews JSON, then the line `---AGENTS-SPLIT---`,
then comments JSON, then a second `---AGENTS-SPLIT---`, then the PR author's
login. Prints `ok` or `missing`. Exit 0 on a successful parse so merge-guard's
`|| _verdict=ok` fail-open still means "python crashed", not "no verdict".
"""
from __future__ import annotations

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
    # Split on the FIRST marker only to separate reviews from everything else:
    # merge-guard writes exactly one
    # `<reviews>\n---AGENTS-SPLIT---\n<comments>\n---AGENTS-SPLIT---\n<pr_author>`,
    # and a review or comment body can legitimately quote the marker (e.g. a
    # reviewer pasting this file's own stdin contract). maxsplit=1 here keeps
    # everything after the first marker — comments JSON, markers and all,
    # plus the trailing author section — together for the next step
    # (RUSH-3080).
    parts = raw.split(SPLIT, 1)
    reviews = None
    comments = None
    pr_author = ""
    try:
        reviews = json.loads(parts[0])
    except Exception:
        reviews = None
    if len(parts) > 1:
        remainder = parts[1]
        # The author section is appended LAST and is a bare login — it can
        # never itself contain the marker — so the real second delimiter is
        # guaranteed to be the RIGHTMOST occurrence of SPLIT in `remainder`.
        # rpartition from the right leaves any marker text quoted inside the
        # comments JSON (which sits to the left of the real delimiter) intact
        # in comments_raw, exactly like the first split does for reviews.
        if SPLIT in remainder:
            comments_raw, _, author_raw = remainder.rpartition(SPLIT)
            pr_author = author_raw.strip()
        else:
            comments_raw = remainder
        try:
            comments = json.loads(comments_raw)
        except Exception:
            comments = None
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
