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
# A tree is never touched while an agent may be using it: a live process inside
# it, any change in it or a transcript naming it within the grace window, or a
# `.agents-keep` file in it. With --preserve, a stale tree holding work that
# exists nowhere else is pushed to wip/<host>/<name> as a draft PR first, and one
# whose commits are all on origin loses only its local copy.
#
# Usage: worktree-sweep.sh [--grace-days N] [--dry-run] [--preserve] [--home DIR]
set -u

GRACE_DAYS=3
DRY_RUN=0
PRESERVE=0
SEARCH_HOME=$HOME

while [ $# -gt 0 ]; do
  case $1 in
    --grace-days) GRACE_DAYS=${2:-3}; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --preserve)   PRESERVE=1; shift ;;
    --home)       SEARCH_HOME=${2:-$HOME}; shift 2 ;;
    *) echo "worktree-sweep: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

now=$(date +%s)
swept=0
held=0

host=$(hostname -s 2>/dev/null || echo unknown)
wtlist=$(mktemp) && livefile=$(mktemp) && transcripts=$(mktemp) && reasons=$(mktemp) &&
  gracestamp=$(mktemp) && scratch=$(mktemp) || { echo "could not create temp file — skipping"; exit 0; }
trap 'rm -f "$wtlist" "$livefile" "$transcripts" "$reasons" "$gracestamp" "$scratch"' EXIT INT TERM

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

# touch -t takes local [[CC]YY]MMDDhhmm[.SS] on both GNU and BSD; only the epoch
# conversion differs (date -d @N on GNU, date -r N on BSD/macOS).
stamp_at() { # <file> <epoch>
  _t=$(date -d "@$2" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$2" +%Y%m%d%H%M.%S 2>/dev/null) || return 1
  touch -t "$_t" "$1"
}

# `git status` refreshes the index when stat data changed and WRITES it, which
# bumps the index mtime — the activity signal below. Every read here passes
# --no-optional-locks so the sweep never makes a tree look freshly used.
gitr() { git --no-optional-locks "$@"; }

# Whether anything in the tree or its git dir changed since <stamp>: an edit, a
# `git add` (index), a commit (HEAD, logs). The directory's own mtime, which this
# used to read, moves only when an entry directly under it is added or removed,
# so a tree being edited every hour read as 30 days idle.
changed_since() { # <wt> <gitdir> <stamp>
  [ -n "$(find "$1" "$2" \( -name node_modules -o -name .next -o -name dist -o -name target \
            -o -name .venv \) -prune -o -newer "$3" -print 2>/dev/null | head -n 1)" ]
}

# Processes whose working directory is inside a worktree. An agent idle for hours
# or days still has its harness process sitting in the tree, so this — not the age
# — is what protects an open session. Linux reads /proc; macOS has no /proc, so lsof.
list_live_cwds() {
  if [ -d /proc/self ]; then
    for _p in /proc/[0-9]*; do readlink "$_p/cwd" 2>/dev/null; done
  else
    lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
  fi
}
refresh_live() { list_live_cwds | sort -u > "$livefile"; }
has_live_process() { # <wt>
  awk -v p="$1/" 'index($0 "/", p) == 1 { f = 1 } END { exit !f }' "$livefile"
}

# Agent transcripts written within the grace window. An agent that works on a tree
# by absolute path from elsewhere (git -C, editing by full path) never has its
# cwd there, but its transcript names the path. Over-matching (fix-110 also
# matches a mention of fix-1103) only ever HOLDS a tree, never frees one.
list_recent_transcripts() {
  for _d in "$SEARCH_HOME/.agents/.history" "$SEARCH_HOME/.claude/projects" "$SEARCH_HOME/.codex/sessions"; do
    [ -e "$_d" ] && find -H "$_d" -type f -newer "$gracestamp" 2>/dev/null
  done | sort -u
}
mentioned_recently() { # <wt>
  [ -s "$transcripts" ] || return 1
  # tr turns the list into NUL-separated paths so names with spaces survive xargs.
  # Tested on output, not exit status: xargs fails if ANY batch has no match.
  [ -n "$(tr '\n' '\0' < "$transcripts" | xargs -0 grep -lF -- "$1" 2>/dev/null | head -n 1)" ]
}

# A `git worktree add` killed mid-checkout (main-branch-guard runs it inside a
# 5-second Codex hook) leaves git's "initializing" lock, an empty index.lock and
# NO index: every file then reads as staged-deleted plus untracked, so the
# uncommitted-changes check holds it forever. It is that only if no commit was
# made on it and no file was written more than 10 minutes after it was created.
is_abandoned_checkout() { # <wt> <gitdir> <ref>
  [ ! -f "$2/index" ] || return 1
  [ "$(cat "$2/locked" 2>/dev/null)" = initializing ] || return 1
  _c=$(mtime_of "$2/HEAD") || return 1
  stamp_at "$scratch" $((_c + 600)) || return 1
  changed_since "$1" "$2/logs" "$scratch" && return 1
  _ch=$(gitr -C "$1" cherry "$3" HEAD 2>/dev/null) || return 1
  [ "$(printf '%s\n' "$_ch" | grep -c '^+')" -eq 0 ]
}

# Paths that must never be pushed by a nightly job, even inside a WIP commit.
SUSPECT_PATHS='(^|/)(\.env[^/]*|id_[a-z0-9]+|[^/]*\.(pem|key|p12|pfx)|credentials[^/]*|secrets?[^/]*\.(json|ya?ml|env))$'

# What to do with one worktree, as "<action> <reason>". Fails CLOSED: an
# unreadable status or an undeterminable merge state is a hold, never a pass. An
# index.lock held by a live agent lands exactly there — on the tree most likely
# to be holding work.
#
# Merge is judged by patch-id (`git cherry`), NOT ancestry: this fleet
# rebase-merges, so a landed branch's SHAs are rewritten and
# `merge-base --is-ancestor` reports NOT merged for work that fully landed — an
# ancestry gate would reclaim nothing at all. Patch-id also subsumes the unpushed
# check, since an unpushed commit has no upstream equivalent.
#
# Actions: hold | remove (merged, or an abandoned checkout) | drop (--preserve:
# every commit is already on origin and the tree is clean) | preserve
# (--preserve: local-only work, pushed as a draft PR before the tree goes).
verdict_for() { # <wt> <ref>
  _wt=$1; _ref=$2
  has_live_process "$_wt" && { echo 'hold live-process'; return; }
  [ -e "$_wt/.agents-keep" ] && { echo 'hold keep-marker'; return; }
  _gd=$(git -C "$_wt" rev-parse --absolute-git-dir 2>/dev/null) || { echo 'hold status-unreadable'; return; }
  changed_since "$_wt" "$_gd" "$gracestamp" && { echo 'hold within-grace'; return; }
  mentioned_recently "$_wt" && { echo 'hold recent-session'; return; }
  is_abandoned_checkout "$_wt" "$_gd" "$_ref" && { echo 'remove abandoned-checkout'; return; }
  _st=$(gitr -C "$_wt" status --porcelain 2>/dev/null) || { echo 'hold status-unreadable'; return; }
  _ch=$(gitr -C "$_wt" cherry "$_ref" HEAD 2>/dev/null) || { echo 'hold merge-state-unknown'; return; }
  _ahead=$(printf '%s\n' "$_ch" | grep -c '^+')
  [ -z "$_st" ] && [ "$_ahead" -eq 0 ] && { echo 'remove merged'; return; }
  if [ "$PRESERVE" != 1 ]; then
    if [ -n "$_st" ]; then echo 'hold uncommitted-changes'; else echo 'hold unmerged-commits'; fi
    return
  fi
  _local=$(gitr -C "$_wt" rev-list HEAD --not --remotes=origin 2>/dev/null | wc -l) || { echo 'hold merge-state-unknown'; return; }
  [ -z "$_st" ] && [ "$_local" -eq 0 ] && { echo 'drop pushed-unmerged'; return; }
  if printf '%s\n' "$_st" | cut -c4- | sed 's/.* -> //' | grep -qE "$SUSPECT_PATHS"; then
    echo 'hold suspect-files'; return
  fi
  echo 'preserve local-work'
}

# --preserve: commit any uncommitted work, push it to wip/<host>/<name>, and open
# (or reuse) a draft PR. Succeeds only once a PR URL exists, so the caller removes
# the tree only when the work is reachable from GitHub. The local branch is kept.
preserve_work() { # <repo> <wt> <ref>
  _repo=$1; _wt=$2; _name=$(basename "$2")
  _orig=$(git -C "$_wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
  _wipb="wip/$host/$_name"
  _slug=$(git -C "$_repo" config --get remote.origin.url | sed -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##')
  _base=${3#origin/}
  if [ -n "$(gitr -C "$_wt" status --porcelain 2>/dev/null)" ]; then
    # Oversized files are not work product; a nightly job never pushes them.
    if [ -n "$(gitr -C "$_wt" ls-files -mo --exclude-standard -z 2>/dev/null | (cd "$_wt" && xargs -0 sh -c 'for f; do [ -f "$f" ] && find "$f" -size +5M; done' sh) | head -n 1)" ]; then
      echo "held (preserve: file over 5 MB): $_name"; return 1
    fi
    git -C "$_wt" add -A >/dev/null 2>&1 &&
      git -C "$_wt" commit -q -m "WIP: uncommitted work from $_name, preserved by worktree-sweep on $host" >/dev/null 2>&1 ||
      { echo "held (preserve: commit failed): $_name"; return 1; }
  fi
  git -C "$_wt" push -q origin "HEAD:refs/heads/$_wipb" >/dev/null 2>&1 ||
    { echo "held (preserve: push failed): $_name"; return 1; }
  command -v gh >/dev/null 2>&1 || { echo "held (preserve: pushed $_wipb, no gh to open a PR): $_name"; return 1; }
  _url=$(gh pr list -R "$_slug" --head "$_wipb" --state open --json url -q '.[0].url' 2>/dev/null)
  if [ -z "$_url" ]; then
    _url=$(gh pr create -R "$_slug" --draft --base "$_base" --head "$_wipb" \
      --title "WIP: $_name (preserved from $host)" \
      --body "worktree-sweep on $host preserved this worktree before removing it: it had work that existed nowhere else and had not been touched for $GRACE_DAYS days.

- Worktree: \`$_name\` (branch \`$_orig\`)

Unfinished work, not ready for review. Close it if the work is obsolete; this branch is the only copy." 2>/dev/null | tail -n 1)
  fi
  case $_url in
    https://*) echo "preserved: $_name -> $_url"; return 0 ;;
    *) echo "held (preserve: pushed $_wipb, PR not opened): $_name"; return 1 ;;
  esac
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

    verdict=$(verdict_for "$wt" "$ref")
    action=${verdict%% *}; reason=${verdict#* }
    if [ "$action" = hold ]; then
      held=$((held + 1)); echo "$reason" >> "$reasons"
      [ "$DRY_RUN" = 1 ] && echo "held ($reason): $name"
      continue
    fi

    if [ "$DRY_RUN" = 1 ]; then
      case $action in
        remove) echo "would reclaim ($reason): $name" ;;
        drop) echo "would remove the local copy (all commits on origin): $name" ;;
        preserve) echo "would preserve as a draft PR, then remove: $name" ;;
      esac
      swept=$((swept + 1))
      continue
    fi

    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)

    # RE-READ immediately before mutating, never from the check above. A box with
    # 136 worktrees takes minutes; an agent that COMMITS mid-sweep leaves a clean
    # tree, and a stale "0 unmerged" would then authorise `branch -D` and destroy
    # that commit. The live-process list is re-read too: an agent may have just
    # opened a session in this tree.
    refresh_live
    again=$(verdict_for "$wt" "$ref")
    if [ "$again" != "$verdict" ]; then
      held=$((held + 1)); echo "changed during sweep" >> "$reasons"
      echo "held (changed during sweep: ${again#* }): $name"
      continue
    fi

    case $action in
      drop|preserve)
        if [ "$action" = preserve ]; then
          preserve_work "$repo" "$wt" "$ref" || { held=$((held + 1)); echo "preserve failed" >> "$reasons"; continue; }
        fi
        # Remove only what provably exists on origin now: a clean tree whose every
        # commit is on a remote-tracking ref (the push above updated origin/wip/...).
        refresh_live
        if has_live_process "$wt" || [ -n "$(gitr -C "$wt" status --porcelain 2>/dev/null)" ] ||
           [ "$(gitr -C "$wt" rev-list HEAD --not --remotes=origin 2>/dev/null | wc -l)" -ne 0 ]; then
          held=$((held + 1)); echo "changed during sweep" >> "$reasons"
          echo "held (changed during sweep after preserving): $name"; continue
        fi
        # No --force; the branch stays as a local ref. Its commits are on origin.
        if git -C "$repo" worktree remove "$wt" >/dev/null 2>&1; then
          echo "reclaimed ($reason): $name ($repo)"; swept=$((swept + 1))
        else
          echo "held (git refused removal): $name"; held=$((held + 1))
        fi
        continue
        ;;
    esac

    # An abandoned checkout has no index, so every file reads as untracked and a
    # plain remove refuses it; --force is safe only because is_abandoned_checkout
    # just re-proved no commit and no write since creation. Everything else gets
    # no --force, so git refuses a tree with uncommitted changes. That is NOT an
    # independent check on the thing that matters: worktree removal does not look
    # at the commit graph, so a branch carrying an unmerged commit is removed
    # without complaint as long as the tree is clean (verified in review). The
    # remaining window is an agent COMMITTING between the re-read above and this
    # call, which leaves a clean tree and would let the deletion below destroy it.
    force=
    if [ "$reason" = abandoned-checkout ]; then
      git -C "$repo" worktree unlock "$wt" >/dev/null 2>&1 || true
      force=--force
    fi
    if git -C "$repo" worktree remove $force "$wt" >/dev/null 2>&1; then
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
      echo "reclaimed ($reason): $name ($repo)"
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
trap 'rm -f "$wtlist" "$allowfile" "$livefile" "$transcripts" "$reasons" "$gracestamp" "$scratch"' EXIT INT TERM
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

# The grace window as a reference file for `find -newer`, and the inputs every
# verdict reads, gathered once: a transcript scan per tree would read the same
# gigabytes hundreds of times. Without a stamp nothing can be judged idle.
stamp_at "$gracestamp" $((now - GRACE_DAYS * 86400)) || { echo "could not set the grace stamp — skipping"; exit 0; }
refresh_live
list_recent_transcripts > "$transcripts"

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

echo "worktree-sweep on $host: reclaimed=$swept held=$held"
# Why each tree was kept. A bare "held=150" hid for weeks that most were broken
# checkouts nothing could ever reclaim.
[ -s "$reasons" ] && sort "$reasons" | uniq -c | sort -rn | sed 's/^ */  held: /'
exit 0
