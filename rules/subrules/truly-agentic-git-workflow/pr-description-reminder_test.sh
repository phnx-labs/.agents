#!/usr/bin/env bash
# Test for pr-description-reminder.sh (PreToolUse Bash reminder).
#
# Verifies the reminder NUDGES (exit 2) a `gh pr create|edit` with a thin inline
# body, and ALLOWS (exit 0) a body that carries any structure (heading/table/
# bullet) or a change-type marker, a --body-file/--fill body, an editor body (no
# body flag), and any non-gh-pr command. Exercises both harness payload shapes:
# Claude snake_case (.tool_input.command) and Grok/Codex camelCase
# (.toolInput.command). Runs the real script over real stdin JSON (no mocking).
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$DIR/pr-description-reminder.sh"
pass=0
fail=0

# check <want_exit> <field> <description> <command>
check() {
  want=$1; field=$2; desc=$3; cmd=$4
  json=$(printf '%s' "$cmd" | jq -Rs --arg f "$field" '{($f):{command:.}}')
  printf '%s' "$json" | "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s (want exit %s, got %s)\n  cmd: %s\n' "$desc" "$want" "$got" "$cmd"
  fi
}

# --- NUDGE (exit 2): thin inline body, both shapes ---
check 2 tool_input "snake thin pr create"      'gh pr create -t x -b "just a real change"'
check 2 toolInput  "camel thin pr create"      'gh pr create -t x -b "just a real change"'
check 2 tool_input "snake thin pr edit"        'gh pr edit 5 -b "updated the thing"'
check 2 tool_input "snake thin --body long"    'gh pr create -t x --body "did some work on the parser today"'

# --- ALLOW (exit 0): body carries structure ---
check 0 tool_input "heading body"   'gh pr create -t x -b "## What: rewired the parser"'
check 0 tool_input "table body"     'gh pr create -t x -b "field | shown"'
check 0 tool_input "bullet body"    'gh pr create -t x -b "- fixed the null check"'
check 0 toolInput  "camel bullet"   'gh pr create -t x -b "- fixed the null check"'

# --- ALLOW (exit 0): body carries a change-type marker ---
check 0 tool_input "docs-only marker" 'gh pr create -t x -b "docs-only: spec the session model"'
check 0 tool_input "feat marker"      'gh pr create -t x -b "feat: add the --all flag"'
check 0 tool_input "bugfix marker"    'gh pr create -t x -b "bugfix for the idle detector"'

# --- ALLOW (exit 0): body not inspectable / absent ---
check 0 tool_input "body-file"        'gh pr create -t x --body-file /tmp/body.md'
check 0 tool_input "fill"             'gh pr create --fill'
check 0 tool_input "no body (editor)" 'gh pr create -t x'
check 0 tool_input "edit label only"  'gh pr edit 5 --add-label bug'

# --- ALLOW (exit 0): not a gh pr command ---
check 0 tool_input "git commit thin"  'git commit -m "wip"'
check 0 toolInput  "echo"             'echo "just a real change"'

printf -- '---\npr-description-reminder: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
