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

# git stub for the declaration-vs-diff cross-check: FAKE_PRD_FILES drives the
# changed-file list so the check is judged against a controlled diff, not this
# repo's real branch. Cases opt in via PATH="$TMP/bin:$PATH".
mkdir -p "$TMP/bin"
cat > "$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "symbolic-ref --short refs/remotes/origin/HEAD") echo "origin/main" ;;
  "diff --name-only "*)                            printf '%s\n' "${FAKE_PRD_FILES:-}" ;;
  *)                                               echo "" ;;
esac
STUB
chmod +x "$TMP/bin/git"
printf 'Just a real change with no proof of a run.\n'          > "$TMP/no-evidence.md"
printf 'Ran it: ![out](https://share.example.com/u/run-shot)\n' > "$TMP/with-image.md"
printf 'Pure refactor, no behavior change.\n'                  > "$TMP/refactor.md"
printf 'A real feature change.\n\n\n\n\n\n\n\n\n\n\nBTW this touches the refactor helper.\n' > "$TMP/deep-declaration.md"
mkdir -p "$TMP/dir with space"
printf 'Just a real change, no proof.\n'                       > "$TMP/dir with space/body.md"

plan_json=$(printf '%s' 'gh pr create -t x -b "no run evidence"' | jq -Rs '{permissionMode:"plan",toolInput:{command:.}}')
printf '%s' "$plan_json" | "$HOOK" >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL: explicit camelCase plan mode should skip the reminder\n'
fi

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
# Cover every flag form the hook branches on: `--body-file <p>`, `--body-file=<p>`,
# `-F <p>`, `-F=<p>`, and a path followed by a further flag.
check 2 tool_input "body-file no evidence"    "gh pr create -t x --body-file $TMP/no-evidence.md"
check 2 tool_input "body-file= equals form"   "gh pr create -t x --body-file=$TMP/no-evidence.md"
check 2 tool_input "-F space form"            "gh pr create -t x -F $TMP/no-evidence.md"
check 2 tool_input "-F= equals form"          "gh pr create -t x -F=$TMP/no-evidence.md"
check 2 tool_input "body-file then flag"      "gh pr create -t x --body-file $TMP/no-evidence.md --draft"

# --- ALLOW (exit 0): a real run result a reviewer can OPEN (remote URL) ---
check 0 tool_input "remote embed"        'gh pr create -t x -b "![result](https://share.example.com/u/run-shot)"'
check 0 tool_input "remote media url"    'gh pr create -t x -b "recording: https://cdn.example.com/demo.mp4"'
check 0 toolInput  "gh asset url"        'gh pr create -t x -b "https://github.com/o/r/assets/12/ab.gif"'
check 0 tool_input "user-attachments"    'gh pr create -t x -b "https://github.com/user-attachments/assets/ab12"'
check 0 tool_input "share host url"      'gh pr create -t x -b "run output: https://share.agents-cli.sh/u/design-run-1"'
check 0 tool_input "body-file image"     "gh pr create -t x --body-file $TMP/with-image.md"

# --- NUDGE (exit 2): things that LOOK like evidence but nobody on GitHub can open ---
# (2026-08-17: PR #317 cleared the old substring check with a fleet-local
# "zion:/tmp/gate-recording-run.txt.png"; a local ![](result.png) embed and a bare
# "demo.mp4" filename cleared it the same way.)
check 2 tool_input "local png path"      'gh pr create -t x -b "ran it, see zion:/tmp/out.png"'
check 2 tool_input "local embed"         'gh pr create -t x -b "![result](shot.png)"'
check 2 tool_input "bare recording name" 'gh pr create -t x -b "flow recording: demo.mp4"'
check 2 tool_input "gist link only"      'gh pr create -t x -b "log: https://gist.github.com/u/abc123"'

# --- ALLOW (exit 0): explicit no-run declaration (release / docs / refactor / test) ---
# Checkable declarations (test-only / docs-only) are verified against the branch
# diff via the git stub; TRUE declarations still clear.
check 0 tool_input "release"             'gh pr create -t x -b "release v1.2.3"'
PATH="$TMP/bin:$PATH" FAKE_PRD_FILES=$'docs/spec.md\nREADME.md' \
  check 0 tool_input "docs-only (diff matches)"  'gh pr create -t x -b "docs-only: spec the model"'
check 0 tool_input "refactor"            'gh pr create -t x -b "pure refactor, no behavior change"'
PATH="$TMP/bin:$PATH" FAKE_PRD_FILES=$'src/widget.test.ts\ntests/e2e_test.sh' \
  check 0 tool_input "test-only (diff matches)"  'gh pr create -t x -b "test-only coverage bump"'
check 0 tool_input "body-file refactor"  "gh pr create -t x --body-file $TMP/refactor.md"
# Declarations only count in the LEAD (title + first 8 body lines) — the word
# "refactor" buried on line 12 of a feature PR is not a declaration.
check 2 tool_input "deep declaration does not clear" "gh pr create -t x --body-file $TMP/deep-declaration.md"
# ...but a declaration in the TITLE does (the "lead with what + type" convention),
# through every flag form gh accepts: --title "...", -t "...", and a bare token.
check 0 tool_input "title declaration clears" "gh pr create --title \"refactor: flatten the loop\" --body-file $TMP/no-evidence.md"
check 0 tool_input "-t short-flag declaration clears" "gh pr create -t \"release v2.0.0\" --body-file $TMP/no-evidence.md"
check 0 tool_input "bare-token title declaration clears" "gh pr create --title=refactor-pass --body-file $TMP/no-evidence.md"
# A non-declaration -t placeholder must NOT clear (x is not a magic word).
check 2 tool_input "-t placeholder does not clear" "gh pr create -t x --body-file $TMP/no-evidence.md"

# --- NUDGE (exit 2): declaration CONTRADICTED by the diff (the PR #2736 gaming) ---
PATH="$TMP/bin:$PATH" FAKE_PRD_FILES=$'apps/cli/src/lib/browser/identity.ts\napps/cli/src/lib/browser/identity.test.ts' \
  check 2 tool_input "test-only contradicted by src files blocks" \
  'gh pr create -t x -b "test-only. Identity-based browser task resolution."'
PATH="$TMP/bin:$PATH" FAKE_PRD_FILES=$'src/server.py' \
  check 2 tool_input "docs-only contradicted by code blocks" \
  'gh pr create -t x -b "docs-only cleanup"'
# Diff unreadable (stubbed git returns nothing) -> fail open.
PATH="$TMP/bin:$PATH" FAKE_PRD_FILES='' \
  check 0 tool_input "test-only with unreadable diff fails open" \
  'gh pr create -t x -b "test-only coverage bump"'

# --- ALLOW (exit 0): body not inspectable / absent -> FAIL OPEN ---
check 0 tool_input "body-file missing"   "gh pr create -t x --body-file $TMP/does-not-exist.md"
# A --body-file path CONTAINING A SPACE cannot be extracted from the command string
# (the token splitter stops at the first space), so it FAILS OPEN. Documented, safe
# (never over-blocks); agent-generated temp paths do not contain spaces.
check 0 tool_input "body-file spaced path" "gh pr create -t x --body-file \"$TMP/dir with space/body.md\""
check 0 tool_input "fill"                'gh pr create --fill'
check 0 tool_input "template"            'gh pr create -t x --template .github/pull_request_template.md'
check 0 tool_input "no body (editor)"    'gh pr create -t x'
check 0 tool_input "edit label only"     'gh pr edit 5 --add-label bug'

# --- ALLOW (exit 0): not a gh pr command ---
check 0 tool_input "git commit"          'git commit -m "wip"'
check 0 toolInput  "echo"                'echo "just a real change"'

printf -- '---\npr-description-reminder: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
