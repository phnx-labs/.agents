#!/usr/bin/env bash
# Tests for check-outcome-backfill.py. Real sqlite, real transcript JSONL on disk,
# no mocking — the script's whole job is reading those two things.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
BF="$HERE/../check-outcome-backfill.py"
STATE="$HERE/../verify-work-state.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "ok   - $1"
  else fail=$((fail + 1)); echo "FAIL - $1: expected [$3], got [$2]"; fi
}

DB="$SANDBOX/state.db"
export VERIFY_WORK_STATE_DB="$DB"

# A transcript where one keep-moving block is followed by a task actually moving
# to completed (demand satisfied), and one handback block is followed by the
# handed-over script being run BY PATH — the shape that a bash-prefix-only
# pattern scores as unmet.
TR="$SANDBOX/t.jsonl"
cat > "$TR" <<'JSONL'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working on it."}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\nSTOP GATE (keep moving): Your task list still has 2 unfinished"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I wrote it to /tmp/deploy.sh, run it when ready."}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\nSTOP GATE (handback): You wrote a runnable script"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"/tmp/deploy.sh --apply 2>&1 | tail -5"}}]}}
JSONL

payload='{"session_id":"bf-1","agent":"claude","launch_id":"L1","prompt":"do the thing"}'
printf '%s' "$payload" | python3 "$STATE" record-prompt >/dev/null 2>&1
printf '%s' "$payload" | python3 "$STATE" record-checks "keep-moving:blocked:unfinished-checklist" "handback:blocked:runnable-not-executed" >/dev/null 2>&1

# The backfill resolves transcripts under ~/.agents/.history/versions/<harness>/…,
# which a sandbox cannot fake, so point it at the fixture through the module.
python3 - "$BF" "$DB" "$TR" > "$SANDBOX/out.txt" 2>&1 <<'PY'
import importlib.util, sqlite3, sys
spec = importlib.util.spec_from_file_location("bf", sys.argv[1])
bf = importlib.util.module_from_spec(spec); spec.loader.exec_module(bf)
records = []
import json
for line in open(sys.argv[3]):
    line = line.strip()
    if line:
        records.append(json.loads(line))
fires = bf.find_fires(records)
print("fires=%d" % len(fires))
print("checks=%s" % ",".join(f[1] for f in fires))
for idx, check, digest, _ts in fires:
    later = [f[0] for f in fires if f[0] > idx]
    end = later[0] if later else len(records)
    tools, mutated, interjected, satisfied = bf.score_window(records, idx, end, check)
    print("%s satisfied=%d tools=%d" % (check, int(satisfied), tools))
    import re as _re
    print("%s hexok=%d" % (check, 1 if _re.fullmatch(r"[0-9a-f]{64}", digest) else 0))
PY

out=$(cat "$SANDBOX/out.txt")
check "both injected blocks are matched to a check" "$(printf '%s' "$out" | grep '^fires=' | cut -d= -f2)" "2"
check "checks are identified by their markers" "$(printf '%s' "$out" | grep '^checks=' | cut -d= -f2)" "keep-moving,handback"
# A task moving to completed is the keep-moving demand; merely touching one is not.
check "keep-moving counts a task reaching completed" \
  "$(printf '%s' "$out" | grep '^keep-moving satisfied' | grep -o 'satisfied=[01]')" "satisfied=1"
# The regression this file exists for: an executable invoked BY PATH.
check "handback counts a /tmp script run by path" \
  "$(printf '%s' "$out" | grep '^handback satisfied' | grep -o 'satisfied=[01]')" "satisfied=1"
check "the message digest is lowercase hex, not text" \
  "$(printf '%s' "$out" | grep '^keep-moving hexok' | cut -d= -f2)" "1"

# The negative half of the headline claim: demand_satisfied is NOT "the agent did
# something afterwards". A task merely moved to in_progress, and a command run that
# is not the handed-over script, must both score UNsatisfied — otherwise the metric
# certifies the very false positives it exists to find.
TR2="$SANDBOX/t2.jsonl"
cat > "$TR2" <<'JSONL'
{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\nSTOP GATE (keep moving): Your task list still has 2 unfinished"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I wrote it to /tmp/deploy.sh, run it when ready."}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\nSTOP GATE (handback): You wrote a runnable script"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"git status --short"}}]}}
JSONL

neg=$(python3 - "$BF" "$TR2" <<'PYEOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("bf", sys.argv[1])
bf = importlib.util.module_from_spec(spec); spec.loader.exec_module(bf)
records = [json.loads(l) for l in open(sys.argv[2]) if l.strip()]
fires = bf.find_fires(records)
out = []
for idx, check, _digest, _ts in fires:
    later = [f[0] for f in fires if f[0] > idx]
    end = later[0] if later else len(records)
    tools, mutated, _inter, satisfied = bf.score_window(records, idx, end, check)
    out.append("%s:sat=%d,tools=%d" % (check, int(satisfied), tools))
print(" ".join(out))
PYEOF
)
check "a task moved to in_progress does NOT satisfy keep-moving" \
  "$(printf '%s' "$neg" | grep -o 'keep-moving:sat=[01]')" "keep-moving:sat=0"
check "an unrelated command does NOT satisfy handback" \
  "$(printf '%s' "$neg" | grep -o 'handback:sat=[01]')" "handback:sat=0"
# ...while still recording that follow-on activity happened. If these were 0 the
# assertions above would pass vacuously, on a window that saw no tools at all.
check "the unsatisfied windows still observed tool activity" \
  "$(printf '%s' "$neg" | grep -c 'tools=0')" "0"

# The write path resolves transcripts under ~/.agents/.history/versions/... , so
# it only derives anything when a transcript is really there. Pointing HOME at the
# sandbox exercises load_transcript + main() for real. Without this the write and
# idempotency assertions compared 0 rows to 0 rows and passed no matter what the
# writer did — including with INSERT OR REPLACE swapped for a plain INSERT.
FAKE_HOME="$SANDBOX/home"
PROJ="$FAKE_HOME/.agents/.history/versions/claude/v1/home/.claude/projects/p"
mkdir -p "$PROJ"
python3 - "$TR" "$PROJ/bf-1.jsonl" <<'PYEOF'
import json, sys, time
from datetime import datetime, timezone
# Stamp the fixture at "now" so it lands inside the pairing tolerance of the
# check_events rows recorded moments ago — the validated path, not the fallback.
now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
with open(sys.argv[2], "w") as out:
    for line in open(sys.argv[1]):
        if line.strip():
            record = json.loads(line)
            record["timestamp"] = now
            out.write(json.dumps(record) + "\n")
PYEOF

before=$(sqlite3 "$DB" "select count(*) from check_outcomes;")
HOME="$FAKE_HOME" python3 "$BF" --db "$DB" >/dev/null 2>&1
check "a default run writes nothing" "$(sqlite3 "$DB" "select count(*) from check_outcomes;")" "$before"

HOME="$FAKE_HOME" python3 "$BF" --db "$DB" --write >/dev/null 2>&1
first=$(sqlite3 "$DB" "select count(*) from check_outcomes;")
check "--write derives a row per matched fire" "$first" "2"
check "the demand each check asked for is scored satisfied" \
  "$(sqlite3 "$DB" "select count(*) from check_outcomes where demand_satisfied=1;")" "2"

HOME="$FAKE_HOME" python3 "$BF" --db "$DB" --write >/dev/null 2>&1; rerun_rc=$?
check "re-running does not duplicate rows" "$(sqlite3 "$DB" "select count(*) from check_outcomes;")" "$first"
# An unchanged row count also happens when the second run CRASHES on a UNIQUE
# violation, so assert it exited cleanly too.
check "the second run exits cleanly rather than crashing" "$rerun_rc" "0"

# --- pairing: one transcript fire may serve exactly one recorded row ----------
# The hook records a fire even when the harness never injects the block, so a
# session routinely holds MORE rows than markers. Nearest-timestamp matching
# without consumption attached every orphan row to the closest real fire and
# scored it against a window that answered a different block. Three rows, two
# injections: exactly two may score.
DB2="$SANDBOX/pair.db"
HOME2="$SANDBOX/home2"
PROJ2="$HOME2/.agents/.history/versions/claude/v1/home/.claude/projects/p"
mkdir -p "$PROJ2"
VERIFY_WORK_STATE_DB="$DB2" python3 "$STATE" record-prompt >/dev/null 2>&1 <<<'{"session_id":"bf-2","agent":"claude","launch_id":"L2","prompt":"x"}'
VERIFY_WORK_STATE_DB="$DB2" python3 "$STATE" record-checks \
  "keep-moving:blocked:a" "keep-moving:blocked:b" "keep-moving:blocked:c" \
  >/dev/null 2>&1 <<<'{"session_id":"bf-2","agent":"claude","launch_id":"L2","prompt":"x"}'

python3 - "$PROJ2/bf-2.jsonl" <<'PYEOF'
import json, sys
from datetime import datetime, timezone
now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
fire = {"type": "user", "isMeta": True, "timestamp": now, "message": {"role": "user",
        "content": "Stop hook feedback:\nSTOP GATE (keep moving): unfinished"}}
done = {"type": "assistant", "timestamp": now, "message": {"role": "assistant", "content":
        [{"type": "tool_use", "id": "t", "name": "TaskUpdate",
          "input": {"taskId": "1", "status": "completed"}}]}}
with open(sys.argv[1], "w") as out:
    for record in (fire, done, fire, done):      # two injections, two responses
        out.write(json.dumps(record) + "\n")
PYEOF

HOME="$HOME2" python3 "$BF" --db "$DB2" --write > "$SANDBOX/pair.out" 2>&1
check "three recorded rows against two injections derive only two" \
  "$(sqlite3 "$DB2" "select count(*) from check_outcomes;")" "2"
check "the row with no unused injection is reported as skipped" \
  "$(grep -c 'no unused injection within' "$SANDBOX/pair.out")" "1"

# --- no timestamp means no honest pairing: skip, never fall back to position ----
DB3="$SANDBOX/nots.db"
HOME3="$SANDBOX/home3"
PROJ3="$HOME3/.agents/.history/versions/claude/v1/home/.claude/projects/p"
mkdir -p "$PROJ3"
VERIFY_WORK_STATE_DB="$DB3" python3 "$STATE" record-prompt >/dev/null 2>&1 <<<'{"session_id":"bf-3","agent":"claude","launch_id":"L3","prompt":"x"}'
VERIFY_WORK_STATE_DB="$DB3" python3 "$STATE" record-checks "keep-moving:blocked:a" \
  >/dev/null 2>&1 <<<'{"session_id":"bf-3","agent":"claude","launch_id":"L3","prompt":"x"}'
cat > "$PROJ3/bf-3.jsonl" <<'JSONL'
{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\nSTOP GATE (keep moving): unfinished"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}
JSONL
HOME="$HOME3" python3 "$BF" --db "$DB3" --write >/dev/null 2>&1
check "an untimestamped transcript scores nothing rather than guessing by position" \
  "$(sqlite3 "$DB3" "select count(*) from check_outcomes;")" "0"

# --- the demand detector reads the status FIELD, not the dumped payload --------
det=$(python3 - "$BF" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("bf", sys.argv[1])
bf = importlib.util.module_from_spec(spec); spec.loader.exec_module(bf)

def sat(tool, payload, before=None):
    fire = {"type": "user", "isMeta": True, "message": {"role": "user",
            "content": "Stop hook feedback:\nSTOP GATE (keep moving): unfinished"}}
    call = {"type": "assistant", "message": {"role": "assistant", "content":
            [{"type": "tool_use", "id": "t", "name": tool, "input": payload}]}}
    records = []
    if before is not None:
        records.append({"type": "assistant", "message": {"role": "assistant", "content":
            [{"type": "tool_use", "id": "b", "name": "TodoWrite", "input": before}]}})
    start = len(records)
    records += [fire, call]
    return int(bf.score_window(records, start, len(records), "keep-moving")[3])

print("content=%d status=%d reemit=%d newdone=%d" % (
    sat("TaskUpdate", {"taskId": "1", "status": "in_progress", "content": "completed the audit"}),
    sat("TaskUpdate", {"taskId": "1", "status": "completed"}),
    sat("TodoWrite", {"todos": [{"id": "1", "status": "completed"}]},
        before={"todos": [{"id": "1", "status": "completed"}]}),
    sat("TodoWrite", {"todos": [{"id": "1", "status": "completed"}, {"id": "2", "status": "completed"}]},
        before={"todos": [{"id": "1", "status": "completed"}]})))
PYEOF
)
check "a task whose CONTENT says completed does not satisfy the demand" \
  "$(printf '%s' "$det" | grep -o 'content=[01]')" "content=0"
check "a task whose STATUS is completed does satisfy it" \
  "$(printf '%s' "$det" | grep -o 'status=[01]')" "status=1"
check "TodoWrite re-emitting an already-complete todo does not satisfy it" \
  "$(printf '%s' "$det" | grep -o 'reemit=[01]')" "reemit=0"
check "TodoWrite completing a NEW todo does satisfy it" \
  "$(printf '%s' "$det" | grep -o 'newdone=[01]')" "newdone=1"

# --- the tolerance itself: a fire far from any injection must not be scored ----
# Every other fixture stamps its records at "now", the same moment the rows are
# recorded, so nothing is ever outside PAIR_TOLERANCE_MS and deleting the bound
# changed no result. This backdates the recorded row an hour past its injection.
DB4="$SANDBOX/tol.db"
HOME4="$SANDBOX/home4"
PROJ4="$HOME4/.agents/.history/versions/claude/v1/home/.claude/projects/p"
mkdir -p "$PROJ4"
VERIFY_WORK_STATE_DB="$DB4" python3 "$STATE" record-prompt >/dev/null 2>&1 <<<'{"session_id":"bf-4","agent":"claude","launch_id":"L4","prompt":"x"}'
VERIFY_WORK_STATE_DB="$DB4" python3 "$STATE" record-checks "keep-moving:blocked:a" \
  >/dev/null 2>&1 <<<'{"session_id":"bf-4","agent":"claude","launch_id":"L4","prompt":"x"}'
sqlite3 "$DB4" "update check_events set created_at_ms = created_at_ms - 3600000;"

python3 - "$PROJ4/bf-4.jsonl" <<'PYEOF'
import json, sys
from datetime import datetime, timezone
now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
records = [
    {"type": "user", "isMeta": True, "timestamp": now, "message": {"role": "user",
     "content": "Stop hook feedback:\nSTOP GATE (keep moving): unfinished"}},
    {"type": "assistant", "timestamp": now, "message": {"role": "assistant", "content":
     [{"type": "tool_use", "id": "t", "name": "TaskUpdate",
       "input": {"taskId": "1", "status": "completed"}}]}},
]
with open(sys.argv[1], "w") as out:
    for record in records:
        out.write(json.dumps(record) + "\n")
PYEOF

HOME="$HOME4" python3 "$BF" --db "$DB4" --write > "$SANDBOX/tol.out" 2>&1
check "a fire an hour from its only injection is not scored" \
  "$(sqlite3 "$DB4" "select count(*) from check_outcomes;")" "0"
# ...and the same row DOES score once it is inside the window, so the assertion
# above is testing the bound rather than some unrelated failure to load.
sqlite3 "$DB4" "update check_events set created_at_ms = created_at_ms + 3600000;"
HOME="$HOME4" python3 "$BF" --db "$DB4" --write >/dev/null 2>&1
check "the same row scores once it falls inside the window" \
  "$(sqlite3 "$DB4" "select count(*) from check_outcomes;")" "1"

# Unscorable checks must never be reported as satisfied — a proxy there would
# inflate the success rate for demands no transcript scan can confirm.
unscorable=$(python3 - "$BF" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("bf", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(",".join(sorted(m.UNSCORABLE)))
PYEOF
)
# delivery joined the set after review: STOP GATE (delivery) fires on five
# independent demands and a release-command detector can see only one of them,
# so scoring it at all would report a working check as broken.
check "delivery, self-audit and swarm are unscorable" "$unscorable" "delivery,self-audit,swarm"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
