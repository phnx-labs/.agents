#!/usr/bin/env bash
# Regression test for the lib-sourcing fail-safe added when the shared
# git-command parser moved to hooks/lib/git-parse.sh. Each consumer sources the
# lib and, if the parser is not defined afterward, must fail CLOSED (exit 2) —
# a guard that cannot parse a command must refuse, not wave it through.
#
# The shipped "no JSON parser" tests strip PATH but leave both libs on disk, so
# they never exercise this new candidate-loop/source block. This test isolates
# each consumer so json-field.sh IS reachable (via the absolute ~/.agents/.system
# fallback under a fake HOME) but git-parse.sh is NOT — proving the guard gets
# past JSON extraction and then fails closed specifically on the missing parser.
#
# Consumers: the three guards that inspect a git command STRING with the shared
# parser. 01-git-require-clean-tree.sh is deliberately NOT here — it matches
# pull/rebase by substring and never sources git-parse.sh (folding it onto the
# parser would change what it blocks), so it has no git-parse fail-closed path.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
# repo root is three dirs up from hooks/lib/tests/
ROOT=$(cd "$DIR/../../.." && pwd)

SANDBOX=$(mktemp -d)
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

# A fake HOME whose ~/.agents/.system/hooks/lib/ carries json-field.sh but NOT
# git-parse.sh. The guards resolve the JSON extractor here (their relative
# ../lib candidate misses in the isolated copy), pass command extraction, then
# hit the absent git-parse.sh and must fail closed.
FAKEHOME="$SANDBOX/home"
FAKELIB="$FAKEHOME/.agents/.system/hooks/lib"
mkdir -p "$FAKELIB"
cp "$ROOT/hooks/lib/json-field.sh" "$FAKELIB/json-field.sh"
# git-facts.sh is optional for main-branch-guard (it falls back), but copy it so
# the guard's own git-facts source loop is exercised the way it ships.
cp "$ROOT/hooks/lib/git-facts.sh" "$FAKELIB/git-facts.sh" 2>/dev/null || true

# consumer-relpath|trigger-command  (each trigger reaches the git-parse source
# block past that guard's fast path).
CASES="
hooks/pre-tool-use/git-guard.sh|git reset --hard HEAD
hooks/pre-tool-use/large-file-add-guard.sh|git add bigfile.bin
rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh|git commit -m x
"

run_isolated() { # $1=script-relpath  $2=command  -> sets RC, ERR (git-parse unreachable)
  local rel="$1" cmd="$2" name box payload errf
  name=$(basename "$rel")
  box="$SANDBOX/iso.$name.$RANDOM"
  mkdir -p "$box"
  cp "$ROOT/$rel" "$box/$name"          # copied alone: no matching ../lib sibling for git-parse
  chmod +x "$box/$name"
  payload=$(printf '{"tool_name":"Bash","toolName":"Bash","cwd":"%s","tool_input":{"command":"%s"},"toolInput":{"command":"%s"}}' "$box" "$cmd" "$cmd")
  errf="$box/err"
  OUT=$(printf '%s' "$payload" | HOME="$FAKEHOME" "$box/$name" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf" 2>/dev/null)
}

printf '%s\n' "$CASES" | while IFS='|' read -r rel cmd; do
  [ -n "$rel" ] || continue
  run_isolated "$rel" "$cmd"
  name=$(basename "$rel")
  if [ "$RC" != 2 ]; then
    printf 'FAIL - %s: git-parse-absent expected rc=2, got rc=%s (stderr: %s)\n' "$name" "$RC" "$ERR"
    echo fail >>"$SANDBOX/results"; continue
  fi
  if ! printf '%s' "$ERR" | grep -q 'shared git-parse lib not found'; then
    printf 'FAIL - %s: rc=2 but stderr missing the git-parse fail-closed reason: %s\n' "$name" "$ERR"
    echo fail >>"$SANDBOX/results"; continue
  fi
  printf 'ok   - %s fails closed (exit 2) when the shared git-parse lib is unreachable\n' "$name"
  echo pass >>"$SANDBOX/results"
done

# Note: json-field.sh being reachable is already proven by the cases above —
# each guard got PAST JSON command extraction to emit the git-parse-specific
# reason. Had json-field been unreachable, the guard would have exited on the
# "shared json-field lib not found" path and the grep above would have failed.

pass=$(grep -c '^pass$' "$SANDBOX/results" 2>/dev/null); pass=${pass:-0}
fail=$(grep -c '^fail$' "$SANDBOX/results" 2>/dev/null); fail=${fail:-0}
printf '\ngit-parse-sourcing: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
