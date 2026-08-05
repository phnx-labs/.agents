#!/usr/bin/env bash
# Tests for 03-vacation-recap.py.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/03-vacation-recap.py"
pass=0; fail=0

check() { # name, expected-substring, actual
  if [[ "$3" == *"$2"* ]]; then pass=$((pass+1)); echo "  ok   $1";
  else fail=$((fail+1)); echo "  FAIL $1"; echo "       want substring: $2"; echo "       got: ${3:0:200}"; fi
}
check_empty() { # name, actual
  if [[ -z "$2" ]]; then pass=$((pass+1)); echo "  ok   $1";
  else fail=$((fail+1)); echo "  FAIL $1 — expected no output, got: ${2:0:200}"; fi
}
check_not_empty() { # name, actual
  if [[ -n "$2" ]]; then pass=$((pass+1)); echo "  ok   $1";
  else fail=$((fail+1)); echo "  FAIL $1 — expected output, got nothing"; fi
}

echo "03-vacation-recap"

# 1. First prompt in a brand new session: nothing to recap against, stay silent,
#    but the state file must be written so the NEXT prompt has something to diff.
h="$(mktemp -d)"
out=$(HOME="$h" python3 "$HOOK" <<< '{"session_id":"s1","prompt":"hi","hook_event_name":"UserPromptSubmit"}' 2>&1)
check_empty "first prompt this session -> no output" "$out"
if [[ -f "$h/.agents/.cache/state/last-user-prompt/s1" ]]; then pass=$((pass+1)); echo "  ok   state file written after first prompt";
else fail=$((fail+1)); echo "  FAIL state file not written"; fi
rm -rf "$h"

# 2. Second prompt shortly after: gap is under the default 2h threshold -> silent.
h="$(mktemp -d)"
mkdir -p "$h/.agents/.cache/state/last-user-prompt"
python3 -c "import time; open('$h/.agents/.cache/state/last-user-prompt/s2','w').write(str(time.time()-5))"
out=$(HOME="$h" python3 "$HOOK" <<< '{"session_id":"s2","prompt":"hi","hook_event_name":"UserPromptSubmit"}' 2>&1)
check_empty "5s gap, default threshold -> no output" "$out"
rm -rf "$h"

# 3. Long gap past the default threshold (2h) -> reminder fires, in plain language,
#    and never touches/replaces the actual prompt content.
h="$(mktemp -d)"
mkdir -p "$h/.agents/.cache/state/last-user-prompt"
python3 -c "import time; open('$h/.agents/.cache/state/last-user-prompt/s3','w').write(str(time.time()-3*3600))"
out=$(HOME="$h" CLAUDECODE=1 python3 "$HOOK" <<< '{"session_id":"s3","prompt":"whats next","hook_event_name":"UserPromptSubmit"}' 2>&1)
check "3h gap (claude) -> recap reminder fires" "back-from-vacation recap" "$out"
check "3h gap (claude) -> mentions hours" "hour" "$out"
if [[ "$out" != *"whats next"* ]]; then pass=$((pass+1)); echo "  ok   original prompt text is not echoed/replaced by the hook";
else fail=$((fail+1)); echo "  FAIL hook output unexpectedly contains the raw prompt text"; fi
rm -rf "$h"

# 4. Custom threshold via env var: a 65s gap with a 60s threshold fires.
h="$(mktemp -d)"
mkdir -p "$h/.agents/.cache/state/last-user-prompt"
python3 -c "import time; open('$h/.agents/.cache/state/last-user-prompt/s4','w').write(str(time.time()-65))"
out=$(HOME="$h" CLAUDECODE=1 AGENTS_VACATION_RECAP_THRESHOLD_SEC=60 python3 "$HOOK" <<< '{"session_id":"s4","prompt":"hi","hook_event_name":"UserPromptSubmit"}' 2>&1)
check "65s gap, 60s threshold -> fires" "back-from-vacation recap" "$out"
rm -rf "$h"

# 5. Non-Claude harness gets JSON additionalContext, not plain text.
h="$(mktemp -d)"
mkdir -p "$h/.agents/.cache/state/last-user-prompt"
python3 -c "import time; open('$h/.agents/.cache/state/last-user-prompt/s5','w').write(str(time.time()-3*3600))"
out=$(HOME="$h" env -u CLAUDECODE -u CLAUDE_PROJECT_DIR python3 "$HOOK" <<< '{"sessionId":"s5","prompt":"hi","hookEventName":"UserPromptSubmit"}' 2>&1)
check "non-claude harness -> JSON additionalContext" '"additionalContext"' "$out"
check "non-claude harness -> hookEventName preserved" '"hookEventName": "UserPromptSubmit"' "$out"
rm -rf "$h"

# 6. Missing session_id: never crash, never block, no output.
h="$(mktemp -d)"
out=$(HOME="$h" python3 "$HOOK" <<< '{"prompt":"hi"}' 2>&1)
rc=$?
check_empty "no session_id -> no output" "$out"
if [[ $rc -eq 0 ]]; then pass=$((pass+1)); echo "  ok   no session_id -> rc 0 (never blocks)";
else fail=$((fail+1)); echo "  FAIL no session_id -> rc $rc, expected 0"; fi
rm -rf "$h"

# 7. Malformed JSON on stdin: never crash.
h="$(mktemp -d)"
out=$(HOME="$h" python3 "$HOOK" <<< 'not json' 2>&1)
rc=$?
check_empty "malformed stdin -> no output" "$out"
if [[ $rc -eq 0 ]]; then pass=$((pass+1)); echo "  ok   malformed stdin -> rc 0 (never blocks)";
else fail=$((fail+1)); echo "  FAIL malformed stdin -> rc $rc, expected 0"; fi
rm -rf "$h"

echo "  $pass passed, $fail failed"
[[ $fail -eq 0 ]]
