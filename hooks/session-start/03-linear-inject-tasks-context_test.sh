#!/usr/bin/env bash
# Tests for 03-linear-inject-tasks-context.sh — the SessionStart Linear brief.
# curl and agents are stubbed via PATH shims; no network, no keychain, no broker.
# Critical-path assertions:
#   - credentials come from the Linear CLI's plaintext config.json
#     (LINEAR_CLI_CONFIG fixture); env vars still win
#   - the hook NEVER invokes the `agents` CLI (no secrets / Touch ID path)
#   - injection lists projects with milestones + top open tickets
#   - active cycle is grouped by project
#   - Your Tasks is routed by Linear's native delegate, per AGENT_SELF, and a
#     leftover agent:* label confers no ownership

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
      "myOpenIssues": {
        "nodes": [
          {
            "identifier": "RUSH-10",
            "title": "Claude is the delegate",
            "description": "Delegated to Claude natively.",
            "priority": 1,
            "state": {"name": "Todo", "type": "unstarted"},
            "assignee": {"name": "Muqsit"},
            "delegate": {"name": "Claude"},
            "labels": {"nodes": [{"name": "engineering"}]},
            "project": {"name": "Agents CLI"}
          }
        ],
        "pageInfo": {"hasNextPage": false}
      },
      "activeCycle": {
        "name": "Cycle 23",
        "startsAt": "2026-08-04T00:00:00.000Z",
        "endsAt": "2026-08-11T00:00:00.000Z",
        "issues": {
          "nodes": [
            {
              "identifier": "RUSH-10",
              "title": "Claude is the delegate",
              "description": "Delegated to Claude natively.",
              "priority": 1,
              "state": {"name": "Todo", "type": "unstarted"},
              "assignee": {"name": "Muqsit"},
              "delegate": {"name": "Claude"},
              "labels": {"nodes": [{"name": "engineering"}]},
              "project": {"name": "Agents CLI"}
            },
            {
              "identifier": "RUSH-11",
              "title": "Codex is the delegate",
              "description": "Delegated to Codex natively.",
              "priority": 2,
              "state": {"name": "Doing", "type": "started"},
              "assignee": {"name": "Muqsit"},
              "delegate": {"name": "Codex"},
              "labels": {"nodes": []},
              "project": {"name": "Agents CLI"}
            },
            {
              "identifier": "RUSH-12",
              "title": "Stale label, no delegate",
              "description": "Carries agent:claude but nobody is delegated.",
              "priority": 3,
              "state": {"name": "Todo", "type": "unstarted"},
              "assignee": {"name": "Muqsit"},
              "delegate": null,
              "labels": {"nodes": [{"name": "agent:claude"}]},
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
printf '%s\n' "$*" >> "$CURL_ARGS"
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
rm -f "$CURL_ARGS"
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

# --- 5. Your Tasks routes by native delegate, per AGENT_SELF -------------------
rm -f "$CURL_ARGS"
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=claude \
  bash "$HOOK" 2>/dev/null)
check_contains "claude lane: Your Tasks lists RUSH-10"     "$out" "RUSH-10"
check_contains "claude lane: header names the delegate"    "$out" "Your Tasks (delegated to Claude)"
check_absent   "no agent:* label header survives"          "$out" "Your Tasks (agent:"
# The other agent's delegated work stays visible in the cycle section.
check_contains "claude lane: codex issue still in cycle"   "$out" "RUSH-11"
# When the delegate-only sweep completes, the counts are exact and carry no
# "of the first N" qualifier — that qualifier only appears on the fallback.
check_contains "claude lane: other lanes counted by name"  "$out" "Other agent lanes: Codex=1"
check_absent   "complete sweep prints no sample caveat"    "$out" "Other agent lanes (of the first"
check_contains "lane sweep asks only for delegate names"   "$(cat "$CURL_ARGS" 2>/dev/null)" "nodes { delegate { name } }"
# RUSH-12 carries agent:claude but has no delegate — it must NOT be owned, and
# the leftover label is shown as an ordinary label.
check_contains "stale agent:* label is inert, shown plain" "$out" "[agent:claude]"
# An issue Your Tasks printed must not be repeated under Cycle-by-project.
check_absent   "printed issue not repeated in cycle"       "$(printf '%s' "$out" | sed -n '/Cycle by project/,$p')" "RUSH-10"

# The delegate name resolves case-insensitively against the harness name, and
# the query asks Linear for that agent's queue directly.
check_contains "delegate filter is sent to Linear"         "$(cat "$CURL_ARGS" 2>/dev/null)" 'eqIgnoreCase: \"claude\"'

# Codex identity: Linear filters myOpenIssues server-side, so the fixture swaps
# to what Codex's own query would return. Claude's work moves to the lane count.
CLAUDE_PAYLOAD="$CURL_PAYLOAD"
export CURL_PAYLOAD="$SANDBOX/payload-codex.json"
python3 - "$CLAUDE_PAYLOAD" "$CURL_PAYLOAD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
cycle = d["data"]["team"]["activeCycle"]["issues"]["nodes"]
mine = [n for n in cycle if (n.get("delegate") or {}).get("name") == "Codex"]
d["data"]["team"]["myOpenIssues"] = {"nodes": mine, "pageInfo": {"hasNextPage": False}}
json.dump(d, open(sys.argv[2], "w"))
PY
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=codex \
  bash "$HOOK" 2>/dev/null)
check_contains "codex lane: header names the delegate"     "$out" "Your Tasks (delegated to Codex)"
check_contains "codex lane: Your Tasks lists RUSH-11"      "$out" "RUSH-11"
check_contains "codex lane: claude counted as other"       "$out" "Claude=1"
check_contains "codex identity reaches the query"          "$(cat "$CURL_ARGS" 2>/dev/null)" 'eqIgnoreCase: \"codex\"'
export CURL_PAYLOAD="$CLAUDE_PAYLOAD"

# --- 5b. no delegated work: the bucket says so instead of guessing ------------
export CURL_PAYLOAD="$SANDBOX/payload-empty-mine.json"
python3 - "$CLAUDE_PAYLOAD" "$CURL_PAYLOAD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["data"]["team"]["myOpenIssues"] = {"nodes": [], "pageInfo": {"hasNextPage": False}}
json.dump(d, open(sys.argv[2], "w"))
PY
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=grok \
  bash "$HOOK" 2>/dev/null)
check_contains "empty queue: says none assigned"           "$out" "Your Tasks (delegated to grok) — none assigned"
check_contains "empty queue: both lanes still counted"     "$out" "Other agent lanes: Claude=1, Codex=1"
export CURL_PAYLOAD="$CLAUDE_PAYLOAD"

# --- 5c. a hostile AGENT_SELF reaches neither the query nor the context -------
rm -f "$CURL_ARGS"
# Linear would filter myOpenIssues server-side for this identity, so use the
# empty-queue fixture: the header then echoes the name, which is the point here.
export CURL_PAYLOAD="$SANDBOX/payload-empty-mine.json"
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID \
  AGENT_SELF='grok" } } evil: issues(first: 1) { nodes { id ' bash "$HOOK" 2>/dev/null)
check_absent   "injection stripped from the query"         "$(cat "$CURL_ARGS" 2>/dev/null)" "evil:"
check_contains "sanitized name still queries"              "$(cat "$CURL_ARGS" 2>/dev/null)" "eqIgnoreCase"
# The name is also printed into the injected context — it must not carry markup.
check_absent   "injection stripped from the brief"         "$out" "evil:"
check_contains "brief prints the sanitized name"           "$out" "delegated to grokevilissuesfirst1nodesid"
export CURL_PAYLOAD="$CLAUDE_PAYLOAD"

# --- 5d. a capped Your Tasks must not drop the rest out of the brief ----------
# Your Tasks (capped at 10) and the cycle page are different queries. Skipping
# "everything delegated to me" from Cycle-by-project would drop delegated issues
# that fell past the cap out of the injection entirely.
export CURL_PAYLOAD="$SANDBOX/payload-overflow.json"
python3 - "$CLAUDE_PAYLOAD" "$CURL_PAYLOAD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
mine = []
for i in range(12):                      # 12 > MY_CAP (10)
    mine.append({
        "identifier": f"RUSH-90{i:02d}", "title": f"mine {i}",
        "description": "", "priority": 1,
        "state": {"name": "Todo", "type": "unstarted"},
        "assignee": {"name": "Muqsit"}, "delegate": {"name": "Claude"},
        "labels": {"nodes": []}, "project": {"name": "Agents CLI"},
    })
d["data"]["team"]["myOpenIssues"] = {"nodes": mine, "pageInfo": {"hasNextPage": True}}
# The 12th one is also on the cycle page; it must survive into Cycle-by-project.
d["data"]["team"]["activeCycle"]["issues"]["nodes"].append(mine[11])
json.dump(d, open(sys.argv[2], "w"))
PY
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=claude \
  bash "$HOOK" 2>/dev/null)
check_contains "overflow: count marked as truncated"       "$out" "Your Tasks (delegated to Claude) — 12+"
check_contains "overflow: names the remainder"             "$out" "more delegated to you (see: linear tasks --agent claude)"
check_contains "overflow: uncapped issue still in brief"   "$out" "RUSH-9011"
export CURL_PAYLOAD="$CLAUDE_PAYLOAD"

# --- 5e. a truncated cycle page must not print exact-looking lane counts ------
rm -f "$CURL_ARGS"
export CURL_PAYLOAD="$SANDBOX/payload-truncated-cycle.json"
python3 - "$CLAUDE_PAYLOAD" "$CURL_PAYLOAD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
# hasNextPage with a cursor that never advances: the lane sweep exhausts its
# page budget without ever completing, which is the case that must fall back to
# counting the page — and say that is what it did.
d["data"]["team"]["activeCycle"]["issues"]["pageInfo"] = {
    "hasNextPage": True, "endCursor": "never-advances"}
json.dump(d, open(sys.argv[2], "w"))
PY
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=claude \
  bash "$HOOK" 2>/dev/null)
check_contains "truncated cycle: count marked"             "$out" "open tasks"
check_contains "truncated cycle: lanes qualified"          "$out" "Other agent lanes (of the first"
check_contains "cycle query asks for more than one page"   "$(cat "$CURL_ARGS" 2>/dev/null)" "first: 250"
export CURL_PAYLOAD="$CLAUDE_PAYLOAD"

# --- 5f. priority 0 means 'no priority', and must sort BELOW Urgent -----------
export CURL_PAYLOAD="$SANDBOX/payload-pri0.json"
python3 - "$CLAUDE_PAYLOAD" "$CURL_PAYLOAD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
base = {"description": "", "state": {"name": "Todo", "type": "unstarted"},
        "assignee": {"name": "Muqsit"}, "delegate": {"name": "Claude"},
        "labels": {"nodes": []}, "project": {"name": "Agents CLI"}}
d["data"]["team"]["myOpenIssues"] = {"nodes": [
    dict(base, identifier="RUSH-8000", title="no priority", priority=0),
    dict(base, identifier="RUSH-8001", title="urgent", priority=1),
], "pageInfo": {"hasNextPage": False}}
json.dump(d, open(sys.argv[2], "w"))
PY
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=claude \
  bash "$HOOK" 2>/dev/null)
urgent_at=$(printf '%s' "$out" | grep -n "RUSH-8001" | head -1 | cut -d: -f1)
none_at=$(printf '%s' "$out" | grep -n "RUSH-8000" | head -1 | cut -d: -f1)
if [ -n "$urgent_at" ] && [ -n "$none_at" ] && [ "$urgent_at" -lt "$none_at" ]; then
  echo "ok   - priority 0 sorts below Urgent"
else
  echo "FAIL - priority 0 sorted above Urgent (urgent line $urgent_at, none line $none_at)"; fail=1
fi
export CURL_PAYLOAD="$CLAUDE_PAYLOAD"

# --- 5g. a payload with no myOpenIssues at all still renders, exit 0 ----------
export CURL_PAYLOAD="$SANDBOX/payload-no-mine.json"
python3 - "$CLAUDE_PAYLOAD" "$CURL_PAYLOAD" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["data"]["team"].pop("myOpenIssues", None)
json.dump(d, open(sys.argv[2], "w"))
PY
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID AGENT_SELF=claude \
  bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && echo "ok   - missing myOpenIssues exit 0" || { echo "FAIL - missing myOpenIssues rc=$rc"; fail=1; }
check_contains "missing myOpenIssues: says none assigned"  "$out" "none assigned"
check_absent   "no 'labeled for you' copy survives"        "$out" "labeled for you"
export CURL_PAYLOAD="$CLAUDE_PAYLOAD"

# --- 5h. GraphQL errors degrade to one line, exit 0 ---------------------------
export CURL_PAYLOAD="$SANDBOX/payload-errors.json"
cat > "$CURL_PAYLOAD" <<'JSON'
{"data": null, "errors": [{"message": "Field 'delegate' doesn't exist on type 'IssueFilter'"}]}
JSON
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID \
  bash "$HOOK" 2>/dev/null); rc=$?
[ "$rc" = "0" ] && echo "ok   - GraphQL error exit 0" || { echo "FAIL - GraphQL error rc=$rc"; fail=1; }
check_contains "GraphQL error: one-line message"           "$out" "Linear query failed"
export CURL_PAYLOAD="$CLAUDE_PAYLOAD"

# --- 6. empty-team payload still clean ----------------------------------------
cat > "$CURL_PAYLOAD" <<'JSON'
{"data":{"users":{"nodes":[{"displayName":"Muqsit","email":"m@example.com","active":true,"app":false,"guest":false}]},"team":{"projects":{"nodes":[]},"activeCycle":null}}}
JSON
out=$(LINEAR_CLI_CONFIG="$SANDBOX/config.json" env -u LINEAR_API_KEY -u LINEAR_TEAM_ID \
  bash "$HOOK" 2>/dev/null)
check_contains "empty team: brief header"                  "$out" "## Team & Agents"
check_contains "empty team: no sprint"                     "$out" "No active sprint in Linear."
check_contains "empty team: no projects message"           "$out" "No projects on this Linear team."

# --- 6b. worst-case latency fits the registered hook timeout -------------------
# The lane sweep runs BEFORE anything prints, so a sweep that overruns is not a
# degraded brief — it is a killed hook and no brief at all. agents.yaml registers
# this hook with `timeout: 15`, so the sum of every --max-time must stay under it.
# Match only real flags with a number — a prose mention of --max-time in a
# comment must not be read as a zero-second budget.
brief_t=$(grep -o -- '--max-time [0-9][0-9]*' "$HOOK" | head -1 | awk '{print $2}')
sweep_t=$(grep -o -- '--max-time [0-9][0-9]*' "$HOOK" | tail -1 | awk '{print $2}')
pages=$(grep -c 'for _ in 1 2 3; do' "$HOOK")
declared=$(awk '/^  linear-tasks:/{f=1} f&&/timeout:/{print $2; exit}' "$HERE/../../agents.yaml" 2>/dev/null)
declared="${declared:-15}"
# One brief request plus three sweep pages, each at its own --max-time.
worst=$(( brief_t + 3 * sweep_t ))
if [ -n "$brief_t" ] && [ "$brief_t" -gt 0 ] && [ "$worst" -le "$declared" ]; then
  echo "ok   - worst-case ${worst}s fits the registered ${declared}s timeout"
else
  echo "FAIL - worst case ${worst}s exceeds the registered ${declared}s hook timeout"; fail=1
fi
[ "$pages" = "1" ] && echo "ok   - sweep page budget is bounded" || { echo "FAIL - sweep page loop changed; re-check the latency budget"; fail=1; }

# --- 7. the agents CLI was never invoked (no secrets broker path) --------------
if [ -f "$AGENTS_CALLS" ]; then
  echo "FAIL - hook invoked agents CLI: $(cat "$AGENTS_CALLS")"; fail=1
else
  echo "ok   - agents CLI never invoked"
fi

exit $fail
