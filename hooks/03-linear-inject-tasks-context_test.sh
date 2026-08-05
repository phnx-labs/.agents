#!/usr/bin/env bash
# Tests for 03-linear-inject-tasks-context.sh — the SessionStart Linear brief.
# curl and agents are stubbed via PATH shims; no network, no keychain, no broker.
# The critical-path assertions: credentials come from the Linear CLI's plaintext
# config.json (LINEAR_CLI_CONFIG fixture), env vars still win, and the hook NEVER
# invokes the `agents` CLI (the old `agents secrets` path could pop Touch ID).

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/03-linear-inject-tasks-context.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
check_contains() { if printf '%s' "$2" | grep -qF "$3"; then echo "ok   - $1"; else echo "FAIL - $1: output missing [$3]"; fail=1; fi; }
check_absent()   { if printf '%s' "$2" | grep -qF "$3"; then echo "FAIL - $1: output contains [$3]"; fail=1; else echo "ok   - $1"; fi; }

run_hook() { ( cd "$SANDBOX" && bash "$HOOK" 2>/dev/null ); }

# --- stubs -------------------------------------------------------------------
mkdir -p "$SANDBOX/bin"

# agents: must NEVER be called by this hook (no secrets broker path anymore).
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
echo "agents-stub-invoked: $*" >> "$AGENTS_CALLS"
exit 1
STUB

# curl: record argv (to prove which credential reached the Authorization
# header), answer with a minimal valid GraphQL payload.
cat > "$SANDBOX/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CURL_ARGS"
cat <<'JSON'
{"data":{"users":{"nodes":[{"displayName":"Muqsit","email":"m@example.com","active":true,"app":false,"guest":false}]},"team":{"projects":{"nodes":[]},"activeCycle":null}}}
JSON
STUB
chmod +x "$SANDBOX/bin/agents" "$SANDBOX/bin/curl"
export PATH="$SANDBOX/bin:$PATH"
export AGENTS_CALLS="$SANDBOX/agents-calls"
export CURL_ARGS="$SANDBOX/curl-args"

# Fixture Linear CLI config.
cat > "$SANDBOX/config.json" <<'JSON'
{"teamId": "team-uuid-1", "apiKey": "lin_api_fixture_key"}
JSON

# --- 1. credentials from config.json: brief renders, fixture key hits the wire -
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID bash -c 'cd "$0" && bash "$1"' "$SANDBOX" "$HOOK" 2>/dev/null)
check_contains "config.json creds: brief header renders" "$out" "## Team & Agents"
check_contains "config.json creds: human listed"         "$out" "Muqsit (m@example.com)"
check_contains "config.json creds: no sprint reported"   "$out" "No active sprint in Linear."
check_contains "fixture apiKey reached Authorization"    "$(cat "$CURL_ARGS" 2>/dev/null)" "Authorization: lin_api_fixture_key"

# --- 2. env vars win over config.json -----------------------------------------
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" LINEAR_API_KEY="lin_api_env_key" LINEAR_TEAM_ID="team-env" bash -c 'cd "$0" && bash "$1"' "$SANDBOX" "$HOOK" 2>/dev/null)
check_contains "env creds: brief renders"                "$out" "## Team & Agents"
check_contains "env apiKey beats fixture on the wire"    "$(cat "$CURL_ARGS" 2>/dev/null)" "Authorization: lin_api_env_key"

# --- 3. no config, no env: one-line skip, exit 0 -------------------------------
rm -f "$CURL_ARGS"
out=$(LINEAR_CLI_CONFIG="$SANDBOX/missing.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID HOME="$SANDBOX/nohome" bash -c 'cd "$0" && bash "$1"' "$SANDBOX" "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && echo "ok   - missing creds exit 0" || { echo "FAIL - missing creds rc=$rc"; fail=1; }
check_contains "missing creds: skip line names the fix"  "$out" "linear setup"
check_absent   "missing creds: no curl attempted"        "$(cat "$CURL_ARGS" 2>/dev/null || echo none)" "linear.app/graphql"

# --- 4. malformed config.json: degrades to the same skip, exit 0 ---------------
echo "not json {{{" > "$SANDBOX/bad.json"
out=$(LINEAR_CLI_CONFIG="$SANDBOX/bad.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID bash -c 'cd "$0" && bash "$1"' "$SANDBOX" "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && echo "ok   - malformed config exit 0" || { echo "FAIL - malformed config rc=$rc"; fail=1; }
check_contains "malformed config: skip line"             "$out" "Linear context skipped"

# --- 5. the agents CLI was never invoked (no secrets broker path) --------------
if [ -f "$AGENTS_CALLS" ]; then
  echo "FAIL - hook invoked agents CLI: $(cat "$AGENTS_CALLS")"; fail=1
else
  echo "ok   - agents CLI never invoked"
fi

exit $fail
