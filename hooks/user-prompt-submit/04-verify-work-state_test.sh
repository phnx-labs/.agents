#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/04-verify-work-state.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
DB="$SANDBOX/state.db"
export VERIFY_WORK_STATE_DB="$DB"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$3], got [$2]"; fail=1; fi; }

out=$(printf '%s' '{"session_id":"prompt-1","agent":"claude","prompt":"record this boundary"}' | python3 "$HOOK" 2>&1)
check "collector stays silent" "$out" ""
check "collector exits successfully" "$?" "0"
check "collector writes one goal boundary" "$(sqlite3 "$DB" 'select count(*) from goal_boundaries;')" "1"

printf '%s' '{broken' | python3 "$HOOK" >/dev/null 2>&1
check "malformed payload does not add state" "$(sqlite3 "$DB" 'select count(*) from goal_boundaries;')" "1"

printf '%s' '{"agent":"codex","prompt":"missing id"}' | env -u AGENT_LAUNCH_ID python3 "$HOOK" >/dev/null 2>&1
check "missing identity does not add state" "$(sqlite3 "$DB" 'select count(*) from goal_boundaries;')" "1"

exit "$fail"
