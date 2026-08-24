#!/usr/bin/env bash
# Real-path tests for 01-git-require-clean-tree.sh plan-mode gating.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../01-git-require-clean-tree.sh"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

git -C "$SANDBOX" init -q
printf 'dirty\n' > "$SANDBOX/untracked.txt"

run_hook() {
  printf '%s' "$1" | AGENTS_DISABLE_FRICTION_LOG=1 "$HOOK" >/dev/null 2>"$SANDBOX/stderr"
  RC=$?
}

fail=0
run_hook "{\"cwd\":\"$SANDBOX\",\"tool_input\":{\"command\":\"git pull\"}}"
if [ "$RC" -eq 2 ] && grep -q 'working tree is dirty' "$SANDBOX/stderr"; then
  echo 'ok   - dirty tree blocks git pull outside plan mode'
else
  echo "FAIL - dirty tree should block outside plan mode (rc=$RC)"
  fail=$((fail + 1))
fi

run_hook "{\"permission_mode\":\"plan\",\"cwd\":\"$SANDBOX\",\"tool_input\":{\"command\":\"git pull\"}}"
if [ "$RC" -eq 0 ] && [ ! -s "$SANDBOX/stderr" ]; then
  echo 'ok   - explicit plan mode skips the guard'
else
  echo "FAIL - explicit plan mode should skip cleanly (rc=$RC)"
  fail=$((fail + 1))
fi

run_hook "{\"permission_mode\":\"future-mode\",\"cwd\":\"$SANDBOX\",\"tool_input\":{\"command\":\"git pull\"}}"
if [ "$RC" -eq 2 ]; then
  echo 'ok   - unknown modes remain guarded'
else
  echo "FAIL - unknown mode must fail safe (rc=$RC)"
  fail=$((fail + 1))
fi

[ "$fail" -eq 0 ]
