#!/usr/bin/env bash
# Tests for large-file-add-guard.sh — the PreToolUse guard against staging a
# large or binary-magic file via `git add`.
#
# Hermetic: fixture files live in a sandboxed git repo; every case builds its
# own JSON payload and feeds it to the guard over stdin. The "fail closed"
# case runs the guard with a sandboxed PATH that has no jq/node/python on it
# (only `cat`, which the guard needs just to read stdin) to reproduce the
# footer-guard fail-open regression class.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../large-file-add-guard.sh"
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

# run_guard <command-string> [max-kb-override] [path-override]
# Sets RC, OUT, ERR.
run_guard() {
  local cmdstr="$1" max_kb="${2:-}" path_override="${3:-}"
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
  elif [ -n "$max_kb" ]; then
    OUT=$(printf '%s' "$json" | LARGE_FILE_GUARD_MAX_KB="$max_kb" "$SH_BIN" "$HOOK" 2>"$errfile")
  else
    OUT=$(printf '%s' "$json" | "$SH_BIN" "$HOOK" 2>"$errfile")
  fi
  RC=$?
  ERR=$(cat "$errfile")
  rm -f "$errfile"
}

check_deny() { # name, command-string, expected-stderr-substring, [max-kb-override]
  run_guard "$2" "${4:-}"
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

check_allow() { # name, command-string, [max-kb-override]
  run_guard "$2" "${3:-}"
  if [ "$RC" -ne 0 ]; then
    echo "FAIL - $1: expected rc=0, got rc=$RC (stderr: $ERR)"; fail=$((fail+1)); return
  fi
  if [ -n "$OUT" ]; then
    echo "FAIL - $1: expected empty stdout (PreToolUse stdout pollutes the prompt), got: $OUT"; fail=$((fail+1)); return
  fi
  echo "ok   - $1"; pass=$((pass+1))
}

echo "large-file-add-guard"

json='{"permission_mode":"plan","tool_input":{"command":"git add oversized.bin"}}'
OUT=$(printf '%s' "$json" | "$SH_BIN" "$HOOK" 2>"$SANDBOX/plan.err")
RC=$?
ERR=$(cat "$SANDBOX/plan.err")
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  echo "ok   - explicit plan mode skips the guard"
  pass=$((pass+1))
else
  echo "FAIL - explicit plan mode should skip cleanly (rc=$RC stdout=$OUT stderr=$ERR)"
  fail=$((fail+1))
fi

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


# --- fixtures ------------------------------------------------------------
REPO="$SANDBOX/repo"
git init -q "$REPO"

BIGFILE_DEFAULT="$REPO/bigfile-default.bin"     # 6 MiB, over the real 5 MiB default
head -c 6291456 /dev/zero > "$BIGFILE_DEFAULT"

BIGFILE_SMALL="$REPO/bigfile-small.bin"         # 10 KiB, only "big" under an overridden threshold
head -c 10240 /dev/zero > "$BIGFILE_SMALL"

SMALLFILE="$REPO/smallfile.txt"
printf 'hello world\n' > "$SMALLFILE"

BINARYFILE="$REPO/binaryfile"                    # ELF magic bytes, tiny — still denied
printf '\x7f\x45\x4c\x46\x02\x01\x01\x00restofdata' > "$BINARYFILE"

SUBDIR="$REPO/a-directory"
mkdir -p "$SUBDIR"

# --- 1. Blocks large / binary files, in various dressings --------------------
check_deny_structured "structured deny for large file" "git add $BIGFILE_DEFAULT" "git.add-large-file" "git lfs"
check_deny "file over the real 5 MiB default threshold" "git add $BIGFILE_DEFAULT" "limit"
check_deny "file over a custom LARGE_FILE_GUARD_MAX_KB threshold" "git add $BIGFILE_SMALL" "limit" 1
check_deny "binary magic bytes (ELF), regardless of size"        "git add $BINARYFILE" "binary magic bytes"
check_deny "chained: benign && oversized add"                    "ls -la && git add $BIGFILE_DEFAULT" "limit"
check_deny "sh -c wrapper"                                        "sh -c \"git add $BIGFILE_DEFAULT\"" "limit"
check_deny "env-var prefix before git"                            "FOO=bar git add $BIGFILE_DEFAULT" "limit"
check_deny "git stage (alias for add)"                            "git stage $BIGFILE_DEFAULT" "limit"

# PHNX-3350: timeout/gtimeout wrappers must not hide large/binary git add.
check_deny "timeout-wrapped large file add"                       "timeout 5 git add $BIGFILE_DEFAULT" "limit"
check_deny "gtimeout-wrapped large file add"                      "gtimeout 5 git add $BIGFILE_DEFAULT" "limit"
check_deny "timeout-wrapped binary magic add"                     "timeout --preserve-status --kill-after=2 -s KILL 5 git add $BINARYFILE" "binary magic bytes"
check_allow "timeout-wrapped small file add"                      "timeout 5 git add $SMALLFILE"
check_deny "nested timeout wrappers"                            "timeout 5 timeout 5 git add $BIGFILE_DEFAULT" "limit"
check_deny "timeout inside sh -c wrapper"                       "sh -c \"timeout 5 git add $BIGFILE_DEFAULT\"" "limit"

# --- 2. Allows the benign neighbour -------------------------------------------
check_allow "small text file under threshold"          "git add $SMALLFILE"
check_allow "non-add git command"                        "git status"
check_allow "git add -A (out of scope, too broad to scan)" "git add -A"
check_allow "quoted glob (expanded by git, not the shell)"  "git add 'dist/*.so'"
check_allow "path that doesn't exist"                     "git add $REPO/does-not-exist.bin"
check_allow "directory target (guard defers to git's own walk)" "git add $SUBDIR"
check_allow "-f/--force explicit override is honored"     "git add -f $BIGFILE_DEFAULT"

# --- 3. Fails CLOSED with no JSON parser on PATH ------------------------------
NOPARSER="$SANDBOX/noparser-bin"
mkdir -p "$NOPARSER"
ln -s "$(command -v cat)" "$NOPARSER/cat"
run_guard "git add $BIGFILE_DEFAULT" "" "$NOPARSER"
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
# (no "git"+"add"/"stage" substrings in the payload -> exits 0 before ever
# needing a parser), proving the deny above is really about the missing
# parser and not about the sandboxed PATH breaking the guard outright.
run_guard "ls -la /tmp" "" "$NOPARSER"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  echo "ok   - no-parser PATH still allows a non-git-add command (fast path, no parse needed)"; pass=$((pass+1))
else
  echo "FAIL - no-parser PATH broke the non-git-add fast path: rc=$RC out=[$OUT]"; fail=$((fail+1))
fi

# --- Harness portability: Grok CLI camelCase payloads (toolName/toolInput) ----
# Grok delivers camelCase hook stdin; the guard MUST deny adding an oversized
# file exactly as for the snake_case twins above. Regression fixture for the
# dual-path extraction (efc7fef) the Bash guards previously carried untested.
KEY_STYLE=camel
check_deny  "camelCase: large file add still denied" "git add $BIGFILE_DEFAULT" "limit"
check_allow "camelCase: small file add still allowed" "git add $SMALLFILE"
KEY_STYLE=snake

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
