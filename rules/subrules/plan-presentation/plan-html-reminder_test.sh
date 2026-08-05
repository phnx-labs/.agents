#!/bin/sh
# Tests for plan-html-reminder.sh — the ExitPlanMode plan-render gate.
# Run: sh plan-html-reminder_test.sh   (no mocks; drives the real hook via stdin)
set -eu

DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
HOOK="$DIR/plan-html-reminder.sh"
SCAN=$(mktemp -d)
REPO=""
trap 'rm -rf "$SCAN" "$REPO"' EXIT
export PLAN_HTML_SCAN_ROOT="$SCAN"

pass=0; fail=0
# run <expected-rc> <label> <json>
run() {
  want=$1; label=$2; json=$3
  got=0
  printf '%s' "$json" | sh "$HOOK" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); echo "ok   — $label (rc=$got)"
  else
    fail=$((fail+1)); echo "FAIL — $label (want rc=$want, got rc=$got)"
  fi
}

EPM='{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"}}'

# 1. ExitPlanMode with an empty scan root -> BLOCK (exit 2).
rm -f "$SCAN"/*.html 2>/dev/null || true
run 2 "ExitPlanMode, no rendered plan -> block" "$EPM"

# 2. ExitPlanMode after a fresh /tmp/plan-<slug>.html -> ALLOW (exit 0).
: > "$SCAN/plan-my-feature.html"
run 0 "ExitPlanMode, canonical plan-<slug>.html present -> allow" "$EPM"

# 3. ExitPlanMode with the scratchpad <slug>-plan.html convention (nested) -> ALLOW.
rm -f "$SCAN"/*.html
mkdir -p "$SCAN/a/b/scratchpad"
: > "$SCAN/a/b/scratchpad/remote-run-plan.html"
run 0 "ExitPlanMode, nested <slug>-plan.html present -> allow" "$EPM"

# 4. A stale render (>90 min old) does NOT satisfy the gate -> block.
rm -rf "$SCAN"/* 2>/dev/null || true
: > "$SCAN/plan-old.html"
touch -d '2 hours ago' "$SCAN/plan-old.html" 2>/dev/null || touch -t 200001010000 "$SCAN/plan-old.html"
run 2 "ExitPlanMode, only a stale plan html -> block" "$EPM"

# 5. A non-ExitPlanMode tool is never gated -> allow, even with an empty root.
rm -f "$SCAN"/*.html 2>/dev/null || true
run 0 "Write tool -> allow (not gated)" '{"tool_name":"Write","tool_input":{"file_path":"/x"}}'

# --- Harness portability: Grok CLI camelCase payloads ---
# Grok sends camelCase `toolName` and names plan-exit `exit_plan_mode`.

# 6. Grok exit_plan_mode with an empty scan root -> BLOCK (the gate must still fire).
rm -f "$SCAN"/*.html 2>/dev/null || true
run 2 "Grok exit_plan_mode, no rendered plan -> block" \
  '{"toolName":"exit_plan_mode","toolInput":{"plan":"x"}}'

# 7. Grok exit_plan_mode after a fresh render -> ALLOW.
: > "$SCAN/plan-grok.html"
run 0 "Grok exit_plan_mode, fresh plan html -> allow" \
  '{"toolName":"exit_plan_mode","toolInput":{"plan":"x"}}'

# 8. THE BUG: a Grok camelCase NON-plan tool with NO fresh plan HTML must ALLOW.
# The old `-n && != ExitPlanMode` test fell through on an empty resolved name and
# exited 2, blocking EVERY tool call in a Grok session. A reminder must fail OPEN.
rm -f "$SCAN"/*.html 2>/dev/null || true
run 0 "Grok camelCase run_terminal_command, no plan html -> allow (not blocked)" \
  '{"toolName":"run_terminal_command","toolInput":{"command":"npm test"}}'

# --- Repo-root artifact path (no PLAN_HTML_SCAN_ROOT override) -----------------
# When the env override is absent, the hook resolves the repo root and scans
# .agents/artifacts/plans/ under it.

run_no_override() {
  want=$1; label=$2; json=$3; cwd=$4
  got=0
  (
    unset PLAN_HTML_SCAN_ROOT
    cd "$cwd"
    printf '%s' "$json" | sh "$HOOK" >/dev/null 2>&1 || exit $?
  ) || got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); echo "ok   — $label (rc=$got)"
  else
    fail=$((fail+1)); echo "FAIL — $label (want rc=$want, got rc=$got)"
  fi
}

REPO=$(mktemp -d)
git -C "$REPO" init -q 2>/dev/null || true
mkdir -p "$REPO/.agents/artifacts/plans"

# 14. Fresh HTML under repo-root .agents/artifacts/plans/ -> ALLOW.
: > "$REPO/.agents/artifacts/plans/plan-repo-root.html"
run_no_override 0 "ExitPlanMode, fresh .agents/artifacts/plans/plan-<slug>.html -> allow" "$EPM" "$REPO"

# 15. Stale HTML under repo root does NOT satisfy -> BLOCK.
rm -f "$REPO/.agents/artifacts/plans"/*.html
: > "$REPO/.agents/artifacts/plans/plan-stale.html"
touch -d '2 hours ago' "$REPO/.agents/artifacts/plans/plan-stale.html" 2>/dev/null || touch -t 200001010000 "$REPO/.agents/artifacts/plans/plan-stale.html"
run_no_override 2 "ExitPlanMode, stale .agents/artifacts/plans HTML -> block" "$EPM" "$REPO"

# 16. Outside a git repo with no override, legacy /tmp fallback still allows.
rm -f "$REPO/.agents/artifacts/plans"/*.html
LEGACY="/tmp/plan-legacy-test-$$.html"
: > "$LEGACY"
# Move into a non-repo temp dir so git rev-parse fails.
OUTSIDE=$(mktemp -d)
run_no_override 0 "ExitPlanMode, legacy /tmp fallback outside repo -> allow" "$EPM" "$OUTSIDE"
rm -f "$LEGACY"
rm -rf "$OUTSIDE"

# --- Part B: checklist gate for multi-step plans -------------------------------
# These need a fresh HTML present so part A always passes and we isolate part B.
TX="$SCAN/transcript.jsonl"
mkfile_nocl() {  # human turn, no checklist tool
  {
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"do a big multi-step task"}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"planning"}]}}'
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}'
  } > "$TX"
}
mkfile_cl() {    # human turn, then a TaskCreate tool_use, then its tool_result(user)
  {
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"do a big multi-step task"}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"TaskCreate","input":{"subject":"A1","description":"d"}}]}}'
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"created 1"}]}}'
  } > "$TX"
}
MULTI='1. first step\n2. second step\n3. third step'

# 9. multi-step plan, no checklist, fresh HTML -> BLOCK (checklist missing).
: > "$SCAN/plan-cl.html"
mkfile_nocl
run 2 "multi-step plan, no checklist -> block" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}'

# 10. multi-step plan, checklist created after the human turn, fresh HTML -> ALLOW.
mkfile_cl
run 0 "multi-step plan, checklist created -> allow" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}'

# 11. trivial plan (no steps), no checklist, fresh HTML -> ALLOW (gate skipped).
mkfile_nocl
run 0 "trivial plan -> allow (checklist gate skipped)" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"},"transcript_path":"'"$TX"'"}'

# 12. multi-step plan, NO transcript_path -> ALLOW (fail open).
run 0 "multi-step plan, no transcript -> allow (fail open)" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"}}'

# 13. multi-step plan WITH checklist but NO fresh HTML -> BLOCK (html missing).
rm -f "$SCAN"/*.html 2>/dev/null || true
mkfile_cl
run 2 "multi-step plan, checklist ok but no HTML -> block" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}'

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
