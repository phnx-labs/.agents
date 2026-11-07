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

# write_source <html> <surface> [pass|fail|none]
# Default carries the critic's `review:` block with verdict: pass so figure and
# checklist cases isolate their own gate; the review cases below vary it.
write_source() {
  html=$1; surface=$2; review=${3:-pass}
  source=${html%.html}.md
  {
    echo "---"
    echo "kind: plan"
    echo "surface: $surface"
    case "$review" in
      pass|fail)
        echo "review:"
        echo "  agent: artifact-critic"
        echo "  session: 00000000-0000-0000-0000-000000000000"
        echo "  verdict: $review"
        ;;
      forged)
        # A hand-written pass with no critic session behind it.
        echo "review:"
        echo "  verdict: pass"
        ;;
      empty-session)
        echo "review:"
        echo "  agent: artifact-critic"
        echo "  session:"
        echo "  verdict: pass"
        ;;
      decoupled)
        # verdict under review:, session and agent parked under another key.
        echo "review:"
        echo "  verdict: pass"
        echo "  notes: none"
        echo "session_holder:"
        echo "  agent: fake-critic"
        echo "  session: totally-made-up-123"
        ;;
      shadowed)
        # session and agent above review:, verdict inside it.
        echo "agent: artifact-critic"
        echo "session: 00000000-0000-0000-0000-000000000000"
        echo "review:"
        echo "  verdict: pass"
        ;;
    esac
    echo "---"
    echo
    echo "## Purpose"
  } > "$source"
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
review:
  agent: artifact-critic
  session: 00000000-0000-0000-0000-000000000000
  verdict: pass
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
review:
  agent: artifact-critic
  session: 00000000-0000-0000-0000-000000000000
  verdict: pass
surface: internal
---

## Purpose
Rework the dashboard.

## Proposed Changes
- src/components/Dashboard.tsx — rebuild the layout
EOF
run 0 "internal-declared plan listing .tsx, behavior evidence -> allow" "$EPM"

# --- Part C: the critic's verdict gates presentation ---------------------------
# A rendered figure is necessary, not sufficient: a plan is presented only after
# the non-author artifact-critic wrote `review:` with `verdict: pass` into the
# source frontmatter. Missing block and a failing verdict both block; the block
# message names artifact-critic as the fix.

# 2h. Fresh figure-bearing HTML, source has NO review block -> BLOCK.
rm -f "$SCAN"/*.html "$SCAN"/*.md 2>/dev/null || true
write_figure_html "$SCAN/plan-no-review.html"
write_source "$SCAN/plan-no-review.html" internal none
run 2 "figure ok but no critic review block -> block" "$EPM"
msg=$(printf '%s' "$EPM" | sh "$HOOK" 2>&1 >/dev/null || true)
if printf '%s' "$msg" | grep -q 'artifact-critic'; then
  pass=$((pass+1)); echo "ok   — missing review names artifact-critic as the fix"
else
  fail=$((fail+1)); echo "FAIL — missing review message does not name artifact-critic"
fi

# 2i. Same render, verdict: fail -> BLOCK.
write_source "$SCAN/plan-no-review.html" internal fail
run 2 "critic verdict: fail -> block" "$EPM"

# 2j. Same render, verdict: pass -> ALLOW.
write_source "$SCAN/plan-no-review.html" internal pass
run 0 "critic verdict: pass -> allow" "$EPM"
# 2h-iii. Forged pass: `review:` with verdict: pass but no session/agent -> BLOCK.
# This is the self-approval bypass; green tests must prove it stays closed.
write_source "$SCAN/plan-no-review.html" internal forged
run 2 "hand-written verdict: pass with no critic session -> block" "$EPM"
write_source "$SCAN/plan-no-review.html" internal empty-session
run 2 "verdict: pass with an empty session field -> block" "$EPM"
write_source "$SCAN/plan-no-review.html" internal decoupled
run 2 "session and agent outside the review block -> block" "$EPM"
write_source "$SCAN/plan-no-review.html" internal shadowed
run 2 "top-level session and agent with a nested verdict -> block" "$EPM"

# 2k. A user-visible plan is gated the same way.
rm -f "$SCAN"/*.html "$SCAN"/*.md 2>/dev/null || true
write_behavior_html "$SCAN/plan-cli-review.html"
write_source "$SCAN/plan-cli-review.html" cli none
run 2 "user-visible plan without critic review -> block" "$EPM"
write_source "$SCAN/plan-cli-review.html" cli pass
run 0 "user-visible plan with critic pass -> allow" "$EPM"
rm -f "$SCAN"/*.html "$SCAN"/*.md 2>/dev/null || true

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

# --- permission_mode gating moved to the shim layer ----------------------------
# hooks.yaml declares matches.permission_mode: plan on the Stop entry; the
# agents-cli generated shim (>= 1.22.47) skips this script for an explicit
# non-plan mode and passes mode-less input through (fail-open — Codex/Grok keep
# the marker backstop). The skip/pass semantics are pinned by the conformance
# suite in agents-cli (src/lib/hooks/cache-matches.test.ts); this script no
# longer reads permission_mode, so a mode-carrying plan turn behaves like any
# plan turn.
rm -f "$SCAN"/plan-*.html "$SCAN"/plan-*.md
printf '%s\n' '{"type":"turn_context","payload":{"collaboration_mode":{"mode":"plan"}}}' > "$CODEX_TX"
run 2 "Stop with permission_mode=plan + plan markers, no render -> block" \
  '{"hook_event_name":"Stop","permission_mode":"plan","transcript_path":"'"$CODEX_TX"'","last_assistant_message":"<proposed_plan>plan</proposed_plan>"}'

# --- Repo-root artifact path (no PLAN_HTML_SCAN_ROOT override) -----------------
# When the env override is absent, the hook resolves the repo root and scans
# .agents/artifacts/ (dated day dirs: yyyy-mm-dd/<title>.html) under it.

run_no_override() {
  want=$1; label=$2; json=$3; cwd=$4
  got=0
  (
    unset PLAN_HTML_SCAN_ROOT
    # Isolate HOME so a fresh ~/.agents/artifacts plan from the host session
    # cannot satisfy an in-repo stale-HTML assertion. Durable-home coverage
    # lives in run_home below, which sets its own FAKE_HOME.
    HOME="$SCAN/fake-home"
    mkdir -p "$HOME"
    export HOME
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
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"browser show ~/.agents/artifacts/2026-11-07/x/plan.html --json"}}]}}'
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b1","content":"{\"via\": \"arc\", \"profile\": \"arc-work\"}"}]}}'
  } > "$TX"
}
mkfile_cl() {    # human turn, then a TaskCreate tool_use, then its tool_result(user)
  {
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"do a big multi-step task"}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"TaskCreate","input":{"subject":"A1","description":"d"}}]}}'
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"created 1"}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"browser show ~/.agents/artifacts/2026-11-07/x/plan.html --json"}}]}}'
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b1","content":"{\"via\": \"arc\", \"profile\": \"arc-work\"}"}]}}'
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

# --- Part C: the plan was opened for the owner ----------------------------------
mkfile_unopened() {  # checklist made, plan never opened, owner asked earlier
  {
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"plan it"}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"TaskCreate","input":{"subject":"A1","description":"d"}}]}}'
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"created 1"}]}}'
  } > "$TX"
}
write_figure_html "$SCAN/plan-open.html"

# 22. Rendered, reviewed, checklist made, never opened -> BLOCK.
mkfile_unopened
run 2 "plan never opened for the owner -> block" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}'

# 23. A browser show from an EARLIER turn does not count for this one.
{
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"first ask"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b0","name":"Bash","input":{"command":"browser show old.html"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b0","content":"{\"via\": \"arc\", \"profile\": \"arc-work\"}"}]}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"now plan it"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"TaskCreate","input":{"subject":"A1","description":"d"}}]}}'
} > "$TX"
run 2 "browser show in an earlier turn -> block" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}'

# 24. Opened this turn -> ALLOW.
mkfile_cl
run 0 "plan opened with browser show this turn -> allow" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}'

# 25. Codex rollout: opened through a function_call after the user message -> ALLOW.
{
  printf '%s\n' '{"type":"event_msg","payload":{"type":"user_message","message":"plan it"}}'
  printf '%s\n' '{"type":"response_item","payload":{"type":"function_call","call_id":"c1","name":"exec_command","arguments":"{\"cmd\":\"browser show plan.html\"}"}}'
  printf '%s\n' '{"type":"response_item","payload":{"type":"function_call_output","call_id":"c1","output":"{\"via\": \"arc\"}"}}'
} > "$TX"
run 0 "codex function_call browser show -> allow" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"},"transcript_path":"'"$TX"'"}'
# 26. Records the harness injects after the open are not the owner's prompt:
# a task notification, a compaction summary, a ! command, an interrupt.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"plan it"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"browser show plan.html --json"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b1","content":"{\"via\": \"arc\", \"profile\": \"arc-work\"}"}]}}'
  printf '%s\n' '{"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>done</task-notification>"}}'
  printf '%s\n' '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued from a previous conversation"}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"<bash-input>git status</bash-input>"}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}'
} > "$TX"
run 0 "injected user records after the open do not reset the turn -> allow" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"},"transcript_path":"'"$TX"'"}'

# 27. Codex injects context as a role-user response_item; only event_msg user_message is the owner.
{
  printf '%s\n' '{"type":"event_msg","payload":{"type":"user_message","message":"plan it"}}'
  printf '%s\n' '{"type":"response_item","payload":{"type":"function_call","call_id":"c1","name":"exec_command","arguments":"{\"cmd\":\"browser show plan.html\"}"}}'
  printf '%s\n' '{"type":"response_item","payload":{"type":"function_call_output","call_id":"c1","output":"{\"via\": \"arc\"}"}}'
  printf '%s\n' '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>cwd</environment_context>"}]}}'
} > "$TX"
run 0 "codex injected context after the open -> allow" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"x"},"transcript_path":"'"$TX"'"}'
rm -f "$SCAN"/plan-open.html "$SCAN"/plan-open.md

# --- Page check: every turn that wrote or named a page, in any mode -------------
STOP_AUTO() { printf '{"hook_event_name":"Stop","permission_mode":"auto","transcript_path":"%s"%s}' "$TX" "${1:-}"; }

# 28. Auto mode: the turn wrote a page and never opened it -> BLOCK.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"make the report"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w","name":"Write","input":{"file_path":"/home/u/.agents/artifacts/2026-11-07/report/index.html","content":"x"}}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Done."}]}}'
} > "$TX"
run 2 "auto mode, page written, not opened -> block" "$(STOP_AUTO)"

# 29. Same turn, opened with browser show -> ALLOW.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"s","name":"Bash","input":{"command":"browser show /home/u/.agents/artifacts/2026-11-07/report/index.html --json"}}]}}' >> "$TX"
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"s","content":"{\"via\": \"arc\", \"profile\": \"arc-work\"}"}]}}' >> "$TX"
run 0 "auto mode, page written and opened -> allow" "$(STOP_AUTO)"

# 30. The final reply names an artifact folder an earlier turn wrote (the ChemStation
# case) -> BLOCK. The folder must exist, so this runs against a fake home.
PAGE_HOME=$(mktemp -d)
mkdir -p "$PAGE_HOME/.local/share/agents/artifacts/2026-11-07/chromatography-agent"
run_page_home() {
  want=$1; label=$2; json=$3; got=0
  printf '%s' "$json" | HOME="$PAGE_HOME" sh "$HOOK" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then pass=$((pass+1)); echo "ok   — $label (rc=$got)"
  else fail=$((fail+1)); echo "FAIL — $label (want rc=$want, got rc=$got)"; fi
}
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"Is it done? Where are the results?"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Results are in ~/.local/share/agents/artifacts/2026-11-07/chromatography-agent/: index.html is the walkthrough."}]}}'
} > "$TX"
run_page_home 2 "final reply names an artifact it never opened -> block" "$(STOP_AUTO)"

# 31. The block fires once: the retry with stop_hook_active passes.
run_page_home 0 "page check blocks once (stop_hook_active) -> allow" "$(STOP_AUTO ',"stop_hook_active":true')"

# 31b. A named artifact that does not exist is a passing mention -> ALLOW.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"where did that go"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"It was under ~/.agents/artifacts/1999-01-01/never-made/ before it was removed."}]}}'
} > "$TX"
run 0 "reply names an artifact that does not exist -> allow" "$(STOP_AUTO)"

# 31c. Reading an artifact writes nothing: Read, sed and grep -> ALLOW (review on #549).
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"what did the brief say"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"r","name":"Read","input":{"file_path":"/home/u/.agents/artifacts/2026-11-07/demo/brief.md"}}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b","name":"Bash","input":{"command":"sed -n 1,140p ~/.agents/artifacts/2026-11-07/demo/brief.md; grep -n hero ~/.local/share/agents/artifacts/2026-11-07/x/src.html"}}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"The brief asks for two headlines."}]}}'
} > "$TX"
run 0 "turn that only reads artifacts -> allow" "$(STOP_AUTO)"

# 31d. An in-repo .agents/artifacts path is a repository file, not a page for the owner -> ALLOW.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"update the readme"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w","name":"Write","input":{"file_path":".agents/artifacts/README.md","content":"x"}}]}}'
} > "$TX"
run 0 "in-repo .agents/artifacts write -> allow" "$(STOP_AUTO)"

# 31f. Opened straight in Arc with AppleScript instead of browser show -> ALLOW.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"show me"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w","name":"Write","input":{"file_path":"/home/u/.agents/artifacts/2026-11-07/r/index.html","content":"x"}}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"o","name":"Bash","input":{"command":"agents ssh zion \"osascript -e '"'"'tell application \\\"Arc\\\"'"'"' -e '"'"'tell front window to make new tab with properties {URL:\\\"file:///x\\\"}'"'"'\""}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"o","content":"{\"via\": \"arc\", \"profile\": \"arc-work\"}"}]}}'
} > "$TX"
run 0 "page opened directly in Arc with AppleScript -> allow" "$(STOP_AUTO)"

# 31g. browser show reported it did not open ("via": "none") -> BLOCK, even though it ran.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"show me"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w","name":"Write","input":{"file_path":"/home/u/.agents/artifacts/2026-11-07/r/index.html","content":"x"}}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"f","name":"Bash","input":{"command":"browser show /home/u/.agents/artifacts/2026-11-07/r/index.html --json"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"f","content":"{\"via\": \"none\", \"profile\": \"arc-work\", \"reason\": \"No visible Arc window shows a Space of Arc profile Work.\"}"}]}}'
} > "$TX"
run 2 "browser show that reported via none -> block" "$(STOP_AUTO)"

# 31h. The failed open followed by a confirmed fallback -> ALLOW.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"g","name":"Bash","input":{"command":"browser show /home/u/.agents/artifacts/2026-11-07/r/index.html --os-browser --json"}}]}}' >> "$TX"
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"g","content":"{\"via\": \"open\"}"}]}}' >> "$TX"
run 0 "failed open then confirmed fallback -> allow" "$(STOP_AUTO)"

# 31i. An open the permission check denied never opened anything -> BLOCK.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"show me"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w","name":"Write","input":{"file_path":"/home/u/.agents/artifacts/2026-11-07/r/index.html","content":"x"}}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"d","name":"Bash","input":{"command":"browser show /home/u/.agents/artifacts/2026-11-07/r/index.html"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"d","is_error":true,"content":"Permission for this action was denied by the Claude Code auto mode classifier."}]}}'
} > "$TX"
run 2 "denied open -> block" "$(STOP_AUTO)"

# 31e. artifacts render of a home page, not opened -> BLOCK.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"render it"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b","name":"Bash","input":{"command":"artifacts render ~/.agents/artifacts/2026-11-07/p/plan.md"}}]}}'
} > "$TX"
run 2 "artifacts render without opening -> block" "$(STOP_AUTO)"

# 32. A turn that touched no page -> ALLOW.
{
  printf '%s\n' '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"fix the test"}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"e","name":"Edit","input":{"file_path":"/repo/src/a.ts"}}]}}'
} > "$TX"
run 0 "turn with no page -> allow" "$(STOP_AUTO)"

# 33. No transcript -> ALLOW (fails open).
run 0 "no transcript -> allow" '{"hook_event_name":"Stop","permission_mode":"auto"}'
mkfile_cl  # later cases expect a turn that opened its plan

# --- Durable home is the canonical artifact root -------------------------------
# Artifacts moved OUT of the repo: a checkout is tracked (stray files collide on
# merge) and is a primary working tree (main-branch-guard denies the write). The
# hook must accept ~/.agents/artifacts/ so plan mode is not blocked by the move,
# while still accepting an in-repo plan committed with its feature.

FAKE_HOME=$(mktemp -d)
HOME_DATE_DIR="$FAKE_HOME/.agents/artifacts/2026-08-27/durable-slug"
mkdir -p "$HOME_DATE_DIR"

run_home() {
  want=$1; label=$2; json=$3; cwd=$4
  got=0
  (
    unset PLAN_HTML_SCAN_ROOT
    HOME=$FAKE_HOME
    export HOME
    cd "$cwd"
    printf '%s' "$json" | sh "$HOOK" >/dev/null 2>&1 || exit $?
  ) || got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); echo "ok   — $label (rc=$got)"
  else
    fail=$((fail+1)); echo "FAIL — $label (want rc=$want, got rc=$got)"
  fi
}

# 20. Fresh figure-bearing HTML in the DURABLE HOME -> ALLOW, from a non-repo cwd.
write_figure_html "$HOME_DATE_DIR/plan.html"
NON_REPO=$(mktemp -d)
run_home 0 "durable home artifact satisfies the render check" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}' \
  "$NON_REPO"

# 21. Nothing anywhere -> still BLOCK. The new root must not become a blanket pass.
rm -f "$HOME_DATE_DIR"/*.html "$HOME_DATE_DIR"/*.md 2>/dev/null || true
run_home 2 "empty durable home still blocks" \
  '{"tool_name":"ExitPlanMode","tool_input":{"plan":"'"$MULTI"'"},"transcript_path":"'"$TX"'"}' \
  "$NON_REPO"

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
