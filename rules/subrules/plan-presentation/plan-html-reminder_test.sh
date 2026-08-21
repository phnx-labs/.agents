#!/bin/sh
# Tests for plan-html-reminder.sh — cross-harness plan presentation check.
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

# Minimal figure-bearing HTML that satisfies the quality check.
write_figure_html() {
  cat > "$1" <<'HTML'
<!doctype html><html><body>
<figure class="artifact-figure"><svg class="artifact-diagram" viewBox="0 0 100 40" role="img" aria-label="t">
  <rect x="10" y="10" width="80" height="20" rx="4" fill="#171717" stroke="#a3e635"/>
</svg></figure>
</body></html>
HTML
  write_source "$1" internal
}

write_source() {
  html=$1; surface=$2
  source=${html%.html}.md
  cat > "$source" <<EOF
---
kind: plan
surface: $surface
---

## Purpose
EOF
}

write_behavior_html() {
  cat > "$1" <<'HTML'
<!doctype html><html><body>
<figure class="artifact-figure artifact-behavior">
  <section data-state="current" data-evidence="capture"><pre>current output</pre></section>
  <section data-evidence="mockup" data-state="proposed"><pre>proposed output</pre></section>
</figure>
</body></html>
HTML
  write_source "$1" cli
}

# 2. ExitPlanMode after a fresh plan HTML WITH a drawn SVG -> ALLOW (exit 0).
write_figure_html "$SCAN/plan-my-feature.html"
run 0 "ExitPlanMode, canonical plan-<slug>.html with SVG figure -> allow" "$EPM"

# 2b. Fresh HTML with NO svg (prose-only shell) -> BLOCK. This is the regression
# that let wall-of-text plans clear the check and open in the browser unreadable.
rm -f "$SCAN"/*.html
printf '%s\n' '<!doctype html><html><body><h1>Prose only</h1><p>no figure</p></body></html>' \
  > "$SCAN/plan-prose-only.html"
write_source "$SCAN/plan-prose-only.html" internal
run 2 "ExitPlanMode, fresh prose-only plan HTML (no svg) -> block" "$EPM"

# 2c. A user-visible plan cannot borrow an unrelated architecture SVG.
rm -f "$SCAN"/*
write_figure_html "$SCAN/plan-cli-architecture.html"
write_source "$SCAN/plan-cli-architecture.html" cli
run 2 "CLI plan, architecture SVG without behavior states -> block" "$EPM"

# 2d. A current capture + proposed faithful mockup satisfies the behavior check.
rm -f "$SCAN"/*
write_behavior_html "$SCAN/plan-cli-behavior.html"
run 0 "CLI plan, current/proposed capture-or-mockup evidence -> allow" "$EPM"

# 2e. Surface is matched case-insensitively — "surface: CLI" passed the
# artifacts-cli validator (which lowercases) but fell through this hook's
# case-sensitive match unchecked.
rm -f "$SCAN"/*
write_behavior_html "$SCAN/plan-upper.html"
sed -i.bak 's/^surface: cli$/surface: CLI/' "$SCAN/plan-upper.md" && rm -f "$SCAN/plan-upper.md.bak"
run 0 "uppercase surface: CLI, behavior evidence -> allow (normalized)" "$EPM"

# 2f. "surface: internal" is not trusted when the plan's own source names UI
# component files — the internal downgrade was the path of least resistance
# around the user-visible mockup requirement.
rm -f "$SCAN"/*
write_figure_html "$SCAN/plan-sneaky.html"
cat > "$SCAN/plan-sneaky.md" <<'EOF'
---
kind: plan
surface: internal
---

## Purpose
Rework the dashboard.

## Proposed Changes
- src/components/Dashboard.tsx — rebuild the layout
EOF
run 2 "internal-declared plan listing .tsx, architecture SVG only -> block" "$EPM"

# 2f-b. A PROSE mention of a .tsx path (an out-of-scope aside) does NOT escalate —
# only list items / table rows (files-changed enumerations) do.
rm -f "$SCAN"/*
write_figure_html "$SCAN/plan-backend.html"
cat > "$SCAN/plan-backend.md" <<'EOF'
---
kind: plan
surface: internal
---

## Purpose
Migrate the queue to Postgres. Out of scope: the dashboard's App.tsx does not change.
EOF
run 0 "internal plan with prose-only .tsx aside, SVG present -> allow" "$EPM"

# 2g. The same UI-touching plan WITH the behavior figure clears.
rm -f "$SCAN"/*
write_behavior_html "$SCAN/plan-sneaky2.html"
cat > "$SCAN/plan-sneaky2.md" <<'EOF'
---
kind: plan
surface: internal
---

## Purpose
Rework the dashboard.

## Proposed Changes
- src/components/Dashboard.tsx — rebuild the layout
EOF
run 0 "internal-declared plan listing .tsx, behavior evidence -> allow" "$EPM"

# 3. ExitPlanMode with the scratchpad <slug>-plan.html convention (nested) -> ALLOW.
rm -f "$SCAN"/*.html
mkdir -p "$SCAN/a/b/scratchpad"
write_figure_html "$SCAN/a/b/scratchpad/remote-run-plan.html"
run 0 "ExitPlanMode, nested <slug>-plan.html with SVG figure -> allow" "$EPM"

# 4. A stale render (>90 min old) does NOT satisfy the check -> block.
rm -rf "$SCAN"/* 2>/dev/null || true
: > "$SCAN/plan-old.html"
touch -d '2 hours ago' "$SCAN/plan-old.html" 2>/dev/null || touch -t 200001010000 "$SCAN/plan-old.html"
run 2 "ExitPlanMode, only a stale plan html -> block" "$EPM"

# 5. A non-ExitPlanMode tool is never checked -> allow, even with an empty root.
rm -f "$SCAN"/*.html 2>/dev/null || true
run 0 "Write tool -> allow (not checked)" '{"tool_name":"Write","tool_input":{"file_path":"/x"}}'

# --- Harness portability: Grok CLI camelCase payloads ---
# Grok sends camelCase `toolName` and names plan-exit `exit_plan_mode`.

# 6. Grok exit_plan_mode with an empty scan root -> BLOCK (the check must still fire).
rm -f "$SCAN"/*.html 2>/dev/null || true
run 2 "Grok exit_plan_mode, no rendered plan -> block" \
  '{"toolName":"exit_plan_mode","toolInput":{"plan":"x"}}'

# 7. Grok exit_plan_mode after a fresh figure-bearing render -> ALLOW.
write_figure_html "$SCAN/plan-grok.html"
run 0 "Grok exit_plan_mode, fresh plan html with SVG -> allow" \
  '{"toolName":"exit_plan_mode","toolInput":{"plan":"x"}}'

# 8. THE BUG: a Grok camelCase NON-plan tool with NO fresh plan HTML must ALLOW.
# The old `-n && != ExitPlanMode` test fell through on an empty resolved name and
# exited 2, blocking EVERY tool call in a Grok session. A reminder must fail OPEN.
rm -f "$SCAN"/*.html 2>/dev/null || true
run 0 "Grok camelCase run_terminal_command, no plan html -> allow (not blocked)" \
  '{"toolName":"run_terminal_command","toolInput":{"command":"npm test"}}'

# --- Stop backstop: Codex plan mode has no ExitPlanMode tool ------------------
CODEX_TX="$SCAN/codex-plan.jsonl"
printf '%s\n' '{"type":"turn_context","payload":{"collaboration_mode":{"mode":"plan"}}}' > "$CODEX_TX"
rm -f "$SCAN"/plan-*.html "$SCAN"/plan-*.md
run 2 "Codex Stop in plan collaboration mode, no render -> block" \
  '{"hook_event_name":"Stop","transcript_path":"'"$CODEX_TX"'","last_assistant_message":"<proposed_plan>plan</proposed_plan>"}'

write_behavior_html "$SCAN/plan-codex.html"
run 0 "Codex Stop in plan collaboration mode, valid behavior render -> allow" \
  '{"hook_event_name":"Stop","transcript_path":"'"$CODEX_TX"'","last_assistant_message":"<proposed_plan>plan</proposed_plan>"}'

rm -f "$SCAN"/plan-*.html "$SCAN"/plan-*.md
printf '%s\n' '{"type":"turn_context","payload":{"collaboration_mode":{"mode":"default"}}}' > "$CODEX_TX"
run 0 "ordinary Codex Stop, no render -> allow" \
  '{"hook_event_name":"Stop","transcript_path":"'"$CODEX_TX"'","last_assistant_message":"A normal answer."}'

run 0 "recursive Stop hook invocation -> allow" \
  '{"hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"<proposed_plan>plan</proposed_plan>"}'

# --- Repo-root artifact path (no PLAN_HTML_SCAN_ROOT override) -----------------
# When the env override is absent, the hook resolves the repo root and scans
# .agents/artifacts/ (dated day dirs: yyyy-mm-dd/<title>.html) under it.

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
# Canonical layout: .agents/artifacts/yyyy-mm-dd/<artifact-title>.html
DATE_DIR="2026-08-05"
mkdir -p "$REPO/.agents/artifacts/$DATE_DIR"

# 14. Fresh figure-bearing HTML under dated artifact path -> ALLOW.
write_figure_html "$REPO/.agents/artifacts/$DATE_DIR/plan-repo-root.html"
run_no_override 0 "ExitPlanMode, fresh .agents/artifacts/yyyy-mm-dd/plan-<slug>.html with SVG -> allow" "$EPM" "$REPO"

# 15. Stale HTML under dated path does NOT satisfy -> BLOCK.
rm -f "$REPO/.agents/artifacts/$DATE_DIR"/*.html
: > "$REPO/.agents/artifacts/$DATE_DIR/plan-stale.html"
touch -d '2 hours ago' "$REPO/.agents/artifacts/$DATE_DIR/plan-stale.html" 2>/dev/null || touch -t 200001010000 "$REPO/.agents/artifacts/$DATE_DIR/plan-stale.html"
run_no_override 2 "ExitPlanMode, stale .agents/artifacts/yyyy-mm-dd HTML -> block" "$EPM" "$REPO"

# 16. Outside a git repo with no override, legacy /tmp fallback still allows
# when the HTML has a drawn SVG figure.
rm -f "$REPO/.agents/artifacts/$DATE_DIR"/*.html
LEGACY="/tmp/plan-legacy-test-$$.html"
write_figure_html "$LEGACY"
# Move into a non-repo temp dir so git rev-parse fails.
OUTSIDE=$(mktemp -d)
run_no_override 0 "ExitPlanMode, legacy /tmp fallback with SVG outside repo -> allow" "$EPM" "$OUTSIDE"
rm -f "$LEGACY"
rm -rf "$OUTSIDE"

# --- Part B: checklist check for multi-step plans -------------------------------
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

# 9. multi-step plan, no checklist, fresh figure-bearing HTML -> BLOCK (checklist missing).
write_figure_html "$SCAN/plan-cl.html"
mkfile_nocl
run 2 "multi-step plan, no checklist -> block" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}'

# 10. multi-step plan, checklist created after the human turn, fresh HTML -> ALLOW.
mkfile_cl
run 0 "multi-step plan, checklist created -> allow" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}'

# 11. trivial plan (no steps), no checklist, fresh HTML -> ALLOW (check skipped).
mkfile_nocl
run 0 "trivial plan -> allow (checklist check skipped)" \
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
