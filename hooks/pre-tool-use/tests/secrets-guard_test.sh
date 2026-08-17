#!/usr/bin/env bash
# Tests for secrets-guard.sh — the PreToolUse guard against the
# secret-materializing one-liners (RUSH-2774): plaintext bundle export,
# bundle-key get, and the non-TTY view --reveal --plaintext escape.
#
# Hermetic: every case builds its own JSON payload and feeds it to the guard
# over stdin; the "fail closed" case runs the guard with a sandboxed PATH that
# has no jq/node/python on it.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../secrets-guard.sh"
SH_BIN="$(command -v sh)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0; fail=0

json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

run_guard() {
  local cmdstr="$1" path_override="${2:-}"
  local json esc_cmd errfile
  esc_cmd=$(json_escape "$cmdstr")
  json=$(printf '{"tool_input":{"command":"%s"}}' "$esc_cmd")
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

echo "secrets-guard"

export AGENTS_DISABLE_FRICTION_LOG=1

# --- denies: the exfiltration one-liners ------------------------------------
check_deny "eval-export idiom (the canonical exfil line)" \
  'eval "$(agents secrets export hetzner.com --plaintext 2>/dev/null)"; crabbox list' \
  "secrets.export-plaintext"
check_deny "bare plaintext export" \
  "agents secrets export npmjs.com --plaintext" \
  "secrets.export-plaintext"
check_deny "plaintext export piped to grep/cut" \
  "agents secrets export npmjs.com --plaintext | grep NPM_TOKEN | cut -d= -f2-" \
  "secrets.export-plaintext"
check_deny "sh -c wrapped export" \
  'sh -c "agents secrets export prod --plaintext"' \
  "secrets.export-plaintext"
check_deny "ag alias" \
  "ag secrets export prod --plaintext" \
  "secrets.export-plaintext"
check_deny "bundle-key get" \
  "agents secrets get npmjs.com NPM_TOKEN" \
  "secrets.get-bundle-key"
check_deny "bundle-key get in a capture" \
  'TOKEN="$(agents secrets get npmjs.com NPM_TOKEN)"' \
  "secrets.get-bundle-key"
check_deny "view reveal plaintext escape" \
  "agents secrets view r2.backups --reveal --plaintext" \
  "secrets.view-reveal-plaintext"

# --- allows: transfer modes, injection, human/metadata surfaces -------------
check_allow "export push to device" \
  "agents secrets export apple.com --device mac-mini --remote-backend file"
check_allow "export to encrypted file" \
  "agents secrets export prod --to-file prod.enc"
check_allow "export to 1password" \
  "agents secrets export prod --to-1password --vault Team"
check_allow "the paved road: exec injection" \
  "agents secrets exec hetzner.com -- crabbox list"
check_allow "exec printenv capture (deliberate composition)" \
  'NPM_TOKEN="$(agents secrets exec npmjs.com -- printenv NPM_TOKEN)"'
check_allow "raw-item get (one arg)" \
  "agents secrets get some-raw-item"
check_allow "masked view" \
  "agents secrets view prod"
check_allow "view --reveal without the escape (CLI TTY gate owns it)" \
  "agents secrets view prod --reveal"
check_allow "prose mentioning the command (echo, not an agents call)" \
  "echo 'never run agents secrets export prod --plaintext'"
check_allow "unrelated command containing the word secrets" \
  "grep -rn 'secrets export' docs/"
check_allow "secrets list" \
  "agents secrets list"

# --- fail-closed: no JSON parser available ----------------------------------
mkdir -p "$SANDBOX/bin"
for tool in cat sed printf; do
  p="$(command -v "$tool" || true)"
  [ -n "$p" ] && ln -sf "$p" "$SANDBOX/bin/$tool"
done
run_guard "agents secrets export prod --plaintext" "$SANDBOX/bin"
if [ "$RC" -eq 2 ] && [ "${ERR#*fail-closed}" != "$ERR" ]; then
  echo "ok   - fails closed with no JSON parser"; pass=$((pass+1))
else
  echo "FAIL - fails closed with no JSON parser: rc=$RC err=$ERR"; fail=$((fail+1))
fi

echo
echo "secrets-guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
