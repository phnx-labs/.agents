#!/usr/bin/env bash
# Tests for 10-mq-read-nudge.py — the PreToolUse Read nudge toward `mq`.
# Hermetic: files live in a sandbox; TMPDIR is pointed at the sandbox so the
# hook's dedup markers are isolated and cleaned up. No network, no real session.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/10-mq-read-nudge.py"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export TMPDIR="$SANDBOX"   # hook markers land here, wiped on exit

fail=0
check_contains() { if printf '%s' "$2" | grep -qF "$3"; then echo "ok   - $1"; else echo "FAIL - $1: output missing [$3]"; fail=1; fi; }
check_empty()    { if [ -z "$2" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected empty output, got [$2]"; fail=1; fi; }

# --- fixtures ----------------------------------------------------------------
BIG="$SANDBOX/big.ts"      # >16 KiB supported file
SMALL="$SANDBOX/small.md"  # tiny supported file
python3 - "$BIG" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(600):
        f.write(f"export function fn{i}(): number {{ return {i} * 2; }}\n")
PY
printf '# tiny\njust a couple lines\n' > "$SMALL"

# Payloads are built inline: single-quote the static JSON, break out only for
# the interpolated path. No python round-trip (that was a fragile quoting sink).
run_hook() { printf '%s' "$1" | python3 "$HOOK" 2>/dev/null; }

# 1. large supported file, plain read -> nudge
out="$(run_hook '{"tool_name":"Read","session_id":"A","tool_input":{"file_path":"'"$BIG"'"}}')"
check_contains "large read nudges" "$out" "[mq]"
check_contains "nudge names the file" "$out" "big.ts"
check_contains "nudge suggests .tree" "$out" ".tree"

# 2. same file + same session -> deduped (silent)
out="$(run_hook '{"tool_name":"Read","session_id":"A","tool_input":{"file_path":"'"$BIG"'"}}')"
check_empty "second read of same file+session is silent" "$out"

# 3. same file, new session -> nudges again
out="$(run_hook '{"tool_name":"Read","session_id":"B","tool_input":{"file_path":"'"$BIG"'"}}')"
check_contains "new session nudges again" "$out" "[mq]"

# 4. small file -> silent
out="$(run_hook '{"tool_name":"Read","session_id":"C","tool_input":{"file_path":"'"$SMALL"'"}}')"
check_empty "small file is silent" "$out"

# 5. targeted read (offset/limit) -> silent (agent already narrowing)
out="$(run_hook '{"tool_name":"Read","session_id":"D","tool_input":{"file_path":"'"$BIG"'","offset":10,"limit":20}}')"
check_empty "targeted read is silent" "$out"

# 6. unsupported extension -> silent
cp "$BIG" "$SANDBOX/blob.bin"
out="$(run_hook '{"tool_name":"Read","session_id":"E","tool_input":{"file_path":"'"$SANDBOX/blob.bin"'"}}')"
check_empty "unsupported extension is silent" "$out"

# 7. non-Read tool -> silent
out="$(run_hook '{"tool_name":"Bash","session_id":"F","tool_input":{"command":"cat big.ts"}}')"
check_empty "non-Read tool is silent" "$out"

# 8. malformed json -> silent (fail-open)
out="$(run_hook "not json at all")"
check_empty "malformed payload is silent" "$out"

# 9. missing file on disk -> silent (can't stat)
out="$(run_hook '{"tool_name":"Read","session_id":"G","tool_input":{"file_path":"'"$SANDBOX/nope.ts"'"}}')"
check_empty "nonexistent file is silent" "$out"

if [ "$fail" -eq 0 ]; then echo "PASS"; else echo "FAILURES"; exit 1; fi
