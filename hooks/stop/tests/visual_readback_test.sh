#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
MODULE="$HERE/../visual_readback.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "ok   - $1"
  else fail=$((fail + 1)); echo "FAIL - $1: expected [$3], got [$2]"; fi
}

inspect() {
  PYTHONPATH="$HERE/.." python3 - "$1" <<'PY'
import json, sys
from visual_readback import inspect_transcript
print(json.dumps(inspect_transcript(sys.argv[1]), sort_keys=True))
PY
}

blind="$SANDBOX/blind.jsonl"
cat > "$blind" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w1","name":"Write","input":{"file_path":"/tmp/mockup.html"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"s1","name":"Bash","input":{"command":"scp /tmp/mockup.html zion:/tmp/ && agents ssh zion 'open /tmp/mockup.html'"}}]}}
EOF
out=$(inspect "$blind")
check "scratch visual is authored" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_authored"])')" "True"
check "scratch visual leaving the session is delivery" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_delivered"])')" "True"
check "blind delivery has no read-back" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_read_back"])')" "False"

disciplined="$SANDBOX/disciplined.jsonl"
cp "$blind" "$disciplined"
cat >> "$disciplined" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"v1","name":"view_image","input":{"path":"/tmp/mockup.png"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"v1","content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"AA=="}}]}]}}
EOF
# The screenshot is itself an authored visual and must precede its read-back.
sed -i '2i {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c1","name":"Bash","input":{"command":"agents browser screenshot -o /tmp/mockup.png"}}]}}' "$disciplined"
out=$(inspect "$disciplined")
check "disciplined session records paired image read-back" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_read_back"])')" "True"

# `agents browser navigate --url file://<artifact>` is one valid way to put a rendered
# plan/visual in front of the user — the optional tab-reuse refinement; opening it in the
# user's DEFAULT browser (`open`/`xdg-open`, covered by the blind case above) is the
# primary path. The navigate path must still count as delivery, or the read-back gate
# silently stops firing for it.
navigate_blind="$SANDBOX/navigate_blind.jsonl"
cat > "$navigate_blind" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w1","name":"Write","input":{"file_path":"/tmp/plan.html"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"n1","name":"Bash","input":{"command":"scp /tmp/plan.html zion:/tmp/ && agents ssh zion 'agents browser navigate --url file:///tmp/plan.html'"}}]}}
EOF
out=$(inspect "$navigate_blind")
check "browser navigate of a visual counts as delivery" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_delivered"])')" "True"
check "browser navigate delivery with no read-back is caught" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_read_back"])')" "False"

overwritten="$SANDBOX/overwritten.jsonl"
cp "$disciplined" "$overwritten"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w2","name":"Write","input":{"file_path":"/tmp/mockup.png"}}]}}' >> "$overwritten"
out=$(inspect "$overwritten")
check "read-back before the latest overwrite does not clear it" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_read_back"])')" "False"

automatic="$SANDBOX/automatic.jsonl"
cat > "$automatic" <<'EOF'
{"type":"item.completed","item":{"id":"shot1","type":"command_execution","command":"agents browser screenshot","aggregated_output":"Screenshot saved to /tmp/browser-shot.png"}}
{"type":"response_item","payload":{"type":"function_call","call_id":"view1","name":"view_image","arguments":"{\"path\":\"/tmp/browser-shot.png\"}"}}
{"type":"response_item","payload":{"type":"function_call_output","call_id":"view1","output":[{"type":"input_image","image_url":"data:image/png;base64,AA=="}]}}
EOF
out=$(inspect "$automatic")
check "Codex auto-named screenshot output is authored" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_authored"])')" "True"
check "Codex input_image read-back clears the render" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["visual_read_back"])')" "True"

malformed="$SANDBOX/malformed.jsonl"
printf 'not-json\n' > "$malformed"
out=$(inspect "$malformed")
check "malformed transcript fails open" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["parser_supported"])')" "False"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
