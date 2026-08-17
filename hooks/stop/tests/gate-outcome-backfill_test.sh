#!/usr/bin/env bash
# Tests for gate-outcome-backfill.py. Real sqlite, real transcript JSONL on disk,
# no mocking — the script's whole job is reading those two things.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
BF="$HERE/../gate-outcome-backfill.py"
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
printf '%s' "$payload" | python3 "$STATE" record-gates "keep-moving:blocked:unfinished-checklist" "handback:blocked:runnable-not-executed" >/dev/null 2>&1

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
print("gates=%s" % ",".join(f[1] for f in fires))
for idx, gate, digest, _ts in fires:
    later = [f[0] for f in fires if f[0] > idx]
    end = later[0] if later else len(records)
    tools, mutated, interjected, satisfied = bf.score_window(records, idx, end, gate)
    print("%s satisfied=%d tools=%d" % (gate, int(satisfied), tools))
    import re as _re
    print("%s hexok=%d" % (gate, 1 if _re.fullmatch(r"[0-9a-f]{64}", digest) else 0))
PY

out=$(cat "$SANDBOX/out.txt")
check "both injected blocks are matched to a gate" "$(printf '%s' "$out" | grep '^fires=' | cut -d= -f2)" "2"
check "gates are identified by their markers" "$(printf '%s' "$out" | grep '^gates=' | cut -d= -f2)" "keep-moving,handback"
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
for idx, gate, _digest, _ts in fires:
    later = [f[0] for f in fires if f[0] > idx]
    end = later[0] if later else len(records)
    tools, mutated, _inter, satisfied = bf.score_window(records, idx, end, gate)
    out.append("%s:sat=%d,tools=%d" % (gate, int(satisfied), tools))
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
# gate_events rows recorded moments ago — the validated path, not the fallback.
now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
with open(sys.argv[2], "w") as out:
    for line in open(sys.argv[1]):
        if line.strip():
            record = json.loads(line)
            record["timestamp"] = now
            out.write(json.dumps(record) + "\n")
PYEOF

before=$(sqlite3 "$DB" "select count(*) from gate_outcomes;")
HOME="$FAKE_HOME" python3 "$BF" --db "$DB" >/dev/null 2>&1
check "a default run writes nothing" "$(sqlite3 "$DB" "select count(*) from gate_outcomes;")" "$before"

HOME="$FAKE_HOME" python3 "$BF" --db "$DB" --write >/dev/null 2>&1
first=$(sqlite3 "$DB" "select count(*) from gate_outcomes;")
check "--write derives a row per matched fire" "$first" "2"
check "the demand each gate asked for is scored satisfied" \
  "$(sqlite3 "$DB" "select count(*) from gate_outcomes where demand_satisfied=1;")" "2"

HOME="$FAKE_HOME" python3 "$BF" --db "$DB" --write >/dev/null 2>&1; rerun_rc=$?
check "re-running does not duplicate rows" "$(sqlite3 "$DB" "select count(*) from gate_outcomes;")" "$first"
# An unchanged row count also happens when the second run CRASHES on a UNIQUE
# violation, so assert it exited cleanly too.
check "the second run exits cleanly rather than crashing" "$rerun_rc" "0"

# Unscorable gates must never be reported as satisfied — a proxy there would
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
# so scoring it at all would report a working gate as broken.
check "delivery, self-audit and swarm are unscorable" "$unscorable" "delivery,self-audit,swarm"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
