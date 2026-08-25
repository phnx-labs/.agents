#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../01-github-ratelimit-nudge.py"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT; export TMPDIR="$SANDBOX"
run() { printf '%s' "$1" | python3 "$HOOK"; }
pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { echo "FAIL - $1"; fail=$((fail+1)); }

# 1. gh secondary rate limit in output -> nudges.
out=$(run '{"tool_name":"Bash","session_id":"s1","tool_input":{"command":"gh pr comment 12 --body x"},"tool_response":{"stdout":"","stderr":"You have exceeded a secondary rate limit. Please retry your request again later."}}')
printf '%s' "$out" | grep -q "github rate-limited" || bad "secondary rate limit did not nudge"; ok

# 2. Same session again -> silent (once per session).
out=$(run '{"tool_name":"Bash","session_id":"s1","tool_input":{"command":"gh api /rate_limit"},"tool_response":{"stderr":"API rate limit exceeded for user"}}')
[ -z "$out" ] || bad "second nudge in same session"; ok

# 3. Primary API rate limit, new session -> nudges.
out=$(run '{"tool_name":"Bash","session_id":"s2","tool_input":{"command":"curl https://api.github.com/repos/o/r"},"tool_response":{"stdout":"{\"message\":\"API rate limit exceeded for 1.2.3.4\"}"}}')
printf '%s' "$out" | grep -q "agents browser" || bad "primary API rate limit did not nudge"; ok

# 4. Successful gh call, no rate limit -> silent.
out=$(run '{"tool_name":"Bash","session_id":"s3","tool_input":{"command":"gh pr list"},"tool_response":{"stdout":"#390 merged\n#389 merged"}}')
[ -z "$out" ] || bad "clean gh output nudged"; ok

# 5. Rate limit text only in the COMMAND, not the output -> silent (no false trip).
out=$(run '{"tool_name":"Bash","session_id":"s4","tool_input":{"command":"grep -r \"rate limit\" ./gh"},"tool_response":{"stdout":"no matches"}}')
[ -z "$out" ] || bad "command-only rate-limit text nudged"; ok

# 6. Rate limit from a NON-github service -> silent (github-gated).
out=$(run '{"tool_name":"Bash","session_id":"s5","tool_input":{"command":"curl https://api.stripe.com/v1/charges"},"tool_response":{"stdout":"rate limit exceeded"}}')
[ -z "$out" ] || bad "non-github rate limit nudged"; ok

# 7. Malformed input -> fails open (no crash, no output).
out=$(run 'not-json-at-all')
[ -z "$out" ] || bad "malformed input did not fail open"; ok

# 8. camelCase (Grok) payload with rate limit -> nudges.
out=$(run '{"toolName":"run_terminal_command","sessionId":"s6","toolInput":{"command":"gh issue list"},"toolResponse":{"stderr":"HTTP 403: API rate limit exceeded (https://api.github.com/)"}}')
printf '%s' "$out" | grep -q "github rate-limited" || bad "camelCase payload did not nudge"; ok

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
