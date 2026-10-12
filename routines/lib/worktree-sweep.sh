#!/bin/sh
# Reclaim PR-bound agent worktrees whose work has landed (PHNX-3503).
#
# Invoked by routines/worktree-sweep.yml. A separate script, not an inline
# `command:` block, because this is destructive: review found FIVE ways the
# earlier versions could delete work they existed to protect or silently do
# nothing. Untestable inline shell is how that recurs, so the logic lives here
# and routines/lib/tests/worktree-sweep_test.sh drives it against real repos.
#
# STRICTLY POSIX — no arrays, no `[[`, no process substitution. `command:`
# routines execute via `/bin/sh -c`, and /bin/sh is dash on the Linux boxes:
#
#   $ /bin/sh -c 'while read x; do :; done < <(printf "a\n")'
#   Syntax error: redirection unexpected
#
# An earlier revision used exactly that and would have aborted before touching a
# single repo — the routine had never worked on any box. A pipe into `while` is
# NOT the fix either: POSIX runs the loop body in a subshell, so the counters
# would be discarded and the summary would always print 0, which is the same
# silent-zero class of bug. The list is materialised through a temp file.
# `sh -n` AND `bash -n` must both stay clean, and the tests run it under both.
#
# NOT a CLI command, deliberately. The agents surface is already 79 top-level /
# 549 total commands and this is maintenance no human types. It can be plain git
# because a command routine runs from the daemon as `/bin/sh -c` with "no agent
# binary, no rotation, no sandbox" (cli/src/lib/daemon/runner.ts:881) — it never
# passes a PreToolUse hook, so git-guard's `git branch -d/-D` deny does not
# apply. That deny stops an AGENT picking branches to delete; here the branch is
# picked by the merge. Agents gain no permission and no command.
#
# An idle worktree that still holds work (uncommitted changes, or commits not on
# the default branch) is PARKED rather than held forever: its work is saved to
# refs/wip/<name> in the repo and the checkout is removed. Idle means no process
# has its working directory inside it and nothing in it changed for --grace-days.
#
# Usage: worktree-sweep.sh [--grace-days N] [--dry-run] [--home DIR]
set -u

GRACE_DAYS=3
DRY_RUN=0
SEARCH_HOME=$HOME

while [ $# -gt 0 ]; do
  case $1 in
    --grace-days) GRACE_DAYS=${2:-3}; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --home)       SEARCH_HOME=${2:-$HOME}; shift 2 ;;
    *) echo "worktree-sweep: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

now=$(date +%s)
swept=0
parked=0
held=0

wtlist=$(mktemp) && cwds=$(mktemp) && changed=$(mktemp) && parkidx=$(mktemp) ||
  { echo "could not create temp file — skipping"; exit 0; }
trap 'rm -f "$wtlist" "$cwds" "$changed" "$parkidx"' EXIT INT TERM

# The ref to compare against: origin/HEAD, else origin/main|master. With no
# default ref every worktree is indeterminate and nothing is removed.
default_ref() {
  r=$(git -C "$1" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null) &&
    [ -n "$r" ] && { printf '%s' "$r"; return 0; }
  for c in origin/main origin/master; do
    if git -C "$1" rev-parse --verify --quiet "$c" >/dev/null 2>&1; then
      printf '%s' "$c"; return 0
    fi
  done
  return 1
}

mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# The working directory of every process this user can see, one per line. A
# process sitting inside a worktree (an agent's shell, a dev server, a test run)
# is the strongest "in use" signal there is, and it holds no matter how long the
# files have been untouched: an agent can idle for days between turns.
snapshot_cwds() {
  if [ -d /proc/self ]; then
    for _p in /proc/[0-9]*; do readlink "$_p/cwd" 2>/dev/null; done > "$cwds"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' > "$cwds"
  else
    : > "$cwds"
  fi
}
# Exact path or a path below it: `fix-110` must not claim a shell in `fix-1103`.
in_use() { awk -v p="$1" '$0 == p || index($0, p "/") == 1 { f = 1 } END { exit !f }' "$cwds"; }

# Newest moment anyone touched this worktree: the directory itself, a commit or
# checkout (the per-worktree HEAD, its reflog, ORIG_HEAD) and every changed or
# untracked path. The worktree directory's own mtime alone moves only when a
# top-level entry is added or removed, so an agent editing src/ for a week read
# as idle. `index` is left out on purpose: `git status`, including this sweep's
# own, rewrites it, which would make every worktree look touched every night.
last_activity() {
  _wt=$1
  _new=$(mtime_of "$_wt") || return 1
  _gd=$(git -C "$_wt" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  for _f in "$_gd/HEAD" "$_gd/logs/HEAD" "$_gd/ORIG_HEAD"; do
    [ -e "$_f" ] || continue
    _m=$(mtime_of "$_f") && [ "$_m" -gt "$_new" ] && _new=$_m
  done
  git -C "$_wt" status --porcelain 2>/dev/null > "$changed" || return 1
  while IFS= read -r _l; do
    _p=${_l#???}; _p=${_p#\"}; _p=${_p%\"}
    case $_p in *' -> '*) _p=${_p#* -> } ;; esac
    [ -e "$_wt/$_p" ] || continue
    _m=$(mtime_of "$_wt/$_p") && [ "$_m" -gt "$_new" ] && _new=$_m
  done < "$changed"
  printf '%s' "$_new"
}

# Every reason a worktree must be left exactly as it is, `park:<why>` when it is
# idle but still holds work, or empty when its work has landed. Fails CLOSED: an
# unreadable status or an undeterminable merge state is a blocker, never a pass.
# An index.lock held by a live agent lands exactly there — on the tree most
# likely to be holding work.
#
# Merge is judged by patch-id (`git cherry`), NOT ancestry: this fleet
# rebase-merges, so a landed branch's SHAs are rewritten and
# `merge-base --is-ancestor` reports NOT merged for work that fully landed — an
# ancestry gate would reclaim nothing at all. Patch-id also subsumes the unpushed
# check, since an unpushed commit has no upstream equivalent.
blockers_for() {
  _wt=$1; _ref=$2; _grace=$3
  in_use "$_wt" && { printf '%s' 'in-use'; return; }
  _last=$(last_activity "$_wt") || { printf '%s' 'activity-unreadable'; return; }
  [ $(( (now - _last) / 86400 )) -lt "$_grace" ] && { printf '%s' 'within-grace'; return; }
  if ! _st=$(git -C "$_wt" status --porcelain 2>/dev/null); then
    printf '%s' 'status-unreadable'; return
  fi
  if [ -n "$_st" ]; then
    # Parking stores the changes as git objects; a tree this large is almost
    # always build output nobody ignored, and copying it into .git defeats the
    # point of reclaiming the disk.
    [ "$(printf '%s\n' "$_st" | wc -l)" -gt 2000 ] && { printf '%s' 'too-many-changes-to-park'; return; }
    printf '%s' 'park:uncommitted-changes'; return
  fi
  if ! _ch=$(git -C "$_wt" cherry "$_ref" HEAD 2>/dev/null); then
    printf '%s' 'merge-state-unknown'; return
  fi
  if [ -n "$_ch" ] && [ "$(printf '%s\n' "$_ch" | grep -c '^+')" -ne 0 ]; then
    printf '%s' 'park:unmerged-commits'; return
  fi
  printf '%s' ''
}

# Snapshot an idle worktree's work into refs/wip/<name> in the repo and print the
# ref. Uncommitted and untracked (not ignored) files become one commit on top of
# HEAD, built in a throwaway index so neither the branch nor the worktree's own
# index moves. The ref lives in the shared object store, so it outlives the
# checkout, is never pushed, and `git worktree add <path> refs/wip/<name>` brings
# the work back. Ignored files are not kept: by definition they are build output.
# The tree the worktree holds right now, tracked edits and untracked files
# included, written through a throwaway index.
worktree_tree() {
  rm -f "$parkidx"
  GIT_INDEX_FILE=$parkidx git -C "$1" read-tree HEAD 2>/dev/null &&
    GIT_INDEX_FILE=$parkidx git -C "$1" add -A . 2>/dev/null &&
    GIT_INDEX_FILE=$parkidx git -C "$1" write-tree 2>/dev/null
}

park() {
  _repo=$1; _wt=$2; _name=$3
  _head=$(git -C "$_wt" rev-parse -q --verify HEAD 2>/dev/null) || return 1
  _tip=$_head
  if [ -n "$(git -C "$_wt" status --porcelain 2>/dev/null)" ]; then
    _tree=$(worktree_tree "$_wt") || return 1
    _tip=$(git -C "$_wt" -c user.name=worktree-sweep -c user.email=worktree-sweep@localhost \
      commit-tree "$_tree" -p "$_head" \
      -m "wip: $_name, parked by worktree-sweep on $(hostname -s 2>/dev/null) $(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null) || return 1
  fi
  _wipref="refs/wip/$_name"
  git -C "$_repo" rev-parse -q --verify "$_wipref" >/dev/null 2>&1 && _wipref="$_wipref-$now"
  git -C "$_repo" update-ref "$_wipref" "$_tip" 2>/dev/null || return 1
  # The ref must hold exactly the tree just read, or the removal below would lose
  # whatever differs.
  [ "$(git -C "$_repo" rev-parse "$_wipref^{tree}" 2>/dev/null)" = "$(git -C "$_repo" rev-parse "$_tip^{tree}" 2>/dev/null)" ] || return 1
  printf '%s' "$_wipref"
}

sweep_repo() {
  repo=$1
  ref=$(default_ref "$repo") || { echo "skip (no default ref): $repo"; return 0; }
  wtdir="$repo/.agents/worktrees"
  [ -d "$wtdir" ] || return 0

  for wt in "$wtdir"/*/; do
    [ -d "$wt" ] || continue
    wt=${wt%/}
    name=$(basename "$wt")

    # Never the primary checkout. An exact compare, not a prefix test — the CLI
    # version used cwd.startsWith(path), so `fix-110` matched `fix-1103` and it
    # reclaimed a worktree nobody named.
    [ "$wt" = "$repo" ] && continue

    # Only sweep paths git still registers as worktrees of this repo.
    git -C "$repo" worktree list --porcelain 2>/dev/null |
      grep -qxF "worktree $wt" || continue

    reason=$(blockers_for "$wt" "$ref" "$GRACE_DAYS")
    case $reason in
      ''|park:*) ;;
      *)
        held=$((held + 1))
        [ "$DRY_RUN" = 1 ] && echo "held ($reason): $name"
        continue ;;
    esac

    if [ "$DRY_RUN" = 1 ]; then
      case $reason in
        park:*) echo "would park (${reason#park:}): $name"; parked=$((parked + 1)) ;;
        *)      echo "would reclaim: $name"; swept=$((swept + 1)) ;;
      esac
      continue
    fi

    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)

    # RE-READ immediately before mutating, never from the check above. A box with
    # 136 worktrees takes minutes; an agent that COMMITS mid-sweep leaves a clean
    # tree, and a stale "0 unmerged" would then authorise `branch -D` and destroy
    # that commit. The process list is re-read too: an agent may have cd'd in.
    snapshot_cwds
    again=$(blockers_for "$wt" "$ref" "$GRACE_DAYS")
    if [ "$again" != "$reason" ]; then
      held=$((held + 1))
      echo "held (changed during sweep: ${again:-landed}): $name"
      continue
    fi

    case $reason in
      park:*)
        if ! wipref=$(park "$repo" "$wt" "$name"); then
          held=$((held + 1)); echo "held (could not park): $name"; continue
        fi
        # Last look after the snapshot: anything written since would not be in
        # the ref, so the checkout stays (the ref is harmless and kept).
        snapshot_cwds
        if [ "$(blockers_for "$wt" "$ref" "$GRACE_DAYS")" != "$reason" ] ||
           [ "$(worktree_tree "$wt")" != "$(git -C "$repo" rev-parse "$wipref^{tree}" 2>/dev/null)" ]; then
          held=$((held + 1)); echo "held (changed while parking, kept $wipref): $name"; continue
        fi
        # --force only because the tree may be dirty; every byte of it is in the
        # ref, checked against the live tree just above. The branch is not touched.
        if git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1; then
          echo "parked: $name -> $wipref ($repo)"
          parked=$((parked + 1))
        else
          held=$((held + 1)); echo "held (git refused removal, kept $wipref): $name"
        fi
        continue ;;
    esac

    # No --force, so git refuses a tree with uncommitted changes. That is NOT an
    # independent check on the thing that matters: worktree removal does not look
    # at the commit graph, so a branch carrying an unmerged commit is removed
    # without complaint as long as the tree is clean (verified in review). The
    # remaining window is an agent COMMITTING between the re-read above and this
    # call, which leaves a clean tree and would let the deletion below destroy it.
    if git -C "$repo" worktree remove "$wt" >/dev/null 2>&1; then
      # FINAL proof, taken after the worktree is gone so no further commit can
      # land on it, and read from the BRANCH ref (which survives removal). Only a
      # branch still provably patch-equivalent upstream is deleted; anything else
      # is kept as a recoverable ref and reported.
      if [ "$branch" != "HEAD" ]; then
        if final=$(git -C "$repo" cherry "$ref" "$branch" 2>/dev/null) &&
           { [ -z "$final" ] || [ "$(printf '%s\n' "$final" | grep -c '^+')" -eq 0 ]; }; then
          # The plain delete refuses a rebase-merged branch (it tests
          # reachability and the SHAs were rewritten), so fall back to the forced
          # form — only here, where patch-id has just re-proven the work landed.
          git -C "$repo" branch -d "$branch" >/dev/null 2>&1 ||
            git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
        else
          echo "kept branch (gained unmerged commits during sweep): $branch"
        fi
      fi
      echo "reclaimed: $name ($repo)"
      swept=$((swept + 1))
    else
      echo "held (git refused removal): $name"
      held=$((held + 1))
    fi
  done
  git -C "$repo" worktree prune >/dev/null 2>&1 || true
}

# Which repos this routine may touch, as extended-regex patterns matched against
# `remote.origin.url`. Defaults to the orgs this fleet manages; override or extend
# with ~/.agents/worktree-sweep.allow (one pattern per line). Anything unmatched is
# reported and never swept, so a personal or vendored checkout is safe by default.
allowfile=$(mktemp) || { echo "could not create temp file — skipping"; exit 0; }
trap 'rm -f "$wtlist" "$cwds" "$changed" "$parkidx" "$allowfile"' EXIT INT TERM
if [ -f "$HOME/.agents/worktree-sweep.allow" ]; then
  cat "$HOME/.agents/worktree-sweep.allow" > "$allowfile"
else
  # ANCHORED to host + exact org. An unanchored '[:/]org/' matches the org as ANY
  # path segment, so `https://gitlab.example.com/mirror-of/phnx-labs/x.git` — an
  # unrelated host where phnx-labs is a nested directory — passed the gate and was
  # swept (demonstrated in review). Match the three real remote spellings only.
  printf '%s\n' \
    '^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)phnx-labs/' \
    '^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)muqsitnawaz/' > "$allowfile"
fi

# DISCOVER the worktree containers; do not guess roots. Measured on yosemite-s1
# (2026-08-30), a hardcoded list of $HOME/{src,workspaces,fleet-base,fleet-work}
# found 14 containers where discovery finds 82 — and three of those four roots
# do not exist anywhere on this fleet. The remainder live under
# $HOME/.agents/repos, $HOME/.agents/.system, $HOME/agents-cli, $HOME/svatlas
# and $HOME itself. Sweeping 17% of the leak would read as success while the
# disk kept filling. Pruning the heavy dirs keeps this ~0.9s across a 3.7T home.
find "$SEARCH_HOME" -maxdepth 7 \
  \( -name node_modules -o -name .cache -o -name .npm -o -name .bun \
     -o -name Library -o -name .venv -o -name dist -o -name target \) -prune -o \
  -type d -path '*/.agents/worktrees' -print > "$wtlist" 2>/dev/null

snapshot_cwds
while IFS= read -r wtdir; do
  repo=$(dirname "$(dirname "$wtdir")")
  # `.git` is a DIRECTORY in a normal checkout but a FILE inside a linked
  # worktree, so test existence, not directory-ness, or nested cases are skipped.
  [ -e "$repo/.git" ] || continue

  # Discovery matches directory SHAPE, not "a repo this fleet manages", so
  # without a gate a nightly destructive job reaches ANY checkout using worktree
  # law — which this repo's own rule makes the universal agent convention, not a
  # fleet-specific one. Proven on this box: discovery finds
  # $HOME/.agents (muqsitnawaz/.agents, a personal config repo) and its 48-day-old
  # `blog-engine` worktree. The old hardcoded roots avoided that by accident, so
  # widening coverage without this gate would be a REGRESSION in blast radius.
  #
  # An opt-out marker is the wrong default for a destructive job: it deletes
  # first in anything nobody thought to mark. This is an ALLOWLIST — a repo is
  # swept only if its origin matches, everything else is reported and left alone.
  origin_url=$(git -C "$repo" config --get remote.origin.url 2>/dev/null || echo '')
  if [ -z "$origin_url" ]; then
    echo "skip (no origin): $repo"; continue
  fi
  # DotAgents config repos are hand-managed and their worktrees are not build
  # output; never sweep them even though they match the org allowlist.
  case $origin_url in
    */.agents|*/.agents.git|*/.agents-system|*/.agents-system.git)
      echo "skip (DotAgents config repo): $repo"; continue ;;
  esac
  if ! printf '%s\n' "$origin_url" | grep -qEf "$allowfile" 2>/dev/null; then
    echo "skip (origin not in allowlist): $repo"; continue
  fi
  # Belt and braces on top of the allowlist, for a repo that is in scope but that
  # someone wants left alone.
  [ -e "$repo/.no-worktree-sweep" ] && { echo "skip (opted out): $repo"; continue; }

  sweep_repo "$repo"
done < "$wtlist"

echo "worktree-sweep on $(hostname -s 2>/dev/null || echo unknown): reclaimed=$swept parked=$parked held=$held"
