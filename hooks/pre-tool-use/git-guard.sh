#!/bin/sh
# git-guard — PreToolUse hook on Bash.
#
# Blocks destructive git ops regardless of how the command is dressed:
# `git -C <path>`, `--git-dir=`, `--work-tree=`, leading env-var assignments
# (FOO=bar git …), chain operators (&&, ||, ;, |, newline), `sh -c "..."` and
# `bash -c "..."` wrappers, absolute path (`/usr/bin/git`), and quoted first
# token (`'git'` / `"git"`).
#
# Also gates `git worktree remove`: allowed when the target tree is clean AND
# has no unpushed commits; denied otherwise (including --force).
#
# Exits 0 (allow) or 2 (deny, message on stderr).
#
# Limitations (intentionally out of scope — these are runtime obfuscation that
# only a sandbox can stop):
#   - `eval "<computed string>"` with the destructive op in the runtime string
#   - `xargs git ...` reading args from stdin
#   - base64-decoded / pipe-built command strings
#   - aliases or shell functions defined elsewhere
#   - `$(...)` / backtick subshells (single-level recursion not implemented)

set -eu

# --- portable JSON field extractor (jq -> node -> python) -------------------
# jq is absent on Windows git-bash; the old `… | jq …` extraction then returned
# empty and this guard fail-OPEN'd (waved the git command through unchecked).
# Prefer jq (fast, present on mac/Linux), fall back to node (always shipped with
# agents-cli) then python. Prints the field value (empty if absent). Returns 1
# ONLY when NO parser exists at all, so the caller can fail CLOSED. node/python
# JSON.parse unescape \n / \t / \" / \\ exactly like jq, so multi-line commands
# still split correctly for the chain scan below.
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

# Fast path: if the raw JSON doesn't even contain the substring "git", there
# is nothing for this hook to police. Skip parse entirely. Cuts the cost off
# every non-git Bash call, which is >80% of them.
input=$(cat)
case "$input" in *git*) ;; *) exit 0 ;; esac

# Extract shell command from PreToolUse JSON. Fail CLOSED if no JSON parser is
# available — a guard that cannot read the command must not wave it through
# (that was the Windows fail-open bug).
#
# Field names differ by harness (Claude/Codex/Kimi/Cursor/Droid: snake_case
# tool_input.command; Grok: camelCase toolInput.command). Try both. Empty on
# both means this event is not a shell tool — allow.
if ! cmd=$(_json_field "$input" tool_input.command); then
  printf 'git-guard: no JSON parser (jq/node/python) available — refusing to run a git command unchecked (fail-closed). Ensure node or jq is on PATH.\n' >&2
  exit 2
fi
[ -z "$cmd" ] && cmd=$(_json_field "$input" toolInput.command) || true
[ -z "$cmd" ] && exit 0

# Session working directory, used to tell whether a history-rewriting op is
# scoped to an isolated worktree (safe) vs the user's main checkout (gated).
cwd=$(_json_field "$input" cwd) || cwd=""
[ -z "$cwd" ] && cwd=$(_json_field "$input" workspaceRoot) || true

deny_reason=""

# Detect `sh|bash -c <inner>` at the raw string level (BEFORE token split) so
# that quoted args like `sh -c "git reset --hard"` stay intact. Naive
# `set -- $seg` would split `"git` away from `reset --hard"` and miss the
# git subcommand entirely. Sets _dash_c_inner on match. Returns 0 on match.
extract_sh_c_inner() {
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

# Check one already-split segment.
check_segment() {
  _seg=$1

  # sh|bash -c wrapper detection must happen BEFORE naive token splitting,
  # because the -c argument is typically a quoted string the naive split
  # would shred.
  if extract_sh_c_inner "$_seg"; then
    if ! check_command_string "$_dash_c_inner"; then return 1; fi
    return 0
  fi

  # Restore default IFS so `set -- $1` actually splits on space/tab/newline.
  # The caller flipped IFS to newline-only to iterate chain segments.
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

  # First token may be: git | /path/to/git | "git" | 'git'
  # Strip enclosing single or double quotes.
  first=$1
  case "$first" in
    \"*\") first=$(printf '%s' "$first" | sed 's/^"\(.*\)"$/\1/') ;;
    \'*\') first=$(printf '%s' "$first" | sed "s/^'\(.*\)'$/\1/") ;;
  esac

  # Accept first token == git OR */git (absolute or relative path).
  case "$first" in
    git|*/git) ;;
    *) return 0 ;;
  esac
  shift

  # Peel git's global flags before the subcommand.
  while [ $# -gt 0 ]; do
    case "$1" in
      -C)            shift; [ $# -gt 0 ] && shift ;;
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

  sub=$1
  shift

  case "$sub" in
    reset|checkout|stash|cherry-pick|revert|clean|reflog|filter-branch|gc|prune|fsck)
      deny_reason="git $sub is denied (rewrites history or destroys work). Use a worktree-based flow instead."
      report_friction "git.$sub" "$deny_reason"
      return 1
      ;;
    rebase)
      # Finishing an already-started rebase is safe — the conflicts were
      # resolved by hand and the only effect is to advance/end the sequence.
      # Only STARTING a rebase rewrites history, so deny that.
      for a in "$@"; do
        case "$a" in
          --continue|--skip|--abort|--quit|--edit-todo|--show-current-patch)
            return 0 ;;
        esac
      done
      # Rebasing your own PR branch inside an isolated worktree is the blessed
      # flow — it rewrites history on a branch nothing else uses and never
      # touches the user's main checkout. Detect it via the worktree path in
      # the command (`git -C <wt> rebase` / `cd <wt> && git rebase`) or the
      # session cwd already being inside one. force-with-lease is already
      # allowed (see `push` below), so the round-trip works end to end.
      case "$cmd$cwd" in
        *"/.agents/worktrees/"*) return 0 ;;
      esac
      deny_reason="git rebase (start) is denied outside a worktree (rewrites history). Run it inside a <repo>/.agents/worktrees/<slug> worktree; finishing an in-progress rebase (--continue/--skip/--abort) is allowed anywhere."
      report_friction "git.rebase-outside-worktree" "$deny_reason"
      return 1
      ;;
    branch)
      for a in "$@"; do
        case "$a" in
          -D|-d|-m|-M|--delete|--force-delete|--move|--force-move)
            deny_reason="git branch $a is denied (deletes/renames a ref). Branch creation/listing is fine."
            report_friction "git.branch-delete" "$deny_reason"
            return 1 ;;
        esac
      done
      return 0
      ;;
    config)
      for a in "$@"; do
        case "$a" in
          --get|--get-all|--get-regexp|-l|--list|--show-origin|--show-scope|-h|--help)
            return 0 ;;
        esac
      done
      deny_reason="git config write is denied. Use --get for reads."
      report_friction "git.config-write" "$deny_reason"
      return 1
      ;;
    push)
      for a in "$@"; do
        case "$a" in
          --force|-f)
            deny_reason="git push --force is denied. Use --force-with-lease."
            report_friction "git.push-force" "$deny_reason"
            return 1 ;;
        esac
      done
      return 0
      ;;
    merge)
      for a in "$@"; do
        case "$a" in
          --abort)
            deny_reason="git merge --abort is denied."
            report_friction "git.merge-abort" "$deny_reason"
            return 1 ;;
        esac
      done
      return 0
      ;;
    worktree)
      [ $# -lt 1 ] && return 0
      [ "$1" != "remove" ] && return 0
      shift
      forced=0
      target=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --force|-f) forced=1; shift ;;
          --) shift; target=${1:-}; break ;;
          -*) shift ;;
          *) target=$1; break ;;
        esac
      done
      [ -z "$target" ] && return 0
      [ ! -d "$target" ] && return 0

      if dirty=$(git -C "$target" status --porcelain 2>/dev/null) && [ -n "$dirty" ]; then
        deny_reason="git worktree remove $target denied — worktree has uncommitted changes:
$(printf '%s\n' "$dirty" | head -5)"
        report_friction "git.worktree-remove-dirty" "$deny_reason"
        return 1
      fi
      if upstream=$(git -C "$target" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
        ahead=$(git -C "$target" rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)
        if [ "${ahead:-0}" -gt 0 ]; then
          deny_reason="git worktree remove $target denied — $ahead unpushed commit(s) on $(git -C "$target" rev-parse --abbrev-ref HEAD). Push or merge first."
          report_friction "git.worktree-remove-unpushed" "$deny_reason"
          return 1
        fi
      fi
      if [ "$forced" = "1" ]; then
        deny_reason="git worktree remove --force denied — drop --force; clean removal is allowed when work is preserved."
        report_friction "git.worktree-remove-force" "$deny_reason"
        return 1
      fi
      return 0
      ;;
  esac
  return 0
}

# Top-level: split a command string on chain operators AND newlines, then
# check each segment. Also called recursively for sh -c inner strings.
check_command_string() {
  _input=$1
  # Restore POSIX-default IFS before reading it — check_segment may have
  # unset IFS, and `OLDIFS=$IFS` under `set -u` would error on unset.
  IFS=$(printf ' \t\n.'); IFS=${IFS%.}
  # Split on chain operators AND real newlines. The actual newline is inserted
  # via shell quoting — `\n` in sed replacement is a GNU/BSD extension that's
  # reliable enough on the macOS sed we target.
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
  printf '%s\n' "$deny_reason" >&2
  exit 2
fi
exit 0
