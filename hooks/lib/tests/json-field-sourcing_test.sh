#!/usr/bin/env bash
# Regression test for the lib-sourcing fail-safe added when _json_field moved to
# hooks/lib/json-field.sh. Each of the 12 consumers sources the lib and, if it
# cannot be found, must take its declared fail-safe: block guards refuse
# (exit 2), advisory hooks skip (exit 0). The shipped "no JSON parser" tests
# strip PATH but leave the lib file on disk, so they exercise the downstream
# parse path, NOT this new candidate-loop/source block. This test isolates each
# consumer so BOTH lib candidates miss — the script copied to a dir with no
# ../lib sibling, and HOME pointed at an empty dir so the absolute
# ~/.agents/.system fallback also misses — and asserts the fail-safe fires.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
# repo root is three dirs up from hooks/lib/tests/
ROOT=$(cd "$DIR/../../.." && pwd)
pass=0
fail=0

SANDBOX=$(mktemp -d)
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT
NOHOME="$SANDBOX/nohome"
mkdir -p "$NOHOME"

# consumer|expected_rc|trigger-command
# The trigger reaches each consumer's source block past any pre-source fast path
# (large-file needs a `git add`, public-artifact an artifacts path, etc.).
CASES="
hooks/pre-tool-use/git-guard.sh|2|git reset --hard HEAD
hooks/pre-tool-use/rm-guard.sh|2|rm -rf /some/path
hooks/pre-tool-use/secrets-guard.sh|2|agents secrets export x --plaintext
hooks/pre-tool-use/large-file-add-guard.sh|2|git add bigfile.bin
hooks/pre-tool-use/public-artifact-guard.sh|2|git add .agents/artifacts/2026-08-23/x.md
hooks/pre-tool-use/01-git-require-clean-tree.sh|2|git pull
rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh|2|git commit -m x
rules/subrules/gh-merge-guard/merge-guard.sh|2|gh pr merge --admin 1
rules/subrules/no-pr-footer/footer-guard.sh|2|gh pr create --body x
rules/subrules/parallel-teams/teams-roster-guard.sh|0|agents teams add t kimi x
rules/subrules/truly-agentic-git-workflow/pr-description-reminder.sh|0|gh pr create --body x
"

run_isolated() { # $1=script-relpath  -> sets RC, ERR (lib made unreachable)
  local rel="$1" cmd="$2" name payload
  name=$(basename "$rel")
  local box="$SANDBOX/iso.$name.$RANDOM"
  mkdir -p "$box"
  cp "$ROOT/$rel" "$box/$name"          # copied alone: no ../lib sibling
  chmod +x "$box/$name"
  payload=$(printf '{"tool_name":"Bash","toolName":"Bash","cwd":"%s","tool_input":{"command":"%s"},"toolInput":{"command":"%s"}}' "$box" "$cmd" "$cmd")
  local errf="$box/err"
  # HOME points at an empty dir so ~/.agents/.system/hooks/lib/json-field.sh
  # also misses; PATH keeps coreutils so ${0%/*}/cd/pwd still resolve. Invoke via
  # the script's own shebang (some guards are #!/bin/bash and use read -d), the
  # way the harness runs them — not a forced `sh`.
  OUT=$(printf '%s' "$payload" | HOME="$NOHOME" "$box/$name" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf" 2>/dev/null)
}

printf '%s\n' "$CASES" | while IFS='|' read -r rel want cmd; do
  [ -n "$rel" ] || continue
  run_isolated "$rel" "$cmd"
  name=$(basename "$rel")
  if [ "$RC" != "$want" ]; then
    printf 'FAIL - %s: lib-absent expected rc=%s, got rc=%s (stderr: %s)\n' "$name" "$want" "$RC" "$ERR"
    echo fail >>"$SANDBOX/results"; continue
  fi
  if [ "$want" = 2 ] && ! printf '%s' "$ERR" | grep -q 'shared json-field lib not found'; then
    printf 'FAIL - %s: rc=2 but stderr missing the fail-closed reason: %s\n' "$name" "$ERR"
    echo fail >>"$SANDBOX/results"; continue
  fi
  verb=$( [ "$want" = 2 ] && echo 'fails closed (exit 2)' || echo 'fails open (exit 0)' )
  printf 'ok   - %s %s when the shared lib is unreachable\n' "$name" "$verb"
  echo pass >>"$SANDBOX/results"
done

# 09-git-pull-forward is SessionStart (payload has no command); test separately.
run_isolated "hooks/session-start/09-git-pull-forward.sh" ""
if [ "$RC" = 0 ]; then
  printf 'ok   - 09-git-pull-forward.sh fails open (exit 0) when the shared lib is unreachable\n'
  echo pass >>"$SANDBOX/results"
else
  printf 'FAIL - 09-git-pull-forward.sh: lib-absent expected rc=0, got rc=%s\n' "$RC"
  echo fail >>"$SANDBOX/results"
fi

# grep -c prints the count (0 when none) even as it exits 1 on no match, so take
# its stdout and don't chain `|| echo 0` (which would append a second line).
pass=$(grep -c '^pass$' "$SANDBOX/results" 2>/dev/null); pass=${pass:-0}
fail=$(grep -c '^fail$' "$SANDBOX/results" 2>/dev/null); fail=${fail:-0}
printf '\njson-field-sourcing: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
