#!/bin/sh
# git-guard — PreToolUse hook on Bash.
#
# Blocks destructive git ops regardless of how the command is dressed:
# `git -C <path>`, `--git-dir=`, `--work-tree=`, leading env-var assignments
# (FOO=bar git …), chain operators (&&, ||, ;, |, newline), `sh -c "..."` and
# `bash -c "..."` wrappers, absolute path (`/usr/bin/git`), and quoted first
# token (`'git'` / `"git"`).
#
# Also checks `git worktree remove`: allowed when the target tree is clean AND
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

# --- shared JSON field extractor -------------------------------------------
# _json_field lives in hooks/lib/json-field.sh (one definition; it was formerly
# copy-pasted into 12 hook scripts). Source it relative to this script, falling
# back to the absolute system-install path, then verify the function is defined
# — a guard that cannot parse its input must refuse, not wave the command
# through, so a missing lib fails CLOSED (exit 2). Same source-then-verify
# contract main-branch-guard uses for git-facts.sh.
# ${0%/*} (POSIX param expansion, no subprocess) instead of `dirname` so the
# source works even when PATH carries no coreutils — the fail-closed "no JSON
# parser" path must still reach the parser lib to report itself.
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
  printf 'git-guard: shared json-field lib not found — refusing to run a git command unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/json-field.sh is present.\n' >&2
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

# Structured denial (RUSH-2295). Models that only see "blocked" retry the same
# op; emitting blocked_op + do_this_instead in the same stderr kills the loop.
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
  printf 'git-guard: no JSON parser succeeded (malformed payload or jq/node/python unavailable) — refusing to run a git command unchecked (fail-closed).\n' >&2
  exit 2
fi
[ -z "$cmd" ] && cmd=$(_json_field "$input" toolInput.command) || true
[ -z "$cmd" ] && exit 0

# Session working directory, used to tell whether a history-rewriting op is
# scoped to an isolated worktree (safe) vs the user's main checkout (blocked).
cwd=$(_json_field "$input" cwd) || cwd=""
[ -z "$cwd" ] && cwd=$(_json_field "$input" workspaceRoot) || true

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
    reset)
      set_deny "git.reset" \
        "git reset is denied (rewrites history or destroys work)." \
        "reconcile with \`git rebase origin/<default>\` (or \`git pull --rebase\`); never \`reset --hard\`. Commit instead of stashing; resolve obstacles at the source."
      return 1
      ;;
    checkout|switch|stash|cherry-pick|revert|clean|reflog|filter-branch|gc|prune|fsck)
      set_deny "git.$sub" \
        "git $sub is denied (switches/rewrites the working tree or destroys work)." \
        "never switch the primary checkout onto another branch — that strands the user's tree behind and dirties it. Create an isolated worktree instead: git worktree add -b <slug> <repo>/.agents/worktrees/<slug> origin/<default>, and work there. To discard a file use \`git restore\`; to move an existing ref materialize it in a new worktree."
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
      set_deny "git.rebase-outside-worktree" \
        "git rebase (start) is denied outside a worktree (rewrites history)." \
        "run it inside a <repo>/.agents/worktrees/<slug> worktree; finishing an in-progress rebase (--continue/--skip/--abort) is allowed anywhere."
      return 1
      ;;
    branch)
      for a in "$@"; do
        case "$a" in
          -D|-d|-m|-M|--delete|--force-delete|--move|--force-move)
            set_deny "git.branch-delete" \
              "git branch $a is denied (deletes/renames a ref)." \
              "create or list branches only; delete a merged PR branch with \`gh pr merge --delete-branch\`, not git branch -d/-D."
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
      set_deny "git.config-write" \
        "git config write is denied." \
        "use \`git config --get\` / \`--list\` for reads only; never rewrite git config from an agent shell."
      return 1
      ;;
    push)
      for a in "$@"; do
        case "$a" in
          --force|-f)
            set_deny "git.push-force" \
              "git push --force is denied." \
              "hand the force-push to the user via the \`!\` session prefix after non-destructive attempts are exhausted; prefer \`--force-with-lease\` only when the user explicitly asked."
            return 1 ;;
          --delete|-d)
            set_deny "git.push-delete" \
              "git push $a deletes a remote branch; branch deletion is banned." \
              "delete a merged PR branch with \`gh pr merge --delete-branch\`, which is allowed."
            return 1 ;;
          :*)
            set_deny "git.push-delete" \
              "git push with a leading-colon refspec ($a) deletes a remote branch; branch deletion is banned." \
              "delete a merged PR branch with \`gh pr merge --delete-branch\`, which is allowed."
            return 1 ;;
        esac
      done
      return 0
      ;;
    merge)
      for a in "$@"; do
        case "$a" in
          --abort)
            set_deny "git.merge-abort" \
              "git merge --abort is denied." \
              "finish the merge (resolve conflicts + commit) or leave the state for the user; do not discard the in-progress merge from an agent shell."
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
        set_deny "git.worktree-remove-dirty" \
          "git worktree remove $target denied — worktree has uncommitted changes:
$(printf '%s\n' "$dirty" | head -5)" \
          "commit or discard the worktree changes first, then re-run \`git worktree remove\` without --force."
        return 1
      fi
      if upstream=$(git -C "$target" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
        ahead=$(git -C "$target" rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)
        if [ "${ahead:-0}" -gt 0 ]; then
          set_deny "git.worktree-remove-unpushed" \
            "git worktree remove $target denied — $ahead unpushed commit(s) on $(git -C "$target" rev-parse --abbrev-ref HEAD)." \
            "push or open a PR from the worktree first, then remove it."
          return 1
        fi
      fi
      if [ "$forced" = "1" ]; then
        set_deny "git.worktree-remove-force" \
          "git worktree remove --force denied." \
          "drop --force; clean removal is allowed when the worktree is clean and fully pushed."
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
  emit_deny
  exit 2
fi
exit 0
