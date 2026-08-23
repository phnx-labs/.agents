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
check missing "no verdict" '[]' '[{"body":"looks big, did not review"}]'
check missing "carried from another PR" '[]' '[{"body":"Non-author APPROVE carried from #2731."}]'
check missing "APPROVE on #N citation" '[]' '[{"body":"Non-author APPROVE on #2731 covers this."}]'
check missing "empty both" '[]' '[]'

printf -- '---\npr-verdict: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
