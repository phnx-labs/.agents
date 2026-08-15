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

malformed="$SANDBOX/malformed.jsonl"
printf 'not-json\n' > "$malformed"
out=$(inspect "$malformed")
check "malformed transcript fails open" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["parser_supported"])')" "False"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
