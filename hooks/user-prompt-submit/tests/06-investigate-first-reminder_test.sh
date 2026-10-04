#!/usr/bin/env bash
# Tests for 06-investigate-first-reminder.sh — run: bash 06-investigate-first-reminder_test.sh
# Executes the real hook: interactive sessions get the rule injected, headless runs get nothing.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../06-investigate-first-reminder.sh"
pass=0; fail=0

out=$(printf '{"prompt":"x"}' | CLAUDE_CODE_ENTRYPOINT=cli bash "$HOOK"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^Investigate first:'; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL interactive: rc=$rc out=$out"; fi

out=$(printf '{"prompt":"x"}' | CLAUDE_CODE_ENTRYPOINT=sdk-cli bash "$HOOK"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL headless: rc=$rc out=$out"; fi

out=$(printf '{"prompt":"x"}' | env -u CLAUDE_CODE_ENTRYPOINT bash "$HOOK"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL other harness: rc=$rc out=$out"; fi

echo "investigate-first-reminder: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
