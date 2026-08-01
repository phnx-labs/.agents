#!/usr/bin/env bash
# Test for pr-description-reminder.sh (PreToolUse Bash reminder).
#
# Model: EVIDENCE-OR-DECLARE. The reminder NUDGES (exit 2) a `gh pr create|edit`
# whose inline body shows no evidence, and ALLOWS (exit 0) a body that carries any
# of: media (screenshot/video/asset), a fenced code block or table, a ticket/plan
# link, or a no-visible-surface / change-type declaration — plus any --body-file /
# --fill / editor body and any non-gh-pr command. Exercises both harness payload
# shapes: Claude snake_case (.tool_input.command) and Grok/Codex camelCase
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

# --- NUDGE (exit 2): no evidence, both shapes ---
check 2 tool_input "snake bare prose"     'gh pr create -t x -b "just a real change"'
check 2 toolInput  "camel bare prose"     'gh pr create -t x -b "just a real change"'
check 2 tool_input "thin pr edit"         'gh pr edit 5 -b "updated the thing"'
check 2 tool_input "prose list no proof"  'gh pr create -t x -b "1. did the thing 2. tested it"'

# --- ALLOW (exit 0): media evidence (screenshot / video / asset) ---
check 0 tool_input "markdown image"  'gh pr create -t x -b "![result](shot.png)"'
check 0 tool_input "png path"        'gh pr create -t x -b "see /tmp/out.png for the render"'
check 0 tool_input "video file"      'gh pr create -t x -b "flow recording: demo.mp4"'
check 0 toolInput  "gh asset url"    'gh pr create -t x -b "https://github.com/o/r/assets/12/ab.gif"'

# --- ALLOW (exit 0): concrete artifact (code block / table) ---
check 0 tool_input "code block"      'gh pr create -t x -b "ran it: ```200 OK```"'
check 0 tool_input "table"           'gh pr create -t x -b "field | shown"'

# --- ALLOW (exit 0): ticket / plan link ---
check 0 tool_input "linear link"     'gh pr create -t x -b "closes https://linear.app/trp/issue/RUSH-9"'
check 0 tool_input "plan html link"  'gh pr create -t x -b "plan: /tmp/plan-foo.html"'

# --- ALLOW (exit 0): no-visible-surface / type declaration ---
check 0 tool_input "docs-only"       'gh pr create -t x -b "docs-only: spec the model"'
check 0 tool_input "refactor"        'gh pr create -t x -b "pure refactor, no behavior change"'
check 0 tool_input "test-only"       'gh pr create -t x -b "test-only coverage bump"'

# --- ALLOW (exit 0): body not inspectable / absent ---
check 0 tool_input "body-file"        'gh pr create -t x --body-file /tmp/body.md'
check 0 tool_input "fill"             'gh pr create --fill'
check 0 tool_input "no body (editor)" 'gh pr create -t x'
check 0 tool_input "edit label only"  'gh pr edit 5 --add-label bug'

# --- ALLOW (exit 0): not a gh pr command ---
check 0 tool_input "git commit"       'git commit -m "wip"'
check 0 toolInput  "echo"             'echo "just a real change"'

printf -- '---\npr-description-reminder: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
