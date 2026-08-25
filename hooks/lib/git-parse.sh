#!/bin/sh
# hooks/lib/git-parse.sh — the shared git-command parser used by every guard
# that inspects a shell command string for a git invocation.
#
# Sourced, never executed. Consumers source it by path (see hooks/AGENTS.md
# §hooks/lib) with a fail-closed check that the parser is defined after the
# source — a guard that cannot parse its input must refuse, not wave the command
# through. This is the same source-then-verify contract the guards already use
# for json-field.sh (#385) and git-facts.sh.
#
# History: this machinery was copy-pasted, near-verbatim, into three guards —
# git-guard.sh (WHAT operation), large-file-add-guard.sh (git add of a blob),
# and main-branch-guard.sh (WHERE: the primary worktree). Each re-implemented
# `sh|bash -c` unwrapping, chain splitting, first-token/`-C` unquoting, env-prefix
# stripping, `git` detection, and global-flag peeling. A parse fix therefore had
# to land in three places; they drifted (large-file grew a redundant sh/bash arm,
# main-branch grew `-C` capture the others lacked). One definition, one fix site.
#
# The parser is policy-free: it identifies the git subcommand and hands it to a
# consumer-supplied `git_on_command <sub> <args...>` callback. WHAT/WHERE policy
# lives in the guard, not here — this file only finds the git invocation.

# git_extract_sh_c_inner <raw> — detect a `sh|bash -c <inner>` wrapper at the
# raw-string level (BEFORE any token split, so a quoted inner command like
# `sh -c "git reset --hard"` is not shredded). Strips a leading run of
# `VAR=value ` env assignments first. On a match, sets the global _dash_c_inner
# to the (one-layer-unquoted) inner command and returns 0; returns 1 otherwise.
git_extract_sh_c_inner() {
  _raw=$1
  _raw=$(printf '%s' "$_raw" | sed 's/^[[:space:]]*//')
  # Strip leading VAR=value assignments (POSIX env-var prefix).
  while :; do
    _pre=$_raw
    _raw=$(printf '%s' "$_raw" | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]][[:space:]]*//')
    [ "$_raw" = "$_pre" ] && break
  done
  # First word must be sh / bash / absolute path to one.
  case "$_raw" in
    sh\ *|bash\ *|/bin/sh\ *|/bin/bash\ *|/usr/bin/sh\ *|/usr/bin/bash\ *) ;;
    *) return 1 ;;
  esac
  # Find first occurrence of " -c " anywhere after the shell name.
  case "$_raw" in
    *" -c "*) ;;
    *) return 1 ;;
  esac
  _inner=${_raw#* -c }
  _inner=$(printf '%s' "$_inner" | sed 's/^[[:space:]]*//')
  # Strip a single layer of wrapping quotes.
  case "$_inner" in
    \"*\") _inner=${_inner#\"}; _inner=${_inner%\"} ;;
    \'*\') _inner=${_inner#\'}; _inner=${_inner%\'} ;;
  esac
  _dash_c_inner=$_inner
  return 0
}

# git_unwrap_quotes <token> — strip ONE layer of matching single or double
# quotes from a token (`"git"` -> git, `'/tmp/x'` -> /tmp/x); prints the token
# unchanged when it is not wholly quote-wrapped. Used for the first token and
# for a quoted `-C <path>` argument.
git_unwrap_quotes() {
  case "$1" in
    \"*\") printf '%s' "$1" | sed 's/^"\(.*\)"$/\1/' ;;
    \'*\') printf '%s' "$1" | sed "s/^'\(.*\)'\$/\1/" ;;
    *) printf '%s' "$1" ;;
  esac
}

# git_split_chains <cmd> — split a command string on the chain operators
# `&&`, `||`, `;`, `|` and on real newlines, printing one segment per line.
# The real newline in the sed replacement is inserted via a backslash-newline
# continuation (a GNU/BSD-portable extension, reliable on the macOS sed we
# target). Callers iterate the output with IFS set to newline.
git_split_chains() {
  printf '%s' "$1" | sed 's/&&/\
/g; s/||/\
/g; s/;/\
/g; s/|/\
/g'
}

# git_scan_segment <segment> — reduce ONE already-split segment to the git
# invocation it runs, then dispatch to the consumer's `git_on_command` callback.
#
# Steps (the machinery every guard shared): skip leading `VAR=value` env
# assignments; unwrap the first token; require it to be `git` or `*/git`
# (non-git segment -> return 0, allow); peel git's global flags, capturing any
# `-C <path>` argument (one-layer-unquoted) into the global GIT_C_PATH; then call
#   git_on_command <subcommand> <remaining-args...>
# and return that callback's rc. Returns 0 (allow) for a non-git or bare-git
# segment. GIT_C_PATH is reset to '' on entry and set before the callback fires,
# so a consumer that resolves a `-C` target reads it; guards that ignore the
# target simply never look at it.
#
# The `sh|bash -c` wrapper is intentionally NOT handled here: the inner-string
# policy (recurse vs. its own recursion path) differs per guard, so the caller
# runs git_extract_sh_c_inner itself BEFORE calling this.
git_scan_segment() {
  GIT_C_PATH=''
  # Restore default IFS so `set -- $1` splits on space/tab/newline. The caller
  # flipped IFS to newline-only to iterate chain segments.
  unset IFS
  # shellcheck disable=SC2086
  set -- $1

  # Skip leading VAR=value assignments.
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && return 0

  # First token may be: git | /path/to/git | "git" | 'git'.
  _first=$(git_unwrap_quotes "$1")
  case "$_first" in
    git|*/git) ;;
    *) return 0 ;;
  esac
  shift

  # Peel git's global flags before the subcommand; capture -C <path>.
  while [ $# -gt 0 ]; do
    case "$1" in
      -C)            shift
                     if [ $# -gt 0 ]; then
                       GIT_C_PATH=$(git_unwrap_quotes "$1"); shift
                     fi ;;
      --git-dir=*|--work-tree=*|--namespace=*) shift ;;
      --git-dir|--work-tree|--namespace)      shift; [ $# -gt 0 ] && shift ;;
      -c)            shift; [ $# -gt 0 ] && shift ;;
      --no-pager|--paginate|--no-replace-objects|--bare|--exec-path=*|--literal-pathspecs|--no-optional-locks)
                     shift ;;
      -*)            shift ;;
      *)             break ;;
    esac
  done
  [ $# -eq 0 ] && return 0

  _sub=$1
  shift
  git_on_command "$_sub" "$@"
}
