#!/usr/bin/env bash
# hooks/registration_test.sh — proves no hook script has silently lost its
# registration in ../agents.yaml and proves the default-on prompt expansion
# hooks have not silently been disabled.
#
# Why this exists: a hook needs TWO things to fire — the script AND its `hooks:`
# entry in ../agents.yaml. Only the script is exercised by its own `_test.sh`,
# so a dropped registration is invisible: the script keeps passing its test
# while never running. This has happened twice (606db6e May 13, 8b006a6 Jun 24;
# see hooks/AGENTS.md), each time as collateral in a commit whose subject said
# nothing about it. `large-file-add-guard` — a data-loss guard — was off for six
# weeks that way. This is the failing test that "is it registered" never had.
#
# For every *.sh / *.py in hooks/ and one-level group dirs (hooks/session-starts/,
# …), excluding the test harness itself (*_test.sh and run_tests.sh), it asserts
# ONE of:
#   1. it has a `script:` entry in ../agents.yaml (basename match), OR
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
visual_readback.py|shared library imported by the registered verify-work-complete Stop path; it is not an event entry point
gate-outcome-backfill.py|offline analysis of already-recorded gate telemetry; deliberately never on a hook path, run by hand
'

fail=0
missing=""

if [ ! -f "$MANIFEST" ]; then
  echo "FAIL - manifest not found: $MANIFEST"
  exit 1
fi

# Registered scripts = every `script:` value under the hooks: mapping, as a
# basename. Nested paths like session-starts/foo.sh still match as foo.sh.
REG_LIST="$(
  grep -E '^[[:space:]]*script:[[:space:]]' "$MANIFEST" \
    | sed -E 's/^[[:space:]]*script:[[:space:]]*//; s/[[:space:]]*$//; s#.*/##'
)"

# Full relative script paths from the manifest (for locating the file on disk).
REG_PATHS="$(
  grep -E '^[[:space:]]*script:[[:space:]]' "$MANIFEST" \
    | sed -E 's/^[[:space:]]*script:[[:space:]]*//; s/[[:space:]]*$//'
)"

if [ -z "$REG_LIST" ]; then
  echo "FAIL - no 'script:' entries found in $MANIFEST — manifest empty or unreadable"
  exit 1
fi

is_registered() { printf '%s\n' "$REG_LIST" | grep -qxF "$1"; }

hook_block() {
  awk -v hook="$1" '
    $0 == "  " hook ":" { found=1; print; next }
    found && $0 ~ /^  [[:alnum:]_-]+:/ { exit }
    found { print }
    END { if (!found) exit 1 }
  ' "$MANIFEST"
}

assert_default_enabled() {
  local internal_name="$1" public_name="$2" block
  if ! block="$(hook_block "$internal_name")"; then
    echo "FAIL - $public_name: internal hook $internal_name is missing from $MANIFEST"
    fail=1
    return
  fi
  if printf '%s\n' "$block" | grep -Eq '^[[:space:]]+enabled:[[:space:]]*false([[:space:]]|$)'; then
    echo "FAIL - $public_name: $internal_name must be enabled by default"
    fail=1
    return
  fi
  echo "ok   - $public_name: $internal_name is enabled by default"
}

# Resolve a registered script basename or relative path to an on-disk file.
resolve_registered_path() {
  local rs="$1"
  if [ -f "$HERE/$rs" ]; then
    printf '%s\n' "$HERE/$rs"
    return 0
  fi
  # Basename-only: search top-level then one-level group dirs.
  local base
  base="$(basename "$rs")"
  if [ -f "$HERE/$base" ]; then
    printf '%s\n' "$HERE/$base"
    return 0
  fi
  local d
  for d in "$HERE"/*/; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in
      # tests/: fixture-only. lib/: shared helpers sourced by hooks, not events.
      tests|test|lib) continue ;;
    esac
    if [ -f "$d$base" ]; then
      printf '%s\n' "$d$base"
      return 0
    fi
  done
  return 1
}

# True if $1 is referenced (by basename) inside any script that is itself
# registered. Only registered scripts are searched — an unregistered caller
# does not make its callee reachable.
is_invoked_by_registered() {
  local target="$1" rs path
  while IFS= read -r rs; do
    [ -n "$rs" ] || continue
    path="$(resolve_registered_path "$rs" 2>/dev/null)" || continue
    if grep -qF "$target" "$path"; then return 0; fi
  done <<EOF
$REG_PATHS
$REG_LIST
EOF
  return 1
}

allowlist_reason() {
  printf '%s\n' "$INTENTIONALLY_UNREGISTERED" | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

check_script() {
  local f="$1"
  local base
  base="$(basename "$f")"
  # Skip the test harness itself — the tests and the runner are not event hooks.
  case "$base" in
    *_test.sh | run_tests.sh | registration_test.sh) return 0 ;;
  esac

  if is_registered "$base"; then
    echo "ok   - $base: registered in agents.yaml"
    return 0
  fi

  if is_invoked_by_registered "$base"; then
    echo "ok   - $base: invoked by a registered script"
    return 0
  fi

  local reason
  reason="$(allowlist_reason "$base")"
  if [ -n "$reason" ]; then
    echo "ok   - $base: intentionally unregistered ($reason)"
    return 0
  fi

  echo "FAIL - $base: no hooks: entry in agents.yaml, not invoked by any registered script, and not allowlisted — it never fires"
  missing="$missing $base"
  fail=1
}

# Top-level scripts.
for f in "$HERE"/*.sh "$HERE"/*.py; do
  [ -e "$f" ] || continue
  check_script "$f"
done

# One-level group dirs (session-starts/, …). Skip tests/ (fixtures) and lib/
# (shared helpers sourced by hooks — not event scripts of their own).
for d in "$HERE"/*/; do
  [ -d "$d" ] || continue
  case "$(basename "$d")" in
    tests|test|lib) continue ;;
  esac
  for f in "$d"*.sh "$d"*.py; do
    [ -e "$f" ] || continue
    check_script "$f"
  done
done

assert_default_enabled "expand-promptcuts" "promptcuts"
assert_default_enabled "expand-bang-commands" "bangcuts"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS - every hook script is reachable and both prompt expansion hooks default on"
else
  echo "FAILURES - hook registration/default assertions failed"
  if [ -n "$missing" ]; then
    echo "Unregistered hook script(s):$missing"
    echo "A script with no agents.yaml entry never fires. Add a hooks: entry (see hooks/AGENTS.md),"
    echo "or add it to INTENTIONALLY_UNREGISTERED in this test with a one-line reason."
  fi
fi
exit $fail
