#!/bin/sh
# plan-html-reminder — plan presentation gate at plan-exit and Stop.
#
# Enforces the plan-presentation rule: a plan must be RENDERED as a self-contained
# HTML doc (plan-render skill) before it is presented, so the user reviews it in the
# browser — skinned in the product's brand, light/dark, and inspected headlessly.
#
# The source of truth is Markdown under the repo's dated artifact layout:
#   `.agents/artifacts/yyyy-mm-dd/<artifact-title>.md`
# (plans: `.../plan-<slug>.md`). `artifacts render ...` produces the
# HTML next to the source. The gate detects a fresh rendered plan HTML under
# `.agents/artifacts/`.
#
# Mechanism: harnesses with a plan-exit tool are checked before that tool runs.
# Harnesses such as Codex, whose plan mode is collaboration state rather than a
# tool call, are checked at Stop after the script proves the current turn is a
# plan turn from the final message or transcript. Non-plan Stop events fail open.
#
# The gate is on the RENDER (a file we can detect). Opening on the Mac and theming are
# driven by the always-on rule text — a headless fleet still renders the file (allowed)
# even when it cannot open a browser.
#
# Exits 0 (allow) or 2 (block, message on stderr). Only gates the AGENT's tool call;
# the user's own actions are unaffected.

set -eu

input=$(cat)

# Prove this is a plan presentation before gating. PreToolUse supplies a plan-exit
# tool name. Stop has no matcher, so inspect the final response and the latest
# collaboration mode recorded in the transcript. This keeps ordinary answers out
# of the gate while covering Codex, which never emits ExitPlanMode.
tool=$(printf '%s' "$input" | jq -r '(.tool_name // .toolName) // empty' 2>/dev/null) || tool=""
event=$(printf '%s' "$input" | jq -r '(.hook_event_name // .hookEventName) // empty' 2>/dev/null) || event=""
tp=$(printf '%s' "$input" | jq -r '(.transcript_path // .transcriptPath) // empty' 2>/dev/null) || tp=""
last_message=$(printf '%s' "$input" | jq -r '(.last_assistant_message // .lastAssistantMessage) // empty' 2>/dev/null) || last_message=""

is_plan=0
case "$tool" in
  ExitPlanMode|exit_plan_mode|exitPlanMode) is_plan=1 ;;
esac

if [ "$is_plan" = 0 ] && { [ "$event" = "Stop" ] || [ "$event" = "stop" ]; }; then
  stop_active=$(printf '%s' "$input" | jq -r '(.stop_hook_active // .stopHookActive) // false' 2>/dev/null) || stop_active=false
  [ "$stop_active" = "true" ] && exit 0
  plan_signal=$(PLAN_LAST_MESSAGE="$last_message" python3 - "$tp" <<'PY' 2>/dev/null || true
import json, os, sys

message = os.environ.get("PLAN_LAST_MESSAGE", "")
if "<proposed_plan>" in message or "<!-- agents-plan -->" in message:
    print("plan")
    raise SystemExit

path = sys.argv[1] if len(sys.argv) > 1 else ""
latest_mode = ""
if path:
    try:
        with open(path, encoding="utf-8") as handle:
            for raw in handle:
                try:
                    record = json.loads(raw)
                except Exception:
                    continue
                stack = [record]
                while stack:
                    value = stack.pop()
                    if isinstance(value, dict):
                        mode = value.get("collaboration_mode")
                        if isinstance(mode, dict) and isinstance(mode.get("mode"), str):
                            latest_mode = mode["mode"]
                        stack.extend(value.values())
                    elif isinstance(value, list):
                        stack.extend(value)
    except Exception:
        pass
if latest_mode == "plan":
    print("plan")
PY
)
  [ "$plan_signal" = "plan" ] && is_plan=1
fi

[ "$is_plan" = 1 ] || exit 0

# The gate has TWO parts, both checked before we allow the plan to be presented:
#   (A) a fresh plan HTML was rendered (browser-reviewable), and
#   (B) for a MULTI-STEP plan, a task checklist was created (the acceptance rubric
#       that then shows in `agents sessions` and drives the watchdog/feed).
# Either missing -> block ONCE with a message naming what's missing. Both self-
# terminating: the agent renders the HTML / creates the checklist and re-calls
# ExitPlanMode, which now passes.

# ---- (A) HTML render check ----------------------------------------------------
# A fresh plan HTML rendered in the last 90 min satisfies this. The canonical
# location is `<repo>/.agents/artifacts/yyyy-mm-dd/` (per plan-presentation /
# plan-render). Scan the whole `.agents/artifacts/` tree so dated day dirs and
# any transitional layout still clear the gate. Scan root is overridable for
# tests via PLAN_HTML_SCAN_ROOT.
# -L: follow symlinks. On macOS /tmp is a symlink to /private/tmp, and BSD find
# will NOT descend a symlinked start path without -L — so the gate could never
# detect a rendered plan on a Mac and blocked ExitPlanMode indefinitely.
scan_roots=""
if [ -n "${PLAN_HTML_SCAN_ROOT:-}" ]; then
  scan_roots="$PLAN_HTML_SCAN_ROOT"
else
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$repo_root" ]; then
    scan_roots="$repo_root/.agents/artifacts"
  else
    # Legacy fallback: /tmp only when we are not inside a git repo. Inside a repo
    # the canonical artifact path is the only accepted location.
    scan_roots="/tmp"
  fi
fi

# A fresh plan HTML is not enough. Its paired Markdown source must declare the
# surface. Internal plans need a drawn SVG; user-visible plans need a semantic
# current/proposed behavior figure, with each state identified as capture or
# mockup. An unrelated architecture SVG cannot satisfy a CLI/UI plan.
html_ok=0
for scan_root in $scan_roots; do
  [ -d "$scan_root" ] || continue
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    source=${candidate%.html}.md
    [ -r "$source" ] || continue
    surface=$(awk '
      NR == 1 && $0 == "---" { frontmatter=1; next }
      frontmatter && $0 == "---" { exit }
      frontmatter && $0 ~ /^surface:[[:space:]]*/ {
        sub(/^surface:[[:space:]]*/, ""); gsub(/["'\''[:space:]]/, ""); print; exit
      }
    ' "$source" 2>/dev/null || true)
    case "$surface" in
      internal)
        if grep -Eqi '<svg\b' "$candidate" 2>/dev/null \
          && grep -Eqi '<(rect|path|circle|ellipse|line|polyline|polygon|text|g)\b' "$candidate" 2>/dev/null; then
          html_ok=1
        fi
        ;;
      cli|web|native|api|workflow)
        if grep -Eqi 'class=["'\''][^"'\'']*\bartifact-behavior\b' "$candidate" 2>/dev/null \
          && grep -Eqi 'data-state=["'\'']current["'\''][^>]*data-evidence=["'\''](capture|mockup)["'\'']|data-evidence=["'\''](capture|mockup)["'\''][^>]*data-state=["'\'']current["'\'']' "$candidate" 2>/dev/null \
          && grep -Eqi 'data-state=["'\'']proposed["'\''][^>]*data-evidence=["'\''](capture|mockup)["'\'']|data-evidence=["'\''](capture|mockup)["'\''][^>]*data-state=["'\'']proposed["'\'']' "$candidate" 2>/dev/null; then
          html_ok=1
        fi
        ;;
    esac
    [ "$html_ok" = 1 ] && break
  done <<EOF
$(find -L "$scan_root" -maxdepth 6 \( -name 'plan-*.html' -o -name '*-plan.html' \) -mmin -90 -print 2>/dev/null)
EOF
  [ "$html_ok" = 1 ] && break
done

# ---- (B) Checklist check (FAILS OPEN) -----------------------------------------
# Only enforced for a genuinely multi-step plan, and only when we can read the
# session transcript. If the harness gives no transcript_path, or the plan is
# trivial, or we cannot locate the human turn, checklist_ok stays 1 (allow) — a
# reminder must never block a legitimate simple plan. A false-pass just skips one
# nudge; a false-block frustrates the user. We bias to open.
checklist_ok=1
plan=$(printf '%s' "$input" | jq -r '(.tool_input.plan // .toolInput.plan // .last_assistant_message // .lastAssistantMessage) // empty' 2>/dev/null) || plan=""
if [ -n "$tp" ] && [ -r "$tp" ]; then
  # "Multi-step" = >=3 step-like lines in the ExitPlanMode plan text
  # (numbered, bulleted, checkbox, "### " heading, or "Phase ").
  steps=$(printf '%s\n' "$plan" | grep -Ec '^[[:space:]]*([0-9]+[.)]|[-*][[:space:]]|#{2,3}[[:space:]]|[Pp]hase[[:space:]]|-[[:space:]]\[[ xX]\])' || true)
  if [ "${steps:-0}" -ge 3 ]; then
    checklist_ok=0
    # Last GENUINE human turn = a "type":"user" line WITHOUT a tool_result
    # (Claude records tool_results as type:user too — those are not human turns).
    last_human=$(grep -n '"type":"user"' "$tp" 2>/dev/null | grep -v 'tool_result' | tail -1 | cut -d: -f1 || true)
    if [ -z "$last_human" ]; then
      checklist_ok=1                       # can't locate a human turn -> fail open
    elif tail -n +"$last_human" "$tp" 2>/dev/null \
         | grep -Eq '"name":"(TaskCreate|TodoWrite|todo_write|update_plan)"'; then
      checklist_ok=1                       # a checklist tool fired for this plan
    fi
  fi
fi

# ---- decide -------------------------------------------------------------------
if [ "$html_ok" = 1 ] && [ "$checklist_ok" = 1 ]; then
  exit 0
fi

# Something's missing — name it, block once.
{
  echo "Before presenting this plan (plan-presentation rule), finish these:"
  echo
  if [ "$html_ok" != 1 ]; then
    echo "* Render and inspect a FIGURE-RICH browser-ready HTML plan headlessly."
    echo "  Load the plan-render skill. Author Markdown under the dated artifact layout:"
    echo "    .agents/artifacts/yyyy-mm-dd/plan-<slug>.md"
    echo "  then:"
    echo "    DATE=\$(date +%F)"
    echo "    artifacts render .agents/artifacts/\$DATE/plan-<slug>.md"
    echo "  HARD REQUIREMENTS (this gate inspects the Markdown + HTML):"
    echo "    - frontmatter surface: internal|cli|web|native|api|workflow"
    echo "    - internal: ≥1 live drawn SVG"
    echo "    - user-visible: .artifact-behavior with current + proposed states"
    echo "      and data-evidence=\"capture\" or \"mockup\" on each state"
    echo "    - fenced code blocks for commands/APIs (not only inline \`code\` pills)"
    echo "    - at least one table (files/risks/validation) and an artifact-callout"
    echo "  artifacts check/render now ERROR if a plan has no drawn SVG figure."
    echo "  Inspect without stealing focus:"
    echo "    agents browser start --url file://\$PWD/.agents/artifacts/\$DATE/plan-<slug>.html"
    echo "    agents browser screenshot"
    echo "  Copy/open it on the interactive host only when the user explicitly requested it."
    echo "  Same layout for any related artifact (visuals, reports): .agents/artifacts/yyyy-mm-dd/<title>.md"
  fi
  if [ "$checklist_ok" != 1 ]; then
    echo "* Create a task checklist for this plan — it has multiple steps."
    echo "  Call TaskCreate for each step (subject + description); the checklist becomes the"
    echo "  acceptance rubric and shows up in \`agents sessions\`. If a tracker is connected"
    echo "  and no ticket is paired with this work, create or pair one and note it."
  fi
  echo
  echo "Then present/stop again — this passes once the render exists and (for a"
  echo "multi-step plan) a checklist was created."
} >&2
exit 2
