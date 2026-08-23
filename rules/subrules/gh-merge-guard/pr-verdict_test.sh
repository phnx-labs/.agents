#!/usr/bin/env bash
# Contract tests for pr-verdict.py — the shared merge-guard / pr-merge-on-green
# verdict. Feeds the same stdin shape merge-guard.sh pipes (reviews JSON,
# ---AGENTS-SPLIT---, comments JSON). No network.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
PY="$DIR/pr-verdict.py"
pass=0
fail=0

check() {
  want=$1
  desc=$2
  reviews=$3
  comments=$4
  got=$(printf '%s\n---AGENTS-SPLIT---\n%s' "$reviews" "$comments" | python3 "$PY" | tr -d '\n')
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s (want %s, got %s)\n' "$desc" "$want" "$got"
  fi
}

check ok "GitHub APPROVED review" '[{"state":"APPROVED"}]' '[]'
check ok "fresh APPROVE comment" '[]' '[{"body":"## Verdict: APPROVE\nRe-verified both findings."}]'
# RUSH-3080: fleet agents cannot `gh pr review --approve` (self-approval blocked),
# so a verdict often arrives as a state=COMMENTED review body via
# `gh pr review --comment`. That must clear the guard too, not only issue comments.
check ok "APPROVE in a state=COMMENTED review body" '[{"state":"COMMENTED","body":"VERDICT: APPROVE\nRe-verified, docs-only."}]' '[]'
check missing "carried-from in a review body" '[{"state":"COMMENTED","body":"APPROVE carried from #2731."}]' '[]'
check missing "non-approving review body" '[{"state":"COMMENTED","body":"VERDICT: REQUEST CHANGES\nem-dash cap violated."}]' '[]'
# RUSH-3080 blocker (caught in review): a review body is only trusted when its
# own state is COMMENTED. A CHANGES_REQUESTED or DISMISSED review whose body
# contains the word APPROVE must NOT launder itself into an approval.
check missing "CHANGES_REQUESTED review body mentioning APPROVE" '[{"state":"CHANGES_REQUESTED","body":"I cannot APPROVE until the null check is fixed."}]' '[]'
check missing "DISMISSED stale approving review body" '[{"state":"DISMISSED","body":"VERDICT: APPROVE"}]' '[]'
# RUSH-3080: a reviewer quoting pr-verdict.py's own stdin contract puts the
# literal ---AGENTS-SPLIT--- marker in the comment body. maxsplit=1 keeps the
# whole comments JSON in parts[1] so it still parses and the verdict is read.
check ok "APPROVE comment that quotes the split marker still clears" '[]' '[{"body":"VERDICT: APPROVE\nvalidated via: printf %s ---AGENTS-SPLIT--- %s | pr-verdict.py"}]'
check missing "no verdict" '[]' '[{"body":"looks big, did not review"}]'
check missing "carried from another PR" '[]' '[{"body":"Non-author APPROVE carried from #2731."}]'
check missing "APPROVE on #N citation" '[]' '[{"body":"Non-author APPROVE on #2731 covers this."}]'
# RUSH-3099: the past tense is the natural word AND GitHub's own review state,
# and the guard's own block message says "Post a GitHub APPROVED review" -- so a
# reviewer writing **APPROVED.** was rejected by the very form it was told to
# use. Real incident: agi-cli#2972, CI green, verdict correct, merge blocked.
check ok "APPROVED (past tense) in an issue comment" '[]' '[{"body":"## Verdict\n**APPROVED.**"}]'
check ok "APPROVED in a state=COMMENTED review body" '[{"state":"COMMENTED","body":"Verdict at 641f33cf3: APPROVED."}]' '[]'
check ok "bare stem APPROVE still clears" '[]' '[{"body":"VERDICT: APPROVE"}]'
# The optional D has to be in the CARRIED filter too, or widening the verdict
# regex silently reopens the #2736 laundering pattern for the past tense only.
check missing "APPROVED on #N citation is still laundering" '[]' '[{"body":"Non-author APPROVED on #2731 covers this."}]'
check missing "APPROVED carried from another PR" '[{"state":"COMMENTED","body":"APPROVED carried from #2731."}]' '[]'
check missing "CHANGES_REQUESTED body saying APPROVED does not launder" '[{"state":"CHANGES_REQUESTED","body":"Not APPROVED until the null check is fixed."}]' '[]'
# Guard the word boundary itself: a longer word starting with APPROVE must not
# clear. Without \b this would match, and "APPROVES"/"APPROVEDLY" are the kind
# of prose a reviewer writes about someone else's verdict.
check missing "APPROVES is not a verdict" '[]' '[{"body":"The other reviewer APPROVES of this direction."}]'

check missing "empty both" '[]' '[]'

printf -- '---\npr-verdict: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
