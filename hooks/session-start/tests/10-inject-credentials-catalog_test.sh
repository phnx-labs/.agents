#!/usr/bin/env bash
# Drives the real `secrets` CLI against a throwaway store and asserts the
# injected catalog: bundle names and descriptions, never a value, no harness
# worker bundles, and silence when there is nothing to report.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../10-inject-credentials-catalog.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "ok   - $1"
  else fail=$((fail + 1)); echo "FAIL - $1: expected [$3], got [$2]"; fi
}
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

command -v secrets >/dev/null || { echo "SKIP - secrets CLI not installed"; exit 0; }

export HOME="$SANDBOX" SECRETS_HOME="$SANDBOX/secrets" SECRETS_PASSPHRASE=test-only SECRETS_NO_USAGE_TRACK=1

out=$(python3 "$HOOK" </dev/null); rc=$?
check "empty store -> exit 0" "$rc" "0"
check "empty store -> silent" "$(has "$out" "## Credentials")" "no"

secrets create stripe.com --description "Stripe test account" >/dev/null 2>&1
secrets add stripe.com STRIPE_SECRET_KEY --value sk_test_placeholder >/dev/null 2>&1
secrets add stripe.com STRIPE_WEBHOOK_SECRET --value whsec_placeholder >/dev/null 2>&1
secrets create linear.app >/dev/null 2>&1
secrets create __codex__ >/dev/null 2>&1

out=$(python3 "$HOOK" </dev/null); rc=$?
check "exit 0" "$rc" "0"
check "header present" "$(has "$out" "## Credentials you can reach")" "yes"
check "bundle with key count and description" \
  "$(printf '%s\n' "$out" | grep -c 'stripe.com  2 keys  Stripe test account')" "1"
check "bundle without description listed" "$(has "$out" "- linear.app")" "yes"
check "harness worker bundle omitted" "$(has "$out" "__codex__")" "no"
check "no value leaks" "$(has "$out" "placeholder")" "no"
check "tells the agent how to use it" "$(has "$out" "secrets exec <bundle> -- <cmd>")" "yes"

# Signed-in browser profiles render as profile: service as account (pure logic;
# the live source is `browser profiles logins --json`).
r=$(python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("inj", "'"$HOOK"'")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.render({"bundles": [], "logins": [
  {"profile": "work", "service": "github", "account": "octo"},
  {"profile": "work", "service": "google", "account": ""}]}, "box"))
')
check "browser logins grouped per profile" \
  "$(has "$r" "- work: github as octo, google")" "yes"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
