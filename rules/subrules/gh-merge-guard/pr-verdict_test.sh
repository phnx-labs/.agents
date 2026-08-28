#!/usr/bin/env bash
# Contract tests for pr-verdict.py — the shared merge-guard / pr-merge-on-green
# verdict. Feeds the same stdin shape the shell callers pipe: three
# base64-encoded segments (reviews JSON, comments JSON, PR author login)
# joined by ---AGENTS-SPLIT---. No network.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
PY="$DIR/pr-verdict.py"
pass=0
fail=0

# Fixtures below carry "user":{"login":"reviewer-bot"} (non-author) unless a
# test is specifically exercising the PHNX-3236 self-authored path, in which
# case the fixture's login matches AUTHOR below.
AUTHOR="pr-author-bot"

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

check() {
  want=$1
  desc=$2
  reviews=$3
  comments=$4
  author=${5:-$AUTHOR}
  got=$(printf '%s\n---AGENTS-SPLIT---\n%s\n---AGENTS-SPLIT---\n%s' "$(b64 "$reviews")" "$(b64 "$comments")" "$(b64 "$author")" | python3 "$PY" | tr -d '\n')
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s (want %s, got %s)\n' "$desc" "$want" "$got"
  fi
}

check ok "GitHub APPROVED review" '[{"state":"APPROVED","user":{"login":"reviewer-bot"}}]' '[]'
check ok "fresh APPROVE comment" '[]' '[{"user":{"login":"reviewer-bot"},"body":"## Verdict: APPROVE\nRe-verified both findings."}]'
# RUSH-3080: fleet agents cannot `gh pr review --approve` (self-approval blocked),
# so a verdict often arrives as a state=COMMENTED review body via
# `gh pr review --comment`. That must clear the guard too, not only issue comments.
check ok "APPROVE in a state=COMMENTED review body" '[{"state":"COMMENTED","user":{"login":"reviewer-bot"},"body":"VERDICT: APPROVE\nRe-verified, docs-only."}]' '[]'
check missing "carried-from in a review body" '[{"state":"COMMENTED","user":{"login":"reviewer-bot"},"body":"APPROVE carried from #2731."}]' '[]'
check missing "non-approving review body" '[{"state":"COMMENTED","user":{"login":"reviewer-bot"},"body":"VERDICT: REQUEST CHANGES\nem-dash cap violated."}]' '[]'
# RUSH-3080 blocker (caught in review): a review body is only trusted when its
# own state is COMMENTED. A CHANGES_REQUESTED or DISMISSED review whose body
# contains the word APPROVE must NOT launder itself into an approval.
check missing "CHANGES_REQUESTED review body mentioning APPROVE" '[{"state":"CHANGES_REQUESTED","user":{"login":"reviewer-bot"},"body":"I cannot APPROVE until the null check is fixed."}]' '[]'
check missing "DISMISSED stale approving review body" '[{"state":"DISMISSED","user":{"login":"reviewer-bot"},"body":"VERDICT: APPROVE"}]' '[]'
# RUSH-3080: a reviewer quoting pr-verdict.py's own stdin contract puts the
# literal ---AGENTS-SPLIT--- marker in the comment body. rpartition on the
# author section, then maxsplit=1 on the first marker, keeps the whole
# comments JSON in one piece so it still parses and the verdict is read.
check ok "APPROVE comment that quotes the split marker still clears" '[]' '[{"user":{"login":"reviewer-bot"},"body":"VERDICT: APPROVE\nvalidated via: printf %s ---AGENTS-SPLIT--- %s | pr-verdict.py"}]'
check missing "no verdict" '[]' '[{"user":{"login":"reviewer-bot"},"body":"looks big, did not review"}]'
check missing "carried from another PR" '[]' '[{"user":{"login":"reviewer-bot"},"body":"Non-author APPROVE carried from #2731."}]'
check missing "APPROVE on #N citation" '[]' '[{"user":{"login":"reviewer-bot"},"body":"Non-author APPROVE on #2731 covers this."}]'
# RUSH-3099: the past tense is the natural word AND GitHub's own review state,
# and the guard's own block message says "Post a GitHub APPROVED review" -- so a
# reviewer writing **APPROVED.** was rejected by the very form it was told to
# use. Real incident: agi-cli#2972, CI green, verdict correct, merge blocked.
check ok "APPROVED (past tense) in an issue comment" '[]' '[{"user":{"login":"reviewer-bot"},"body":"## Verdict\n**APPROVED.**"}]'
check ok "APPROVED in a state=COMMENTED review body" '[{"state":"COMMENTED","user":{"login":"reviewer-bot"},"body":"Verdict at 641f33cf3: APPROVED."}]' '[]'
check ok "bare stem APPROVE still clears" '[]' '[{"user":{"login":"reviewer-bot"},"body":"VERDICT: APPROVE"}]'
check missing "explicit refusal does not approve" '[]' '[{"user":{"login":"reviewer-bot"},"body":"I do NOT APPROVE"}]'
check missing "cannot approve does not approve" '[]' '[{"user":{"login":"reviewer-bot"},"body":"cannot APPROVE until tests pass"}]'
check missing "fenced approval sample does not approve" '[]' '[{"user":{"login":"reviewer-bot"},"body":"Example:\n```text\nVERDICT: APPROVE\n```"}]'
check missing "inline approval sample does not approve" '[]' '[{"user":{"login":"reviewer-bot"},"body":"Use `VERDICT: APPROVE` after review."}]'
# The optional D has to be in the CARRIED filter too, or widening the verdict
# regex silently reopens the #2736 laundering pattern for the past tense only.
check missing "APPROVED on #N citation is still laundering" '[]' '[{"user":{"login":"reviewer-bot"},"body":"Non-author APPROVED on #2731 covers this."}]'
check missing "APPROVED carried from another PR" '[{"state":"COMMENTED","user":{"login":"reviewer-bot"},"body":"APPROVED carried from #2731."}]' '[]'
check missing "CHANGES_REQUESTED body saying APPROVED does not launder" '[{"state":"CHANGES_REQUESTED","user":{"login":"reviewer-bot"},"body":"Not APPROVED until the null check is fixed."}]' '[]'
# Guard the word boundary itself: a longer word starting with APPROVE must not
# clear. Without \b this would match, and "APPROVES"/"APPROVEDLY" are the kind
# of prose a reviewer writes about someone else's verdict.
check missing "APPROVES is not a verdict" '[]' '[{"user":{"login":"reviewer-bot"},"body":"The other reviewer APPROVES of this direction."}]'

check missing "empty both" '[]' '[]'

# PHNX-3236: self-merge bypass. A fleet identity that opened the PR posting
# its own "APPROVE" must NOT clear the guard, in any of the three shapes a
# non-author verdict can legitimately take.
check missing "self-authored COMMENTED review body saying APPROVE does not clear" \
  '[{"state":"COMMENTED","user":{"login":"pr-author-bot"},"body":"VERDICT: APPROVE"}]' '[]'
check missing "self-authored issue comment saying APPROVE does not clear" \
  '[]' '[{"user":{"login":"pr-author-bot"},"body":"VERDICT: APPROVE"}]'
check missing "self-authored issue comment saying APPROVED does not clear" \
  '[]' '[{"user":{"login":"pr-author-bot"},"body":"**APPROVED.**"}]'
check missing "self-authored formal APPROVED review does not clear (defense in depth)" \
  '[{"state":"APPROVED","user":{"login":"pr-author-bot"}}]' '[]'
# The exact bypass shape: the PR's own author is the ONLY reviewer, and the
# only thing on the PR is their own comment.
check missing "sole reviewer is the PR author" \
  '[{"state":"COMMENTED","user":{"login":"pr-author-bot"},"body":"lgtm, APPROVE"}]' \
  '[{"user":{"login":"pr-author-bot"},"body":"self-merging, APPROVE"}]'
# A genuine non-author verdict alongside a self-authored comment must still
# clear — the self-authored one is just ignored, not poisoning the whole PR.
check ok "non-author APPROVE clears even with a self-authored comment present too" \
  '[]' '[{"user":{"login":"pr-author-bot"},"body":"bumping this"},{"user":{"login":"reviewer-bot"},"body":"VERDICT: APPROVE"}]'
# Case-insensitive login comparison — GitHub logins are case-insensitive.
check missing "author comparison is case-insensitive" \
  '[]' '[{"user":{"login":"PR-Author-Bot"},"body":"VERDICT: APPROVE"}]'
# No user field at all on an item (defensive: must not crash, must not clear
# via an unidentifiable author).
check ok "item with no user field is treated as non-author (not excluded)" \
  '[]' '[{"body":"VERDICT: APPROVE"}]'

# pr-merge-on-green.sh feeds `gh pr view --json reviews,comments` payloads,
# which key the author as `author.login` (GraphQL shape), not `user.login`
# (the REST shape merge-guard.sh feeds). Both must be recognized.
check missing "self-authored review in the author.login (GraphQL) shape does not clear" \
  '[{"state":"COMMENTED","author":{"login":"pr-author-bot"},"body":"VERDICT: APPROVE"}]' '[]'
check missing "self-authored comment in the author.login (GraphQL) shape does not clear" \
  '[]' '[{"author":{"login":"pr-author-bot"},"body":"VERDICT: APPROVE"}]'
check ok "non-author comment in the author.login (GraphQL) shape still clears" \
  '[]' '[{"author":{"login":"reviewer-bot"},"body":"VERDICT: APPROVE"}]'

# Live bug, reproduced reviewing PHNX-3236 itself (not hypothetical): a
# REVIEW body — not just a comment, the only case RUSH-3080 tested — quoting
# this file's own stdin-contract marker corrupted a plain-text split: the
# FIRST "---AGENTS-SPLIT---" in the whole raw string landed inside the
# reviews JSON, so both reviews and comments failed to parse and a genuine
# non-author APPROVE read as "missing". Base64-encoding each segment (this
# test's `b64` helper, matching the real shell callers) makes the marker
# structurally impossible to embed, so this must clear regardless of how
# many times the review body quotes it.
check ok "review body quoting the split marker still clears (reviews-side corruption)" \
  '[{"state":"COMMENTED","user":{"login":"reviewer-bot"},"body":"the stdin contract is <reviews>---AGENTS-SPLIT---<comments>---AGENTS-SPLIT---<author>. VERDICT: APPROVE"}]' \
  '[]'
check ok "review body quoting the marker four times still clears" \
  '[{"state":"COMMENTED","user":{"login":"reviewer-bot"},"body":"---AGENTS-SPLIT--- ---AGENTS-SPLIT--- ---AGENTS-SPLIT--- ---AGENTS-SPLIT--- VERDICT: APPROVE"}]' \
  '[]'
check missing "self-authored review quoting the marker still does not clear" \
  '[{"state":"COMMENTED","user":{"login":"pr-author-bot"},"body":"see ---AGENTS-SPLIT--- in the docstring. VERDICT: APPROVE"}]' \
  '[]'

printf -- '---\npr-verdict: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
