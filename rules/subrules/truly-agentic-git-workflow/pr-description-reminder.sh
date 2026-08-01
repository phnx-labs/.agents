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

# Structure / change-type signals. If ANY appears in the command (biased to
# ALLOW to keep false-blocks near zero), the body is considered glanceable.
#  - markdown heading (##), table (|), or a bullet ("- " / "* ")
#  - a change-type marker (docs-only, bugfix, feat:, etc.)
case "$cmd" in
  *"##"*|*"|"*|*"- "*|*"* "*) exit 0 ;;
esac
# Case-insensitive type-marker scan.
lower=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
case "$lower" in
  *"docs-only"*|*"docs only"*|*"no behavior change"*|*"no-behavior-change"*|\
  *"bugfix"*|*"bug fix"*|*"hotfix"*|*"test-only"*|*"test only"*|\
  *"refactor"*|*"feature"*|*"feat:"*|*"fix:"*|*"chore:"*|*"docs:"*|*"perf:"*)
    exit 0 ;;
esac

# Thin inline body — nudge once. Satisfiable: add structure and retry.
{
  echo "PR-description reminder (truly-agentic-git-workflow): this gh pr body looks thin — a reviewer reads the body, not the diff."
  echo
  echo "Make it glanceable, then retry:"
  echo "  * Lead with a one-line what + type at the very top — docs-only / bugfix / feature / refactor / test-only (a no-behavior-change PR says so)."
  echo "  * Highlight the important parts: a '##' heading, a table, or '- ' bullets — not a prose wall."
  echo "  * Add a before/after (table, screenshot, or real command output) when there's a visible or behavioral delta."
  echo "  * For a docs PR, state the audience (maintainers vs end users)."
  echo
  echo "This clears as soon as the body carries any heading/table/bullet or a type marker. Body from --body-file / --fill is never nudged."
} >&2
exit 2
