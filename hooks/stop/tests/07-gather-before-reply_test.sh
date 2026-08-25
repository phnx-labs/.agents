#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../07-gather-before-reply.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "ok   - $1"
  else fail=$((fail + 1)); echo "FAIL - $1: expected [$3], got [$2]"; fi
}

# Run the hook against a transcript file; echo "FIRED" if it injected guidance,
# "SILENT" otherwise. Asserts exit 0 in every case (advisory, never blocks).
run() {
  local transcript="$1" out rc
  out=$(printf '{"transcript_path":%s}' "\"$transcript\"" | python3 "$HOOK"; echo "rc=$?")
  rc="${out##*rc=}"
  out="${out%rc=*}"
  [ "$rc" -eq 0 ] || { echo "FAIL - hook exited $rc (must be 0)"; fail=$((fail + 1)); }
  if [ -n "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then echo "FIRED"; else echo "SILENT"; fi
}

# 1. User typed a message, agent replied with text only, no tool call → FIRED.
f="$SANDBOX/no-gather.jsonl"
cat > "$f" <<'EOF'
{"type":"user","message":{"role":"user","content":"why do we still have these env vars?"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"You're exactly right on all three points."}]}}
EOF
check "no tool call since user message -> fires" "$(run "$f")" "FIRED"

# 2. Agent made a tool call after the user message → SILENT.
f="$SANDBOX/gathered.jsonl"
cat > "$f" <<'EOF'
{"type":"user","message":{"role":"user","content":"why do we still have these env vars?"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Grep","input":{"pattern":"SANDBOX_POOL_ENABLED"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"They route every agent to the pool. Here is why."}]}}
EOF
check "a tool call since user message -> silent" "$(run "$f")" "SILENT"

# 3. A Skill invocation is a tool call → SILENT.
f="$SANDBOX/used-skill.jsonl"
cat > "$f" <<'EOF'
{"type":"user","message":{"role":"user","content":"design the release flow"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"s1","name":"Skill","input":{"skill":"release"}}]}}
EOF
check "a skill invocation counts as gathering -> silent" "$(run "$f")" "SILENT"

# 4. A tool_result is type:user but is NOT a user message, so it does not reset
#    the boundary: the tool_use before it still counts as gathering → SILENT.
f="$SANDBOX/tool-result-not-boundary.jsonl"
cat > "$f" <<'EOF'
{"type":"user","message":{"role":"user","content":"check the sandbox routing"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"grep -rn SANDBOX ."}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"match"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Found it, here is the routing."}]}}
EOF
check "tool_result is not a user boundary -> silent" "$(run "$f")" "SILENT"

# 5. A message queued mid-turn (queue-operation) counts as the user speaking:
#    reply with no tool call after it → FIRED.
f="$SANDBOX/queue-op.jsonl"
cat > "$f" <<'EOF'
{"type":"user","message":{"role":"user","content":"first question"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"a.ts"}}]}}
{"type":"queue-operation","content":"actually, push back: why is it required?"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"You are right, let's remove it."}]}}
EOF
check "queued mid-turn message is a boundary -> fires" "$(run "$f")" "FIRED"

# 6. Fail open: a missing transcript path must not block, must stay silent.
check "missing transcript -> silent (fail open)" "$(run "$SANDBOX/does-not-exist.jsonl")" "SILENT"

# 7. Fail open: malformed JSON lines must not block, must stay silent.
f="$SANDBOX/malformed.jsonl"
printf 'not json at all\n{"type":"user"\n' > "$f"
check "malformed transcript -> silent (fail open)" "$(run "$f")" "SILENT"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
