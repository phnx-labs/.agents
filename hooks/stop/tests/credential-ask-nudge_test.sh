#!/usr/bin/env bash
# Drives the real `secrets` CLI against a throwaway store (HOME and SECRETS_HOME
# both point into a sandbox), so the catalog the hook matches against is real.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../credential-ask-nudge.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "ok   - $1"
  else fail=$((fail + 1)); echo "FAIL - $1: expected [$3], got [$2]"; fi
}

command -v secrets >/dev/null || { echo "SKIP - secrets CLI not installed"; exit 0; }

export HOME="$SANDBOX" SECRETS_HOME="$SANDBOX/secrets" SECRETS_PASSPHRASE=test-only SECRETS_NO_USAGE_TRACK=1
secrets create stripe.com --description "Stripe test account" >/dev/null 2>&1
secrets add stripe.com STRIPE_SECRET_KEY --value sk_test_placeholder >/dev/null 2>&1
secrets create __claude__ >/dev/null 2>&1
# Generic bundle names a real machine carries; none may turn an ordinary word
# into a match (review finding on #481).
for b in share auth prod; do secrets create "$b" >/dev/null 2>&1; done

# Runs the hook; prints "BLOCK" (exit 2 + message on stderr) or "PASS" (exit 0).
run() {
  local msg="$1" sid="${2-s1}" transcript="${3:-}" active="${4:-false}" err rc
  err=$(python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"last_assistant_message":sys.argv[2],"transcript_path":sys.argv[3],"stop_hook_active":sys.argv[4]=="true"}))' \
    "$sid" "$msg" "$transcript" "$active" | python3 "$HOOK" 2>&1 >/dev/null)
  rc=$?
  LAST_ERR="$err"
  case "$rc" in 2) echo BLOCK ;; 0) echo PASS ;; *) echo "RC$rc" ;; esac
}

ASK="I'm blocked on the billing sync. Can you share the Stripe API key so I can call the API?"

check "credential ask matching a bundle -> blocks" "$(run "$ASK" a)" "BLOCK"
run "$ASK" b >/dev/null
case "$LAST_ERR" in *"secrets exec stripe.com --"*) r=named ;; *) r="$LAST_ERR" ;; esac
check "nudge names the bundle to run under" "$r" "named"
case "$LAST_ERR" in *sk_test_placeholder*) r=leaked ;; *) r=clean ;; esac
check "nudge never contains a value" "$r" "clean"

check "same topic again, same session -> passes" "$(run "$ASK" a)" "PASS"
check "same topic reworded, same session -> passes" \
  "$(run "Could you paste the stripe secret key? I still need it." a)" "PASS"
check "same topic, new session -> blocks" "$(run "$ASK" c)" "BLOCK"

check "credential ask with no catalog match -> passes" \
  "$(run "Can you share the Twilio auth token?" d)" "PASS"
check "generic bundle names never match ordinary words" \
  "$(run "I need your Twilio API key. Please share it so the prod auth check passes." d2)" "PASS"
check "service named far from the credential word -> passes" \
  "$(run "The Stripe dashboard looked fine earlier when I checked the billing graphs and the invoices. Can you share the VPN password?" d3)" "PASS"
check "no session id -> passes (no shared cool-off key)" "$(run "$ASK" "")" "PASS"
check "one-time code ask -> passes" \
  "$(run "Stripe sent a 2FA verification code. Can you give me the code?" e)" "PASS"
check "mentions a credential but asks nothing -> passes" \
  "$(run "I ran the sync under the Stripe API key from the bundle. Done." f)" "PASS"
check "stop_hook_active -> passes" "$(run "$ASK" g "" true)" "PASS"
check "harness worker bundle is never offered" \
  "$(run "Can you give me the claude token?" h)" "PASS"

# A real final message from a headless Claude run: it asked for "the key from
# you" and named STRIPE_SECRET_KEY, never the words "API key". This slipped
# past the first version of the pattern.
check "real ask: 'need the key from you' + env var name -> blocks" \
  "$(run "$(cat "$HERE/testdata/ask-key-from-you.txt")" real1)" "BLOCK"

# The agent already looked at secrets this session (Claude transcript shape):
# its ask is informed, so it passes.
t="$SANDBOX/consulted.jsonl"
cat > "$t" <<'EOF'
{"type":"user","message":{"role":"user","content":"sync billing"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"secrets list --json"}}]}}
EOF
check "already consulted secrets (claude) -> passes" "$(run "$ASK" i "$t")" "PASS"

# Same in the Codex rollout shape.
t="$SANDBOX/consulted-codex.jsonl"
cat > "$t" <<'EOF'
{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"secrets exec stripe.com -- env\"}"}}
EOF
check "already consulted secrets (codex) -> passes" "$(run "$ASK" j "$t")" "PASS"

# The injected catalog text mentions `secrets list` in a non-tool record; that
# must not count as the agent having looked.
t="$SANDBOX/injected-only.jsonl"
cat > "$t" <<'EOF'
{"type":"user","message":{"role":"user","content":"## Credentials you can reach\nOther machines: `secrets list --hosts a,b`"}}
EOF
check "injected catalog text is not a lookup -> blocks" "$(run "$ASK" k "$t")" "BLOCK"

# Matching against signed-in browser profiles (pure logic; the live source is
# `browser profiles logins --json`).
r=$(cd "$HERE/.." && python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("nudge", "credential-ask-nudge.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cat = {"bundles": [], "logins": [{"profile": "work", "service": "github", "account": "octo"}]}
b, l = m.matches("Can you log in to GitHub for me?", cat)
print("work/octo" if l and l[0]["account"] == "octo" and "browser start --profile work" in m.nudge(b, l) else "miss")
')
check "browser login match -> nudge names the profile" "$r" "work/octo"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
