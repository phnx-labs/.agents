#!/usr/bin/env bash
# Tests for 02-worktree-reclaim-nudge.py — the PostToolUse nudge that fires after
# a PR merge so the worktree gets reclaimed (PHNX-3503).
#
# The whole risk in this hook is its FIRING RULE. It must fire on a real merge
# and stay silent everywhere else — including on a `gh pr diff` whose output
# literally contains this hook's own source, which is the trap that
# 01-github-ratelimit-nudge documents and which a naive substring match fails.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../02-worktree-reclaim-nudge.py"
pass=0; fail=0

# Each case gets a distinct session id, derived from its LABEL rather than a
# counter. A counter does not work here: payload() is invoked inside $(...), a
# subshell, so an increment never reaches the parent — every case would reuse one
# id, the once-per-session stamp would silence everything after the first fire,
# and every later "silent" expectation would pass for the wrong reason.
payload() { # <command> <stdout> <exit_code> <session-key>
  python3 -c '
import json,sys
print(json.dumps({
  "tool_name":"Bash",
  "session_id":sys.argv[4],
  "tool_input":{"command":sys.argv[1]},
  "tool_response":{"stdout":sys.argv[2],"stderr":"","exit_code":int(sys.argv[3])},
}))' "$1" "$2" "$3" "$4"
}

expect() { # <label> <want: fire|silent> <command> <stdout> <exit>
  local label="$1" want="$2"
  local sid="wt-nudge-test-$$-$(printf '%s' "$label" | cksum | cut -d' ' -f1)"
  local out; out=$(payload "$3" "$4" "$5" "$sid" | python3 "$HOOK" 2>/dev/null)
  local got="silent"
  [ -n "$out" ] && got="fire"
  if [ "$got" = "$want" ]; then
    echo "ok   - $label"; pass=$((pass+1))
  else
    echo "FAIL - $label: wanted $want, got $got"; fail=$((fail+1))
  fi
}

echo "worktree-reclaim-nudge"

# --- fires on a real, successful merge -------------------------------------
expect "gh pr merge --rebase succeeds" fire \
  "gh pr merge 421 --rebase --delete-branch" "Merged pull request #421" 0
expect "REST merge succeeds" fire \
  'gh api -X PUT repos/o/r/pulls/12/merge' '{"merged":true,"message":"Pull Request successfully merged"}' 0

# --- silent on everything that is not a completed merge --------------------
expect "gh pr view is not a merge" silent \
  "gh pr view 421 --json state" '{"state":"MERGED"}' 0
expect "gh pr list is not a merge" silent \
  "gh pr list --state merged" "421  merged  fix things" 0
expect "failed merge (non-zero exit)" silent \
  "gh pr merge 421 --rebase" "" 1
expect "failed merge (not mergeable)" silent \
  "gh pr merge 421 --rebase" "GraphQL: Pull request is not mergeable" 0
expect "blocked merge (review required)" silent \
  "gh pr merge 421 --rebase" "review is required by reviewers with write access" 0
expect "merge attempt that says nothing succeeded" silent \
  "gh pr merge 421 --rebase" "" 0

# --- the documented trap: prose that MENTIONS merging ----------------------
# A diff of this very hook contains the string "gh pr merge" in its docstring.
expect "gh pr diff carrying this hook's own source" silent \
  "gh pr diff 500" "+# ... a \`gh pr merge\` reference in a docstring ... merged" 0
expect "grep of a file mentioning gh pr merge" silent \
  "grep -rn 'gh pr merge' hooks/" "hooks/x.py:12: # gh pr merge ... merged" 0
expect "cat of a changelog naming the merge" silent \
  "cat CHANGELOG.md" "- fires after gh pr merge; the PR was merged" 0

# --- a STRING exit code must still gate ------------------------------------
# `isinstance(exit_code, int)` skipped the check for any other type, so a harness
# serialising exit_code as "1" fired the nudge on a FAILED merge (found in review).
out=$(python3 -c '
import json
print(json.dumps({"tool_name":"Bash","session_id":"wt-strexit-'"$$"'",
  "tool_input":{"command":"gh pr merge 9 --rebase"},
  "tool_response":{"stdout":"merged","stderr":"","exit_code":"1"}}))' | python3 "$HOOK" 2>/dev/null)
if [ -z "$out" ]; then echo "ok   - string non-zero exit code still gates"; pass=$((pass+1)); else echo "FAIL - string exit code bypassed the gate"; fail=$((fail+1)); fi
out=$(python3 -c '
import json
print(json.dumps({"tool_name":"Bash","session_id":"wt-strexit0-'"$$"'",
  "tool_input":{"command":"gh pr merge 9 --rebase"},
  "tool_response":{"stdout":"Merged pull request #9","stderr":"","exit_code":"0"}}))' | python3 "$HOOK" 2>/dev/null)
if [ -n "$out" ]; then echo "ok   - string zero exit code still fires"; pass=$((pass+1)); else echo "FAIL - string 0 wrongly suppressed the nudge"; fail=$((fail+1)); fi

# --- once per session ------------------------------------------------------
sid="wt-nudge-once-$$"
one=$(python3 -c '
import json
print(json.dumps({"tool_name":"Bash","session_id":"'"$sid"'",
  "tool_input":{"command":"gh pr merge 1 --rebase"},
  "tool_response":{"stdout":"Merged pull request #1","stderr":"","exit_code":0}}))')
first=$(printf '%s' "$one" | python3 "$HOOK" 2>/dev/null)
second=$(printf '%s' "$one" | python3 "$HOOK" 2>/dev/null)
if [ -n "$first" ] && [ -z "$second" ]; then
  echo "ok   - nudges once per session, not on every merge"; pass=$((pass+1))
else
  echo "FAIL - once-per-session: first='${first:0:20}' second='${second:0:20}'"; fail=$((fail+1))
fi

# --- non-Bash tools and malformed input never fire -------------------------
out=$(echo '{"tool_name":"Write","tool_input":{"command":"gh pr merge 1"}}' | python3 "$HOOK" 2>/dev/null)
if [ -z "$out" ]; then echo "ok   - non-Bash tool ignored"; pass=$((pass+1)); else echo "FAIL - non-Bash tool fired"; fail=$((fail+1)); fi
out=$(echo 'not json' | python3 "$HOOK" 2>/dev/null); rc=$?
if [ -z "$out" ] && [ "$rc" -eq 0 ]; then echo "ok   - malformed payload fails open"; pass=$((pass+1)); else echo "FAIL - malformed payload"; fail=$((fail+1)); fi

# --- camelCase (Grok) payloads --------------------------------------------
out=$(python3 -c '
import json
print(json.dumps({"toolName":"Bash","sessionId":"wt-camel-'"$$"'",
  "toolInput":{"command":"gh pr merge 7 --rebase"},
  "toolResponse":{"stdout":"Merged pull request #7","stderr":"","exit_code":0}}))' | python3 "$HOOK" 2>/dev/null)
if [ -n "$out" ]; then echo "ok   - camelCase payload fires"; pass=$((pass+1)); else echo "FAIL - camelCase payload silent"; fail=$((fail+1)); fi

echo "---"
echo "worktree-reclaim-nudge: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
