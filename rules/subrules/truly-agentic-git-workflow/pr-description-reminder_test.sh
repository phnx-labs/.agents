#!/usr/bin/env bash
# Test for pr-description-reminder.sh (PreToolUse Bash reminder).
#
# Model: RAN-IT-OR-EXEMPT. The reminder NUDGES (exit 2) a `gh pr create|edit`
# whose body shows no proof of a RUN, and ALLOWS (exit 0) a body that carries a
# real run result (screenshot/recording/asset) OR an explicit no-run declaration
# (release / docs / refactor / test-only). Key hardening this test locks in:
#   - a --body-file <path> body is READ and its CONTENT inspected (agents route
#     nearly every real PR body through --body-file; waving it through was the
#     hole that let evidence-free feature PRs land).
#   - a bare ticket / plan LINK is CONTEXT, not run-evidence — it no longer clears
#     the requirement on its own.
#   - a --fill / --template / editor body (not readable here) and a missing/unreadable
#     --body-file still FAIL OPEN (allow) — a reminder must never block a legit PR.
# Exercises both harness payload shapes: Claude snake_case (.tool_input.command)
# and Grok/Codex camelCase (.toolInput.command). Runs the real script over real
# stdin JSON (no mocking); --body-file cases use real on-disk fixtures.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$DIR/pr-description-reminder.sh"
pass=0
fail=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf 'Just a real change with no proof of a run.\n'          > "$TMP/no-evidence.md"
printf 'Ran it, here is the result: ![out](result.png)\n'     > "$TMP/with-image.md"
printf 'Pure refactor, no behavior change.\n'                  > "$TMP/refactor.md"

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

# --- NUDGE (exit 2): inline body with no proof of a run, both shapes ---
check 2 tool_input "snake bare prose"     'gh pr create -t x -b "just a real change"'
check 2 toolInput  "camel bare prose"     'gh pr create -t x -b "just a real change"'
check 2 tool_input "thin pr edit"         'gh pr edit 5 -b "updated the thing"'
check 2 tool_input "prose list no proof"  'gh pr create -t x -b "1. did the thing 2. tested it"'
# A code block or table is NOT proof of a run -> nudge.
check 2 tool_input "code block only"      'gh pr create -t x -b "impl: ```function f(){}```"'
check 2 tool_input "table only"           'gh pr create -t x -b "field | shown"'
# A bare ticket / plan LINK is context, not run-evidence -> nudge (tightened).
check 2 tool_input "linear link only"     'gh pr create -t x -b "closes https://linear.app/trp/issue/RUSH-9"'
check 2 tool_input "plan html link only"  'gh pr create -t x -b "plan: .agents/artifacts/2026-08-05/plan-foo.html"'
# A --body-file body is now READ and inspected -> no evidence in the file -> nudge.
check 2 tool_input "body-file no evidence" "gh pr create -t x --body-file $TMP/no-evidence.md"

# --- ALLOW (exit 0): a real run result (screenshot / recording / asset) ---
check 0 tool_input "markdown image"      'gh pr create -t x -b "![result](shot.png)"'
check 0 tool_input "png path"            'gh pr create -t x -b "ran it, see /tmp/out.png"'
check 0 tool_input "recording file"      'gh pr create -t x -b "flow recording: demo.mp4"'
check 0 toolInput  "gh asset url"        'gh pr create -t x -b "https://github.com/o/r/assets/12/ab.gif"'
check 0 tool_input "body-file image"     "gh pr create -t x --body-file $TMP/with-image.md"

# --- ALLOW (exit 0): explicit no-run declaration (release / docs / refactor / test) ---
check 0 tool_input "release"             'gh pr create -t x -b "release v1.2.3"'
check 0 tool_input "docs-only"           'gh pr create -t x -b "docs-only: spec the model"'
check 0 tool_input "refactor"            'gh pr create -t x -b "pure refactor, no behavior change"'
check 0 tool_input "test-only"           'gh pr create -t x -b "test-only coverage bump"'
check 0 tool_input "body-file refactor"  "gh pr create -t x --body-file $TMP/refactor.md"

# --- ALLOW (exit 0): body not inspectable / absent -> FAIL OPEN ---
check 0 tool_input "body-file missing"   "gh pr create -t x --body-file $TMP/does-not-exist.md"
check 0 tool_input "fill"                'gh pr create --fill'
check 0 tool_input "template"            'gh pr create -t x --template .github/pull_request_template.md'
check 0 tool_input "no body (editor)"    'gh pr create -t x'
check 0 tool_input "edit label only"     'gh pr edit 5 --add-label bug'

# --- ALLOW (exit 0): not a gh pr command ---
check 0 tool_input "git commit"          'git commit -m "wip"'
check 0 toolInput  "echo"                'echo "just a real change"'

printf -- '---\npr-description-reminder: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
