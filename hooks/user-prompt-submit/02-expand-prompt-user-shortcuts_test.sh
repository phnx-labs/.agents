#!/usr/bin/env bash
# Tests for 02-expand-prompt-user-shortcuts.sh.
#
# The case that matters most is layer resolution. This hook was registered for
# months while reading ONLY the legacy ~/.agents-system path, so on any fresh
# install the system layer never loaded and the hook silently produced nothing.
# Nothing caught it: the script itself was fine, and there was no test.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/02-expand-prompt-user-shortcuts.sh"
pass=0; fail=0

check() { # name, expected-substring, actual
  if [[ "$3" == *"$2"* ]]; then pass=$((pass+1)); echo "  ok   $1";
  else fail=$((fail+1)); echo "  FAIL $1"; echo "       want substring: $2"; echo "       got: ${3:0:200}"; fi
}
check_empty() { # name, actual
  if [[ -z "$2" ]]; then pass=$((pass+1)); echo "  ok   $1";
  else fail=$((fail+1)); echo "  FAIL $1 — expected no output, got: ${2:0:120}"; fi
}

mkhome() { # $1 = layer dir relative to HOME, $2 = expansion text
  local h; h="$(mktemp -d)"
  mkdir -p "$h/$1"
  printf 'shortcuts:\n  "#tok": |\n    %s\n' "$2" > "$h/$1/promptcuts.yaml"
  echo "$h"
}

echo "02-expand-prompt-user-shortcuts"

# 1. The regression guard: system layer at the CANONICAL path must load.
h=$(mkhome ".agents/.system/hooks" "SYSTEM_EXPANSION")
out=$(HOME="$h" bash "$HOOK" <<< '{"prompt":"#tok","hook_event_name":"UserPromptSubmit"}' 2>&1)
check "canonical system layer (~/.agents/.system) is read" "SYSTEM_EXPANSION" "$out"
rm -rf "$h"

# 2. The legacy path still works, for a folded pre-migration install.
h=$(mkhome ".agents-system/hooks" "LEGACY_EXPANSION")
out=$(HOME="$h" bash "$HOOK" <<< '{"prompt":"#tok","hook_event_name":"UserPromptSubmit"}' 2>&1)
check "legacy system layer (~/.agents-system) still read" "LEGACY_EXPANSION" "$out"
rm -rf "$h"

# 3. User layer wins over system on a key collision.
h=$(mkhome ".agents/.system/hooks" "SYSTEM_EXPANSION")
mkdir -p "$h/.agents/hooks"
printf 'shortcuts:\n  "#tok": |\n    USER_EXPANSION\n' > "$h/.agents/hooks/promptcuts.yaml"
out=$(HOME="$h" bash "$HOOK" <<< '{"prompt":"#tok","hook_event_name":"UserPromptSubmit"}' 2>&1)
check "user layer overrides system on collision" "USER_EXPANSION" "$out"
rm -rf "$h"

# 4. A prompt with no shortcut token is passed through untouched (no context injected).
h=$(mkhome ".agents/.system/hooks" "SYSTEM_EXPANSION")
out=$(HOME="$h" bash "$HOOK" <<< '{"prompt":"just a normal prompt","hook_event_name":"UserPromptSubmit"}' 2>&1)
check_empty "no token -> no output" "$out"
rm -rf "$h"

# 5. Backticked # syntax is explicit and removes its delimiters on replacement.
h=$(mkhome ".agents/.system/hooks" "BACKTICK_HASH_EXPANSION")
out=$(HOME="$h" CLAUDECODE=1 bash "$HOOK" <<< '{"prompt":"Use `#tok` now","hook_event_name":"UserPromptSubmit"}' 2>&1)
check "backticked # marker expands" "Use BACKTICK_HASH_EXPANSION now" "$out"
rm -rf "$h"

# 6. !! is the hashtag-free alias, bare or backticked.
h=$(mkhome ".agents/.system/hooks" "DOUBLE_BANG_EXPANSION")
out=$(HOME="$h" CLAUDECODE=1 bash "$HOOK" <<< '{"prompt":"Use !!tok now","hook_event_name":"UserPromptSubmit"}' 2>&1)
check "bare !! marker expands" "Use DOUBLE_BANG_EXPANSION now" "$out"
out=$(HOME="$h" CLAUDECODE=1 bash "$HOOK" <<< '{"prompt":"Use `!!tok` now","hook_event_name":"UserPromptSubmit"}' 2>&1)
check "backticked !! marker expands" "Use DOUBLE_BANG_EXPANSION now" "$out"
rm -rf "$h"

# 7. Unregistered hashtags and doubled words remain ordinary prompt text.
h=$(mkhome ".agents/.system/hooks" "SYSTEM_EXPANSION")
out=$(HOME="$h" bash "$HOOK" <<< '{"prompt":"Discuss #release and !!important","hook_event_name":"UserPromptSubmit"}' 2>&1)
check_empty "unregistered # / !! markers -> no output" "$out"
rm -rf "$h"

# 8. No promptcuts.yaml anywhere: exit clean, emit nothing. Never block a prompt.
h="$(mktemp -d)"
out=$(HOME="$h" bash "$HOOK" <<< '{"prompt":"#tok","hook_event_name":"UserPromptSubmit"}' 2>&1)
rc=$?
check_empty "missing promptcuts.yaml -> no output" "$out"
if [[ $rc -eq 0 ]]; then pass=$((pass+1)); echo "  ok   missing promptcuts.yaml -> rc 0 (never blocks)";
else fail=$((fail+1)); echo "  FAIL missing promptcuts.yaml -> rc $rc, expected 0"; fi
rm -rf "$h"

echo "  $pass passed, $fail failed"
[[ $fail -eq 0 ]]
