#!/bin/sh
# git-facts.sh — shared short-TTL cache of per-worktree git facts for PreToolUse
# guards (RUSH-2293).
#
# Why this exists (and why it is NOT the agents-cli `cache:` hook shim):
#   The hook-level `cache:` machinery stores stdout and always exits 0 on hit
#   (apps/cli/src/lib/hooks/cache.ts). Putting that on a deny-capable guard would
#   soft-allow after the first allow within the TTL — including after a branch
#   switch onto the default branch. We cache only derived *facts*, and every
#   consumer still runs its own allow/deny logic.
#
# Cached facts (per worktree root):
#   top   — git rev-parse --show-toplevel
#   cur   — current branch short name (empty if detached)
#   def   — origin/HEAD default branch short name (may be empty)
#   on    — 1 if cur is the default (or main/master fallback), else 0
#
# Invalidation (both required for a hit):
#   1. TTL expiry (default 5s; override GIT_FACTS_TTL_SEC; 0 disables cache)
#   2. HEAD content change — re-read of the worktree HEAD file on every lookup
#      so a `git checkout` / `git switch` invalidates immediately, even inside
#      the TTL window. Key material is (abs path of the *input dir*) for the
#      dir→top map, and (top + HEAD content) is validated on the repo entry.
#
# State: ~/.agents/.cache/state/git-facts/  (override with GIT_FACTS_CACHE_DIR)
# Format (one line, pipe-separated, no newlines in fields):
#   v1|<expiry_epoch>|<top>|<cur>|<def>|<on>|<head_content>
#
# Public API (source this file, then call):
#   git_facts_load <dir>
#     Sets GIT_FACTS_TOP / GIT_FACTS_CUR / GIT_FACTS_DEF / GIT_FACTS_ON_DEFAULT.
#     Returns 0 when <dir> is inside a git worktree, 1 otherwise.
#   git_facts_on_default <dir>
#     Convenience: return 0 if protected (on default branch), 1 if allow.
#     Also sets _top / _cur / _def for deny-message callers (main-branch-guard).
#
# Hit/miss counters (for tests / microbenches; process-local only):
#   GIT_FACTS_HITS  GIT_FACTS_MISSES

# Defaults — keep overridable for tests.
: "${GIT_FACTS_TTL_SEC:=5}"
: "${GIT_FACTS_CACHE_DIR:=${HOME}/.agents/.cache/state/git-facts}"
: "${GIT_FACTS_HITS:=0}"
: "${GIT_FACTS_MISSES:=0}"

# --- internals --------------------------------------------------------------

_git_facts_hash() {
  # 12-hex digest of stdin. Prefer openssl (mac+linux), then sha1sum, then python.
  if command -v openssl >/dev/null 2>&1; then
    openssl sha1 2>/dev/null | awk '{print substr($NF,1,12)}'
    return 0
  fi
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum 2>/dev/null | awk '{print substr($1,1,12)}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 1 2>/dev/null | awk '{print substr($1,1,12)}'
    return 0
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 || continue
    "$_py" -c 'import hashlib,sys; print(hashlib.sha1(sys.stdin.buffer.read()).hexdigest()[:12])' 2>/dev/null
    return 0
  done
  # Last resort: not cryptographic, but still partitions cache files.
  tr -cd 'A-Za-z0-9/._-' | head -c 64 | wc -c | awk '{print $1}'
}

_git_facts_absdir() {
  # Absolute path of an existing directory. Empty on failure.
  _d=$1
  [ -n "$_d" ] || return 1
  [ -d "$_d" ] || return 1
  # Prefer realpath/GNU readlink; fall back to subshell cd.
  if command -v realpath >/dev/null 2>&1; then
    realpath "$_d" 2>/dev/null && return 0
  fi
  if command -v readlink >/dev/null 2>&1; then
    _rl=$(readlink -f "$_d" 2>/dev/null) || _rl=""
    [ -n "$_rl" ] && { printf '%s\n' "$_rl"; return 0; }
  fi
  (CDPATH= cd "$_d" 2>/dev/null && pwd -P)
}

# Read the raw HEAD file content for a worktree root (no git fork).
# Handles plain .git/ dirs and linked worktrees (.git file → gitdir:).
_git_facts_read_head() {
  _top=$1
  _gitpath="$_top/.git"
  if [ -f "$_gitpath" ]; then
    # gitdir: /abs/path/to/.git/worktrees/<name>
    _gd=$(sed -n 's/^gitdir:[[:space:]]*//p' "$_gitpath" 2>/dev/null | head -1)
    [ -n "$_gd" ] || return 1
    # Relative gitdir is rare but legal — resolve against $_top.
    case "$_gd" in
      /*|[A-Za-z]:/*) ;;
      *) _gd="$_top/$_gd" ;;
    esac
    [ -f "$_gd/HEAD" ] || return 1
    tr -d '\n' < "$_gd/HEAD" 2>/dev/null
    return 0
  fi
  if [ -d "$_gitpath" ] && [ -f "$_gitpath/HEAD" ]; then
    tr -d '\n' < "$_gitpath/HEAD" 2>/dev/null
    return 0
  fi
  return 1
}

_git_facts_now() {
  date +%s
}

_git_facts_compute() {
  # $1 = abs dir inside a (candidate) worktree.
  # On success sets _gf_top/_gf_cur/_gf_def/_gf_on/_gf_head and returns 0.
  _in=$1
  _gf_top=$(git -C "$_in" rev-parse --show-toplevel 2>/dev/null) || return 1
  # Normalize top (git may return a path with symlinks).
  _gf_top_abs=$(_git_facts_absdir "$_gf_top" 2>/dev/null) || _gf_top_abs=$_gf_top
  [ -n "$_gf_top_abs" ] && _gf_top=$_gf_top_abs

  _gf_cur=$(git -C "$_gf_top" symbolic-ref --short -q HEAD 2>/dev/null) || _gf_cur=""
  _gf_def=$(git -C "$_gf_top" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || _gf_def=""
  _gf_head=$(_git_facts_read_head "$_gf_top" 2>/dev/null) || _gf_head=""

  _gf_on=0
  if [ -n "$_gf_cur" ]; then
    if [ -n "$_gf_def" ] && [ "$_gf_cur" = "$_gf_def" ]; then
      _gf_on=1
    else
      case "$_gf_cur" in
        main|master) _gf_on=1 ;;
      esac
    fi
  fi
  return 0
}

_git_facts_cache_path() {
  # $1 = key material (string)
  _h=$(printf '%s' "$1" | _git_facts_hash)
  [ -n "$_h" ] || return 1
  printf '%s/%s\n' "$GIT_FACTS_CACHE_DIR" "$_h"
}

_git_facts_write() {
  # $1=path  remaining fields already in _gf_*
  _path=$1
  _exp=$2
  mkdir -p "$GIT_FACTS_CACHE_DIR" 2>/dev/null || return 0
  # Atomic-ish: write tmp then mv. Fail-open on any error.
  _tmp="$_path.tmp.$$"
  # Escape pipes in fields by replacing with unlikely sentinel — paths and
  # branch names almost never contain '|'; if they do, skip caching.
  case "$_gf_top$_gf_cur$_gf_def$_gf_head" in
    *'|'*) rm -f "$_tmp" 2>/dev/null; return 0 ;;
  esac
  printf 'v1|%s|%s|%s|%s|%s|%s\n' \
    "$_exp" "$_gf_top" "$_gf_cur" "$_gf_def" "$_gf_on" "$_gf_head" >"$_tmp" 2>/dev/null \
    && mv -f "$_tmp" "$_path" 2>/dev/null \
    || rm -f "$_tmp" 2>/dev/null
  return 0
}

_git_facts_try_read() {
  # $1=cache path  $2=expected abs dir (for top containment, optional)
  # On hit: sets _gf_* and returns 0. On miss: return 1.
  _path=$1
  [ -f "$_path" ] || return 1
  _line=$(head -1 "$_path" 2>/dev/null) || return 1
  case "$_line" in
    v1\|*) ;;
    *) return 1 ;;
  esac
  # Split carefully without IFS side effects on the caller.
  _rest=${_line#v1|}
  _exp=${_rest%%|*}; _rest=${_rest#*|}
  _gf_top=${_rest%%|*}; _rest=${_rest#*|}
  _gf_cur=${_rest%%|*}; _rest=${_rest#*|}
  _gf_def=${_rest%%|*}; _rest=${_rest#*|}
  _gf_on=${_rest%%|*}; _rest=${_rest#*|}
  _gf_head=$_rest

  # TTL check (0 = disabled / always recompute).
  case "${GIT_FACTS_TTL_SEC}" in
    ''|*[!0-9]*) ;; # treat as default path below
    0) return 1 ;;
  esac
  _now=$(_git_facts_now)
  # Non-numeric expiry → miss.
  case "$_exp" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_now" -le "$_exp" ] || return 1

  # HEAD re-validation: branch switch changes HEAD content → miss.
  [ -n "$_gf_top" ] && [ -d "$_gf_top" ] || return 1
  _live_head=$(_git_facts_read_head "$_gf_top" 2>/dev/null) || _live_head=""
  [ "$_live_head" = "$_gf_head" ] || return 1

  return 0
}

# --- public API -------------------------------------------------------------

# git_facts_load <dir>
# Returns 0 if <dir> is inside a git worktree; 1 otherwise.
git_facts_load() {
  GIT_FACTS_TOP=""
  GIT_FACTS_CUR=""
  GIT_FACTS_DEF=""
  GIT_FACTS_ON_DEFAULT=0

  _dir=${1:-.}
  # Windows backslashes → forward.
  case "$_dir" in *\\*) _dir=$(printf '%s' "$_dir" | tr '\\' '/') ;; esac

  # Nearest existing ancestor (Write may target a not-yet-created path's parent
  # already resolved by the caller; still tolerate a missing leaf).
  _probe=$_dir
  while [ ! -d "$_probe" ]; do
    _nd=$(dirname "$_probe")
    [ "$_nd" = "$_probe" ] && break
    _probe=$_nd
  done
  [ -d "$_probe" ] || return 1

  _abs=$(_git_facts_absdir "$_probe" 2>/dev/null) || _abs=$_probe
  [ -n "$_abs" ] || _abs=$_probe

  # TTL 0 → always recompute (tests).
  _ttl=${GIT_FACTS_TTL_SEC:-5}
  case "$_ttl" in ''|*[!0-9]*) _ttl=5 ;; esac

  _cpath=""
  if [ "$_ttl" -gt 0 ]; then
    _cpath=$(_git_facts_cache_path "dir:$_abs" 2>/dev/null) || _cpath=""
    if [ -n "$_cpath" ] && _git_facts_try_read "$_cpath"; then
      GIT_FACTS_HITS=$((GIT_FACTS_HITS + 1))
      GIT_FACTS_TOP=$_gf_top
      GIT_FACTS_CUR=$_gf_cur
      GIT_FACTS_DEF=$_gf_def
      GIT_FACTS_ON_DEFAULT=$_gf_on
      return 0
    fi
  fi

  if ! _git_facts_compute "$_abs"; then
    GIT_FACTS_MISSES=$((GIT_FACTS_MISSES + 1))
    return 1
  fi
  GIT_FACTS_MISSES=$((GIT_FACTS_MISSES + 1))
  GIT_FACTS_TOP=$_gf_top
  GIT_FACTS_CUR=$_gf_cur
  GIT_FACTS_DEF=$_gf_def
  GIT_FACTS_ON_DEFAULT=$_gf_on

  if [ "$_ttl" -gt 0 ] && [ -n "$_cpath" ]; then
    _now=$(_git_facts_now)
    _exp=$((_now + _ttl))
    _git_facts_write "$_cpath" "$_exp"
    # Also write under the worktree root key so sibling paths share one entry
    # after the first resolution of each abs dir maps to the same top+head.
    if [ "$_gf_top" != "$_abs" ]; then
      _cpath2=$(_git_facts_cache_path "dir:$_gf_top" 2>/dev/null) || _cpath2=""
      [ -n "$_cpath2" ] && _git_facts_write "$_cpath2" "$_exp"
    fi
  fi
  return 0
}

# git_facts_on_default <dir>
# Return 0 if <dir> is on the default branch (protected), 1 if allow.
# Sets _top / _cur / _def for deny-message builders.
git_facts_on_default() {
  _top=""
  _cur=""
  _def=""
  if ! git_facts_load "$1"; then
    return 1
  fi
  _top=$GIT_FACTS_TOP
  _cur=$GIT_FACTS_CUR
  _def=$GIT_FACTS_DEF
  [ -z "$_cur" ] && return 1
  [ "$GIT_FACTS_ON_DEFAULT" = 1 ] && return 0
  return 1
}
