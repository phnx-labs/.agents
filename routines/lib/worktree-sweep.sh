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
held=0

wtlist=$(mktemp) || { echo "could not create temp file — skipping"; exit 0; }
trap 'rm -f "$wtlist"' EXIT INT TERM

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

# Every reason a worktree is NOT reclaimable, or empty when it is. Fails CLOSED:
# an unreadable status or an undeterminable merge state is a blocker, never a
# pass. An index.lock held by a live agent lands exactly there — on the tree most
# likely to be holding work.
#
# Merge is judged by patch-id (`git cherry`), NOT ancestry: this fleet
# rebase-merges, so a landed branch's SHAs are rewritten and
# `merge-base --is-ancestor` reports NOT merged for work that fully landed — an
# ancestry gate would reclaim nothing at all. Patch-id also subsumes the unpushed
# check, since an unpushed commit has no upstream equivalent.
blockers_for() {
  _wt=$1; _ref=$2; _grace=$3
  _mt=$(mtime_of "$_wt") || { printf '%s' 'age-unreadable'; return; }
  _age=$(( (now - _mt) / 86400 ))
  [ "$_age" -lt "$_grace" ] && { printf '%s' 'within-grace'; return; }
  if ! _st=$(git -C "$_wt" status --porcelain 2>/dev/null); then
    printf '%s' 'status-unreadable'; return
  fi
  [ -n "$_st" ] && { printf '%s' 'uncommitted-changes'; return; }
  if ! _ch=$(git -C "$_wt" cherry "$_ref" HEAD 2>/dev/null); then
    printf '%s' 'merge-state-unknown'; return
  fi
  if [ -n "$_ch" ] && [ "$(printf '%s\n' "$_ch" | grep -c '^+')" -ne 0 ]; then
    printf '%s' 'unmerged-commits'; return
  fi
  printf '%s' ''
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
    if [ -n "$reason" ]; then
      held=$((held + 1))
      [ "$DRY_RUN" = 1 ] && echo "held ($reason): $name"
      continue
    fi

    if [ "$DRY_RUN" = 1 ]; then
      echo "would reclaim: $name"
      swept=$((swept + 1))
      continue
    fi

    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)

    # RE-READ immediately before mutating, never from the check above. A box with
    # 136 worktrees takes minutes; an agent that COMMITS mid-sweep leaves a clean
    # tree, and a stale "0 unmerged" would then authorise `branch -D` and destroy
    # that commit.
    reason=$(blockers_for "$wt" "$ref" "$GRACE_DAYS")
    if [ -n "$reason" ]; then
      held=$((held + 1))
      echo "held (changed during sweep: $reason): $name"
      continue
    fi

    # No --force: git's own refusal is a second, independent opinion.
    if git -C "$repo" worktree remove "$wt" >/dev/null 2>&1; then
      # `-d` refuses a rebase-merged branch (it tests reachability and the SHAs
      # were rewritten), so fall back to `-D` — only here, where patch-id has
      # just proven the work landed.
      if [ "$branch" != "HEAD" ]; then
        git -C "$repo" branch -d "$branch" >/dev/null 2>&1 ||
          git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
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
trap 'rm -f "$wtlist" "$allowfile"' EXIT INT TERM
if [ -f "$HOME/.agents/worktree-sweep.allow" ]; then
  cat "$HOME/.agents/worktree-sweep.allow" > "$allowfile"
else
  printf '%s\n' \
    '[:/]phnx-labs/' \
    '[:/]muqsitnawaz/' > "$allowfile"
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

echo "worktree-sweep on $(hostname -s 2>/dev/null || echo unknown): reclaimed=$swept held=$held"
