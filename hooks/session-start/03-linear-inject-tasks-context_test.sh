#!/usr/bin/env bash
# Tests for 03-linear-inject-tasks-context.sh — the SessionStart Linear brief.
# curl and agents are stubbed via PATH shims; no network, no keychain, no broker.
# Critical-path assertions:
#   - credentials come from the Linear CLI's plaintext config.json
#     (LINEAR_CLI_CONFIG fixture); env vars still win
#   - the hook NEVER invokes the `agents` CLI (no secrets / Touch ID path)
#   - injection lists projects with milestones + top open tickets
#   - active cycle is grouped by project; Your Tasks still agent-routed

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/03-linear-inject-tasks-context.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
check_contains() { if printf '%s' "$2" | grep -qF "$3"; then echo "ok   - $1"; else echo "FAIL - $1: output missing [$3]"; fail=1; fi; }
check_absent()   { if printf '%s' "$2" | grep -qF "$3"; then echo "FAIL - $1: output contains [$3]"; fail=1; else echo "ok   - $1"; fi; }

# --- stubs -------------------------------------------------------------------
mkdir -p "$SANDBOX/bin"

# agents: must NEVER be called by this hook (no secrets broker path).
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
echo "agents-stub-invoked: $*" >> "$AGENTS_CALLS"
exit 1
STUB

# Default curl stub: rich multi-project payload used by most tests.
# Overridden per-test via CURL_PAYLOAD when needed.
export CURL_PAYLOAD="$SANDBOX/payload.json"
cat > "$CURL_PAYLOAD" <<'JSON'
{
  "data": {
    "users": {
      "nodes": [
        {"displayName": "Muqsit", "email": "m@example.com", "active": true, "app": false, "guest": false},
        {"displayName": "claude", "email": "claude@linear.app", "active": true, "app": true, "guest": false},
        {"displayName": "codex", "email": "codex@linear.app", "active": true, "app": true, "guest": false}
      ]
    },
    "team": {
      "projects": {
        "nodes": [
          {
            "name": "Agents CLI",
            "state": "backlog",
            "progress": 0.84,
            "projectMilestones": {
              "nodes": [
                {"name": "Factory converts strategy to shipped outcomes", "targetDate": "2026-09-15", "progress": 0.1, "sortOrder": 1},
                {"name": "Factory reliability — self-heals", "targetDate": "2026-09-30", "progress": 0.0, "sortOrder": 2}
              ]
            },
            "issues": {
              "nodes": [
                {"identifier": "RUSH-1", "title": "Urgent agents-cli bug", "priority": 1, "state": {"name": "Todo", "type": "unstarted"}, "assignee": {"displayName": "Muqsit"}},
                {"identifier": "RUSH-2", "title": "Medium agents-cli task", "priority": 3, "state": {"name": "Todo", "type": "unstarted"}, "assignee": null}
              ]
            }
          },
          {
            "name": "Rush App",
            "state": "started",
            "progress": 0.5,
            "projectMilestones": {
              "nodes": [
                {"name": "First paying users", "targetDate": "2026-08-15", "progress": 0.4, "sortOrder": 1}
              ]
            },
            "issues": {
              "nodes": [
                {"identifier": "RUSH-99", "title": "Rush onboarding polish", "priority": 2, "state": {"name": "Doing", "type": "started"}, "assignee": {"displayName": "Muqsit"}}
              ]
            }
          },
          {
            "name": "Old Stuff",
            "state": "completed",
            "progress": 1.0,
            "projectMilestones": {"nodes": []},
            "issues": {"nodes": []}
          }
        ]
      },
      "activeCycle": {
        "name": "Cycle 23",
        "startsAt": "2026-08-04T00:00:00.000Z",
        "endsAt": "2026-08-11T00:00:00.000Z",
        "issues": {
          "nodes": [
            {
              "identifier": "RUSH-10",
              "title": "Claude owns this",
              "description": "A task for the claude agent lane.",
              "priority": 1,
              "state": {"name": "Todo", "type": "unstarted"},
              "assignee": {"name": "Muqsit"},
              "labels": {"nodes": [{"name": "agent:claude"}, {"name": "engineering"}]},
              "project": {"name": "Agents CLI"}
            },
            {
              "identifier": "RUSH-11",
              "title": "Codex owns this",
              "description": "A task for codex.",
              "priority": 2,
              "state": {"name": "Doing", "type": "started"},
              "assignee": {"name": "Muqsit"},
              "labels": {"nodes": [{"name": "agent:codex"}]},
              "project": {"name": "Agents CLI"}
            },
            {
              "identifier": "RUSH-12",
              "title": "Unowned rush app item",
              "description": "No agent label.",
              "priority": 3,
              "state": {"name": "Todo", "type": "unstarted"},
              "assignee": {"name": "Muqsit"},
              "labels": {"nodes": []},
              "project": {"name": "Rush App"}
            }
          ]
        }
      }
    }
  }
}
JSON

cat > "$SANDBOX/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CURL_ARGS"
cat "$CURL_PAYLOAD"
STUB
chmod +x "$SANDBOX/bin/agents" "$SANDBOX/bin/curl"
export PATH="$SANDBOX/bin:$PATH"
export AGENTS_CALLS="$SANDBOX/agents-calls"
export CURL_ARGS="$SANDBOX/curl-args"

# Fixture Linear CLI config.
cat > "$SANDBOX/config.json" <<'JSON'
{"teamId": "team-uuid-1", "apiKey": "lin_api_fixture_key"}
JSON

# Fake a cwd that matches Agents CLI via git-less basename.
mkdir -p "$SANDBOX/work/agents-cli"
cd "$SANDBOX/work/agents-cli" || exit 1

# --- 1. credentials from config.json: projects + milestones render -------------
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID \
  bash "$HOOK" 2>/dev/null)
check_contains "config.json creds: team header"            "$out" "## Team & Agents"
check_contains "config.json creds: human listed"           "$out" "Muqsit (m@example.com)"
check_contains "config.json creds: projects section"       "$out" "## Projects ("
check_contains "config.json creds: Agents CLI project"     "$out" "### Agents CLI"
check_contains "config.json creds: cwd marker"             "$out" "★ cwd"
check_contains "config.json creds: Agents CLI milestone"   "$out" "Factory converts strategy to shipped outcomes"
check_contains "config.json creds: Rush App project"       "$out" "### Rush App"
check_contains "config.json creds: Rush App milestone"     "$out" "First paying users"
check_contains "config.json creds: project top issue"      "$out" "RUSH-1"
check_contains "config.json creds: cycle header"           "$out" "## Cycle 23"
check_contains "config.json creds: cycle by project"       "$out" "### Cycle by project"
check_contains "fixture apiKey reached Authorization"      "$(cat "$CURL_ARGS" 2>/dev/null)" "Authorization: lin_api_fixture_key"
# Completed projects must not appear in the live list
check_absent   "completed project filtered out"            "$out" "### Old Stuff"

# --- 2. env vars win over config.json -----------------------------------------
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" LINEAR_API_KEY="lin_api_env_key" LINEAR_TEAM_ID="team-env" \
  bash "$HOOK" 2>/dev/null)
check_contains "env creds: projects render"                "$out" "## Projects ("
check_contains "env apiKey beats fixture on the wire"      "$(cat "$CURL_ARGS" 2>/dev/null)" "Authorization: lin_api_env_key"

# --- 3. no config, no env: one-line skip, exit 0 -------------------------------
rm -f "$CURL_ARGS"
out=$(LINEAR_CLI_CONFIG="$SANDBOX/missing.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID HOME="$SANDBOX/nohome" \
  bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && echo "ok   - missing creds exit 0" || { echo "FAIL - missing creds rc=$rc"; fail=1; }
check_contains "missing creds: skip line names the fix"    "$out" "linear setup"
check_absent   "missing creds: no curl attempted"          "$(cat "$CURL_ARGS" 2>/dev/null || echo none)" "linear.app/graphql"

# --- 4. malformed config.json: degrades to the same skip, exit 0 ---------------
echo "not json {{{" > "$SANDBOX/bad.json"
out=$(LINEAR_CLI_CONFIG="$SANDBOX/bad.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID \
  bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && echo "ok   - malformed config exit 0" || { echo "FAIL - malformed config rc=$rc"; fail=1; }
check_contains "malformed config: skip line"               "$out" "Linear context skipped"

# --- 5. Your Tasks routes by AGENT_SELF (claude default) ----------------------
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=claude \
  bash "$HOOK" 2>/dev/null)
check_contains "claude lane: Your Tasks lists RUSH-10"     "$out" "RUSH-10"
check_contains "claude lane: header agent:claude"          "$out" "Your Tasks (agent:claude)"
# codex-owned should appear under cycle-by-project, not Your Tasks block as only item
check_contains "claude lane: codex issue still in cycle"   "$out" "RUSH-11"

out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=codex \
  bash "$HOOK" 2>/dev/null)
check_contains "codex lane: Your Tasks lists RUSH-11"      "$out" "RUSH-11"
check_contains "codex lane: header agent:codex"            "$out" "Your Tasks (agent:codex)"

# --- 6. empty-team payload still clean ----------------------------------------
cat > "$CURL_PAYLOAD" <<'JSON'
{"data":{"users":{"nodes":[{"displayName":"Muqsit","email":"m@example.com","active":true,"app":false,"guest":false}]},"team":{"projects":{"nodes":[]},"activeCycle":null}}}
JSON
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID \
  bash "$HOOK" 2>/dev/null)
check_contains "empty team: brief header"                  "$out" "## Team & Agents"
check_contains "empty team: no sprint"                     "$out" "No active sprint in Linear."
check_contains "empty team: no projects message"           "$out" "No projects on this Linear team."

# --- 7. the agents CLI was never invoked (no secrets broker path) --------------
if [ -f "$AGENTS_CALLS" ]; then
  echo "FAIL - hook invoked agents CLI: $(cat "$AGENTS_CALLS")"; fail=1
else
  echo "ok   - agents CLI never invoked"
fi

exit $fail
