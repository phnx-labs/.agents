#!/usr/bin/env bash
# hooks/run_tests.sh — the pre-PR gate for this repo's hooks and guard rules.
#
# Runs every `*_test.sh` in hooks/ and in rules/subrules/*/ (which includes
# registration_test.sh — the integrity check that a hook script has not silently
# lost its agents.yaml registration). Exits non-zero if any test fails.
#
# Run it before opening a PR that touches hooks/, rules/subrules/, or agents.yaml.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

fail=0
ran=0

run_one() {
  local t="$1"
  ran=$((ran + 1))
  echo "=== $t ==="
  if bash "$t"; then
    echo "--- PASS: $t"
  else
    echo "--- FAIL: $t"
    fail=1
  fi
  echo
}

# Hooks (registration_test.sh matches this glob).
for t in "$HERE"/*_test.sh; do
  [ -e "$t" ] || continue
  run_one "$t"
done

# Guard rules under rules/subrules/*/.
for t in "$ROOT"/rules/subrules/*/*_test.sh; do
  [ -e "$t" ] || continue
  run_one "$t"
done

echo "================================================================"
if [ "$fail" -eq 0 ]; then
  echo "ALL TESTS PASSED ($ran suites)"
else
  echo "SOME TESTS FAILED ($ran suites run)"
fi
exit $fail
