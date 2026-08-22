#!/usr/bin/env bash
# Tests for teams-roster-guard.sh (RUSH-3020). Hermetic: fake HOME with a fake
# installed-harness registry and fake team records; the guard reads only those.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/teams-roster-guard.sh"
fail=0

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX"

mk_versions() { # $@ = harness names installed
  rm -rf "$SANDBOX/.agents/.history/versions"
  for h in "$@"; do mkdir -p "$SANDBOX/.agents/.history/versions/$h/1.0/home"; done
}

add_teammate() { # $1 team, $2 harness
  local id
  id=$(date +%s%N)$RANDOM
  mkdir -p "$SANDBOX/.agents/.history/teams/agents/$id"
  printf '{"task_name":"%s","agent_type":"%s"}\n' "$1" "$2" \
    > "$SANDBOX/.agents/.history/teams/agents/$id/meta.json"
}

run_guard() { # $1 = command string -> echoes exit code
  printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")" \
    | sh "$GUARD" >/dev/null 2>"$SANDBOX/stderr"
  echo $?
}

check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$3] got [$2]"; fail=1; fi; }

# 1. Two same-harness teammates exist; 3rd same-harness add -> block.
mk_versions claude codex grok
add_teammate feat claude; add_teammate feat claude
check "3rd same-harness add blocks" "$(run_guard 'agents teams add feat claude "Owns: src/a" --name t3')" "2"
grep -q "single-harness:" "$SANDBOX/stderr" && echo "ok   - block message teaches the escape token" || { echo "FAIL - no escape token in message"; fail=1; }

# 2. Same add WITH the stated reason -> allow.
check "single-harness: reason clears the guard" "$(run_guard 'agents teams add feat claude "Owns: src/a. single-harness: darwin Keychain paths" --name t3')" "0"

# 3. Mixed roster -> allow (only pure monocultures fire).
rm -rf "$SANDBOX/.agents/.history/teams"
add_teammate mix claude; add_teammate mix grok
check "mixed roster passes" "$(run_guard 'agents teams add mix claude "Owns: src/b" --name t3')" "0"

# 4. Harness-agnostic: a grok monoculture trips it too.
rm -rf "$SANDBOX/.agents/.history/teams"
add_teammate gk grok; add_teammate gk grok
check "non-claude monoculture blocks the same" "$(run_guard 'agents teams add gk grok "Owns: src/c" --name t3')" "2"

# 5. Single-harness install -> never fires (mixing is impossible).
mk_versions claude
rm -rf "$SANDBOX/.agents/.history/teams"
add_teammate solo claude; add_teammate solo claude
check "single-harness install never fires" "$(run_guard 'agents teams add solo claude "Owns: src/d" --name t3')" "0"

# 6. First and second adds never fire.
mk_versions claude codex
rm -rf "$SANDBOX/.agents/.history/teams"
check "first add passes" "$(run_guard 'agents teams add fresh claude "Owns: src/e" --name t1')" "0"
add_teammate fresh claude
check "second add passes" "$(run_guard 'agents teams add fresh claude "Owns: src/f" --name t2')" "0"

# 7. Non-teams commands pass untouched; unreadable state fails open.
check "unrelated command passes" "$(run_guard 'git status')" "0"
rm -rf "$SANDBOX/.agents/.history/teams"
add_teammate broken claude; add_teammate broken claude
for f in "$SANDBOX/.agents/.history/teams/agents/"*/meta.json; do printf 'not-json' > "$f"; done
check "corrupt roster records fail open" "$(run_guard 'agents teams add broken claude "Owns: src/g" --name t3')" "0"

if [ "$fail" -ne 0 ]; then echo "teams-roster-guard_test: FAILED"; exit 1; fi
echo "teams-roster-guard_test: all passed"
