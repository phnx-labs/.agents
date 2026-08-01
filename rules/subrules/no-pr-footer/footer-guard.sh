#!/bin/sh
# no-pr-footer/footer-guard.sh — PreToolUse(Bash) guard.
#
# Blocks `gh pr create|edit`, `gh issue create|edit`, and `git commit` whose
# inline body carries the "Generated with Claude Code" promo footer. Muqsit's
# standing rule: that line is garbage and must never reach a PR/issue/commit.
#
# Reads the hook JSON from stdin, extracts the tool command via jq. Claude Code
# sends it under snake_case .tool_input.command; Grok CLI sends camelCase
# .toolInput.command — read either so the footer block works on both harnesses.
# Exits 0 (allow) or 2 (deny, message on stderr). Only inline bodies are seen;
# a footer injected via --body-file is invisible here (acceptable — the common
# failure mode in the retro was an inline --body heredoc).
input=$(cat)

# Fast path: ignore anything that isn't a gh pr/issue or git commit command.
case "$input" in
  *"gh pr "*|*"gh issue "*|*"git commit"*) ;;
  *) exit 0 ;;
esac

# Extract the tool command with a jq -> node -> python fallback chain so the guard
# does not fail OPEN when jq is absent (e.g. stock Git Bash on Windows). Sibling
# guards (main-branch-guard, merge-guard) use the same helper and fail CLOSED.
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

if ! cmd=$(_json_field "$input" tool_input.command toolInput.command); then
  # No JSON parser available — fail CLOSED. The command already matched the
  # gh/git fast path above, so refuse it unchecked rather than let a footer slip.
  printf '%s\n' 'footer-guard: no JSON parser (jq/node/python) available — refusing the gh/git command unchecked (fail-closed). Ensure node or jq is on PATH.' >&2
  exit 2
fi
[ -n "$cmd" ] || exit 0

# Only the body-bearing subcommands.
case "$cmd" in
  *"gh pr create"*|*"gh pr edit"*|*"gh issue create"*|*"gh issue edit"*|*"git commit"*) ;;
  *) exit 0 ;;
esac

# Detect the promo footer in any of its forms.
case "$cmd" in
  *"Generated with"*"Claude Code"*|*"claude.com/claude-code"*|*"claude.ai/code"*|*"🤖 Generated"*)
    printf '%s\n' 'Blocked: remove the "Generated with Claude Code" footer from the body. Muqsit'\''s standing rule — that promo line is garbage and must never appear in PR/issue/commit bodies. Delete the line and retry.' >&2
    exit 2
    ;;
esac
exit 0
