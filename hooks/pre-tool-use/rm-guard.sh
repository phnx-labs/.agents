#!/bin/sh
# rm-guard — PreToolUse hook on Bash.
#
# Blocks `rm -r` / `rm -R` targeting protected paths regardless of dressing:
# leading env-var assignments, chain operators (&&, ||, ;, |, newline),
# `sh -c "..."` and `bash -c "..."` wrappers, absolute path (`/bin/rm`),
# quoted first token (`'rm'` / `"rm"`).
#
# Protected paths (literal, $HOME-resolved, tilde, glob siblings):
#   /            ~                   $HOME
#   ~/.agents    ~/.ssh              ~/.config
#   ~/Library    ~/Documents         ~/Desktop
#   ~/src        ~/Phoenix           ~/Rush
#   /Users       /Applications       /System
#
# Allows `rm -r` on anything else (tmp dirs, build output, node_modules).
# Allows `rm <file>` (no recursive flag) regardless of target.
#
# Exits 0 (allow) or 2 (deny, message on stderr).
#
# Limitations (out of scope — runtime obfuscation only a sandbox catches):
#   - `eval`, `xargs rm`, `$(...)` subshells, base64
#   - variable expansion (`rm -rf "$VAR"`) — we treat any $-prefixed target as
#     suspicious and block to be safe

set -eu

# --- shared JSON field extractor -------------------------------------------
# _json_field lives in hooks/lib/json-field.sh (one definition; formerly copied
# into 12 hook scripts). Source it relative to this script, fall back to the
# absolute system-install path, then verify it is defined — a guard that cannot
# parse its input must refuse, not wave `rm` through, so a missing lib fails
# CLOSED (exit 2). ${0%/*} (POSIX, no subprocess) locates the lib even when
# PATH carries no coreutils.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../lib/json-field.sh" "${HOME}/.agents/.system/hooks/lib/json-field.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../lib/json-field.sh
    . "$_cand"
    if command -v _json_field >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v _json_field >/dev/null 2>&1; then
  printf 'rm-guard: shared json-field lib not found — refusing to run an rm command unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/json-field.sh is present.\n' >&2
  exit 2
fi

# --- shared timeout-wrapper peeler ------------------------------------------
# `timeout 5 rm -rf $HOME` would otherwise bypass the guard because `timeout`
# is the first token. The peeler lives in hooks/lib/git-parse.sh (shared with
# git-guard and main-branch-guard) and returns the real inner command.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../lib/git-parse.sh" "${HOME}/.agents/.system/hooks/lib/git-parse.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../lib/git-parse.sh
    . "$_cand"
    if command -v git_peel_timeout_wrapper >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v git_peel_timeout_wrapper >/dev/null 2>&1; then
  printf 'rm-guard: shared git-parse lib not found — refusing to run an rm command unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/git-parse.sh is present.\n' >&2
  exit 2
fi

# --- friction self-report ---------------------------------------------------
# Guard hooks exit 2 before any `agents` process exists, so they cannot emit
# in-process. This helper fires the hidden recorder in the background, fully
# fail-open, so a missing/slow CLI never breaks the guard's hot path.
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


# Fast path: no "rm" anywhere in the JSON payload, nothing to police.
input=$(cat)
case "$input" in *rm*) ;; *) exit 0 ;; esac

# Fail CLOSED if no JSON parser is available — a guard that cannot read the
# command must not wave a potential `rm -rf` through (the Windows fail-open bug).
# Claude/Codex/Kimi/Cursor/Droid: tool_input.command; Grok: toolInput.command.
if ! cmd=$(_json_field "$input" tool_input.command); then
  printf 'rm-guard: no JSON parser succeeded (malformed payload or jq/node/python unavailable) — refusing to run the command unchecked (fail-closed).\n' >&2
  exit 2
fi
[ -z "$cmd" ] && cmd=$(_json_field "$input" toolInput.command) || true
[ -z "$cmd" ] && exit 0

is_protected_path() {
  _p=$1
  # Strip trailing slash for consistent comparison.
  case "$_p" in
    /) return 0 ;;
  esac
  _p=${_p%/}

  # Expand leading ~ to $HOME.
  case "$_p" in
    "~"|"~/")     return 0 ;;
    "~"/*)        _p="${HOME}${_p#\~}" ;;
  esac

  # Block any variable-expansion target — we can't introspect the value.
  case "$_p" in
    *'$'*) return 0 ;;
  esac

  # $HOME bare.
  [ "$_p" = "$HOME" ] && return 0

  # Exact-match protected roots.
  for prot in \
    / \
    /Users \
    /Applications \
    /System \
    /Library \
    "$HOME" \
    "$HOME/.agents" \
    "$HOME/.ssh" \
    "$HOME/.config" \
    "$HOME/.claude" \
    "$HOME/.codex" \
    "$HOME/.gemini" \
    "$HOME/Library" \
    "$HOME/Documents" \
    "$HOME/Desktop" \
    "$HOME/Downloads" \
    "$HOME/src" \
    "$HOME/Phoenix" \
    "$HOME/Rush"
  do
    [ "$_p" = "$prot" ] && return 0
  done

  return 1
}

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

check_segment() {
  _seg=$1

  _seg=$(git_peel_timeout_wrapper "$_seg")

  if extract_sh_c_inner "$_seg"; then
    if ! check_command_string "$_dash_c_inner"; then return 1; fi
    return 0
  fi

  unset IFS
  # shellcheck disable=SC2086
  set -- $_seg

  # Skip leading VAR=value assignments.
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && return 0

  first=$1
  case "$first" in
    \"*\") first=$(printf '%s' "$first" | sed 's/^"\(.*\)"$/\1/') ;;
    \'*\') first=$(printf '%s' "$first" | sed "s/^'\(.*\)'$/\1/") ;;
  esac

  # Accept first token == rm OR */rm.
  case "$first" in
    rm|*/rm) ;;
    *) return 0 ;;
  esac
  shift

  # Look for -r / -R / -rf / -fr / --recursive in flags, collect targets.
  recursive=0
  targets=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; while [ $# -gt 0 ]; do targets="$targets $1"; shift; done; break ;;
      --recursive) recursive=1; shift ;;
      --no-preserve-root) shift ;;
      -*)
        # Compact flag bundle like -rf, -Rf, -fr.
        case "$1" in
          *r*|*R*) recursive=1 ;;
        esac
        shift
        ;;
      *) targets="$targets $1"; shift ;;
    esac
  done

  [ "$recursive" = "0" ] && return 0
  [ -z "$targets" ] && return 0

  for tgt in $targets; do
    if is_protected_path "$tgt"; then
      set_deny "rm.protected-path" \
        "rm -r on protected path denied: $tgt. Protected paths: /, \$HOME, ~/.agents, ~/.ssh, ~/.config, ~/Library, ~/Documents, ~/Desktop, ~/src, ~/Phoenix, ~/Rush, /Users, /Applications, /System. Variable-expansion targets (\$VAR) are also denied because their value is unknown at hook time." \
        "use \`trash\` (or move to /tmp), or scope the path to a non-protected dir; never \`rm -rf\` home, src, or system roots."
      return 1
    fi
  done
  return 0
}

check_command_string() {
  _input=$1
  # Restore POSIX-default IFS before reading it — check_segment may have
  # unset IFS, and `OLDIFS=$IFS` under `set -u` would error on unset.
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
