#!/bin/sh
# truly-agentic-git-workflow/pr-description-reminder.sh — PreToolUse(Bash) reminder.
#
# Nudges once when a `gh pr create` / `gh pr edit` ships an INLINE body that is
# thin — a bare blob with no structure and no change-type marker. The reviewer
# reads the body, not the diff, so a wall-of-prose (or one-liner) PR is one they
# cannot glance. The fix the reminder asks for: lead with a `what + type`
# (docs-only / bugfix / feature / refactor / test-only), highlight the important
# parts (a heading, a table, or bullets), and add a before/after when there is a
# visible or behavioral delta.
#
# SATISFIABLE, not a wall: it clears the moment the body carries any structure or
# a type marker. It fires ONLY on an inline --body/-b; a --body-file / -F / --fill
# / --template / --web / editor body is never inspected and always allowed.
#
# Multi-harness: reads the tool command from Claude's snake_case
# .tool_input.command OR Grok/Codex camelCase .toolInput.command, via a
# jq -> node -> python fallback chain (same helper as footer-guard). Unlike the
# footer guard this FAILS OPEN — a reminder must never block a legit PR, so any
# parse/extract failure exits 0.
input=$(cat)

# Fast path: ignore anything that isn't a gh pr command.
case "$input" in
  *"gh pr "*) ;;
  *) exit 0 ;;
esac

# Extract the tool command with a jq -> node -> python fallback so the reminder
# does not misfire when jq is absent (e.g. stock Git Bash on Windows).
_json_field() {
  # $1 = json, $2 = primary dotted key, $3 = optional fallback dotted key
  if command -v jq >/dev/null 2>&1; then
    if [ -n "${3:-}" ]; then
      printf '%s' "$1" | jq -r "((.$2) // (.$3)) // empty" 2>/dev/null
    else
      printf '%s' "$1" | jq -r "(.$2) // empty" 2>/dev/null
    fi
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const dig=(o,p)=>{for(const k of p.split("."))o=(o==null?null:o[k]);return o};try{let o=JSON.parse(s);let v=dig(o,process.argv[1]);if((v==null||v==="")&&process.argv[2])v=dig(o,process.argv[2]);process.stdout.write(v==null?"":String(v))}catch(e){}})' "$2" "${3:-}" 2>/dev/null
    return 0
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$1" | "$_py" -c 'import json,sys
try: o=json.load(sys.stdin)
except Exception: o=None
def dig(o,p):
    for k in p.split("."):
        o=o.get(k) if isinstance(o,dict) else None
    return o
v=dig(o,sys.argv[1])
if (v is None or v=="") and len(sys.argv)>2 and sys.argv[2]:
    v=dig(o,sys.argv[2])
sys.stdout.write("" if v is None else str(v))' "$2" "${3:-}" 2>/dev/null
    return 0
  done
  return 1
}

# No JSON parser -> FAIL OPEN (a reminder must never block a legit PR).
cmd=$(_json_field "$input" tool_input.command toolInput.command) || exit 0
[ -n "$cmd" ] || exit 0

# Only the body-bearing subcommands.
case "$cmd" in
  *"gh pr create"*|*"gh pr edit"*) ;;
  *) exit 0 ;;
esac

# Body comes from a file / commits / editor / browser -> not inspectable, allow.
case "$cmd" in
  *"--body-file"*|*" -F "*|*"--fill"*|*"--fill-first"*|*"--fill-verbose"*|*"--template"*|*"--web"*) exit 0 ;;
esac

# No inline body flag at all -> gh opens an editor (create) or it's a non-body
# edit (e.g. --add-label) -> nothing to inspect, allow.
case "$cmd" in
  *"--body"*|*" -b "*) ;;
  *) exit 0 ;;
esac

# EVIDENCE-OR-DECLARE. A PR body must show something concrete or declare why it
# can't. Allow (exit 0) if the command carries ANY of the signals below — matched
# as substrings over the whole command, biased to ALLOW to keep false-blocks near
# zero. The RULE TEXT carries the strong bar (a screenshot is required for a
# user-visible change); this hook is the backstop for a body that shows nothing.

# 1) Media evidence — a screenshot / GIF / video, inline or as an uploaded asset.
case "$cmd" in
  *"!["*|*".png"*|*".jpg"*|*".jpeg"*|*".gif"*|*".webp"*|\
  *".mp4"*|*".mov"*|*".webm"*|\
  *"user-attachments/assets"*|*"githubusercontent.com"*|*"/assets/"*) exit 0 ;;
esac
# 2) A concrete artifact for a no-UI change — a fenced code block or a table.
case "$cmd" in
  *'```'*|*"|"*) exit 0 ;;
esac
# 3) A no-visible-surface / change-type declaration (case-insensitive), OR a link
#    to a Linear ticket or a shared plan (both count as attached context).
lower=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
case "$lower" in
  *"docs-only"*|*"docs only"*|*"docs:"*|*"no behavior change"*|*"no-behavior-change"*|\
  *"no visible surface"*|*"no user-visible"*|*"refactor"*|*"test-only"*|*"test only"*|\
  *"chore:"*|*"internal only"*|\
  *"linear.app/"*|*"getrush.ai/"*|*".html"*) exit 0 ;;
esac

# Body shows no evidence — nudge once. Satisfiable: attach any of the above.
{
  echo "PR-description evidence reminder (truly-agentic-git-workflow): this gh pr body shows no evidence — a reviewer reads the body, not the diff."
  echo
  echo "Attach ONE of these, then retry (it clears as soon as any is present):"
  echo "  * A SCREENSHOT of the user-visible outcome (required for a visible change) — an uploaded asset, or an on-disk image referenced by full path."
  echo "  * A VIDEO of the flow when a still won't do — capture a web app with the browser skill, or a terminal flow with 'agents pty', and attach it."
  echo "  * For a no-UI change: real command/test output in a fenced code block, or a before/after table."
  echo "  * If there is genuinely no visible surface: mark it docs-only / refactor / test-only."
  echo
  echo "Also link, when applicable: the Linear ticket for this work, and a shareable link to the plan file if a plan was shared."
  echo
  echo "A --body-file / --fill body is never nudged."
} >&2
exit 2
