#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="$HERE/../verify-work-state.py"
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

visual="$SANDBOX/visual.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/mockup.html"}}]}}' > "$visual"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"scp /tmp/mockup.html zion:/tmp/mockup.html"}}]}}' >> "$visual"
out=$(eval_payload "{\"session_id\":\"visual-1\",\"agent\":\"claude\",\"transcript_path\":\"$visual\"}")
check "delivered scratch visual is delivery evidence" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["delivery_evidence"])')" "True"

# A new prompt boundary excludes every prior goal's delivery evidence.
scoped="$SANDBOX/scoped.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/old.ts"}}]}}' > "$scoped"
printf '{"session_id":"scoped-1","agent":"claude","prompt":"now inspect the browser","transcript_path":"%s"}' "$scoped" | python3 "$STATE" record-prompt >/dev/null
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"agents browser screenshot"}}]}}' >> "$scoped"
out=$(eval_payload "{\"session_id\":\"scoped-1\",\"agent\":\"claude\",\"transcript_path\":\"$scoped\"}")
check "new goal excludes prior repository mutation" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["delivery_evidence"])')" "False"
check "new goal keeps its own browser evidence" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["context_kind"])')" "browser-external"

# PR ownership is durable across prompts even though classification is scoped.
owned="$SANDBOX/owned.jsonl"
: > "$owned"
printf '{"session_id":"owned-1","agent":"claude","prompt":"open the PR","transcript_path":"%s"}' "$owned" | python3 "$STATE" record-prompt >/dev/null
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"create-1","name":"Bash","input":{"command":"gh pr create --title widget"}}]}}' >> "$owned"
printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"create-1","content":"https://github.com/acme/repo/pull/12"}]}}' >> "$owned"
out=$(eval_payload "{\"session_id\":\"owned-1\",\"agent\":\"claude\",\"transcript_path\":\"$owned\"}")
check "created PR enters ownership ledger" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["owned_prs"][0])')" "https://github.com/acme/repo/pull/12"
printf '{"session_id":"owned-1","agent":"claude","prompt":"check one fact","transcript_path":"%s"}' "$owned" | python3 "$STATE" record-prompt >/dev/null
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/a.ts"}}]}}' >> "$owned"
out=$(eval_payload "{\"session_id\":\"owned-1\",\"agent\":\"claude\",\"transcript_path\":\"$owned\"}")
check "follow-up goal does not inherit delivery classification" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["context_kind"])')" "research-diagnostic"
check "follow-up goal retains owned PR" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["owned_prs"][0])')" "https://github.com/acme/repo/pull/12"

# Structured telemetry makes every harness's check fires observable without
# depending on transcript feedback persistence.
printf '%s' '{"session_id":"owned-1","agent":"claude"}' | python3 "$STATE" record-check delivery blocked incomplete-delivery-chain >/dev/null
check "check telemetry records structured event" "$(sqlite3 "$DB" "select check_name||':'||outcome||':'||reason_code from check_events where session_key='claude:owned-1';")" "delivery:blocked:incomplete-delivery-chain"

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

# Existing v1 databases migrate in place without losing goal history.
V1="$SANDBOX/v1.db"
sqlite3 "$V1" "create table meta(key text primary key,value text not null); insert into meta values('schema_version','1'); create table goal_boundaries(session_key text not null,ordinal integer not null,prompt_sha256 text not null,created_at_ms integer not null,primary key(session_key,ordinal)); insert into goal_boundaries values('claude:legacy',1,'abc',9999999999999);"
out=$(VERIFY_WORK_STATE_DB="$V1" eval_payload "{\"session_id\":\"legacy\",\"agent\":\"claude\",\"transcript_path\":\"$research\"}")
check "v1 database migrates to the current schema" "$(sqlite3 "$V1" "select value from meta where key='schema_version';")" "4"
check "v1 migration preserves goal row" "$(sqlite3 "$V1" "select count(*) from goal_boundaries where session_key='claude:legacy';")" "1"
check "v1 migration adds transcript offset" "$(sqlite3 "$V1" "select transcript_offset from goal_boundaries where session_key='claude:legacy';")" "0"

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

# --- check_outcomes (schema v4) -------------------------------------------------
# The measurement table. It is written offline by the backfill, never at connect
# time, so the migration is a version stamp plus CREATE TABLE IF NOT EXISTS. What
# these pin is that an EXISTING v2 database survives the bump with its rows intact
# — that is the whole risk, since the live one already holds hundreds of fires.

check "schema version is 4" "$(sqlite3 "$DB" "select value from meta where key='schema_version';")" "4"
check "check_outcomes exists" \
  "$(sqlite3 "$DB" "select name from sqlite_master where type='table' and name='check_outcomes';")" \
  "check_outcomes"

# a v2 database with rows must migrate without losing them
V2="$SANDBOX/v2.db"
cp "$DB" "$V2"
sqlite3 "$V2" "drop table check_outcomes; alter table check_events rename to gate_events; alter table gate_events rename column check_name to gate_name; update meta set value='2' where key='schema_version';"
sqlite3 "$V2" "insert into gate_events(session_key,goal_ordinal,gate_name,outcome,reason_code,created_at_ms)
               values('claude:v2-canary',1,'open-pr','blocked','owned-pr-open',$(python3 -c 'import time;print(int(time.time()*1000))'));"
before=$(sqlite3 "$V2" "select count(*) from gate_events;")
VERIFY_WORK_STATE_DB="$V2" python3 "$STATE" evaluate >/dev/null 2>&1 <<'EOF'
{"session_id":"native-1","agent":"claude","transcript_path":"/nonexistent"}
EOF
check "v2 database migrates to v4" "$(sqlite3 "$V2" "select value from meta where key='schema_version';")" "4"
check "v2 rows survive the migration" "$(sqlite3 "$V2" "select count(*) from check_events;")" "$before"
check "migration creates check_outcomes" \
  "$(sqlite3 "$V2" "select name from sqlite_master where type='table' and name='check_outcomes';")" \
  "check_outcomes"

# an outcome row orphaned from its check event must not survive a prune
# derived_at_ms must be RECENT. With an epoch-1970 value this row is removed by the
# age-based delete instead, and the assertion below then passes even if the
# orphan-by-id sweep is deleted outright — a test that survives a broken build.
NOW_MS=$(python3 -c 'import time;print(int(time.time()*1000))')
sqlite3 "$V2" "insert into check_outcomes(check_event_id,derived_at_ms) values(999999,$NOW_MS);"
check "orphan row is present before prune" \
  "$(sqlite3 "$V2" "select count(*) from check_outcomes where check_event_id not in (select id from check_events);")" "1"
sqlite3 "$V2" "update meta set value='0' where key='last_pruned_ms';"
VERIFY_WORK_STATE_DB="$V2" python3 "$STATE" evaluate >/dev/null 2>&1 <<'EOF'
{"session_id":"native-1","agent":"claude","transcript_path":"/nonexistent"}
EOF
check "prune drops orphaned outcomes" \
  "$(sqlite3 "$V2" "select count(*) from check_outcomes where check_event_id not in (select id from check_events);")" "0"

# an unknown future version must still refuse rather than silently downgrade
V9="$SANDBOX/v9.db"; cp "$DB" "$V9"
sqlite3 "$V9" "update meta set value='9' where key='schema_version';"
VERIFY_WORK_STATE_DB="$V9" python3 "$STATE" evaluate >/dev/null 2>&1 <<'EOF'
{"session_id":"native-1","agent":"claude","transcript_path":"/nonexistent"}
EOF
check "unknown schema version leaves the stamp alone" \
  "$(sqlite3 "$V9" "select value from meta where key='schema_version';")" "9"

# --- record-checks: the batched writer -----------------------------------------
# Recording only blocks is what left check_events with 325 rows all reading
# 'blocked' — no denominator, so no check had a false-positive rate. These pin that
# allow outcomes are writable, that a batch is all-or-nothing, and that one bad
# triple cannot half-write the rest.

BATCH_DB="$SANDBOX/batch.db"
export VERIFY_WORK_STATE_DB="$BATCH_DB"
printf '%s' "$prompt" | python3 "$STATE" record-prompt >/dev/null

out=$(printf '%s' "$prompt" | python3 "$STATE" record-checks \
  "open-pr:skipped:no-owned-pr" "keep-moving:passed:checklist-clear" "stop:skipped:not-claiming-done")
check "batch reports how many it wrote" \
  "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])')" "3"
check "batch writes every row" "$(sqlite3 "$BATCH_DB" "select count(*) from check_events;")" "3"
check "passed outcome is recorded" \
  "$(sqlite3 "$BATCH_DB" "select count(*) from check_events where outcome='passed';")" "1"
check "skipped outcome is recorded" \
  "$(sqlite3 "$BATCH_DB" "select count(*) from check_events where outcome='skipped';")" "2"
check "more than one outcome value now exists" \
  "$(sqlite3 "$BATCH_DB" "select count(distinct outcome) from check_events;")" "2"

# one invalid triple must abort the WHOLE batch, not write the good ones first
before=$(sqlite3 "$BATCH_DB" "select count(*) from check_events;")
printf '%s' "$prompt" | python3 "$STATE" record-checks \
  "open-pr:passed:fine" "bad:NOTANOUTCOME:x" >/dev/null 2>&1 || true
check "an invalid triple writes nothing at all" \
  "$(sqlite3 "$BATCH_DB" "select count(*) from check_events;")" "$before"

# a malformed spec is rejected the same way
printf '%s' "$prompt" | python3 "$STATE" record-checks "missing-colons" >/dev/null 2>&1 || true
check "a malformed spec writes nothing" \
  "$(sqlite3 "$BATCH_DB" "select count(*) from check_events;")" "$before"

# an empty batch is a no-op, not an error
out=$(printf '%s' "$prompt" | python3 "$STATE" record-checks)
check "an empty batch records nothing" \
  "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["recorded"])')" "False"

export VERIFY_WORK_STATE_DB="$DB"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
