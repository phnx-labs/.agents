#!/usr/bin/env bash
# Tests for linear-guard.py — the PreToolUse guard that restrains agent tracker
# sprawl: DENY creating a Linear project, NUDGE (non-blocking) creating an issue,
# ALLOW everything else.
#
# Hermetic: every case builds its own JSON payload and feeds it to the guard
# over stdin.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../linear-guard.py"
PY_BIN="$(command -v python3 || command -v python)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0; fail=0

# JSON-escape a raw string (backslash, double-quote, newlines -> \n).
json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# run_raw <raw-stdin> — feed arbitrary bytes (not necessarily valid JSON) to the
# guard. Sets RC, OUT, ERR. Used for the fail-closed / fast-path payload cases.
run_raw() {
  local raw="$1" errfile
  errfile="$SANDBOX/err.$$.$RANDOM"
  OUT=$(printf '%s' "$raw" | "$PY_BIN" "$HOOK" 2>"$errfile")
  RC=$?
  ERR=$(cat "$errfile")
  rm -f "$errfile"
}

# run_guard <command-string> — sets RC, OUT, ERR.
run_guard() {
  local cmdstr="$1" json esc_cmd errfile
  esc_cmd=$(json_escape "$cmdstr")
  if [ "${KEY_STYLE:-snake}" = camel ]; then
    json=$(printf '{"toolName":"Bash","toolInput":{"command":"%s"}}' "$esc_cmd")
  else
    json=$(printf '{"tool_input":{"command":"%s"}}' "$esc_cmd")
  fi
  errfile="$SANDBOX/err.$$.$RANDOM"
  OUT=$(printf '%s' "$json" | "$PY_BIN" "$HOOK" 2>"$errfile")
  RC=$?
  ERR=$(cat "$errfile")
  rm -f "$errfile"
}

check_deny_structured() { # name, command, needle1, needle2
  run_guard "$2"
  if [ "$RC" -ne 2 ]; then
    echo "FAIL - $1: expected rc=2, got rc=$RC"; fail=$((fail+1)); return
  fi
  for needle in "blocked_op:" "reason:" "do_this_instead:" "$3" "$4"; do
    if [ "${ERR#*"$needle"}" = "$ERR" ]; then
      echo "FAIL - $1: stderr missing [$needle], got: $ERR"; fail=$((fail+1)); return
    fi
  done
  echo "ok   - $1"; pass=$((pass+1))
}

check_nudge() { # name, command — rc=0, stdout carries the additionalContext nudge
  run_guard "$2"
  if [ "$RC" -ne 0 ]; then
    echo "FAIL - $1: expected rc=0, got rc=$RC (stderr: $ERR)"; fail=$((fail+1)); return
  fi
  for needle in "additionalContext" "linear-restraint" "advisory"; do
    if [ "${OUT#*"$needle"}" = "$OUT" ]; then
      echo "FAIL - $1: stdout missing [$needle], got: $OUT"; fail=$((fail+1)); return
    fi
  done
  echo "ok   - $1"; pass=$((pass+1))
}

check_allow() { # name, command — rc=0, empty stdout (silent allow)
  run_guard "$2"
  if [ "$RC" -ne 0 ]; then
    echo "FAIL - $1: expected rc=0, got rc=$RC (stderr: $ERR)"; fail=$((fail+1)); return
  fi
  if [ -n "$OUT" ]; then
    echo "FAIL - $1: expected empty stdout, got: $OUT"; fail=$((fail+1)); return
  fi
  echo "ok   - $1"; pass=$((pass+1))
}

echo "linear-guard"

# --- DENY: creating a project -----------------------------------------------
check_deny_structured "deny linear projects create" \
  "linear projects create --name Foo" "linear.projects-create" "owner"
check_deny_structured "deny with global --team flag before projects" \
  "linear --team ENG projects create --name Bar" "linear.projects-create" "owner"
check_deny_structured "deny chained after a benign cmd" \
  "linear tasks --project AGI && linear projects create --name Baz" "linear.projects-create" "archive"

# --- NUDGE: creating an issue (non-blocking) --------------------------------
check_nudge "nudge linear create" "linear create fix-the-thing --priority high"
check_nudge "nudge with --team global flag" "linear --team ENG create some-bug"
check_nudge "nudge issue created inside a project (not a project-create)" \
  "linear create issue-in-a-project --project AGI"
check_nudge "nudge under Grok camelCase payload" "linear create grok-shaped-issue"

# --- NUDGE: amending via a comment -> prefer updating the description ---------
check_nudge "nudge on a bare update --comment (context-piling)" \
  'linear update ABC-1 --comment "some more context about the bug"'
run_guard 'linear update ABC-1 --comment "more context"'
if [ "${OUT#*description instead}" = "$OUT" ]; then
  echo "FAIL - comment nudge should steer to the description"; fail=$((fail+1))
else echo "ok   - comment nudge steers to the description"; pass=$((pass+1)); fi
# Delivery-proof / status-change comments are legitimate — stay quiet.
check_allow "allow update --done --proof --comment (delivery evidence)" \
  'linear update ABC-1 --done --proof "PR #5" --comment "shipped"'
check_allow "allow update --status ... --comment (status move)" \
  'linear update ABC-1 --status Done --comment "closed via PR"'

# --- ALLOW: everything else, silently ---------------------------------------
check_allow "allow linear create --help"        "linear create --help"
check_allow "allow linear tasks"                "linear tasks --project AGI"
check_allow "allow linear update"               "linear update PHNX-1 --done"
check_allow "allow linear projects archive"     "linear projects archive Foo"
check_allow "allow non-linear command"          "git commit -m wip"
check_allow "allow unrelated word 'linear' free" "echo done"

# --- Over-match false positives: the denied phrase inside quoted argument text
# must NOT trip DENY/NUDGE (regression for the substring-scan bug) -------------
check_allow "phrase in a linear update --description, not a real project-create" \
  'linear update ABC-1 --description "we should never do linear projects create again"'
check_allow "grep for the guard's own denied phrase is not a project-create" \
  'grep -rn "linear projects create" hooks/'
check_allow "unrelated tool with 'projects create' substring" \
  "nonlinear-migrate projects create-user"
check_allow "git commit message mentioning linear create is not a create" \
  'git commit -m "note: do not run linear create"'

# --- Fail-closed contract (hooks/AGENTS.md): a deny-capable guard refuses on an
# unparseable payload that mentions linear; the raw fast path allows everything
# with no linear substring at all --------------------------------------------
run_raw 'not json at all but mentions linear projects create'
if [ "$RC" -eq 2 ] && [ -n "$ERR" ]; then echo "ok   - fail-closed on unparseable linear payload"; pass=$((pass+1));
else echo "FAIL - fail-closed on unparseable linear payload: rc=$RC err=[$ERR]"; fail=$((fail+1)); fi

run_raw 'not json at all, and nothing to police here'
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then echo "ok   - fast-path allow on non-linear unparseable payload"; pass=$((pass+1));
else echo "FAIL - fast-path allow on non-linear payload: rc=$RC out=[$OUT]"; fail=$((fail+1)); fi

run_raw ''
if [ "$RC" -eq 0 ]; then echo "ok   - empty stdin allows (no linear substring)"; pass=$((pass+1));
else echo "FAIL - empty stdin: rc=$RC"; fail=$((fail+1)); fi

# ReDoS regression (py/redos): a pathological flag-like input must return fast
# (the old nested-quantifier regex backtracked exponentially on `-- -` repeats).
# Reaching a verdict at all proves there is no catastrophic backtracking; a hang
# would wedge the whole test run.
REDOS_INPUT="linear $(yes '\-\- \-' 2>/dev/null | head -400 | tr -d '\n') create"
check_nudge "redos-safe on pathological flag input" "$REDOS_INPUT"

# Grok camelCase deny path
KEY_STYLE=camel run_guard "linear projects create --name Zap"; :
KEY_STYLE=camel check_deny_structured "deny under Grok camelCase payload" \
  "linear projects create --name Zap" "linear.projects-create" "owner"

echo "---"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
