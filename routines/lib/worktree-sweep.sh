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
today=$(date +%Y-%m-%d)
swept=0
held=0

host=$(hostname -s 2>/dev/null || echo unknown)
wtlist=$(mktemp) && livefile=$(mktemp) && transcripts=$(mktemp) && mentioned=$(mktemp) && patfile=$(mktemp) &&
  reasons=$(mktemp) && gracestamp=$(mktemp) && scratch=$(mktemp) && allowfile=$(mktemp) ||
  { echo "could not create temp file — skipping"; exit 1; }
cleanup() { rm -f "$wtlist" "$livefile" "$transcripts" "$mentioned" "$patfile" "$reasons" "$gracestamp" "$scratch" "$allowfile"; }
# The signal handlers EXIT. A handler that only cleaned up would let the script
# resume with its grace stamp and transcript list deleted — and then every tree
# reads as idle (reproduced in review: a TERM mid-run removed a fresh tree).
trap cleanup EXIT
trap 'exit 130' INT TERM

# Network calls from a nightly job must not hang it. `timeout` is GNU coreutils;
# macOS without it runs them unbounded rather than not at all.
if command -v timeout >/dev/null 2>&1; then TO="timeout 300"; else TO=; fi

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

# `git status` refreshes the index when stat data changed and WRITES it. Every
# read here passes --no-optional-locks so the sweep itself never does that.
gitr() { git --no-optional-locks "$@"; }

# Whether the tree was worked in since <stamp>: a file edited, created or deleted
# in it, or a commit or checkout (HEAD, logs/HEAD). The tree directory's own
# mtime, which this used to read alone, moves only when an entry directly under
# it is added or removed, so a tree edited every hour read as 30 days idle.
#
# NOT the git dir itself or its index. Any plain `git status` (an IDE, a prompt,
# a hook, the previous sweep) rewrites the index through a lock-file rename,
# which moves both. Measured on yosemite-m1: 132 of 139 trees read "active" from
# that alone. Staging is still seen, through the edit that preceded it.
#
# A missing stamp means "changed": with no reference point nothing is idle.
changed_since() { # <wt> <gitdir> <stamp>
  [ -f "$3" ] || return 0
  [ -n "$(find "$1" \( -name node_modules -o -name .next -o -name dist -o -name target \
            -o -name .venv \) -prune -o -newer "$3" -print 2>/dev/null | head -n 1)" ] && return 0
  for _f in "$2/HEAD" "$2/logs/HEAD"; do
    [ -e "$_f" ] && [ -n "$(find "$_f" -newer "$3" 2>/dev/null)" ] && return 0
  done
  return 1
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
  [ -f "$livefile" ] || return 0
  awk -v p="$1/" 'index($0 "/", p) == 1 { f = 1 } END { exit !f }' "$livefile"
}

# Agent transcripts written within the grace window. An agent that works on a tree
# by absolute path from elsewhere (git -C, editing by full path) never has its
# cwd there, but its transcript names the path.
list_recent_transcripts() { # <stamp>
  for _d in "$SEARCH_HOME/.agents/.history" "$SEARCH_HOME/.claude/projects" "$SEARCH_HOME/.codex/sessions" \
            "$SEARCH_HOME/.gemini" "$SEARCH_HOME/.local/share/opencode"; do
    [ -e "$_d" ] && find -H "$_d" -type f -newer "$1" 2>/dev/null
  done | sort -u
}
# One pass over every transcript for every tree path (grep -F -f is one
# automaton), instead of one pass per tree: on a box with 500 trees and gigabytes
# of transcripts the per-tree scan would not finish inside the routine timeout.
# Over-matching (a mention of fix-1103 also marks fix-110) only ever HOLDS.
build_mentioned() { # <patterns file>
  : > "$mentioned"
  [ -s "$transcripts" ] && [ -s "$1" ] || return 0
  tr '\n' '\0' < "$transcripts" | xargs -0 grep -ohF -f "$1" 2>/dev/null | sort -u > "$mentioned"
}
mentioned_recently() { # <wt>
  [ -f "$mentioned" ] || return 0
  grep -qxF -- "$1" "$mentioned"
}
# Immediately before mutating: a fresh transcript list, scanned for this tree only.
mentioned_now() { # <wt>
  [ -f "$gracestamp" ] || return 0
  [ -n "$(list_recent_transcripts "$gracestamp" | tr '\n' '\0' | xargs -0 grep -lF -- "$1" 2>/dev/null | head -n 1)" ]
}

# A `git worktree add` killed mid-checkout (main-branch-guard runs it inside a
# 5-second Codex hook) leaves git's "initializing" lock and NO index: every file
# then reads as staged-deleted plus untracked, so the uncommitted-changes check
# holds it forever. It is that only if no commit was made on it and nothing was
# written more than 2 minutes after it was created (the checkout itself is killed
# within seconds).
is_abandoned_checkout() { # <wt> <gitdir> <ref>
  [ ! -f "$2/index" ] || return 1
  [ "$(cat "$2/locked" 2>/dev/null)" = initializing ] || return 1
  _c=$(mtime_of "$2/HEAD") || return 1
  stamp_at "$scratch" $((_c + 120)) || return 1
  changed_since "$1" "$2" "$scratch" && return 1
  _ch=$(gitr -C "$1" cherry "$3" HEAD 2>/dev/null) || return 1
  [ "$(printf '%s\n' "$_ch" | grep -c '^+')" -eq 0 ] || return 1
  [ -z "$(gitr -C "$1" rev-list --merges "$3..HEAD" 2>/dev/null)" ]
}

# Gitignored paths a removal would delete that are not rebuildable caches. A
# plain `git worktree remove` deletes ignored files without a word, and those are
# exactly .env files, local databases and notes. They are copied to
# ~/.agents-swept/<date>/<repo>/<tree>/ before the tree goes (salvage_ignored).
CACHE_DIRS='(^|/)(node_modules|\.next|\.nuxt|\.svelte-kit|dist|build|out|target|\.venv|venv|__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.tox|\.turbo|\.cache|\.parcel-cache|\.gradle|coverage|\.wrangler|\.vercel|\.output)(/|$)'
ignored_to_keep() { # <wt>
  gitr -C "$1" ls-files -o -i --exclude-standard --directory 2>/dev/null | grep -vE "$CACHE_DIRS"
}
SALVAGE_MAX_KB=102400
salvage_ignored() { # <repo> <wt>
  _keep=$(ignored_to_keep "$2") || true
  [ -n "$_keep" ] || return 0
  _kb=$(printf '%s\n' "$_keep" | (cd "$2" && while IFS= read -r p; do du -sk "$p" 2>/dev/null; done) | awk '{s+=$1} END {print s+0}')
  [ "$_kb" -le "$SALVAGE_MAX_KB" ] || { echo "held (ignored files total ${_kb} KB, over the salvage cap): $(basename "$2")"; return 1; }
  _dest="$SEARCH_HOME/.agents-swept/$today/$(basename "$1")/$(basename "$2")"
  mkdir -p "$_dest" || return 1
  printf '%s\n' "$_keep" | (cd "$2" && tar -cf - -T - 2>/dev/null) | (cd "$_dest" && tar -xf -) || return 1
  echo "salvaged ignored files of $(basename "$2") to $_dest"
}

# What a nightly job must never push. Names are checked across every path the WIP
# commit or push would carry; contents are scanned for key and token shapes.
SUSPECT_PATHS='(^|/)(\.env[^/]*|\.npmrc|\.netrc|\.pgpass|\.pypirc|id_[a-z0-9]+|[^/]*\.(pem|key|p8|p12|pfx|ppk|jks|keystore)|credentials[^/]*|service-account[^/]*\.json|secrets?[^/]*\.(json|ya?ml|env|toml))$'
SUSPECT_CONTENT='-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|xox[abposr]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{32,}|sk_live_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}'
MAX_PRESERVE_FILES=2000
# Every path a preserve would publish: uncommitted (untracked listed file by file,
# never collapsed to a directory), staged, and every file the local commits touch.
paths_to_publish() { # <wt> <ref>
  { gitr -C "$1" ls-files -mo --exclude-standard
    gitr -C "$1" diff --cached --name-only
    gitr -C "$1" diff --name-only "$2...HEAD"; } 2>/dev/null | sort -u
}
publish_blocker() { # <wt> <ref> -> a reason, or nothing
  _p=$(paths_to_publish "$1" "$2")
  [ "$(printf '%s\n' "$_p" | grep -c .)" -le "$MAX_PRESERVE_FILES" ] || { echo "over $MAX_PRESERVE_FILES files"; return; }
  printf '%s\n' "$_p" | grep -qE "$SUSPECT_PATHS" && { echo "suspect-files"; return; }
  _hit=$(printf '%s\n' "$_p" | (cd "$1" && while IFS= read -r f; do
           [ -f "$f" ] || continue
           [ -n "$(find "$f" -size +5M 2>/dev/null)" ] && { echo big; break; }
           grep -qE -- "$SUSPECT_CONTENT" "$f" 2>/dev/null && { echo secret; break; }
         done))
  case $_hit in big) echo "file over 5 MB" ;; secret) echo "suspect-files" ;; esac
}

# What to do with one worktree, as "<action> <reason>". Fails CLOSED: an
# unreadable status or an undeterminable merge state is a hold, never a pass. An
# index.lock held by a live agent lands exactly there — on the tree most likely
# to be holding work.
#
# Merge is judged by patch-id (`git cherry`), NOT ancestry: this fleet
# rebase-merges, so a landed branch's SHAs are rewritten and
# `merge-base --is-ancestor` reports NOT merged for work that fully landed — an
# ancestry gate would reclaim nothing at all. Patch-id also subsumes the unpushed
# check, since an unpushed commit has no upstream equivalent. `git cherry` skips
# MERGE commits, though, so a branch whose only change sits in a merge (a conflict
# resolution, an evil merge) reads as landed: a merge on the branch is never
# "merged" (reproduced in review: such a branch was deleted).
#
# Actions: hold | remove (merged, or an abandoned checkout) | drop (--preserve:
# every commit is on origin outside wip/, and the tree is clean) | preserve
# (--preserve: work that exists nowhere else, pushed as a draft PR first).
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
  _merges=$(gitr -C "$_wt" rev-list --merges "$_ref..HEAD" 2>/dev/null) || { echo 'hold merge-state-unknown'; return; }
  _ahead=$(printf '%s\n' "$_ch" | grep -c '^+')
  [ -z "$_st" ] && [ "$_ahead" -eq 0 ] && [ -z "$_merges" ] && { echo 'remove merged'; return; }
  if [ "$PRESERVE" != 1 ]; then
    if [ -n "$_st" ]; then echo 'hold uncommitted-changes'; else echo 'hold unmerged-commits'; fi
    return
  fi
  # Commits not on any origin ref except our own wip/ pushes (--exclude takes the
  # pattern without refs/remotes/ when it precedes --remotes): a tree whose work
  # only reached wip/<host>/<name> still needs its PR before it may go.
  _lo=$(gitr -C "$_wt" rev-list HEAD --not --exclude='origin/wip/*' --remotes=origin 2>/dev/null) ||
    { echo 'hold merge-state-unknown'; return; }
  [ -z "$_st" ] && [ -z "$_lo" ] && { echo 'drop pushed-unmerged'; return; }
  _b=$(publish_blocker "$_wt" "$_ref")
  [ -n "$_b" ] && { echo "hold $_b"; return; }
  echo 'preserve local-work'
}

# --preserve: commit any uncommitted work, push it to wip/<host>/<name>, and open
# (or reuse) a draft PR, on a PRIVATE repo only. Succeeds only once a PR URL
# exists, so the caller removes the tree only when the work is reachable from
# GitHub. The local branch is kept.
preserve_work() { # <repo> <wt> <ref>
  _repo=$1; _wt=$2; _name=$(basename "$2")
  _orig=$(git -C "$_wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
  _wipb="wip/$host/$_name"
  _slug=$(git -C "$_repo" config --get remote.origin.url | sed -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##')
  _base=${3#origin/}
  # Unfinished work and the host name never go to a public repository.
  _priv=$($TO gh repo view -R "$_slug" --json isPrivate -q .isPrivate 2>/dev/null)
  [ "$_priv" = true ] || { echo "held (preserve: $_slug is not confirmed private): $_name"; return 1; }
  if [ -n "$(gitr -C "$_wt" status --porcelain 2>/dev/null)" ]; then
    git -C "$_wt" add -A >/dev/null 2>&1 &&
      git -C "$_wt" commit -q -m "WIP: uncommitted work from $_name, preserved by worktree-sweep on $host" >/dev/null 2>&1 ||
      { echo "held (preserve: commit failed): $_name"; return 1; }
  fi
  $TO git -C "$_wt" push -q origin "HEAD:refs/heads/$_wipb" >/dev/null 2>&1 ||
    { echo "held (preserve: push failed): $_name"; return 1; }
  _url=$($TO gh pr list -R "$_slug" --head "$_wipb" --state open --json url -q '.[0].url' 2>/dev/null)
  if [ -z "$_url" ]; then
    _url=$($TO gh pr create -R "$_slug" --draft --base "$_base" --head "$_wipb" \
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
  for wt in "$wtdir"/*/; do [ -d "$wt" ] && printf '%s\n' "${wt%/}"; done > "$patfile"
  build_mentioned "$patfile"

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
    mentioned_now "$wt" && again='hold recent-session'
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
        # A failed rev-list is a hold, never "nothing local".
        refresh_live
        if ! lo=$(gitr -C "$wt" rev-list HEAD --not --remotes=origin 2>/dev/null) || [ -n "$lo" ] ||
           has_live_process "$wt" || [ -n "$(gitr -C "$wt" status --porcelain 2>/dev/null)" ]; then
          held=$((held + 1)); echo "changed during sweep" >> "$reasons"
          echo "held (changed during sweep after preserving): $name"; continue
        fi
        salvage_ignored "$repo" "$wt" || { held=$((held + 1)); echo "ignored files not salvaged" >> "$reasons"; continue; }
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
    else
      salvage_ignored "$repo" "$wt" || { held=$((held + 1)); echo "ignored files not salvaged" >> "$reasons"; continue; }
    fi
    if git -C "$repo" worktree remove $force "$wt" >/dev/null 2>&1; then
      # FINAL proof, taken after the worktree is gone so no further commit can
      # land on it, and read from the BRANCH ref (which survives removal). Only a
      # branch still provably patch-equivalent upstream is deleted; anything else
      # is kept as a recoverable ref and reported.
      if [ "$branch" != "HEAD" ]; then
        if final=$(git -C "$repo" cherry "$ref" "$branch" 2>/dev/null) &&
           { [ -z "$final" ] || [ "$(printf '%s\n' "$final" | grep -c '^+')" -eq 0 ]; } &&
           fm=$(git -C "$repo" rev-list --merges "$ref..$branch" 2>/dev/null) && [ -z "$fm" ]; then
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
if [ -f "$HOME/.agents/worktree-sweep.allow" ]; then
  # A blank line is a pattern that matches every URL: drop blanks.
  grep -v '^[[:space:]]*$' "$HOME/.agents/worktree-sweep.allow" > "$allowfile"
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
stamp_at "$gracestamp" $((now - GRACE_DAYS * 86400)) || { echo "could not set the grace stamp — skipping"; exit 1; }
refresh_live
list_recent_transcripts "$gracestamp" > "$transcripts"

# --preserve publishes, so it needs a signed-in gh. Without one the work is
# HELD, never pushed to a branch with no PR to surface it.
if [ "$PRESERVE" = 1 ] && [ "$DRY_RUN" != 1 ] && ! $TO gh auth status >/dev/null 2>&1; then
  echo "preserve off: gh is not signed in on $host; work that exists only here is held"
  PRESERVE=0
fi

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
