#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HERE/verify-work-state.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
DB="$SANDBOX/state.db"
export VERIFY_WORK_STATE_DB="$DB"

pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); echo "ok   - $1"
  else
    fail=$((fail + 1)); echo "FAIL - $1: expected [$3], got [$2]"
  fi
}

eval_payload() {
  python3 "$STATE" evaluate <<EOF
$1
EOF
}

prompt='{"session_id":"native-1","agent":"claude","launch_id":"launch-1","prompt":"build the secret widget"}'
out=$(printf '%s' "$prompt" | python3 "$STATE" record-prompt)
check "prompt boundary records" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["recorded"])')" "True"
check "goal ordinal starts at one" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["goal_ordinal"])')" "1"

raw=$(sqlite3 "$DB" "select prompt_sha256 from goal_boundaries;")
check "prompt is stored only as SHA-256" "${#raw}" "64"
if grep -a -q "secret widget" "$DB"; then
  echo "FAIL - raw prompt leaked into database"; fail=$((fail + 1))
else
  echo "ok   - raw prompt is absent"; pass=$((pass + 1))
fi
check "database permissions are private" "$(stat -c '%a' "$DB" 2>/dev/null || stat -f '%Lp' "$DB")" "600"

mk_transcript() {
  local name="$1" body="$2" file
  file="$SANDBOX/$name.jsonl"
  printf '%s\n' "$body" > "$file"
  printf '%s' "$file"
}

browser=$(mk_transcript browser '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"agents browser screenshot"}}]}}')
out=$(eval_payload "{\"session_id\":\"native-1\",\"agent\":\"claude\",\"transcript_path\":\"$browser\"}")
check "browser work is non-delivery" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["delivery_evidence"])')" "False"
check "browser context is classified" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["context_kind"])')" "browser-external"

research=$(mk_transcript research '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/a.ts"}}]}}')
out=$(eval_payload "{\"session_id\":\"research-1\",\"agent\":\"codex\",\"transcript_path\":\"$research\"}")
check "read-only work is non-delivery" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["context_kind"])')" "research-diagnostic"

codex_research=$(mk_transcript codex-research '{"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"pwd","aggregated_output":"/repo","exit_code":0,"status":"completed"}}')
out=$(eval_payload "{\"session_id\":\"codex-research-1\",\"agent\":\"codex\",\"transcript_path\":\"$codex_research\"}")
check "Codex command execution is classified read-only" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["context_kind"])')" "research-diagnostic"

ticket=$(mk_transcript ticket '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"linear create --title follow-up"}}]}}')
out=$(eval_payload "{\"session_id\":\"ticket-1\",\"agent\":\"claude\",\"transcript_path\":\"$ticket\"}")
check "ticket creation is not delivery" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["context_kind"])')" "ticket-creation"

review=$(mk_transcript review '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"gh pr review https://github.com/acme/repo/pull/7 --approve"}}]}}')
out=$(eval_payload "{\"session_id\":\"review-1\",\"agent\":\"codex\",\"transcript_path\":\"$review\"}")
check "review does not establish merge ownership" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["context_kind"])')" "review-only"

write=$(mk_transcript write '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/a.ts","old_string":"a","new_string":"b"}}]}}')
out=$(eval_payload "{\"session_id\":\"write-1\",\"agent\":\"claude\",\"transcript_path\":\"$write\"}")
check "tracked edit is delivery evidence" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["delivery_evidence"])')" "True"

tmpwrite=$(mk_transcript tmpwrite '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/handoff.sh","content":"echo hi"}}]}}')
out=$(eval_payload "{\"session_id\":\"tmp-1\",\"agent\":\"claude\",\"transcript_path\":\"$tmpwrite\"}")
check "temporary script is not repository delivery" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["delivery_evidence"])')" "False"

# A launch-only boundary is reconciled into the native session when SessionStart
# later supplies both identities.
printf '%s' '{"launch_id":"launch-late","agent":"codex","prompt":"first"}' | python3 "$STATE" record-prompt >/dev/null
printf '%s' '{"session_id":"native-late","launch_id":"launch-late","agent":"codex","prompt":"second"}' | python3 "$STATE" record-prompt >/dev/null
aliases=$(sqlite3 "$DB" "select count(distinct session_key) from session_aliases where alias_value in ('launch-late','native-late');")
check "launch/native aliases reconcile to one session" "$aliases" "1"
goals=$(sqlite3 "$DB" "select count(*) from goal_boundaries where session_key='codex:native-late';")
check "provisional goal history follows native identity" "$goals" "2"

# Old rows are pruned during an ordinary write; the current session survives.
sqlite3 "$DB" "update decisions set created_at_ms=0; update meta set value='0' where key='last_pruned_ms';"
eval_payload "{\"session_id\":\"fresh-1\",\"agent\":\"claude\",\"transcript_path\":\"$browser\"}" >/dev/null
old=$(sqlite3 "$DB" "select count(*) from decisions where created_at_ms=0;")
check "30-day retention prunes stale decisions" "$old" "0"

# Duplicate managed hook versions can write concurrently. WAL + the bounded
# busy timeout must keep independent session writes intact.
for i in 1 2 3 4 5 6 7 8; do
  printf '{"session_id":"parallel-%s","agent":"claude","prompt":"p%s"}' "$i" "$i" \
    | env -u AGENT_LAUNCH_ID python3 "$STATE" record-prompt >/dev/null &
done
wait
parallel=$(sqlite3 "$DB" "select count(*) from goal_boundaries where session_key like 'claude:parallel-%';")
check "concurrent hook processes preserve all writes" "$parallel" "8"

# An unknown schema version is bounded and fail-open; the hook never guesses a
# migration for state it does not understand.
MISMATCH="$SANDBOX/mismatch.db"
sqlite3 "$MISMATCH" "create table meta(key text primary key,value text not null); insert into meta values('schema_version','999');"
out=$(VERIFY_WORK_STATE_DB="$MISMATCH" eval_payload '{"session_id":"future","agent":"claude"}')
check "unknown schema fails open" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["recorded"])')" "False"
check "unknown schema reports bounded error type" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_error"])')" "RuntimeError"

# A writer holding the database longer than the 100 ms budget cannot wedge the
# Stop path. The second process returns a bounded state_error.
READY="$SANDBOX/lock-ready"
python3 - "$DB" "$READY" <<'PY' &
import sqlite3, sys, time
db = sqlite3.connect(sys.argv[1])
db.execute("BEGIN IMMEDIATE")
open(sys.argv[2], "w").close()
time.sleep(0.5)
db.rollback()
PY
locker=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$READY" ] && break; sleep 0.02; done
out=$(eval_payload "{\"session_id\":\"locked\",\"agent\":\"claude\",\"transcript_path\":\"$browser\"}")
wait "$locker"
check "lock timeout fails open" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["recorded"])')" "False"
check "lock timeout reports bounded error type" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_error"])')" "OperationalError"

# Malformed databases are quarantined and replaced without exposing details.
CORRUPT="$SANDBOX/corrupt.db"
printf 'not sqlite' > "$CORRUPT"
out=$(VERIFY_WORK_STATE_DB="$CORRUPT" eval_payload '{"session_id":"broken","agent":"claude"}')
check "corrupt database recovers" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["recorded"])')" "True"
check "corrupt database is quarantined" "$(ls "$CORRUPT".corrupt-* 2>/dev/null | wc -l | tr -d ' ')" "1"
check "replacement database is valid" "$(sqlite3 "$CORRUPT" 'PRAGMA integrity_check')" "ok"

# Missing identity is stateless and never creates an unjoinable row.
out=$(env -u AGENT_LAUNCH_ID VERIFY_WORK_STATE_DB="$DB" python3 "$STATE" evaluate <<EOF
{"transcript_path":"$browser"}
EOF
)
check "missing identity stays stateless" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["recorded"])')" "False"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
