#!/usr/bin/env bash
# hooks/run_tests.sh — the pre-PR check for this repo's hooks and guard rules.
#
# Runs every `*_test.sh` in hooks/ and in rules/subrules/*/ (which includes
# registration_test.sh — the integrity check that a hook script has not silently
# lost its agents.yaml registration). Exits non-zero if any test fails.
#
# A per-hook test lives in a `tests/` subdir of its own event dir
# (hooks/<event>/tests/<name>_test.sh), one level deeper than the hook script it
# covers — see hooks/AGENTS.md. This runner discovers both layouts so a test is
# never silently skipped by living in the "wrong" place.
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

# Hooks at the root (registration_test.sh matches this glob).
for t in "$HERE"/*_test.sh; do
  [ -e "$t" ] || continue
  run_one "$t"
done

# Hooks in one-level group dirs (e.g. session-start/), for any test still
# living beside its script.
for t in "$HERE"/*/*_test.sh; do
  [ -e "$t" ] || continue
  run_one "$t"
done

# Hooks in the per-event tests/ subdir (hooks/<event>/tests/<name>_test.sh) —
# the current convention (hooks/AGENTS.md).
for t in "$HERE"/*/tests/*_test.sh; do
  [ -e "$t" ] || continue
  run_one "$t"
done

# The skills namespace check. It lives outside hooks/ because it tests skills,
# but it is a pre-PR integrity check exactly like registration_test.sh — and an
# un-run test rots the same way the flat-namespace bug it catches did. Ship it
# inside this runner rather than hoping someone types it by hand.
for t in "$ROOT"/skills/*_test.sh; do
  [ -e "$t" ] || continue
  run_one "$t"
done

# Guard rules under rules/subrules/*/.
# Routine helper libs (routines/lib/tests/<name>_test.sh). Not hooks, but the
# worktree sweep is destructive shell and must carry the same pre-PR gate.
for t in "$ROOT"/routines/*/tests/*_test.sh; do
  [ -e "$t" ] || continue
  run_suite "$t"
done

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
