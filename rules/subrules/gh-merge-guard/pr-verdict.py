#!/usr/bin/env python3
"""Shared PR verdict check used by merge-guard.sh and pr-merge-on-green.

A PR is merge-clearing when EITHER:
  - a GitHub review has state APPROVED, OR
  - a whole-word APPROVE or APPROVED that is not a carried-from citation (the #2736
    laundering pattern), does not have a refusal attached to THAT token
    (PHNX-3118 — "NOT APPROVED", "do not approve", "refuse to APPROVE"), and is
    not merely QUOTED inside fenced/inline code (PHNX-3118)
    appears in the body of a COMMENTED review
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

# PHNX-3118: matching a bare APPROVE anywhere in the body has no notion of
# whether the body is USING the word as a verdict or NEGATING it. An explicit
# refusal — "I have NOT APPROVED this yet", "do not approve; not APPROVED", a
# COMMENTED review reading "NOT APPROVED - see below" — contains the whole word
# APPROVE(D) and cleared the guard.
#
# Negation is judged per APPROVE token by WORD-COUNT proximity, and a refusal on
# ANY token vetoes the whole item. Two failure modes shaped this:
#
#   * A fixed connector allowlist ("not <yet|be|to> approve") let any other
#     adverb through — "do not CURRENTLY approve", "would not PERSONALLY approve"
#     cleared the gate. So a cue counts when it sits within NEGATION_MAX_WORDS
#     words of the token, whatever those words are — "not <=3 words> approve".
#     That still lets an incidental negation many words upstream go by:
#     "I have not found any other issues, APPROVE" keeps clearing.
#   * Returning True on the FIRST un-negated token let a bare mention outvote an
#     explicit refusal in the same body — "I do NOT APPROVE this. ... APPROVE"
#     laundered a rejection into a pass, the exact PHNX-3118 vulnerability. So if
#     ANY token in an item is negated, the whole item is vetoed to "no verdict".
#
# Bare "no" attaches to nouns ("no issues, APPROVE"), so it only counts when it
# sits IMMEDIATELY before the token ("no APPROVE from me"); the verb-governing
# cues ("not", "cannot", "do not", "refuse to", …) get the full word window.
#
# Proximity is measured within the token's own CLAUSE (bounded by . ; : ! ?
# newline —): a negation in a PRIOR sentence does not govern the verdict, so
# "Cannot fault this diff. APPROVE" and "…is not already covered. VERDICT:
# APPROVE" clear. Word-count and clause scope compose — the cue must be both in
# the same clause AND within the word window — so neither an upstream noun-
# negation ("not a single nit left, so APPROVE") nor a prior-sentence one blocks.
#
# The guard's documented bias is false-negatives over false-positives — it only
# ever blocks a merge, never launders a rejection — so an ambiguous body that
# pairs a refusal with a bare mention resolves to "missing", never "ok".
NEGATION_LOOKBACK = 96
CLAUSE_BOUNDARY = re.compile(r"[.;:!?\n\r—]")
NEGATED_NEAR = re.compile(
    r"\b(?:"
    r"not|never|cannot|can\s*not|"
    r"can'?t|wo\s*n'?t|won'?t|do\s*n'?t|does\s*n'?t|did\s*n'?t|"
    r"should\s*n'?t|would\s*n'?t|could\s*n'?t|"
    r"is\s*n'?t|are\s*n'?t|was\s*n'?t|were\s*n'?t|"
    r"has\s*n'?t|have\s*n'?t|had\s*n'?t|"
    r"(?:do|does|did|will|would|shall|should|could|can|is|are|was|were|"
    r"has|have|had)\s+not|"
    r"refuse[sd]?\s+to|refusing\s+to|declin(?:e|es|ed|ing)\s+to|"
    r"unable\s+to|unwilling\s+to|holding\s+off\s+(?:on|from)"
    r")\b(?:\W+\w+){0,3}\W*$",
    re.I,
)
NEGATED_ADJACENT = re.compile(r"\bno\W*$", re.I)


def _token_negated(body: str, start: int) -> bool:
    """True if a refusal governs the APPROVE token at ``start`` — a verb-shaped
    negation cue within NEGATED_NEAR's word window, or a bare "no" immediately
    before the token, AND within the token's own clause. The clause runs from the
    nearest boundary char left of the token (or NEGATION_LOOKBACK back, whichever
    is closer), so a negation in a prior sentence ("Cannot fault this diff.
    APPROVE") or many words upstream ("…any other issues, APPROVE") never
    suppresses a live verdict."""
    seg_start = max(0, start - NEGATION_LOOKBACK)
    for b in CLAUSE_BOUNDARY.finditer(body, 0, start):
        if b.end() > seg_start:
            seg_start = b.end()
    left = body[seg_start:start]
    return bool(NEGATED_NEAR.search(left) or NEGATED_ADJACENT.search(left))

# PHNX-3118: a verdict token that is only being DISCUSSED — quoted inside a
# fenced code block (``` … ```) or an inline code span (` … `), which is exactly
# how a review of THIS parser talks about the word APPROVE — is not a real
# verdict. Strip both before matching so a body whose ONLY APPROVE is inside code
# reads as "no verdict" rather than clearing the guard (same false-positive shape
# as the footer-guard). Fenced blocks are removed first so their inner backticks
# can't confuse the inline pass.
#
# The inline span must be BALANCED and SINGLE-LINE: an opening run of N backticks
# closed by a run of the same length (\1) on the same line. The earlier
# `+[^`]*`+ paired ANY backtick with the next one anywhere later in the body, so
# one stray unclosed backtick plus an ordinary code span further down silently
# swallowed everything between them — including a real out-of-code VERDICT:
# APPROVE (PHNX-3118 review 4). Requiring a same-length close and forbidding
# newlines inside bounds the strip to a genuine span and stops the swallow.
FENCED_CODE = re.compile(r"```.*?```|~~~.*?~~~", re.S)
INLINE_CODE = re.compile(r"(`+)[^\n]*?\1")


def _strip_code(body: str) -> str:
    """Blank fenced code blocks and inline code spans (replaced by a space so
    surrounding word boundaries are preserved) so a quoted/discussed verdict
    token is not read as a live verdict."""
    return INLINE_CODE.sub(" ", FENCED_CODE.sub(" ", body))


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
    """True if any item carries a live APPROVE verdict. Applies to both review
    bodies and issue-comment bodies.

    The check is DELIBERATELY ASYMMETRIC between the raw and code-stripped body,
    and that asymmetry is what makes code-stripping unable to launder a rejection
    (PHNX-3118 review 5):

      * The VETO signals — a "carried from #NNNN" citation (RUSH-3099) and a
        negated APPROVE token (_token_negated) — are checked on the RAW body. A
        refusal like "I do NOT APPROVE this" vetoes the item even if _strip_code
        would have swallowed it between a stray backtick and an unrelated code
        span. _strip_code cannot perfectly tell a real code delimiter from an
        accidental one, so if it could delete a refusal the guard would clear a
        rejection — the one thing the charter forbids. Checking the veto on raw
        removes that path by construction.
      * The POSITIVE signal — the presence of a live APPROVE token — is checked
        on the code-STRIPPED body, so a token merely quoted inside code (exactly
        how a review of THIS parser discusses the word) never clears the guard.

    Net: the worst a _strip_code imperfection can now do is drop a real approve
    from the positive pass (wrongly BLOCK — the safe, documented-bias direction),
    never hide a refusal (launder — forbidden). An item clears only when its raw
    body carries neither a carried-citation nor any negated APPROVE token, AND
    its code-stripped body still has at least one un-negated APPROVE token."""
    if not isinstance(items, list):
        return False
    for it in items:
        raw = it.get("body") or ""
        # VETO on raw — immune to code-stripping.
        if CARRIED.search(raw):
            continue
        if any(_token_negated(raw, m.start()) for m in APPROVE.finditer(raw)):
            continue
        # POSITIVE on the code-stripped body — a quoted token does not clear.
        stripped = _strip_code(raw)
        tokens = list(APPROVE.finditer(stripped))
        if not tokens:
            continue
        if any(_token_negated(stripped, m.start()) for m in tokens):
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
