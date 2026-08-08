#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/02-expand-prompt-bang-commands.sh"
pass=0; fail=0

check() {
  if [[ "$3" == *"$2"* ]]; then pass=$((pass+1)); echo "  ok   $1"
  else fail=$((fail+1)); echo "  FAIL $1"; echo "       want: $2"; echo "       got: ${3:0:240}"; fi
}

echo "02-expand-prompt-bang-commands"

out=$(printf '%s' '{"prompt":"A `!printf one` B `! printf two`","cwd":"/tmp","hook_event_name":"UserPromptSubmit"}' | bash "$HOOK")
check "terse and explicit commands expand in source order" 'A `one` B `two`' "$out"

out=$(printf '%s' '{"prompt":"Keep `!important` literal","cwd":"/tmp","hook_event_name":"UserPromptSubmit"}' | bash "$HOOK")
if [[ -z "$out" ]]; then pass=$((pass+1)); echo "  ok   bare identifier stays literal"
else fail=$((fail+1)); echo "  FAIL bare identifier stays literal — got: ${out:0:240}"; fi

elapsed=$(python3 - "$HOOK" <<'PY'
import json, subprocess, sys, time
hook = sys.argv[1]
payload = {"prompt": "`! sleep 0.4; printf one` `! sleep 0.4; printf two` `! sleep 0.4; printf three`", "cwd": "/tmp"}
started = time.perf_counter()
result = subprocess.run(["bash", hook], input=json.dumps(payload), text=True, capture_output=True, check=True)
elapsed = time.perf_counter() - started
assert all(word in result.stdout for word in ("one", "two", "three")), result.stdout
print(f"{elapsed:.3f}")
PY
)
if python3 - "$elapsed" <<'PY'
import sys
raise SystemExit(0 if float(sys.argv[1]) < 0.8 else 1)
PY
then pass=$((pass+1)); echo "  ok   three 400ms commands execute concurrently (${elapsed}s)"
else fail=$((fail+1)); echo "  FAIL commands ran too slowly (${elapsed}s; sequential is at least 1.2s)"; fi

marker=$(mktemp)
rm -f "$marker"
payload=$(python3 - "$marker" <<'PY'
import json, os, sys
marker = sys.argv[1]
if os.name == "nt":
    command = f'powershell -NoProfile -Command "Start-Sleep 7; New-Item -ItemType File -Path {marker}"'
else:
    command = f"sleep 7; touch {marker}"
print(json.dumps({"prompt": f"`! {command}`", "cwd": os.getcwd()}))
PY
)
out=$(printf '%s' "$payload" | bash "$HOOK")
check "command timeout is reported" '[timeout]' "$out"
sleep 3
if [[ ! -e "$marker" ]]; then pass=$((pass+1)); echo "  ok   timeout kills the command process group"
else fail=$((fail+1)); echo "  FAIL timed-out child survived and wrote $marker"; fi

many='{"prompt":"`! true` `! true` `! true` `! true` `! true` `! true` `! true` `! true` `! true`","cwd":"/tmp"}'
out=$(printf '%s' "$many" | bash "$HOOK")
check "parallel command count is bounded" 'at most 8 inline commands per prompt' "$out"

echo "  $pass passed, $fail failed"
[[ $fail -eq 0 ]]
