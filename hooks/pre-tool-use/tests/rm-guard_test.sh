#!/usr/bin/env bash
# Tests for rm-guard.sh — the PreToolUse guard against `rm -r` on protected
# paths.
#
# Hermetic: every case builds its own JSON payload and feeds it to the guard
# over stdin; the "fail closed" case runs the guard with a sandboxed PATH that
# has no jq/node/python on it (only `cat`, which the guard needs just to read
# stdin) to reproduce the footer-guard fail-open regression class.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../rm-guard.sh"
# Resolve the interpreter to an ABSOLUTE path once, up front — the "no parser"
# case below runs it with PATH overridden to a sandbox dir, and a bare `sh`
# command name would then fail to resolve at all (command not found) rather
# than exercising the guard's own fail-closed behavior.
SH_BIN="$(command -v sh)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0; fail=0

# JSON-escape a raw string for embedding as a JSON string value: backslash,
# then double-quote, then real newlines -> \n (slurp-mode sed, GNU + BSD safe).
json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# run_guard <command-string> [path-override]
# Sets RC, OUT, ERR.
run_guard() {
  local cmdstr="$1" path_override="${2:-}"
  local json esc_cmd errfile
  esc_cmd=$(json_escape "$cmdstr")
  # KEY_STYLE=camel emits a Grok-shaped payload (toolName/toolInput); default
  # snake_case is byte-identical to before.
  if [ "${KEY_STYLE:-snake}" = camel ]; then
    json=$(printf '{"toolName":"Bash","toolInput":{"command":"%s"}}' "$esc_cmd")
  else
    json=$(printf '{"tool_input":{"command":"%s"}}' "$esc_cmd")
  fi
  errfile="$SANDBOX/err.$$.$RANDOM"
  if [ -n "$path_override" ]; then
    OUT=$(printf '%s' "$json" | PATH="$path_override" "$SH_BIN" "$HOOK" 2>"$errfile")
  else
    OUT=$(printf '%s' "$json" | "$SH_BIN" "$HOOK" 2>"$errfile")
  fi
  RC=$?
  ERR=$(cat "$errfile")
  rm -f "$errfile"
}

check_deny() { # name, command-string, expected-stderr-substring
  run_guard "$2"
  if [ "$RC" -ne 2 ]; then
    echo "FAIL - $1: expected rc=2, got rc=$RC"; fail=$((fail+1)); return
  fi
  if [ -z "$ERR" ]; then
    echo "FAIL - $1: rc=2 but stderr is empty (no reason given)"; fail=$((fail+1)); return
  fi
  if [ -n "${3:-}" ] && [ "${ERR#*"$3"}" = "$ERR" ]; then
    echo "FAIL - $1: stderr missing [$3], got: $ERR"; fail=$((fail+1)); return
  fi
  echo "ok   - $1"; pass=$((pass+1))
}

check_allow() { # name, command-string
  run_guard "$2"
  if [ "$RC" -ne 0 ]; then
    echo "FAIL - $1: expected rc=0, got rc=$RC (stderr: $ERR)"; fail=$((fail+1)); return
  fi
  if [ -n "$OUT" ]; then
    echo "FAIL - $1: expected empty stdout (PreToolUse stdout pollutes the prompt), got: $OUT"; fail=$((fail+1)); return
  fi
  echo "ok   - $1"; pass=$((pass+1))
}

echo "rm-guard"

# RUSH-2295 structured denial shape
check_deny_structured() {
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
check_deny_structured "structured deny for rm protected path" "rm -rf ~/.agents" "rm.protected-path" "trash"


# --- 1. Blocks rm -r/-rf on protected paths, in various dressings ------------
check_deny "rm -rf ~/.agents"                       "rm -rf ~/.agents" "protected path denied"
check_deny "rm -rf \$HOME"                           'rm -rf $HOME' "protected path denied"
check_deny "rm -rf bare tilde"                       "rm -rf ~" "protected path denied"
check_deny "rm -rf /"                                "rm -rf /" "protected path denied"
check_deny "rm -rf /Users"                           "rm -rf /Users" "protected path denied"
check_deny "rm -rf ~/.ssh (compact -rf flag)"        "rm -rf ~/.ssh" "protected path denied"
check_deny "rm -Rf ~/Documents (capital R)"          "rm -Rf ~/Documents" "protected path denied"
check_deny "rm -r --force ~/Desktop (long recursive)" "rm --recursive ~/Desktop" "protected path denied"
check_deny "chained: benign && destructive"          "ls -la && rm -rf ~/.config" "protected path denied"
check_deny "env-var prefix before rm"                "FOO=bar rm -rf ~/src" "protected path denied"
check_deny "sh -c wrapper"                           'sh -c "rm -rf ~/.agents"' "protected path denied"
check_deny "bash -c wrapper"                          'bash -c "rm -rf ~/Rush"' "protected path denied"
check_deny "quoted first token"                        "'rm' -rf ~/.agents" "protected path denied"
check_deny "variable-expansion target treated as suspicious" 'rm -rf "$SOME_VAR"' "protected path denied"

# PHNX-3350: timeout/gtimeout wrappers must not hide destructive rm on protected paths.
check_deny "timeout-wrapped rm -rf \$HOME"      "timeout 5 rm -rf \$HOME" "protected path denied"
check_deny "gtimeout-wrapped rm -rf ~"          "gtimeout 5 rm -rf ~" "protected path denied"
check_deny "timeout with all common options"    "timeout --preserve-status --kill-after=2 -s KILL 5 rm -rf ~/.agents" "protected path denied"
check_deny "timeout-wrapped sh -c rm"           'timeout 5 sh -c "rm -rf ~/.ssh"' "protected path denied"
check_allow "timeout-wrapped rm on unprotected tmp dir" "timeout 5 rm -rf $TMP_SCRATCH"
check_allow "timeout-wrapped rm single file"    "timeout 5 rm $PROTECTED_FILE"

# --- 2. Allows the benign neighbour -------------------------------------------
TMP_SCRATCH="$SANDBOX/scratch-dir"
mkdir -p "$TMP_SCRATCH"
check_allow "rm -rf on an unprotected tmp dir"    "rm -rf $TMP_SCRATCH"
PROTECTED_FILE="$SANDBOX/agents-like/one-file.txt"
mkdir -p "$(dirname "$PROTECTED_FILE")"
: > "$PROTECTED_FILE"
check_allow "rm single file, no recursive flag"   "rm $PROTECTED_FILE"
check_allow "non-rm command"                       "ls -la /tmp"
check_allow "rm -f on a single file (no -r)"       "rm -f $PROTECTED_FILE"

# --- 3. Fails CLOSED with no JSON parser on PATH ------------------------------
NOPARSER="$SANDBOX/noparser-bin"
mkdir -p "$NOPARSER"
ln -s "$(command -v cat)" "$NOPARSER/cat"
run_guard "rm -rf ~/.agents" "$NOPARSER"
if [ "$RC" -eq 2 ]; then
  echo "ok   - no JSON parser on PATH -> fails closed (rc=2)"; pass=$((pass+1))
else
  echo "FAIL - no JSON parser on PATH -> expected rc=2, got rc=$RC"; fail=$((fail+1))
fi
if [ "${ERR#*"no JSON parser"}" != "$ERR" ]; then
  echo "ok   - fail-closed message names the missing parser"; pass=$((pass+1))
else
  echo "FAIL - fail-closed stderr missing 'no JSON parser', got: $ERR"; fail=$((fail+1))
fi
# Sanity: this same PATH still lets a benign command through the fast path
# (no "rm" substring in the payload at all -> exits 0 before ever needing a
# parser), proving the deny above is really about the missing parser and not
# about the sandboxed PATH breaking the guard outright.
run_guard "ls -la /tmp" "$NOPARSER"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  echo "ok   - no-parser PATH still allows a non-rm command (fast path, no parse needed)"; pass=$((pass+1))
else
  echo "FAIL - no-parser PATH broke the non-rm fast path: rc=$RC out=[$OUT]"; fail=$((fail+1))
fi

# --- Harness portability: Grok CLI camelCase payloads (toolName/toolInput) ----
# Grok delivers camelCase hook stdin; the guard MUST deny a protected-path rm
# exactly as for the snake_case twins above. Pins the dual-path extraction
# (efc7fef) with a regression fixture the Bash guards previously lacked.
KEY_STYLE=camel
check_deny  "camelCase: rm -rf ~/.agents still denied" "rm -rf ~/.agents" "protected path denied"
check_allow "camelCase: rm -rf unprotected tmp allowed" "rm -rf $TMP_SCRATCH"
KEY_STYLE=snake

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
