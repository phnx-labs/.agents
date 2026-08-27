#!/bin/sh
# main-branch-guard — PreToolUse hook on Write / Edit / MultiEdit / NotebookEdit
# and Bash.
#
# Enforces the Truly Agentic Git Workflow: no agent tool call may create, update,
# or delete a tracked file, or `git add` / `git commit`, while the target is
# inside the PRIMARY working tree of a repo — the user's own checkout — on ANY
# branch (not just the default). All work goes through an isolated LINKED worktree
# (`git worktree add` under <repo>/.agents/worktrees/<slug>) + PR. Linked
# worktrees, non-git paths (/tmp, scratchpad, loose files), and gitignored paths
# (harness memory under .history/, .agents/scratch, .agents/artifacts) are
# unaffected — a gitignored file never dirties the tracked tree or lands in a PR.
#
# Why the whole primary tree: blocking only the default branch let agents check
# out a feature branch in the user's main checkout and never switch back, leaving
# it stranded on a branch and dozens of commits behind (the review-2704 trap).
#
# Fires on:
#   - Write / Edit / MultiEdit / NotebookEdit -> inspects .tool_input.file_path
#     (or .notebook_path); resolves its enclosing repo and current branch.
#   - Bash -> inspects `git commit|add|stage` segments; resolves the target repo
#     from `-C <path>` or the session cwd.
#   - Bash -> also blocks `git worktree add -b/-B`: a new-branch worktree must be
#     based on a freshly-fetched remote ref (origin/<default>), never an implicit
#     HEAD or a local branch (the "worktree-ing off a stale local commit" trap).
#     "Freshly-fetched" is mechanical: the remote-tracking ref (or FETCH_HEAD)
#     must be newer than AGENTS_WORKTREE_FETCH_MAX_AGE_SEC (default 900s / 15m).
#     Form-only origin/* was not enough — agents passed a days-stale origin/main.
#
# Exits 0 (allow) or 2 (deny, message on stderr).
#
# No exceptions, no escape hatch — by design. This hook only blocks the AGENT's
# tool calls: the user's own editor, `!`-prefixed session commands, and git's
# internal hooks are unaffected.
#
# Bash destinations are checked too: redirection, `tee`, `cp`, `mv`, `install`,
# `scp`, and `rsync`, including commands nested under `sh -c`, plain `ssh`, and
# `agents ssh`. Each destination is judged against its own local or remote repo;
# the session cwd is never used as a proxy for a destination in another tree.
# `agents run --device` and remote `agents teams` carry prompts to separately
# guarded agents rather than executing a shell destination directly. Crabbox
# writes only into its leased ephemeral checkout, not a user's primary checkout.
#
# Limitations (intentionally out of scope — runtime obfuscation only a sandbox
# can stop): `eval`/`xargs`/`$(...)` subshells feeding a git command string,
# base64-decoded commands. The commit check is defense in depth, not the sole
# barrier — the file-tool block already stops an agent authoring content on the
# default branch through Write/Edit/NotebookEdit.
#
# -C resolution (RUSH-2743): a `git -C "$VAR" commit|add|stage` target is
# expanded from literal `NAME=value` assignments earlier in the same command
# string (`$(git rev-parse --show-toplevel)` / `$(pwd)` count as the session
# cwd). A target that stays unresolvable, or that does not exist, is judged as
# the PARSED target — the check allows (git itself errors; nothing mutates) and
# never falls back to blaming the session cwd, which false-blocked linked-
# worktree commits in compound/heredoc/multiline `-m` commands. Heredoc
# detection is quote-parity aware (a `<<TAG` inside an open quote is data, not
# an opener), but ESCAPED quotes (`echo "a \"<<EOF\""`) defeat the parity
# count — the same static-parser limit as the subshell class above; a sandbox,
# not more regex, is the answer there.

set -eu

# --- shared JSON field extractor -------------------------------------------
# _json_field lives in hooks/lib/json-field.sh (one definition; formerly copied
# into 12 hook scripts — this file held the canonical 3-arg superset that is now
# the lib's body). Source it relative to this script, fall back to the absolute
# system-install path, then verify it is defined — this guard is the "primary
# tree is untouchable" choke point, so if it cannot parse it must refuse rather
# than allow (fail CLOSED, exit 2). Same source-then-verify contract this file
# already uses for git-facts.sh below. ${0%/*} (POSIX, no subprocess) locates
# the lib even when PATH carries no coreutils.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../../../hooks/lib/json-field.sh" "${HOME}/.agents/.system/hooks/lib/json-field.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../../../hooks/lib/json-field.sh
    . "$_cand"
    if command -v _json_field >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v _json_field >/dev/null 2>&1; then
  printf 'main-branch-guard: shared json-field lib not found — refusing the tool call unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/json-field.sh is present.\n' >&2
  exit 2
fi

input=$(cat)
# Fail CLOSED if no JSON parser is available — the guard can't tell which tool is
# firing, so it must not silently allow a possible default-branch mutation.
if ! tool=$(_json_field "$input" tool_name toolName); then
  printf 'main-branch-guard: no JSON parser succeeded (malformed payload or jq/node/python unavailable) — refusing the tool call unchecked (fail-closed).\n' >&2
  exit 2
fi
[ -z "$tool" ] && exit 0

cwd=$(_json_field "$input" cwd) || cwd=""   # cwd is shared by both harnesses
# Windows harnesses send backslash-separated, drive-letter-rooted cwds
# (C:\Users\..., I:\Vault\...). The POSIX tools below (case globs, dirname,
# git) expect forward slashes, so normalize once, up front.
case "$cwd" in *\\*) cwd=$(printf '%s' "$cwd" | tr '\\' '/') ;; esac

deny_reason=""

# Shared short-TTL git-fact cache (RUSH-2293). NOT the agents-cli hook `cache:`
# shim — that soft-allows (exit 0) on hit and would miss a branch switch onto
# the default branch. Facts only; this guard still decides allow/deny itself.
# Resolve the lib relative to this script so it works both from the system
# install (~/.agents/.system/...) and from a worktree checkout of this repo.
_MBG_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
_GIT_FACTS_READY=0
for _cand in \
  "$_MBG_DIR/../../../hooks/lib/git-facts.sh" \
  "${HOME}/.agents/.system/hooks/lib/git-facts.sh"
do
  if [ -f "$_cand" ]; then
    # shellcheck source=../../../hooks/lib/git-facts.sh
    . "$_cand"
    # Only trust the lib if it actually exports the function we call. A stale lib
    # — present but pre-dating git_facts_in_primary_tree, exactly the state a
    # non-atomic two-file sync produces (main-branch-guard updated, git-facts not
    # yet) — would otherwise leave _GIT_FACTS_READY=1 and make the
    # `if in_primary_tree` test hit an undefined function (rc!=0, immune to
    # `set -e` inside an `if`), fall through, and ALLOW a primary-tree commit.
    # Fail-safe: fall through to the git-fork fallback below instead.
    if command -v git_facts_in_primary_tree >/dev/null 2>&1; then
      _GIT_FACTS_READY=1
      break
    fi
  fi
done
unset _MBG_DIR _cand

# in_primary_tree <dir> — return 0 (protected) if <dir> is inside the PRIMARY
# working tree of a git repo — the user's own checkout — on ANY branch. Return 1
# (allow) for: not a git repo, OR a linked worktree (`git worktree add`, where all
# agent work belongs). Sets _top / _cur / _def for the caller's deny message.
#
# Why the whole primary tree, not just the default branch: agents were checking
# out a feature branch IN the user's main checkout and never switching back,
# stranding it on a branch and dozens of commits behind (the review-2704 trap).
# Blocking only the default branch let that through. The primary tree is off
# limits on every branch; the ONLY place an agent writes is a linked worktree.
#
# Uses the shared git-facts cache (HEAD-validated, short TTL). If the lib is
# missing OR stale (no git_facts_in_primary_tree — see the source loop above),
# fall through to git forks so the guard never soft-opens. Primary vs linked is
# fork-free via the `.git` entry: a directory → primary; a file pointing under
# `.git/worktrees/` → linked worktree (allow); a file pointing elsewhere (a
# submodule's `.git/modules/…`, or unknown) → protect.
in_primary_tree() {
  if [ "${_GIT_FACTS_READY:-0}" = 1 ]; then
    git_facts_in_primary_tree "$1"
    return $?
  fi
  _top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  _cur=$(git -C "$_top" symbolic-ref --short -q HEAD 2>/dev/null) || _cur=""
  _def=$(git -C "$_top" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || _def=""
  if [ -d "$_top/.git" ]; then
    return 0                        # primary working tree (any branch) — protected
  elif [ -f "$_top/.git" ]; then
    _gd=$(sed -n 's/^gitdir:[[:space:]]*//p' "$_top/.git" 2>/dev/null | head -1)
    case "$_gd" in
      */worktrees/*) return 1 ;;    # linked worktree — the blessed agent path
      *)             return 0 ;;    # submodule / unknown pointer — protect
    esac
  fi
  return 1                          # not a normal primary tree — allow
}

# Build the worktree the agent should have been working in, and return its path.
#
# Why the guard does this instead of only describing it: this refusal fires ~131
# times across ~63 sessions, and every one of those is an agent that wanted to
# write, stopped, read a recipe, ran four commands, and retried. Measured
# recovery is 72% — the best of any guard, precisely because the message already
# pastes a runnable recipe. The remaining 28% is agents fumbling the recipe or
# wandering off. Handing over a directory that already exists removes the step
# that can be fumbled.
#
# Safety: creating a linked worktree is additive and reversible. It touches
# nothing in the primary tree, cannot lose work, and a leftover is removed with
# `git worktree remove`. On ANY failure this is silent — the refusal still
# happens, it just falls back to describing the recipe. A guard must never
# become less protective because a convenience step broke.
_ensure_worktree() {
  _repo=$1
  command -v git >/dev/null 2>&1 || return 1
  [ -n "${AGENTS_NO_AUTO_WORKTREE:-}" ] && return 1

  # Name: <harness>-<yyyy-mm-dd>-<hhmm>-<session8>. Each part earns its place —
  # the harness says who made it, the timestamp sorts chronologically and says
  # when, and the session chunk makes it unique AND resolvable: the worktree can
  # be traced straight back with `agents sessions <session8>`.
  # AGENTS_AGENT_NAME and AGENTS_SESSION_ID are both exported by buildExecEnv.
  _who=${AGENTS_AGENT_NAME:-agent}
  _sid=$(printf '%s' "${AGENTS_SESSION_ID:-$$}" | tr -cd 'A-Za-z0-9' | cut -c1-8)
  [ -z "$_sid" ] && _sid=$$
  _dir="$_repo/.agents/worktrees"

  # Reuse the one this session already got, so a session with six blocked writes
  # ends up with one worktree and not six. Matching on the session chunk rather
  # than the whole name is what makes this survive the clock: a later block
  # computes a different HHMM, but the same session still finds its worktree —
  # and it needs no state file to do it.
  for _prev in "$_dir"/*-"$_sid"; do
    [ -d "$_prev" ] || continue
    printf '%s' "$_prev"
    return 0
  done

  _stamp=$(date +%Y-%m-%d-%H%M 2>/dev/null) || return 1
  _name="$_who-$_stamp-$_sid"

  # Bound the fetch: this runs inside a PreToolUse guard on EVERY blocked write, so
  # it must never HANG. A bare `git fetch` can block indefinitely on a credential /
  # host-key prompt (a real /dev/tty exists in these terminal sessions) or a
  # blackholed route (VPN down). GIT_TERMINAL_PROMPT=0 refuses the HTTPS credential
  # prompt; BatchMode=yes refuses the SSH host-key/password prompt; ConnectTimeout
  # caps the TCP connect. On any of these the fetch fails fast and `|| return 1`
  # makes the guard deny (fail CLOSED) with its normal reason — the pre-#368
  # behavior of an instant deny, never a hang. (No dependency on a `timeout` binary,
  # which is absent on stock macOS.)
  GIT_TERMINAL_PROMPT=0 \
    GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=5" \
    git -C "$_repo" fetch origin --quiet >/dev/null 2>&1 || return 1
  _base=$(git -C "$_repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  [ -z "$_base" ] && return 1
  _wt="$_dir/$_name"
  git -C "$_repo" worktree add -b "$_name" "$_wt" "origin/$_base" >/dev/null 2>&1 || return 1
  [ -d "$_wt" ] || return 1
  printf '%s' "$_wt"
}

set_deny_reason() {
  # $1 = what is blocked (e.g. the file path or "git commit"); uses _top/_cur.
  _where=$_top
  [ -n "$_cur" ] && _where="$_top (branch '$_cur')"

  _ready=$(_ensure_worktree "$_top" 2>/dev/null) || _ready=""

  if [ -n "$_ready" ]; then
    deny_reason="Blocked: $1 in the PRIMARY working tree of $_where.

No agent may modify the user's primary working tree — on ANY branch. It is the
checkout the user works in; leaving it dirty or switched onto a feature branch
strands their machine.

A worktree is ready for you — redo this write there:
  $_ready
It is branched off freshly-fetched origin/HEAD. Work, commit, and push from it,
then open a PR. Rename the branch if you want a task-shaped name:
  git -C \"$_ready\" branch -m <slug>"
    return
  fi

  deny_reason="Blocked: $1 in the PRIMARY working tree of $_where.

No agent may modify the user's primary working tree — on ANY branch. It is the
checkout the user works in; leaving it dirty or switched onto a feature branch
strands their machine. All work goes through an isolated LINKED worktree + PR
(the Truly Agentic Git Workflow). No exceptions.

Create a worktree off the freshly-fetched default branch, then work there:
  REPO=$_top
  git -C \"\$REPO\" fetch origin
  BASE=\$(git -C \"\$REPO\" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
  git -C \"\$REPO\" worktree add -b <slug> \"\$REPO/.agents/worktrees/<slug>\" \"origin/\$BASE\"
then edit under \$REPO/.agents/worktrees/<slug>/, commit there, push, and open a PR."
}

# --- File-tool branch ------------------------------------------------------
case "$tool" in
  Write|Edit|MultiEdit|NotebookEdit)
    fp=$(_json_field "$input" tool_input.file_path toolInput.file_path) || fp=""
    [ -z "$fp" ] && fp=$(_json_field "$input" tool_input.notebook_path toolInput.notebook_path)
    [ -z "$fp" ] && exit 0
    # Windows-style paths (C:\..., I:\..., or a Claude-Code-supplied C:/..., I:/...)
    # must be recognized as absolute, never concatenated onto cwd. Bug history:
    # the old `/*` -only check let a drive-letter path like `I:\tmp\out.html` or
    # `I:/tmp/out.html` fall through to the relative branch, producing a bogus
    # "$cwd/I:\tmp\out.html" that `dirname` walked back up to cwd itself — so an
    # edit to a file completely outside the repo was misreported as "on the
    # default branch of <repo>". Normalize backslashes first so the case glob,
    # `dirname`, and `git -C` all agree on one separator.
    is_drive_abs=0
    case "$fp" in *\\*) fp=$(printf '%s' "$fp" | tr '\\' '/') ;; esac
    # Resolve a relative path against the session cwd.
    case "$fp" in
      [A-Za-z]:/*) is_drive_abs=1 ;;
      /*) ;;
      *) [ -n "$cwd" ] && fp="$cwd/$fp" ;;
    esac
    # Nearest existing ancestor directory (a Write may be creating a new file).
    d=$(dirname "$fp")
    while [ ! -d "$d" ]; do
      _nd=$(dirname "$d")
      [ "$_nd" = "$d" ] && break
      d=$_nd
    done
    [ -d "$d" ] || exit 0
    # Drive-letter absolute path on a POSIX box: the drive root does not exist
    # locally, so the path cannot be inside any git repo here. Without this check
    # the dirname walk above collapses to `.', which is the session cwd and may
    # itself be in the primary tree — producing a false deny for a file that is
    # completely outside the repo.
    # A missing drive root is necessary but NOT sufficient: a `..` component
    # climbs out of the fake drive segment, so `C:/../tracked.txt` resolves to
    # `<cwd>/tracked.txt` — a real file in the primary tree. Verified against the
    # guard as first shipped: it exited 0 and a standard mkdir-then-write
    # overwrote the tracked file, in a guard whose own header says "No
    # exceptions, no escape hatch — by design". So a traversal path falls through
    # to the real primary-tree check instead of taking the exemption.
    #
    # Only traversal needs handling here. A literal `C:` DIRECTORY in the tree is
    # already covered: the test above is `[ ! -d "${fp%%:*}:/" ]` with no leading
    # slash, so it resolves relative to the process cwd, not the filesystem root.
    # Measured both ways — dir present and `C:` symlinked to the tree root both
    # already deny without any extra check, so guarding them again would be a
    # branch no test can distinguish.
    if [ "$is_drive_abs" = 1 ] && [ ! -d "${fp%%:*}:/" ]; then
      case "$fp" in
        *../*|*/..) ;;   # traversal — fall through to the real check below
        *) exit 0 ;;
      esac
    fi
    if in_primary_tree "$d"; then
      # A gitignored path can never be committed and never dirties the tracked
      # tree — allow it. This is what the harness memory dir (.history/,
      # gitignored) and runtime scratch/artifact dirs rely on; blocking them
      # would break normal agent operation. Tracked paths (real source, or a
      # would-be new tracked file) fall through to the deny and must go via a
      # linked worktree + PR. check-ignore works on not-yet-created paths too.
      if git -C "$_top" check-ignore -q "$fp" 2>/dev/null; then
        exit 0
      fi
      set_deny_reason "editing '$fp'"
      printf '%s\n' "$deny_reason" >&2
      exit 2
    fi
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

# --- Bash branch: block writes and git mutations in primary working trees ------
# Parser presence already confirmed by the tool_name extraction above.
cmd=$(_json_field "$input" tool_input.command toolInput.command) || cmd=""
[ -z "$cmd" ] && exit 0

# --- shared git-command parser ---------------------------------------------
# The git-invocation finder — `sh|bash -c` unwrapping (git_extract_sh_c_inner),
# chain splitting (git_split_chains), and the env/quote/global-flag reducer
# (git_scan_segment, which captures any `-C <path>` into GIT_C_PATH) — lives in
# hooks/lib/git-parse.sh (one definition, shared with git-guard and
# large-file-add-guard). Source it relative to this script, fall back to the
# absolute system-install path, then verify — this guard is the primary-tree
# choke point, so if it cannot parse it must refuse rather than allow (fail
# CLOSED, exit 2). Same source-then-verify contract used for json-field.sh and
# git-facts.sh above.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../../../hooks/lib/git-parse.sh" "${HOME}/.agents/.system/hooks/lib/git-parse.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../../../hooks/lib/git-parse.sh
    . "$_cand"
    if command -v git_scan_segment >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v git_scan_segment >/dev/null 2>&1 \
  || ! command -v write_scan_segment >/dev/null 2>&1 \
  || ! command -v git_extract_remote_inner >/dev/null 2>&1; then
  printf 'main-branch-guard: shared git-parse lib not found — refusing the tool call unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/git-parse.sh is present.\n' >&2
  exit 2
fi

# --- `-C <path>` variable resolution (RUSH-2743) -----------------------------
# The guard parses command STRINGS, so `git -C "$REPO" commit` reaches it with
# the variable unexpanded. resolve_repo_dir used to emit `<cwd>/$REPO` — a path
# that never exists — and git_facts_load's nearest-existing-ancestor walk then
# collapsed it to the session cwd, blaming the PRIMARY tree for a commit aimed
# at a linked worktree (two real false blocks in one session, 2026-08-15).
#
# Resolution is best-effort and static: a literal `NAME=value` assignment seen
# earlier in the SAME command string is recorded and substituted into a leading
# `$NAME` / `${NAME}` of a later -C target. `$(git rev-parse --show-toplevel)`
# and `$(pwd)` count as the session cwd — the recipe idiom, and exactly what
# they evaluate to where the command runs. Anything else that stays
# unresolvable (an env var set outside this string, another command
# substitution) marks the target UNRESOLVABLE and the commit check FAILS TOWARD
# THE PARSED TARGET — it allows rather than blaming the cwd the agent
# explicitly steered away from. git itself errors on a bogus -C, so nothing
# can be mutated; a false block, by contrast, teaches agents to work around
# the guard. Runtime obfuscation is already out of scope (see header).
_MBG_VARS=""
_MBG_UNRESOLVED="<mbg:unresolved>"

_mbg_var_record() { # $1=name  $2=value (may be the tombstone sentinel)
  _MBG_VARS="${_MBG_VARS}
$1=$2"
}

# _mbg_shell_quote <value> — quote one value for the remote POSIX shell without
# allowing a path surfaced from the command string to become shell syntax.
_mbg_shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# remote_primary_tree <host> <path> — ask the destination host to resolve the
# path's nearest existing ancestor and classify its own checkout. Worktrees are
# checked first and win. On a protected result, sets _top/_cur for the denial.
# Returns 0 for primary, 1 for linked/non-repo, and 2 when the destination host
# cannot be inspected. Safe /tmp and agent-home destinations never call this.
remote_primary_tree() {
  _rp_host=$1
  _rp_path=$2
  command -v agents >/dev/null 2>&1 || return 2
  _rp_q=$(_mbg_shell_quote "$_rp_path")
  _rp_script="p=$_rp_q; case \"\$p\" in '~/'*) p=\"\$HOME/\${p#'~/'}\" ;; esac; if [ -d \"\$p\" ]; then d=\$p; else d=\$(dirname \"\$p\"); fi; while [ ! -d \"\$d\" ]; do n=\$(dirname \"\$d\"); [ \"\$n\" = \"\$d\" ] && break; d=\$n; done; top=\$(git -C \"\$d\" rev-parse --show-toplevel 2>/dev/null) || { printf 'NONE\\n'; exit 0; }; if [ -f \"\$top/.git\" ] && grep -q '/worktrees/' \"\$top/.git\" 2>/dev/null; then printf 'LINKED\\n'; elif [ -d \"\$top/.git\" ] || [ -f \"\$top/.git\" ]; then cur=\$(git -C \"\$top\" symbolic-ref --short -q HEAD 2>/dev/null || true); printf 'PRIMARY|%s|%s\\n' \"\$top\" \"\$cur\"; else printf 'NONE\\n'; fi"
  _rp_out=$(agents ssh "$_rp_host" "$_rp_script" 2>/dev/null) || return 2
  case "$_rp_out" in
    PRIMARY\|*)
      _rp_rest=${_rp_out#PRIMARY|}
      _top=${_rp_rest%%|*}
      _cur=${_rp_rest#*|}
      return 0 ;;
    LINKED|NONE) return 1 ;;
    *) return 2 ;;
  esac
}

# write_on_destination <kind> <destination> <remote-host> — WHERE policy for
# write_scan_segment. The scanner stays policy-free; this callback resolves the
# destination's own repo and blocks only primary checkouts.
_mbg_lexical_path() {
  printf '%s\n' "$1" | awk '
    {
      p = $0; prefix = ""
      if (substr(p, 1, 2) == "~/") { prefix = "~/"; p = substr(p, 3) }
      else if (substr(p, 1, 6) == "$HOME/") { prefix = "$HOME/"; p = substr(p, 7) }
      else if (substr(p, 1, 1) == "/") { prefix = "/"; p = substr(p, 2) }
      n = split(p, a, "/"); depth = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (depth > 0) depth--; else if (prefix == "") stack[++depth] = ".."; continue }
        stack[++depth] = a[i]
      }
      out = prefix
      for (i = 1; i <= depth; i++) out = out (i > 1 ? "/" : "") stack[i]
      print out
    }
  '
}

write_on_destination() {
  _wd_kind=$1
  _wd_path=$2
  _wd_host=${3:-}

  # scp/rsync encode the remote host in the destination token.
  case "$_wd_kind:$_wd_path" in
    scp:*:*|rsync:*:*)
      _wd_host=${_wd_path%%:*}
      _wd_path=${_wd_path#*:} ;;
  esac
  case "$_wd_path" in *\\*) _wd_path=$(printf '%s' "$_wd_path" | tr '\\' '/') ;; esac

  case "$_wd_path" in
    /*|[A-Za-z]:/*|'~/'*|'$HOME/'*) ;;
    *) _wd_path=${WRITE_DEST_CWD:-${cwd:-.}}/$_wd_path ;;
  esac
  _wd_path=$(_mbg_lexical_path "$_wd_path")
  # This check MUST precede repo discovery: linked worktrees live below the
  # protected repo root. Lexical normalization runs first so `worktrees/x/../..`
  # cannot disguise a destination back in the primary checkout.
  case "$_wd_path" in */.agents/worktrees/*) return 0 ;; esac
  # Explicit always-safe destinations; avoid a remote round-trip for the
  # documented artifact readback pattern and agent-owned state.
  case "$_wd_path" in
    /tmp|/tmp/*|'~/.agents'|'~/.agents/'*|'$HOME/.agents'|'$HOME/.agents/'*) return 0 ;;
  esac

  if [ -n "$_wd_host" ]; then
    case "$_wd_path" in /*|'~/'*) ;; *) return 0 ;; esac
    if remote_primary_tree "$_wd_host" "$_wd_path"; then
      deny_reason="Blocked: $_wd_kind destination '$_wd_host:$_wd_path' is in the PRIMARY working tree of $_top${_cur:+ (branch '$_cur')}.

No agent may write into a user's primary checkout, locally or across machines.
Write to a linked worktree under <repo>/.agents/worktrees/<slug>/ instead."
      return 1
    else
      _wd_remote_rc=$?
    fi
    if [ "$_wd_remote_rc" -eq 2 ]; then
      deny_reason="Blocked: could not verify remote $_wd_kind destination '$_wd_host:$_wd_path'.

The primary-checkout guard fails closed when a remote destination cannot be
classified. Use /tmp, ~/.agents, or a linked .agents/worktrees path, or restore
fleet reachability and retry."
      return 1
    fi
    return 0
  fi

  case "$_wd_path" in
    '~/'*) _wd_path=${HOME}/${_wd_path#'~/'} ;;
    /*|[A-Za-z]:/*) ;;
    *) _wd_path=${cwd:-.}/$_wd_path ;;
  esac
  if [ -d "$_wd_path" ]; then _wd_dir=$_wd_path; else _wd_dir=$(dirname "$_wd_path"); fi
  while [ ! -d "$_wd_dir" ]; do
    _wd_next=$(dirname "$_wd_dir")
    [ "$_wd_next" = "$_wd_dir" ] && break
    _wd_dir=$_wd_next
  done
  [ -d "$_wd_dir" ] || return 0
  if in_primary_tree "$_wd_dir"; then
    set_deny_reason "$_wd_kind destination '$_wd_path'"
    return 1
  fi
  return 0
}

_mbg_var_get() { # $1=name -> prints value; rc 1 when unknown or tombstoned
  [ -n "$_MBG_VARS" ] || return 1
  _vg=$(printf '%s\n' "$_MBG_VARS" | awk -v n="$1" '
    index($0, n "=") == 1 { v = substr($0, length(n) + 2); found = 1 }
    END { if (found) printf "%s", v }')
  [ -n "$_vg" ] || return 1
  [ "$_vg" = "$_MBG_UNRESOLVED" ] && return 1
  printf '%s' "$_vg"
}

# _mbg_expand_leading_var <string> — substitute a LEADING `$NAME`/`${NAME}`
# from the recorded assignments, iterating so `WT=$REPO/sub` chains resolve.
# Prints the (possibly unchanged) string; rc 1 when a leading variable exists
# but cannot be resolved.
_mbg_expand_leading_var() {
  _ev=$1
  _evi=0
  while [ "$_evi" -lt 8 ]; do
    case "$_ev" in
      '${'*)
        _en=${_ev#'${'}
        _en=${_en%%\}*}
        _erest=${_ev#'${'"$_en"\}} ;;
      '$'*)
        _et=${_ev#'$'}
        _en=$(printf '%s' "$_et" | sed 's/[^A-Za-z0-9_].*$//')
        [ -n "$_en" ] || return 1
        _erest=${_et#"$_en"} ;;
      *)
        printf '%s' "$_ev"
        return 0 ;;
    esac
    _eval=$(_mbg_var_get "$_en") || return 1
    _ev="$_eval$_erest"
    _evi=$((_evi + 1))
  done
  return 1
}

# _mbg_note_assignment <segment> — record a segment that is a plain
# `NAME=value` assignment. rc 0 when the segment WAS an assignment (recorded
# or tombstoned — either way it is not a command to check); rc 1 otherwise.
_mbg_note_assignment() {
  _seg_a=$1
  case "$_seg_a" in
    [A-Za-z_]*=*) ;;
    *) return 1 ;;
  esac
  _an=${_seg_a%%=*}
  case "$_an" in *[!A-Za-z_0-9]*) return 1 ;; esac
  _av=${_seg_a#*=}
  case "$_av" in
    \"*\") _av=${_av#\"}; _av=${_av%\"} ;;
    \'*\') _av=${_av#\'}; _av=${_av%\'} ;;
  esac
  # cwd-equivalent substitutions (the worktree-recipe idiom): they evaluate to
  # the toplevel/cwd where the command runs, so resolve them to the session
  # cwd. This keeps `REPO=$(git rev-parse --show-toplevel); git -C "$REPO"
  # commit` in a primary checkout a DENY, not an unresolvable-allow.
  case "$_av" in
    '$(git rev-parse --show-toplevel)'|'$(pwd)')
      _mbg_var_record "$_an" "${cwd:-.}"
      return 0 ;;
  esac
  # A value that is ENTIRELY a command substitution (`X=$(anything)`, spaces
  # included) is a real assignment we cannot evaluate → tombstone, so a later
  # literal for the same name cannot leak through (last assignment wins).
  case "$_av" in
    '$('*')'|'`'*'`')
      _mbg_var_record "$_an" "$_MBG_UNRESOLVED"
      return 0 ;;
  esac
  # Any other value with whitespace is an env-prefixed command (`FOO=1 git …`,
  # `FOO=$(x) git commit …`) — NOT a plain assignment segment; leave it to
  # check_segment's prefix stripping so the command itself is still checked.
  case "$_av" in *[[:space:]]*) return 1 ;; esac
  case "$_av" in
    *'$('*|*'`'*)
      _mbg_var_record "$_an" "$_MBG_UNRESOLVED"
      return 0 ;;
  esac
  if _avx=$(_mbg_expand_leading_var "$_av"); then
    _av=$_avx
  else
    _mbg_var_record "$_an" "$_MBG_UNRESOLVED"
    return 0
  fi
  case "$_av" in
    *'$'*) _mbg_var_record "$_an" "$_MBG_UNRESOLVED" ;;
    *)     _mbg_var_record "$_an" "$_av" ;;
  esac
  return 0
}

# _mbg_strip_heredoc_bodies — drop TERMINATED heredoc bodies from a command
# string so body lines are never parsed as commands (a heredoc body is data;
# splitting it into segments produced false `git …` matches). Conservative:
# an unterminated heredoc keeps its lines (fail toward the old behavior), and
# here-strings (`<<<`) are neutralized before scanning.
_mbg_strip_heredoc_bodies() {
  awk '
    BEGIN { tag = ""; nbuf = 0; q = sprintf("%c", 39); dq = "\"" }
    function flushbuf(  i) { for (i = 1; i <= nbuf; i++) print buf[i]; nbuf = 0 }
    {
      if (tag != "") {
        line = $0
        if (strip_tabs) sub(/^\t+/, "", line)
        if (line == tag) { tag = ""; nbuf = 0; next }
        nbuf++; buf[nbuf] = $0
        next
      }
      scan = $0
      gsub(/<<</, " ", scan)
      re = "<<-?[ \t]*[" dq q "]?[A-Za-z_][A-Za-z_0-9]*"
      if (match(scan, re)) {
        # Quote parity: a << inside an open quote on this line (echo "x <<EOF")
        # is string data, not a heredoc opener. Odd count of preceding quotes
        # -> skip; the line (and what follows) keeps the old conservative
        # parse instead of being swallowed into a phantom body.
        pre = substr(scan, 1, RSTART - 1)
        t1 = pre; ndq = gsub(dq, "&", t1)
        t2 = pre; nsq = gsub("[" q "]", "&", t2)
        if (ndq % 2 == 0 && nsq % 2 == 0) {
          m = substr(scan, RSTART, RLENGTH)
          strip_tabs = (substr(m, 3, 1) == "-")
          sub(/^<<-?[ \t]*/, "", m)
          gsub("[" dq q "]", "", m)
          tag = m
        }
      }
      print
    }
    END { flushbuf() }
  '
}

# Resolve the repo dir a git segment operates on: the `-C <path>` argument if
# present (relative resolves against cwd), else the session cwd.
resolve_repo_dir() {
  _cpath=$1
  case "$_cpath" in *\\*) _cpath=$(printf '%s' "$_cpath" | tr '\\' '/') ;; esac
  if [ -n "$_cpath" ]; then
    case "$_cpath" in
      /*|[A-Za-z]:/*) printf '%s' "$_cpath" ;;
      *)  printf '%s' "${cwd:-.}/$_cpath" ;;
    esac
  else
    printf '%s' "${cwd:-.}"
  fi
}

set_worktree_deny() {
  # $1 = new branch name (may be empty), $2 = what's wrong with the base.
  _bn=${1:-<slug>}
  deny_reason="Blocked: creating worktree branch '$_bn' from $2.

A new-branch worktree must be based on a freshly-fetched remote-tracking ref, not
a local or implicit base — a local default branch can be stale, so you'd branch
off an old commit. Fetch first and base off origin/<default>:
  REPO=\$(git rev-parse --show-toplevel)
  git -C \"\$REPO\" fetch origin
  BASE=\$(git -C \"\$REPO\" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
  git -C \"\$REPO\" worktree add -b $_bn \"\$REPO/.agents/worktrees/$_bn\" \"origin/\$BASE\""
}

# _file_mtime_epoch <path> — portable mtime as unix seconds (GNU + BSD stat).
_file_mtime_epoch() {
  # GNU coreutils first, then BSD/macOS.
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo ""
}

# check_remote_ref_freshness <repo> <symbolic-full-name> <base-label> <newbr>
# After the base has passed the refs/remotes/* form check, require that the
# remote-tracking ref (or FETCH_HEAD) was refreshed recently. Default max age
# is 900s (15m); override with AGENTS_WORKTREE_FETCH_MAX_AGE_SEC. Set to 0 to
# disable the age check (form-only). Does NOT network-fetch here — that belongs
# in the agent recipe / createWorktree, not inside PreToolUse.
check_remote_ref_freshness() {
  _fr_repo=$1
  _fr_full=$2
  _fr_label=$3
  _fr_newbr=$4
  _max_age=${AGENTS_WORKTREE_FETCH_MAX_AGE_SEC:-900}
  # Non-numeric or empty → default. 0 disables (tests / offline deliberate).
  case "$_max_age" in
    ''|*[!0-9]*) _max_age=900 ;;
  esac
  [ "$_max_age" -eq 0 ] && return 0

  _check_path=""
  # Paths from `rev-parse --git-path` are relative to the *process cwd*, not the
  # repo — resolve absolute or the age check looks at the wrong file (or none).
  _ref_path=$(git -C "$_fr_repo" rev-parse --path-format=absolute --git-path "$_fr_full" 2>/dev/null) \
    || _ref_path=""
  if [ -n "$_ref_path" ] && [ -f "$_ref_path" ]; then
    _check_path=$_ref_path
  else
    # Packed-refs or missing loose file → FETCH_HEAD is the last-fetch stamp.
    _fh=$(git -C "$_fr_repo" rev-parse --path-format=absolute --git-path FETCH_HEAD 2>/dev/null) \
      || _fh=""
    if [ -n "$_fh" ] && [ -f "$_fh" ]; then
      _check_path=$_fh
    fi
  fi
  # Cannot determine age → form already required origin/*; fail open on age only.
  [ -z "$_check_path" ] && return 0

  _mtime=$(_file_mtime_epoch "$_check_path")
  [ -z "$_mtime" ] && return 0
  _now=$(date +%s)
  _age=$((_now - _mtime))
  # Clock skew / future mtime: treat as fresh.
  [ "$_age" -lt 0 ] && return 0
  if [ "$_age" -gt "$_max_age" ]; then
    set_worktree_deny "$_fr_newbr" \
      "a stale remote-tracking ref '$_fr_label' (last refreshed ${_age}s ago; max ${_max_age}s — run git fetch origin first)"
    return 1
  fi
  return 0
}

# check_worktree_base <repo> <args-after-`worktree`...> — check NEW-branch worktree
# creation so the branch is based on a freshly-fetched remote-tracking ref
# (origin/<default>), never an implicit HEAD or a local branch (either can be a
# stale default branch — the "worktree-ing off a stale local commit" trap). Only
# `worktree add -b/-B` (new branch) is checked; materializing an existing ref
# (`worktree add <path> <ref>` without -b) and `worktree list/remove/...` pass.
check_worktree_base() {
  _wrepo=$1; shift
  [ "${1:-}" = "add" ] || return 0
  shift
  _creating=0
  _newbr=""
  _wbase=""
  _npos=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -b|-B)     _creating=1; shift; [ $# -gt 0 ] && { _newbr=$1; shift; } ;;
      -b?*|-B?*) _creating=1; _newbr=${1#-[bB]}; shift ;;   # glued `-bNAME` / `-BNAME`
      --reason)  shift; [ $# -gt 0 ] && shift ;;  # `--lock --reason <str>`
      --)        shift
                 [ $# -gt 0 ] && shift            # <path>
                 [ $# -gt 0 ] && _wbase=$1        # [<commit-ish>]
                 break ;;
      -*)        shift ;;                         # --force/--detach/--checkout/...
      *)         _npos=$((_npos + 1))
                 if [ "$_npos" -eq 1 ]; then shift; else _wbase=$1; shift; fi ;;
    esac
  done
  # Only new-branch creation is base-sensitive.
  [ "$_creating" -eq 1 ] || return 0

  if [ -z "$_wbase" ]; then
    set_worktree_deny "$_newbr" "an implicit base (current HEAD)"
    return 1
  fi
  # Canonicalize the base to its full ref name so all of git's idiomatic forms
  # classify identically: bare `trunk`, `heads/trunk`, `refs/heads/trunk` all
  # resolve to refs/heads/trunk (local); `origin/x`, `refs/remotes/origin/x` to
  # refs/remotes/... A raw SHA / tag has no branch ref -> deliberate, allow.
  _full=$(git -C "$_wrepo" rev-parse --symbolic-full-name "$_wbase" 2>/dev/null) || _full=""
  case "$_full" in
    refs/remotes/*)                       # remote form — then require recent fetch
      check_remote_ref_freshness "$_wrepo" "$_full" "$_wbase" "$_newbr"
      return $? ;;
    refs/heads/*)                         # local branch — the stale trap we're closing
      set_worktree_deny "$_newbr" "the local branch '$_wbase'"
      return 1 ;;
    *)                                    # raw SHA / tag / unresolved — deliberate, allow
      return 0 ;;
  esac
}

# WHERE policy: given a git subcommand and its args (git-parse has stripped the
# sh -c wrapper, env prefix, quotes, and git's global flags, and captured any
# `-C <path>` into GIT_C_PATH), block `git commit|add|stage` aimed at the primary
# working tree and vet `git worktree add -b/-B`. Invoked by git_scan_segment.
git_on_command() {
  _sub=$1
  shift

  # Expand a leading `$NAME`/`${NAME}` in the -C target from assignments seen
  # earlier in this command string (RUSH-2743). If a `$` survives, the target
  # is unresolvable — the checks below must fail toward the PARSED target,
  # never fall back to the session cwd.
  cpath=$GIT_C_PATH
  _c_unres=0
  case "$cpath" in
    *'$'*)
      if _cpx=$(_mbg_expand_leading_var "$cpath"); then
        cpath=$_cpx
        case "$cpath" in *'$'*) _c_unres=1 ;; esac
      else
        _c_unres=1
      fi ;;
  esac

  case "$_sub" in
    commit|add|stage)
      # RUSH-2743: an explicit -C target that is unresolvable or nonexistent
      # never falls back to the session cwd. Before this rule, the
      # nearest-existing-ancestor walk in git_facts_load collapsed
      # `<cwd>/$REPO` to the cwd itself and blamed the primary tree for a
      # commit aimed at a linked worktree. git errors on a bogus -C, so
      # nothing can be mutated — allow.
      [ "$_c_unres" -eq 1 ] && return 0
      _repo=$(resolve_repo_dir "$cpath")
      if [ -n "$cpath" ] && [ ! -d "$_repo" ]; then
        return 0
      fi
      if in_primary_tree "$_repo"; then
        set_deny_reason "\`git $_sub\`"
        return 1
      fi
      return 0
      ;;
    worktree)
      _repo=$(resolve_repo_dir "$cpath")
      check_worktree_base "$_repo" "$@"
      return $?
      ;;
    *) return 0 ;;
  esac
  return 0
}

# Check one already-split segment: unwrap an `sh|bash -c` wrapper (recurse), else
# hand the segment to the shared git-parse reducer, which dispatches any git
# invocation to git_on_command above.
check_segment() {
  if git_extract_sh_c_inner "$1"; then
    check_command_string "$_dash_c_inner"
    return
  fi
  if git_extract_remote_inner "$1"; then
    _saved_remote=${WRITE_REMOTE_HOST:-}
    _saved_dest_cwd=${WRITE_DEST_CWD:-}
    WRITE_REMOTE_HOST=$_remote_host
    WRITE_DEST_CWD='~'
    check_command_string "$_remote_inner"
    _remote_rc=$?
    WRITE_REMOTE_HOST=$_saved_remote
    WRITE_DEST_CWD=$_saved_dest_cwd
    return "$_remote_rc"
  fi
  write_scan_segment "$1" || return $?
  # Git WHERE checks are local today. Remote direct writes are covered above;
  # a remote agent is independently guarded when dispatched through the fleet.
  [ -n "${WRITE_REMOTE_HOST:-}" ] && return 0
  git_scan_segment "$1"
}

check_command_string() {
  _input=$1
  # Heredoc bodies are data, not commands — drop terminated ones before the
  # segment split so body lines never parse as `git …` segments (RUSH-2743).
  case "$_input" in
    *'<<'*) _input=$(printf '%s\n' "$_input" | _mbg_strip_heredoc_bodies) ;;
  esac
  IFS=$(printf ' \t\n.'); IFS=${IFS%.}
  OLDIFS=$IFS
  IFS='
'
  for seg in $(git_split_chains "$_input"); do
    seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$seg" ] && continue
    # A plain `NAME=value` segment feeds later `-C "$NAME"` resolution; it is
    # not itself a command to check (RUSH-2743).
    if _mbg_note_assignment "$seg"; then continue; fi
    if ! check_segment "$seg"; then
      IFS=$OLDIFS
      return 1
    fi
  done
  IFS=$OLDIFS
  return 0
}

WRITE_DEST_CWD=${cwd:-.}
if ! check_command_string "$cmd"; then
  printf '%s\n' "$deny_reason" >&2
  exit 2
fi
exit 0
