#!/bin/bash
# PreToolUse hook: block git pull/rebase/autostash when working tree is dirty.
# Fast path uses pure-bash pattern matching (no forks) so non-git Bash calls
# add ~2ms. Only git-ish commands pay for jq + git status.

IFS= read -rd '' input

case "$input" in
  *'"command":"git '*|*'--autostash'*) ;;
  *) exit 0 ;;
esac

# --- portable JSON field extractor (jq -> node -> python) -------------------
# jq is absent on Windows git-bash; the old `jq <<< "$input"` then returned empty
# and this guard fail-OPEN'd (allowed pull/rebase on a dirty tree, destroying
# uncommitted work). Prefer jq, fall back to node (always shipped with agents-cli)
# then python. Returns 1 ONLY when NO parser exists -> fail CLOSED.
_json_field() {  # $1=json  $2=dotted.path
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r "(.$2) // empty" 2>/dev/null; return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{let o=JSON.parse(s);for(const k of process.argv[1].split("."))o=(o==null?null:o[k]);process.stdout.write(o==null?"":String(o))}catch(e){}})' "$2" 2>/dev/null; return 0
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$1" | "$_py" -c 'import json,sys
try: o=json.load(sys.stdin)
except Exception: o=None
for k in sys.argv[1].split("."):
    o=o.get(k) if isinstance(o,dict) else None
sys.stdout.write("" if o is None else str(o))' "$2" 2>/dev/null
    return 0
  done
  return 1
}

# --- friction self-report ---------------------------------------------------
# This hook exits 2 before any `agents` process exists, so it cannot emit
# in-process. Fires the hidden recorder in the background, fully fail-open,
# so a missing/slow CLI never breaks the guard's hot path.
report_friction() {  # $1=failureId  $2=error-message
  [ -z "${AGENTS_DISABLE_FRICTION_LOG:-}" ] || return 0
  (agents _internal friction --surface guard --id "$1" \
    --error "$2" --command "$cmd" || true) </dev/null >/dev/null 2>&1 &
}

if ! cmd=$(_json_field "$input" tool_input.command); then
  echo "git-require-clean-tree: no JSON parser (jq/node/python) available — refusing git pull/rebase unchecked (fail-closed)." >&2
  exit 2
fi

case "$cmd" in
  "git pull"*|"git rebase"*|*" git pull"*|*" git rebase"*|*"--autostash"*) ;;
  *) exit 0 ;;
esac

cwd=$(_json_field "$input" cwd) || cwd=""
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

[ -z "$(git status --porcelain 2>/dev/null)" ] && exit 0

deny_reason="Blocked: working tree is dirty. git pull/rebase/autostash on a dirty tree can destroy uncommitted work. Commit (or manually stash) first, then retry."
echo "$deny_reason" >&2
report_friction "git.pull-rebase-dirty-tree" "$deny_reason"
exit 2
