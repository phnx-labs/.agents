#!/usr/bin/env bash
# hooks/registration_test.sh — proves no hook script has silently lost its
# registration in ../agents.yaml.
#
# Why this exists: a hook needs TWO things to fire — the script AND its `hooks:`
# entry in ../agents.yaml. Only the script is exercised by its own `_test.sh`,
# so a dropped registration is invisible: the script keeps passing its test
# while never running. This has happened twice (606db6e May 13, 8b006a6 Jun 24;
# see hooks/AGENTS.md), each time as collateral in a commit whose subject said
# nothing about it. `large-file-add-guard` — a data-loss guard — was off for six
# weeks that way. This is the failing test that "is it registered" never had.
#
# For every *.sh / *.py in hooks/ (excluding the test harness itself —
# *_test.sh and run_tests.sh) it asserts ONE of:
#   1. it has a `script:` entry in ../agents.yaml, OR
#   2. it is invoked by a script that itself IS registered — the
#      verify-delivery-chain.py case: no entry of its own, but piped into by
#      00-agent-verify-work-complete.sh, which is registered as
#      verify-work-complete and runs on every Stop, OR
#   3. it is in the INTENTIONALLY_UNREGISTERED allowlist below, with a reason.
# Anything matching none of those fails.
#
# Case 2 searches ONLY within registered scripts, so the "referenced but the
# caller is itself unregistered" trap does not pass: 02-expand-prompt-bang-
# commands.py is referenced by 02-expand-prompt-skill-refs.py, but that caller
# has no entry, so a reference from it would not count (bang-commands passes
# only because it has its own entry, expand-bang-commands).
#
# Manifest is resolved from $HERE/../agents.yaml; override with
# REGISTRATION_MANIFEST for a fixture (e.g. a restored historical agents.yaml).

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${REGISTRATION_MANIFEST:-$HERE/../agents.yaml}"

# Scripts deliberately present-but-unregistered. Format: "<script>|<reason>".
# Keep unindented; parsed field-by-field on '|'.
INTENTIONALLY_UNREGISTERED='
02-expand-prompt-skill-refs.py|unfinished feature — git log -S over the manifest returns zero commits, so it was never registered; register it or delete it, do not treat it as a regression
'

fail=0
missing=""

if [ ! -f "$MANIFEST" ]; then
  echo "FAIL - manifest not found: $MANIFEST"
  exit 1
fi

# Registered scripts = every `script:` value under the hooks: mapping, as a
# basename. The whole manifest is the hooks block, so every `script:` line is a
# hook registration; nothing else in this file uses that key.
REG_LIST="$(
  grep -E '^[[:space:]]*script:[[:space:]]' "$MANIFEST" \
    | sed -E 's/^[[:space:]]*script:[[:space:]]*//; s/[[:space:]]*$//; s#.*/##'
)"

if [ -z "$REG_LIST" ]; then
  echo "FAIL - no 'script:' entries found in $MANIFEST — manifest empty or unreadable"
  exit 1
fi

is_registered() { printf '%s\n' "$REG_LIST" | grep -qxF "$1"; }

# True if $1 is referenced (by basename) inside any script that is itself
# registered. Only registered scripts are searched — an unregistered caller
# does not make its callee reachable.
is_invoked_by_registered() {
  local target="$1" rs
  while IFS= read -r rs; do
    [ -n "$rs" ] || continue
    [ -f "$HERE/$rs" ] || continue
    if grep -qF "$target" "$HERE/$rs"; then return 0; fi
  done <<EOF
$REG_LIST
EOF
  return 1
}

allowlist_reason() {
  printf '%s\n' "$INTENTIONALLY_UNREGISTERED" | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

for f in "$HERE"/*.sh "$HERE"/*.py; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  # Skip the test harness itself — the tests and the runner are not event hooks.
  case "$base" in
    *_test.sh | run_tests.sh) continue ;;
  esac

  if is_registered "$base"; then
    echo "ok   - $base: registered in agents.yaml"
    continue
  fi

  if is_invoked_by_registered "$base"; then
    echo "ok   - $base: invoked by a registered script"
    continue
  fi

  reason="$(allowlist_reason "$base")"
  if [ -n "$reason" ]; then
    echo "ok   - $base: intentionally unregistered ($reason)"
    continue
  fi

  echo "FAIL - $base: no hooks: entry in agents.yaml, not invoked by any registered script, and not allowlisted — it never fires"
  missing="$missing $base"
  fail=1
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS - every hook script is registered, invoked by a registered script, or allowlisted"
else
  echo "FAILURES - unregistered hook script(s):$missing"
  echo "A script with no agents.yaml entry never fires. Add a hooks: entry (see hooks/AGENTS.md),"
  echo "or add it to INTENTIONALLY_UNREGISTERED in this test with a one-line reason."
fi
exit $fail
