#!/usr/bin/env bash
# Tests for hooks/lib/json-field.sh — the shared JSON field extractor sourced by
# every guard/inject hook. Covers what the 12 consumers depend on:
#   - snake_case path extraction (Claude/Codex/Kimi/Cursor/Droid)
#   - the 3-arg camelCase fallback (Grok: snake empty -> camel resolves)
#   - nested paths (tool_input.command)
#   - a missing field -> empty output, return 0
#   - NO parser available (jq/node/python all absent) -> return 1, so the caller
#     can fail CLOSED. This is the Windows-git-bash fail-open bug the lib exists
#     to prevent.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
LIB="$DIR/../json-field.sh"
pass=0
fail=0

# shellcheck source=../json-field.sh
. "$LIB"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

ok()   { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# eq <name> <expected> <actual>
eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi
}

SNAKE='{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"/repo"}'
CAMEL='{"toolName":"Bash","toolInput":{"command":"git status"},"cwd":"/repo"}'

eq "snake: top-level field"            "Bash"       "$(_json_field "$SNAKE" tool_name)"
eq "snake: nested field"               "git status" "$(_json_field "$SNAKE" tool_input.command)"
eq "snake: shared cwd"                 "/repo"      "$(_json_field "$SNAKE" cwd)"
eq "missing field -> empty"            ""           "$(_json_field "$SNAKE" tool_input.nope)"

# 3-arg alternate path: snake resolves -> camel arg ignored.
eq "3-arg, snake present wins"         "git status" "$(_json_field "$SNAKE" tool_input.command toolInput.command)"
# 3-arg on a camelCase payload: snake empty -> camel resolves (the Grok path).
eq "3-arg, camel fallback (Grok)"      "git status" "$(_json_field "$CAMEL" tool_input.command toolInput.command)"
eq "3-arg camel top-level (Grok)"      "Bash"       "$(_json_field "$CAMEL" tool_name toolName)"
# Without the alternate arg, a camelCase payload yields empty on the snake path.
eq "2-arg on camel payload -> empty"   ""           "$(_json_field "$CAMEL" tool_input.command)"

if _json_field '{malformed' tool_input.command >/dev/null 2>&1; then
  bad "malformed JSON must return 1"
else
  ok "malformed JSON returns 1 (caller chooses fail-closed/open policy)"
fi

if _hook_skip_plan_mode '{"permission_mode":"plan"}'; then
  ok "snake: explicit plan mode skips"
else
  bad "snake: explicit plan mode should skip"
fi
if _hook_skip_plan_mode '{"permissionMode":"plan"}'; then
  ok "camel: explicit plan mode skips"
else
  bad "camel: explicit plan mode should skip"
fi
if _hook_skip_plan_mode '{"permission_mode":"future-mode"}'; then
  bad "unknown mode must remain guarded"
else
  ok "unknown mode remains guarded"
fi
if _hook_skip_plan_mode '{}'; then
  bad "missing mode must remain guarded"
else
  ok "missing mode remains guarded"
fi
if _hook_skip_plan_mode '{malformed'; then
  bad "malformed plan payload must remain guarded"
else
  ok "malformed plan payload remains guarded"
fi

# No parser at all -> return 1 (caller fails closed). Sandbox PATH carries only
# the builtins the function itself needs to run its `command -v` probes; jq,
# node, python are all absent.
if PATH="$SANDBOX/bin" _json_field "$SNAKE" tool_input.command >/dev/null 2>&1; then
  bad "no-parser -> return 1 (got 0, would fail OPEN)"
else
  ok "no-parser -> return 1 (caller can fail closed)"
fi
if PATH="$SANDBOX/bin" _hook_skip_plan_mode '{"permission_mode":"plan"}' >/dev/null 2>&1; then
  bad "no-parser plan gate must remain guarded"
else
  ok "no-parser plan gate remains guarded"
fi

printf '\njson-field: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
