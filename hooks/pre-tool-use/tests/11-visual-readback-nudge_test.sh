#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../11-visual-readback-nudge.py"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT; export TMPDIR="$SANDBOX"
run() { printf '%s' "$1" | python3 "$HOOK"; }
out=$(run '{"tool_name":"Bash","session_id":"one","tool_input":{"command":"scp /tmp/mockup.html zion:/tmp/"}}')
printf '%s' "$out" | grep -q 'visual read-back' || { echo "FAIL - ship did not nudge"; exit 1; }
out=$(run '{"tool_name":"Bash","session_id":"one","tool_input":{"command":"scp /tmp/mockup.html zion:/tmp/"}}')
[ -z "$out" ] || { echo "FAIL - duplicate nudge"; exit 1; }
out=$(run '{"tool_name":"Bash","session_id":"two","tool_input":{"command":"echo /tmp/mockup.html"}}')
[ -z "$out" ] || { echo "FAIL - non-ship nudged"; exit 1; }
out=$(run 'not-json')
[ -z "$out" ] || { echo "FAIL - malformed input did not fail open"; exit 1; }
echo "4 passed, 0 failed"
