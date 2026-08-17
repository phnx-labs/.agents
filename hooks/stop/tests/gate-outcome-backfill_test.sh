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
print("gates=%s" % ",".join(g for _, g, _ in fires))
for i, (idx, gate, digest) in enumerate(fires):
    later = [f[0] for f in fires if f[0] > idx]
    end = later[0] if later else len(records)
    tools, mutated, interjected, satisfied = bf.score_window(records, idx, end, gate)
    print("%s satisfied=%d tools=%d" % (gate, int(satisfied), tools))
    print("%s shalen=%d" % (gate, len(digest)))
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
check "the message digest is a sha256, not text" \
  "$(printf '%s' "$out" | grep '^keep-moving shalen' | cut -d= -f2)" "64"

# Writing is opt-in: a default run must not touch the database.
before=$(sqlite3 "$DB" "select count(*) from gate_outcomes;")
python3 "$BF" --db "$DB" >/dev/null 2>&1
check "a default run writes nothing" "$(sqlite3 "$DB" "select count(*) from gate_outcomes;")" "$before"

# And it must be re-runnable without doubling rows.
python3 "$BF" --db "$DB" --write >/dev/null 2>&1
first=$(sqlite3 "$DB" "select count(*) from gate_outcomes;")
python3 "$BF" --db "$DB" --write >/dev/null 2>&1
check "re-running does not duplicate rows" "$(sqlite3 "$DB" "select count(*) from gate_outcomes;")" "$first"

# Unscorable gates must never be reported as satisfied — a proxy there would
# inflate the success rate for demands no transcript scan can confirm.
unscorable=$(python3 - "$BF" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("bf", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(",".join(sorted(m.UNSCORABLE)))
PYEOF
)
check "self-audit and swarm are unscorable" "$unscorable" "self-audit,swarm"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
