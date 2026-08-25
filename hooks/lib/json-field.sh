#!/bin/sh
# hooks/lib/json-field.sh — the portable JSON field extractor shared by every
# guard and inject hook that reads a hook-event payload off stdin.
#
# Sourced, never executed. Consumers source it by path (see hooks/AGENTS.md
# §hooks/lib) with a fail-closed check that the function is defined after the
# source — a guard that cannot read its input must refuse, not wave the call
# through. This is the same source-then-verify contract main-branch-guard uses
# for git-facts.sh.
#
# History: this body was copy-pasted verbatim into 11 hook scripts (git-guard,
# main-branch-guard, merge-guard, rm-guard, secrets-guard,
# large-file-add-guard, teams-roster-guard, pr-description-reminder,
# public-artifact-guard, 01-git-require-clean-tree, 09-git-pull-forward). A
# parser fix therefore had to land in 11 places and demonstrably did not — the
# camelCase alternate-path arg reached main-branch-guard first and the rest
# open-coded the same fallback at their call sites instead. One definition, one
# place to fix.
#
# _json_field <json> <dotted.path> [<alternate.dotted.path>]
#   Prints the field value (empty if absent). The optional 3rd arg is a second
#   dotted path tried when the first resolves empty — harness portability:
#   Claude/Codex/Kimi/Cursor/Droid send snake_case (tool_name,
#   tool_input.command); Grok sends camelCase (toolName, toolInput.command). A
#   caller passes the snake_case path as $2 and its camelCase twin as $3.
#
#   jq is absent on Windows git-bash; the old `… | jq …` extraction then
#   returned empty and a guard fail-OPEN'd (waved the command through
#   unchecked). Prefer jq (fast, present on mac/Linux), fall back to node
#   (always shipped with agents-cli) then python. Returns 1 when no parser exists
#   or the payload is malformed, so each caller can apply its documented
#   fail-closed or fail-open boundary policy.
_json_field() {  # $1=json  $2=dotted.path  [$3=alternate.dotted.path]
  if command -v jq >/dev/null 2>&1; then
    if [ -n "${3:-}" ]; then
      _json_value=$(printf '%s' "$1" | jq -r "((.$2) // (.$3)) // empty" 2>/dev/null) || return 1
    else
      _json_value=$(printf '%s' "$1" | jq -r "(.$2) // empty" 2>/dev/null) || return 1
    fi
    printf '%s' "$_json_value"
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const dig=(o,p)=>{for(const k of p.split("."))o=(o==null?null:o[k]);return o};try{let o=JSON.parse(s);let v=dig(o,process.argv[1]);if((v==null||v==="")&&process.argv[2])v=dig(o,process.argv[2]);process.stdout.write(v==null?"":String(v))}catch(e){process.exitCode=1}})' "$2" "${3:-}" 2>/dev/null
    return $?
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$1" | "$_py" -c 'import json,sys
try: o=json.load(sys.stdin)
except Exception: sys.exit(1)
def dig(o,p):
    for k in p.split("."):
        o=o.get(k) if isinstance(o,dict) else None
    return o
v=dig(o,sys.argv[1])
if (v is None or v=="") and len(sys.argv)>2 and sys.argv[2]:
    v=dig(o,sys.argv[2])
sys.stdout.write("" if v is None else str(v))' "$2" "${3:-}" 2>/dev/null
    return $?
  done
  return 1
}

# _hook_skip_plan_mode <hook-event-json>
#   Returns 0 only for an explicit plan-mode event. Missing, unknown, malformed,
#   or unparsable values return 1 so a safety guard remains active (fail safe).
_hook_skip_plan_mode() {
  _hook_mode=$(_json_field "$1" permission_mode permissionMode) || return 1
  [ "$_hook_mode" = "plan" ]
}
