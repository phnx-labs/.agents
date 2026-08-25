#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../01-github-ratelimit-nudge.py"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT; export TMPDIR="$SANDBOX"
run() { printf '%s' "$1" | python3 "$HOOK" 2>/tmp/gh_nudge_err; }
pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { echo "FAIL - $1"; fail=$((fail+1)); }

# --- fires on a REAL rate-limit hit ----------------------------------------

# 1. gh secondary rate limit on stderr -> nudges.
out=$(run '{"tool_name":"Bash","session_id":"s1","tool_input":{"command":"gh pr comment 12 --body x"},"tool_response":{"stdout":"","stderr":"You have exceeded a secondary rate limit and have been temporarily blocked from content creation. Please retry your request again later."}}')
printf '%s' "$out" | grep -q "github rate-limited" || bad "secondary rate limit did not nudge"; ok

# 2. Same session again -> silent (once per session).
out=$(run '{"tool_name":"Bash","session_id":"s1","tool_input":{"command":"gh api /rate_limit"},"tool_response":{"stderr":"API rate limit exceeded for user"}}')
[ -z "$out" ] || bad "second nudge in same session"; ok

# 3. Primary API rate limit on gh stderr, new session -> nudges.
out=$(run '{"tool_name":"Bash","session_id":"s2","tool_input":{"command":"gh api repos/o/r"},"tool_response":{"stdout":"","stderr":"gh: API rate limit exceeded for user ID 5.","exit_code":1}}')
printf '%s' "$out" | grep -q "agents browser" || bad "primary gh rate limit did not nudge"; ok

# 4. curl 403 body on stdout (curl exits 0) to api.github.com -> nudges (structured, short).
out=$(run '{"tool_name":"Bash","session_id":"s3","tool_input":{"command":"curl https://api.github.com/repos/o/r"},"tool_response":{"stdout":"{\"message\":\"API rate limit exceeded for 1.2.3.4\",\"documentation_url\":\"https://docs.github.com/rest\"}","stderr":""}}')
printf '%s' "$out" | grep -q "github rate-limited" || bad "curl structured 403 did not nudge"; ok

# 5. Grok camelCase payload, stderr hit -> nudges.
out=$(run '{"toolName":"run_terminal_command","sessionId":"s4","toolInput":{"command":"gh issue list"},"toolResponse":{"stderr":"HTTP 403: API rate limit exceeded (https://api.github.com/)"}}')
printf '%s' "$out" | grep -q "github rate-limited" || bad "camelCase payload did not nudge"; ok

# --- must NOT nudge (the reviewer's false-positive repros) ------------------

# 6. `cat` of this hook's own source (prose mentions "rate limit exceeded") -> silent (command not a GitHub call).
SRC="$(cat "$HOOK")"
out=$(printf '%s' "{\"tool_name\":\"Bash\",\"session_id\":\"s5\",\"tool_input\":{\"command\":\"cat hooks/post-tool-use/01-github-ratelimit-nudge.py\"},\"tool_response\":$(python3 -c 'import json,sys;print(json.dumps({"stdout":open(sys.argv[1]).read(),"stderr":""}))' "$HOOK")}" | python3 "$HOOK")
[ -z "$out" ] || bad "cat of hook source nudged"; ok

# 7. `grep` of the CHANGELOG entry -> silent (command not a GitHub call).
out=$(run '{"tool_name":"Bash","session_id":"s6","tool_input":{"command":"grep -A5 ratelimit-nudge CHANGELOG.md"},"tool_response":{"stdout":"- the primary API rate limit exceeded, the secondary rate limit, or an x-ratelimit-remaining: 0 header","stderr":""}}')
[ -z "$out" ] || bad "grep of CHANGELOG prose nudged"; ok

# 8. SUCCESSFUL `gh pr diff` whose large stdout contains the trigger prose (and even a structured body) -> silent (clean stderr, exit 0, stdout too large for the structured branch).
big=$(python3 -c 'print("+ some diff line\n"*300 + "+ {\"message\":\"API rate limit exceeded for x\"}\n" + "+ rate limit exceeded appears as prose here\n" + "+ more\n"*300)')
out=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","session_id":"s7","tool_input":{"command":"gh pr diff 391 --repo phnx-labs/.agents-system"},"tool_response":{"stdout":sys.argv[1],"stderr":"","exit_code":0}}))' "$big" | python3 "$HOOK")
[ -z "$out" ] || bad "successful gh pr diff nudged on prose"; ok

# 9. Rate-limit prose only in the COMMAND, clean non-github output -> silent.
out=$(run '{"tool_name":"Bash","session_id":"s8","tool_input":{"command":"grep -r \"rate limit exceeded\" ./gh"},"tool_response":{"stdout":"no matches","stderr":""}}')
[ -z "$out" ] || bad "command-only rate-limit text nudged"; ok

# 10. Rate limit from a NON-github service (stripe) -> silent (not a GitHub call).
out=$(run '{"tool_name":"Bash","session_id":"s9","tool_input":{"command":"curl https://api.stripe.com/v1/charges"},"tool_response":{"stdout":"{\"message\":\"rate limit exceeded\"}","stderr":""}}')
[ -z "$out" ] || bad "non-github rate limit nudged"; ok

# --- fails open, never crashes ---------------------------------------------

# 11. Not JSON at all -> fails open, no output, no traceback.
out=$(run 'rate limit exceeded but not json')
[ -z "$out" ] || bad "non-json input produced output"
grep -qi 'Traceback' /tmp/gh_nudge_err && bad "non-json input crashed"; ok

# 12. Valid JSON but NOT an object (array), with a trigger phrase -> fails open (the SHOULD fix).
out=$(run '["rate limit exceeded","github.com"]')
[ -z "$out" ] || bad "non-dict JSON produced output"
grep -qi 'Traceback' /tmp/gh_nudge_err && bad "non-dict JSON crashed (AttributeError)"; ok

# 13. Clean successful gh call, no rate limit -> silent.
out=$(run '{"tool_name":"Bash","session_id":"s10","tool_input":{"command":"gh pr list"},"tool_response":{"stdout":"#390 merged\n#389 merged","stderr":"","exit_code":0}}')
[ -z "$out" ] || bad "clean gh output nudged"; ok

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
