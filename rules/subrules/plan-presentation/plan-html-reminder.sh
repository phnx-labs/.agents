#!/bin/sh
# plan-html-reminder — PreToolUse hook on ExitPlanMode.
#
# Enforces the plan-presentation rule: a plan must be RENDERED as a self-contained
# HTML doc (plan-render skill) before it is presented, so the user reviews it in the
# browser — skinned in the product's brand, light/dark, opened on the Mac they sit at.
#
# Mechanism: the moment an agent goes to present a plan (ExitPlanMode), check whether a
# fresh plan HTML was written this session. If yes -> allow. If no -> block ONCE (exit 2)
# with a reminder; the agent renders `/tmp/plan-<slug>.html`, opens it, and re-calls
# ExitPlanMode, which now finds the file and passes. Self-terminating; never loops.
#
# The gate is on the RENDER (a file we can detect). Opening on the Mac and theming are
# driven by the always-on rule text — a headless fleet still renders the file (allowed)
# even when it cannot open a browser.
#
# Exits 0 (allow) or 2 (block, message on stderr). Only gates the AGENT's tool call;
# the user's own actions are unaffected.

set -eu

input=$(cat)

# Matcher already scopes us to the plan-exit tool, but confirm defensively — this
# is a REMINDER hook, so it must ONLY ever fire on a genuine plan-exit and fail
# OPEN (allow) for anything else. Read the tool name across harnesses: Claude Code
# sends snake_case .tool_name = "ExitPlanMode"; Grok CLI sends camelCase
# .toolName = "exit_plan_mode".
#
# The gate runs ONLY when the tool is a recognized plan-exit tool. If the name is
# empty (unknown/unparsed harness) or anything else, exit 0 — a reminder must
# never block an unrelated tool call. (The old `-n && != ExitPlanMode` test
# fell THROUGH on an empty name and blocked EVERY tool call in a Grok session
# whenever no fresh plan HTML existed — the exact bug this fixes.)
tool=$(printf '%s' "$input" | jq -r '(.tool_name // .toolName) // empty' 2>/dev/null) || tool=""
case "$tool" in
  ExitPlanMode|exit_plan_mode) ;;   # recognized plan-exit -> run the render gate below
  *) exit 0 ;;                       # empty / unknown / any other tool -> allow
esac

# The gate has TWO parts, both checked before we allow the plan to be presented:
#   (A) a fresh plan HTML was rendered (browser-reviewable), and
#   (B) for a MULTI-STEP plan, a task checklist was created (the acceptance rubric
#       that then shows in `agents sessions` and drives the watchdog/feed).
# Either missing -> block ONCE with a message naming what's missing. Both self-
# terminating: the agent renders the HTML / creates the checklist and re-calls
# ExitPlanMode, which now passes.

# ---- (A) HTML render check ----------------------------------------------------
# A fresh plan HTML rendered in the last 90 min satisfies this. Covers both the
# canonical `/tmp/plan-<slug>.html` and the `<slug>-plan.html` scratchpad convention.
# Scan root is /tmp (where the recipe renders); overridable for tests.
# -L: follow symlinks. On macOS /tmp is a symlink to /private/tmp, and BSD find
# will NOT descend a symlinked start path without -L — so the gate could never
# detect a rendered plan on a Mac and blocked ExitPlanMode indefinitely.
scan_root="${PLAN_HTML_SCAN_ROOT:-/tmp}"
html_ok=0
if find -L "$scan_root" -maxdepth 6 \( -name 'plan-*.html' -o -name '*-plan.html' \) -mmin -90 \
     -print -quit 2>/dev/null | grep -q .; then
  html_ok=1
fi

# ---- (B) Checklist check (FAILS OPEN) -----------------------------------------
# Only enforced for a genuinely multi-step plan, and only when we can read the
# session transcript. If the harness gives no transcript_path, or the plan is
# trivial, or we cannot locate the human turn, checklist_ok stays 1 (allow) — a
# reminder must never block a legitimate simple plan. A false-pass just skips one
# nudge; a false-block frustrates the user. We bias to open.
checklist_ok=1
tp=$(printf '%s' "$input" | jq -r '(.transcript_path // .transcriptPath) // empty' 2>/dev/null) || tp=""
plan=$(printf '%s' "$input" | jq -r '(.tool_input.plan // .toolInput.plan) // empty' 2>/dev/null) || plan=""
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
    echo "* Render it as browser-ready HTML and open it on the user's Mac."
    echo "  Load the plan-render skill: write /tmp/plan-<slug>.html (hero, TOC, >=1 hand-"
    echo "  authored inline-SVG diagram, callouts, tagged tables), skinned in the product"
    echo "  brand with a light/dark toggle. Start from the skill's template.html."
    echo "  Open it on the online macOS device (resolve the host from \`agents devices\`):"
    echo "    scp /tmp/plan-<slug>.html <host>:/tmp/ && agents ssh <host> 'open /tmp/plan-<slug>.html'"
    echo "  Headless fleet with no browser host: still render the file (that clears this)."
  fi
  if [ "$checklist_ok" != 1 ]; then
    echo "* Create a task checklist for this plan — it has multiple steps."
    echo "  Call TaskCreate for each step (subject + description); the checklist becomes the"
    echo "  acceptance rubric and shows up in \`agents sessions\`. If a tracker is connected"
    echo "  and no ticket is paired with this work, create or pair one and note it."
  fi
  echo
  echo "Then call ExitPlanMode again — this passes once the render exists and (for a"
  echo "multi-step plan) a checklist was created."
} >&2
exit 2
