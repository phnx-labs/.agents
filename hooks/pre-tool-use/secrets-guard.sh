#!/bin/sh
# secrets-guard — PreToolUse hook on Bash (RUSH-2774).
#
# Blocks the secret-materializing one-liners that dump bundle values into an
# agent's context and session transcript:
#
#   agents secrets export <b> --plaintext            whole bundle to stdout
#   agents secrets get <bundle> <KEY>                one bundle value to stdout
#   agents secrets view <b> --reveal --plaintext     the non-TTY reveal escape
#
# agents-cli >= the RUSH-2774 build refuses these in the CLI itself; this guard
# is the skew-immune backstop for boxes still running older installed CLIs — it
# fires on the agent's own Bash call before any CLI executes. The paved path is
# injection: `agents secrets exec <bundle> -- <cmd>` (values ride the child
# process env, never stdout).
#
# Unwraps: leading env-var assignments, chain operators (&&, ||, ;, |,
# newline), `sh -c`/`bash -c` wrappers, a leading `eval`, and one level of
# $(...) command substitution — the canonical exfil idiom is
# `eval "$(agents secrets export <b> --plaintext)"`.
#
# Exits 0 (allow) or 2 (deny, structured message on stderr).
#
# Limitations (out of scope — runtime obfuscation only a sandbox catches):
#   - base64, `xargs`, computed strings, deeper substitution nesting

set -eu

# --- portable JSON field extractor (jq -> node -> python) -------------------
# Same contract as rm-guard/git-guard: returns 1 ONLY when NO parser exists,
# so the caller can fail CLOSED instead of waving the command through.
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
report_friction() {  # $1=failureId  $2=error-message
  [ -z "${AGENTS_DISABLE_FRICTION_LOG:-}" ] || return 0
  _friction_cmd=$cmd
  _friction_id=$1
  _friction_msg=$2
  (agents _internal friction --surface guard --id "$_friction_id" \
    --error "$_friction_msg" --command "$_friction_cmd" || true) </dev/null >/dev/null 2>&1 &
}

# Structured denial (RUSH-2295) — same shape as git-guard.
deny_op=""
deny_reason=""
deny_next=""
set_deny() {  # $1=blocked_op  $2=reason  $3=do_this_instead
  deny_op=$1
  deny_reason=$2
  deny_next=$3
  report_friction "$1" "$2"
}
emit_deny() {
  printf 'blocked_op: %s\nreason: %s\ndo_this_instead: %s\n' \
    "$deny_op" "$deny_reason" "$deny_next" >&2
}

# Fast path: no "secrets" anywhere in the JSON payload, nothing to police.
input=$(cat)
case "$input" in *secrets*) ;; *) exit 0 ;; esac

# Fail CLOSED if no JSON parser is available.
if ! cmd=$(_json_field "$input" tool_input.command); then
  printf 'secrets-guard: no JSON parser (jq/node/python) available — refusing to run the command unchecked (fail-closed). Ensure node or jq is on PATH.\n' >&2
  exit 2
fi
[ -z "$cmd" ] && cmd=$(_json_field "$input" toolInput.command) || true
[ -z "$cmd" ] && exit 0

# Detect `sh|bash -c <inner>` at raw string level (see git-guard.sh).
extract_sh_c_inner() {
  _raw=$1
  _raw=$(printf '%s' "$_raw" | sed 's/^[[:space:]]*//')
  while :; do
    _pre=$_raw
    _raw=$(printf '%s' "$_raw" | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]][[:space:]]*//')
    [ "$_raw" = "$_pre" ] && break
  done
  case "$_raw" in
    sh\ *|bash\ *|/bin/sh\ *|/bin/bash\ *|/usr/bin/sh\ *|/usr/bin/bash\ *) ;;
    *) return 1 ;;
  esac
  case "$_raw" in
    *" -c "*) ;;
    *) return 1 ;;
  esac
  _inner=${_raw#* -c }
  _inner=$(printf '%s' "$_inner" | sed 's/^[[:space:]]*//')
  case "$_inner" in
    \"*\") _inner=${_inner#\"}; _inner=${_inner%\"} ;;
    \'*\') _inner=${_inner#\'}; _inner=${_inner%\'} ;;
  esac
  _dash_c_inner=$_inner
  return 0
}

# Raw-string unwrap for a leading `eval "<cmd>"` / `eval '<cmd>'` — the naive
# whitespace tokenizer glues the opening quote onto the first inner word
# (`"agents`), so the agents|ag first-token check would silently miss a plainly
# quoted eval (the bypass the #336 review reproduced). Mirror the sh -c unwrap:
# strip env prefixes + `eval` + one layer of quotes at the string level, then
# check the inner as its own command string.
extract_eval_inner() {  # sets _eval_inner
  _raw=$(printf '%s' "$1" | sed 's/^[[:space:]]*//')
  while :; do
    _pre=$_raw
    _raw=$(printf '%s' "$_raw" | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]][[:space:]]*//')
    [ "$_raw" = "$_pre" ] && break
  done
  case "$_raw" in
    eval\ *) ;;
    *) return 1 ;;
  esac
  _inner=${_raw#eval }
  _inner=$(printf '%s' "$_inner" | sed 's/^[[:space:]]*//')
  case "$_inner" in
    \"*\") _inner=${_inner#\"}; _inner=${_inner%\"} ;;
    \'*\') _inner=${_inner#\'}; _inner=${_inner%\'} ;;
  esac
  [ -n "$_inner" ] || return 1
  _eval_inner=$_inner
  return 0
}

# One level of $(...) unwrap — the eval-export idiom wraps the real command in a
# substitution (`eval "$(agents secrets export …)"`). Single-quoted spans are
# scrubbed FIRST: a `$(` inside single quotes never expands, so prose like
# `echo 'do not eval $(agents secrets export …)'` must not deny (the RUSH-2760
# false-positive class, reproduced by the #336 review).
extract_substitution_inner() {  # sets _subst_inner
  _raw=$1
  _scrubbed=$(printf '%s' "$_raw" | sed "s/'[^']*'//g")
  case "$_scrubbed" in
    *'$('*) ;;
    *) return 1 ;;
  esac
  _subst_inner=${_scrubbed#*\$\(}
  _subst_inner=${_subst_inner%\)*}
  [ -n "$_subst_inner" ] || return 1
  return 0
}

check_segment() {
  _seg=$1

  if extract_sh_c_inner "$_seg"; then
    if ! check_command_string "$_dash_c_inner"; then return 1; fi
    return 0
  fi

  if extract_eval_inner "$_seg"; then
    if ! check_command_string "$_eval_inner"; then return 1; fi
    return 0
  fi

  if extract_substitution_inner "$_seg"; then
    if ! check_command_string "$_subst_inner"; then return 1; fi
    # Fall through: the outer segment may ALSO be an agents call.
  fi

  unset IFS
  # shellcheck disable=SC2086
  set -- $_seg

  # Skip leading VAR=value assignments (a bare unquoted `eval agents …` was
  # already unwrapped above; a residual `eval` token here covers `eval agents`).
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      eval) shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && return 0

  first=$1
  case "$first" in
    \"*\") first=$(printf '%s' "$first" | sed 's/^"\(.*\)"$/\1/') ;;
    \'*\') first=$(printf '%s' "$first" | sed "s/^'\(.*\)'$/\1/") ;;
  esac

  case "$first" in
    agents|ag|*/agents|*/ag) ;;
    *) return 0 ;;
  esac
  shift
  [ $# -gt 0 ] && [ "$1" = "secrets" ] || return 0
  shift
  [ $# -gt 0 ] || return 0
  sub=$1
  shift

  case "$sub" in
    export)
      has_plaintext=0
      has_destination=0
      for a in "$@"; do
        case "$a" in
          --plaintext) has_plaintext=1 ;;
          --device|--host|--to-1password|--to-file) has_destination=1 ;;
        esac
      done
      if [ "$has_plaintext" = "1" ] && [ "$has_destination" = "0" ]; then
        set_deny "secrets.export-plaintext" \
          "secrets export --plaintext prints a whole bundle to stdout — inside an agent session that lands in the model context and the session transcript (RUSH-2774)." \
          "run the consuming command under injection: \`agents secrets exec <bundle> -- <cmd>\` (values ride the child env, never stdout); one value in a script: \`VAR=\"\$(agents secrets exec <bundle> -- printenv KEY)\`."
        return 1
      fi
      ;;
    get)
      nonflag=0
      for a in "$@"; do
        case "$a" in
          -*) ;;
          *) nonflag=$((nonflag + 1)) ;;
        esac
      done
      if [ "$nonflag" -ge 2 ]; then
        set_deny "secrets.get-bundle-key" \
          "secrets get <bundle> <KEY> prints a bundle credential to stdout — inside an agent session that lands in the model context and the session transcript (RUSH-2774)." \
          "run the consuming command under injection: \`agents secrets exec <bundle> -- <cmd>\`, or \`agents secrets exec <bundle> -- printenv <KEY>\` inside a script you author."
        return 1
      fi
      ;;
    view)
      has_reveal=0
      has_plaintext=0
      for a in "$@"; do
        case "$a" in
          --reveal) has_reveal=1 ;;
          --plaintext) has_plaintext=1 ;;
        esac
      done
      if [ "$has_reveal" = "1" ] && [ "$has_plaintext" = "1" ]; then
        set_deny "secrets.view-reveal-plaintext" \
          "secrets view --reveal --plaintext is the non-TTY reveal escape — it prints bundle values into the agent context and session transcript (RUSH-2774; removed in current agents-cli)." \
          "inspect key NAMES with \`agents secrets view <bundle>\` (masked), or run the consuming command under \`agents secrets exec <bundle> -- <cmd>\`."
        return 1
      fi
      ;;
  esac
  return 0
}

check_command_string() {
  _input=$1
  IFS=$(printf ' \t\n.'); IFS=${IFS%.}
  _chains=$(printf '%s' "$_input" | sed 's/&&/\
/g; s/||/\
/g; s/;/\
/g; s/|/\
/g')

  OLDIFS=$IFS
  IFS='
'
  for seg in $_chains; do
    seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$seg" ] && continue
    if ! check_segment "$seg"; then
      IFS=$OLDIFS
      return 1
    fi
  done
  IFS=$OLDIFS
  return 0
}

if ! check_command_string "$cmd"; then
  emit_deny
  exit 2
fi
exit 0
