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
# has its working directory inside it, nothing in it changed and no agent
# transcript named it for --grace-days, and it has no `.agents-keep` file.
# Gitignored files that are not caches are copied to ~/.agents-swept/ first.
# With --preserve, a parked worktree on a PRIVATE repo is also pushed to
# wip/<host>/<name> and opened as a draft PR, so its work is not on one disk only.
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
host=$(hostname -s 2>/dev/null || echo unknown)
swept=0
parked=0
held=0
# Stop starting new worktrees after 15 minutes, inside the routine's 20-minute
# timeout: a box with 500 worktrees finishes the rest the next night instead of
# being killed mid-run with nothing reported.
BUDGET_SECONDS=900
RETRY_CAP=20
out_of_time() { [ $(( $(date +%s) - now )) -ge "$BUDGET_SECONDS" ]; }

wtlist=$(mktemp) && cwds=$(mktemp) && changed=$(mktemp) && parkidx=$(mktemp) &&
  allowfile=$(mktemp) && transcripts=$(mktemp) && mentioned=$(mktemp) && patfile=$(mktemp) &&
  gracestamp=$(mktemp) && scanstamp=$(mktemp) && scratch=$(mktemp) && tarfile=$(mktemp) && reasons=$(mktemp) ||
  { echo "could not create temp file — skipping"; exit 1; }
cleanup() {
  rm -f "$wtlist" "$cwds" "$changed" "$parkidx" "$allowfile" "$transcripts" "$mentioned" \
    "$patfile" "$gracestamp" "$scanstamp" "$scratch" "$tarfile" "$reasons"
}
# The signal handlers EXIT. One that only cleaned up let the script resume with
# its inputs deleted (reproduced in review: after a TERM mid-run, a tree inside
# the grace window was removed).
trap cleanup EXIT
trap 'exit 130' INT TERM

# Network calls (--preserve) must not hang a nightly job. GNU `timeout` only;
# without it they run unbounded rather than not at all.
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

# The working directory of every process this user can see, one per line. A
# process sitting inside a worktree (an agent's shell, a dev server, a test run)
# is the strongest "in use" signal there is, and it holds no matter how long the
# files have been untouched: an agent can idle for days between turns. One fork:
# GNU readlink takes every /proc entry at once.
snapshot_cwds() {
  if [ -d /proc/self ]; then
    readlink /proc/[0-9]*/cwd > "$cwds" 2>/dev/null
  elif command -v lsof >/dev/null 2>&1; then
    lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' > "$cwds"
  else
    : > "$cwds"
  fi
}
# Exact path or a path below it: `fix-110` must not claim a shell in `fix-1103`.
# /proc and lsof report physical paths, so the worktree is matched both as found
# and with symlinks resolved (macOS /tmp is /private/tmp).
in_use() {
  # No process list at all (no /proc and no lsof, or a readlink that takes one
  # operand) cannot prove anything idle: every worktree counts as in use.
  [ -s "$cwds" ] || return 0
  _phys=$(cd "$1" 2>/dev/null && pwd -P) || _phys=$1
  awk -v p="$1" -v q="$_phys" '
    $0 == p || index($0, p "/") == 1 || $0 == q || index($0, q "/") == 1 { f = 1 }
    END { exit !f }' "$cwds"
}

# True when anyone touched the worktree after <cutoff>, or when that cannot be
# judged (fails closed: an unjudgeable tree is held). Reads the directory, a
# commit or checkout (the per-worktree HEAD, its reflog, ORIG_HEAD), and every
# changed or untracked file listed in $changed (`status -uall`, so a file deep in
# an untracked directory counts, not just the directory). The worktree
# directory's own mtime alone moves only when a top-level entry is added or
# removed, so an agent editing src/ for a week read as idle. `index` is left out
# on purpose: `git status`, including this sweep's own, rewrites it, which would
# make every worktree look touched every night. Stops at the first recent path.
recently_touched() {
  _wt=$1; _cut=$2
  _m=$(mtime_of "$_wt") || return 0
  [ "$_m" -gt "$_cut" ] && return 0
  for _f in "$_gd/HEAD" "$_gd/logs/HEAD" "$_gd/ORIG_HEAD"; do
    [ -e "$_f" ] || continue
    _m=$(mtime_of "$_f") || return 0
    [ "$_m" -gt "$_cut" ] && return 0
  done
  while IFS= read -r _l; do
    _xy=${_l%"${_l#??}"}; _p=${_l#???}
    case $_p in *' -> '*) _p=${_p#* -> } ;; esac
    if [ -e "$_wt/$_p" ] || [ -L "$_wt/$_p" ]; then
      _m=$(mtime_of "$_wt/$_p") || return 0
      [ "$_m" -gt "$_cut" ] && return 0
    else
      # A deleted file has no mtime. Anything else that does not resolve is a
      # name git C-quoted (a quote, backslash or newline in it): unjudgeable.
      case $_xy in *D*) ;; *) return 0 ;; esac
    fi
  done < "$changed"
  return 1
}

# touch -t takes local [[CC]YY]MMDDhhmm[.SS] on both GNU and BSD; only the epoch
# conversion differs (date -d @N on GNU, date -r N on BSD/macOS).
stamp_at() { # <file> <epoch>
  _t=$(date -d "@$2" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$2" +%Y%m%d%H%M.%S 2>/dev/null) || return 1
  touch -t "$_t" "$1"
}

# Agent transcripts written within the grace window. An agent that works on a
# tree by absolute path from elsewhere (git -C, editing by full path, reading it
# to review) never has its cwd there, but its transcript names the path.
#
# Conversation files only: Claude's projects/, Codex's and Grok's sessions/,
# Gemini's chats/, OpenCode's session/. NOT a harness's own config (~/.claude.json
# and kin list every directory ever opened), the activity feed, or the agents
# CLI's session index (~/.agents/.history/sessions/sessions.db), which name every
# tree and are rewritten all the time: on yosemite-m5 the first two held 91 of
# 94, on yosemite-s0 the index alone held 246.
list_recent_transcripts() { # <stamp>
  for _d in "$SEARCH_HOME/.agents/.history" "$SEARCH_HOME/.claude/projects" "$SEARCH_HOME/.codex/sessions" \
            "$SEARCH_HOME/.gemini" "$SEARCH_HOME/.local/share/opencode"; do
    [ -e "$_d" ] && find -H "$_d" -type f \( -path '*/projects/*' -o -path '*/sessions/*' \
      -o -path '*/chats/*' -o -path '*/session/*' -o -path '*/storage/message/*' -o -path '*/storage/part/*' \) \
      ! -path '*/activity/*' ! -path '*/.agents/.history/sessions/*' \
      ! -name '*.db' ! -name '*.db-wal' ! -name '*.db-shm' ! -name '*.sqlite*' -newer "$1" 2>/dev/null
  done | sort -u
}
# ONE pass over every recent transcript for every tree path on the box (grep -F -f
# is one automaton), once per run. Measured: 20.8 GB of transcripts from 3 days on
# one box, ~28 s per pass, so a pass per repo or per tree cannot finish inside
# the routine timeout. Over-matching (a mention of fix-1103 also marks fix-110)
# only ever HOLDS. -a: a transcript store with binary records is read as text.
#
# A transcript that names more than SURVEY_TREES different trees is a survey (a
# disk cleanup, an inventory, a review of the fleet), not a session working in
# them: on yosemite-m5 four such sessions named 25-40 trees each and held 90 of
# 93. Its mentions do not hold; a session working in a tree names a handful.
# EXCEPT within the last RECENT_HOURS: any transcript written that recently holds
# every tree it names, so a live orchestrator driving many trees by path is
# never mistaken for a survey.
SURVEY_TREES=5
RECENT_HOURS=12
# Paths named by working sessions among the transcripts listed on stdin.
working_mentions() {
  tr '\n' '\0' | xargs -0 grep -aoHF -f "$patfile" 2>/dev/null | sort -u |
    awk -v max="$SURVEY_TREES" '
      { i = index($0, ":/"); f = substr($0, 1, i - 1); p = substr($0, i + 1)
        n[f]++; at[NR] = f; path[NR] = p }
      END { for (k = 1; k <= NR; k++) if (n[at[k]] <= max) print path[k] }' | sort -u
}
build_mentioned() {
  : > "$mentioned"
  [ -s "$transcripts" ] && [ -s "$patfile" ] || return 0
  stamp_at "$scratch" $((now - RECENT_HOURS * 3600)) || return 1
  { working_mentions < "$transcripts"
    list_recent_transcripts "$scratch" | tr '\n' '\0' | xargs -0 grep -aohF -f "$patfile" 2>/dev/null
  } | sort -u > "$mentioned"
}
mentioned_recently() { # <wt>
  [ -f "$mentioned" ] || return 0
  grep -qxF -- "$1" "$mentioned"
}
# Right before mutating: only transcripts written since the run's scan.
# Anything written since the scan is within RECENT_HOURS, so every mention holds.
mentioned_since_scan() { # <wt>
  [ -f "$scanstamp" ] || return 0
  [ -n "$(list_recent_transcripts "$scanstamp" | tr '\n' '\0' | xargs -0 grep -alF -- "$1" 2>/dev/null | head -n 1)" ]
}

# Merge commits on <range> that carry a change of their own. `git cherry` skips
# merges, so a conflict resolution or an "evil merge" is invisible to it, and a
# branch whose only work sits in a merge read as landed (reproduced in review: it
# was deleted). A merge whose tree is exactly what git builds from its two
# parents (a plain catch-up `git merge origin/main`) adds nothing and is not
# counted. merge-tree --write-tree needs git >= 2.38; without it every merge counts.
merges_with_changes() { # <dir> <range>
  _ms=$(git -C "$1" rev-list --merges "$2" 2>/dev/null) || { echo unknown; return; }
  for _m in $_ms; do
    [ "$(git -C "$1" rev-list --parents -n 1 "$_m" | wc -w)" -eq 3 ] || { echo "$_m"; continue; }
    _auto=$(git -C "$1" merge-tree --write-tree "$_m^1" "$_m^2" 2>/dev/null | head -n 1) || { echo "$_m"; continue; }
    [ "$_auto" = "$(git -C "$1" rev-parse "$_m^{tree}")" ] || echo "$_m"
  done
}

# A `git worktree add` killed mid-checkout (main-branch-guard runs it inside a
# 5-second Codex hook) leaves git's "initializing" lock and NO index: every file
# reads as staged-deleted plus untracked, and the lock held it forever. Measured on
# yosemite-m6: 87 such trees, 98 GB. It is that only when no commit was made on it
# and nothing in it was written more than 2 minutes after it was created (the
# checkout itself is killed within seconds).
is_abandoned_checkout() { # <wt> <gitdir> <ref>
  [ ! -f "$2/index" ] || return 1
  [ "$(cat "$2/locked" 2>/dev/null)" = initializing ] || return 1
  _c=$(mtime_of "$2/HEAD") || return 1
  stamp_at "$scratch" $((_c + 120)) || return 1
  [ -z "$(find "$1" "$2/HEAD" "$2/logs/HEAD" -newer "$scratch" 2>/dev/null | head -n 1)" ] || return 1
  _ch=$(git -C "$1" cherry "$3" HEAD 2>/dev/null) || return 1
  [ "$(printf '%s\n' "$_ch" | grep -c '^+')" -eq 0 ] || return 1
  [ -z "$(merges_with_changes "$1" "$3..HEAD")" ]
}

# Gitignored paths a removal deletes that are not rebuildable caches: .env files,
# local databases, notes. Neither a park commit nor `git worktree remove` keeps
# them, so they are copied to ~/.agents-swept/<date>/<repo>/<tree>/ (private to
# this user) before the tree goes. Over the cap, the tree is held.
CACHE_DIRS='(^|/)(node_modules|\.next|\.nuxt|\.svelte-kit|dist|target|\.venv|__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache|\.tox|\.turbo|\.cache|\.parcel-cache|\.gradle|\.wrangler|\.vercel|\.output)(/|$)'
SALVAGE_MAX_KB=102400
salvage_ignored() { # <repo> <wt>
  # An ls-files failure is not "nothing to salvage": the removal would then
  # delete whatever it could not list.
  _all=$(git -C "$2" -c core.quotepath=off ls-files -o -i --exclude-standard --directory 2>/dev/null) ||
    { echo "ignored files unreadable"; return 1; }
  _keep=$(printf '%s\n' "$_all" | grep -vE "$CACHE_DIRS")
  [ -n "$_keep" ] || return 0
  _kb=$(printf '%s\n' "$_keep" | (cd "$2" && while IFS= read -r _p; do du -sk "$_p" 2>/dev/null; done) | awk '{s += $1} END {print s + 0}')
  [ "$_kb" -le "$SALVAGE_MAX_KB" ] || { echo "ignored files total ${_kb} KB, over the salvage cap"; return 1; }
  mkdir -p "$SEARCH_HOME/.agents-swept" && chmod 700 "$SEARCH_HOME/.agents-swept" || return 1
  _dest="$SEARCH_HOME/.agents-swept/$today/$(basename "$1")/$(basename "$2")"
  mkdir -p "$_dest" || return 1
  # Through a file: a pipe reports only the extractor's status.
  printf '%s\n' "$_keep" | (cd "$2" && tar -cf "$tarfile" -T - 2>/dev/null) || return 1
  (cd "$_dest" && tar -xf "$tarfile") || return 1
  echo "salvaged ignored files to $_dest"
}

# What --preserve must never publish. Names are checked over every path the park
# commit carries beyond the default branch; contents are scanned for key shapes.
SUSPECT_PATHS='(^|/)(\.env[^/]*|\.npmrc|\.netrc|\.pgpass|\.pypirc|id_[a-z0-9]+|[^/]*\.(pem|key|p8|p12|pfx|ppk|jks|keystore)|credentials[^/]*|service-account[^/]*\.json|secrets?[^/]*\.(json|ya?ml|env|toml))$'
SUSPECT_CONTENT='-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|xox[abposr]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{32,}|sk_live_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}'
# Scans exactly what a push of <commit> sends: every commit in <ref>..<commit>,
# not only the final tree, since a key committed and then deleted is still in the
# pushed history (reproduced in review). Names come from every commit's file list,
# contents from every added line, sizes from every blob. One git process each, no
# path list on a command line, and anything but a clean "no match" blocks.
publish_blocker() { # <repo> <commit> <ref> -> a reason, or nothing
  _r="$3..$2"
  # -m: without it git log prints nothing for a merge commit, and this sweep
  # parks exactly the merges that carry a change of their own.
  git -C "$1" -c core.quotepath=off log -m --format= --name-only --no-renames "$_r" > "$scratch" 2>/dev/null ||
    { echo "history unreadable"; return; }
  grep -qE "$SUSPECT_PATHS" "$scratch"; _rc=$?
  [ "$_rc" -eq 0 ] && { echo "suspect file names"; return; }
  [ "$_rc" -eq 1 ] || { echo "name scan failed"; return; }
  git -C "$1" log -m -p --format= --no-color --no-ext-diff --text "$_r" > "$scratch" 2>/dev/null ||
    { echo "history unreadable"; return; }
  grep -aqE "^\+.*($SUSPECT_CONTENT)" "$scratch"; _rc=$?
  [ "$_rc" -eq 0 ] && { echo "suspect file contents"; return; }
  [ "$_rc" -eq 1 ] || { echo "content scan failed"; return; }
  # Only the id goes to cat-file: it reads a whole "<id> <path>" line as one name,
  # reports it missing, and the check would pass on nothing.
  _big=$(git -C "$1" rev-list --objects "$_r" 2>/dev/null | cut -d' ' -f1 |
    git -C "$1" cat-file --batch-check='%(objecttype) %(objectsize)' 2>/dev/null |
    awk '$NF == "missing" { print "bad"; exit } $1 == "blob" && $2 > 5242880 { print "big"; exit }
         END { if (NR == 0) print "bad" }')
  case $_big in big) echo "a file over 5 MB" ;; bad) echo "history unreadable" ;; esac
}

# --preserve: push a parked worktree's commit to wip/<host>/<name> and open (or
# reuse) a draft PR, on a repo gh confirms PRIVATE. The local refs/wip ref keeps
# the work whatever happens here, so a failure costs nothing and is retried the
# next night only by hand (the tree is already gone): report it loudly.
publish_park() { # <repo> <wipref> <ref> <name> <orig-branch>
  _slug=$(git -C "$1" config --get remote.origin.url | sed -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#\.git$##')
  _wipb="wip/$host/$4"
  # A settled outcome (published, or refused for what the work is or where it
  # lives) is recorded in refs/wip-checked/, so the retry pass below does not
  # re-judge it every night. A network failure is not recorded: it is retried.
  _checked="refs/wip-checked/${2#refs/wip/}"
  case $_slug in *://*|*@*|'') git -C "$1" update-ref "$_checked" "$2" 2>/dev/null
    echo "not published (origin is not on GitHub), kept locally in $2"; return 0 ;; esac
  _b=$(publish_blocker "$1" "$2" "$3")
  case $_b in
    '') ;;
    # What the work is settles it; a scan that could not run does not.
    "suspect file names"|"suspect file contents"|"a file over 5 MB")
      git -C "$1" update-ref "$_checked" "$2" 2>/dev/null; echo "not published ($_b), kept locally in $2"; return 0 ;;
    *) echo "not published ($_b, retried next run), kept locally in $2"; return 0 ;;
  esac
  # `gh repo view` takes the repository as an argument; it has no -R. With -R
  # every repo read as not private and nothing was ever published.
  _priv=$($TO gh repo view "$_slug" --json isPrivate -q .isPrivate 2>/dev/null)
  case $_priv in
    true) ;;
    false) git -C "$1" update-ref "$_checked" "$2" 2>/dev/null
           echo "not published ($_slug is not private), kept locally in $2"; return 0 ;;
    *) echo "not published ($_slug visibility unknown, retried next run), kept locally in $2"; return 0 ;;
  esac
  # A later tree with the same name gets its own branch rather than a rejected
  # non-fast-forward push onto the first one's PR.
  if ! $TO git -C "$1" push -q origin "$2:refs/heads/$_wipb" >/dev/null 2>&1; then
    _wipb="$_wipb-$now"
    $TO git -C "$1" push -q origin "$2:refs/heads/$_wipb" >/dev/null 2>&1 ||
      { echo "PUBLISH FAILED (push), kept locally in $2"; return 0; }
  fi
  _url=$($TO gh pr list -R "$_slug" --head "$_wipb" --state open --json url -q '.[0].url' 2>/dev/null)
  [ -n "$_url" ] || _url=$($TO gh pr create -R "$_slug" --draft --base "${3#origin/}" --head "$_wipb" \
      --title "WIP: $4 (parked on $host)" \
      --body "worktree-sweep on $host parked this worktree: it held work that existed nowhere else and had not been touched for $GRACE_DAYS days.

- Worktree: \`$4\` (branch \`$5\`)
- Also kept on $host as \`$2\`

Unfinished work, not ready for review. Close it if the work is obsolete." 2>/dev/null | tail -n 1)
  case $_url in
    https://*) git -C "$1" update-ref "$_checked" "$2" 2>/dev/null; echo "published: $_url" ;;
    *) echo "PUBLISH FAILED (PR not opened; pushed $_wipb), kept locally in $2" ;;
  esac
}

# Why the work in an idle worktree cannot be saved whole into one commit, or
# empty when it can. Each case is something `worktree remove --force` would
# destroy that a commit of the tree does not carry, so each one HOLDS:
#   - an untracked directory with its own .git (with -uall, the only entries
#     ending in "/"): `git add -A` records it as a bare gitlink, not its files;
#   - submodules: only the recorded commit is kept, never their edits or their
#     unpushed commits, and their git dirs live under the worktree's admin dir;
# Ignored files (.env and the like) do not hold: salvage_ignored copies every
# ignored path that is not a cache before any removal.
unparkable() {
  if grep -q '/$' "$changed"; then printf '%s' 'nested-repo'; return; fi
  if [ -e "$_wt/.gitmodules" ] || git -C "$_wt" ls-files -s 2>/dev/null | grep -q '^160000'; then
    printf '%s' 'has-submodules'; return
  fi
  printf '%s' ''
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
  [ -e "$_wt/.agents-keep" ] && { printf '%s' 'keep-marker'; return; }
  mentioned_recently "$_wt" && { printf '%s' 'recent-session'; return; }
  _gd=$(git -C "$_wt" rev-parse --absolute-git-dir 2>/dev/null) || { printf '%s' 'status-unreadable'; return; }
  is_abandoned_checkout "$_wt" "$_gd" "$_ref" && { printf '%s' 'reclaim:abandoned-checkout'; return; }
  [ -e "$_gd/locked" ] && { printf '%s' 'locked'; return; }
  # A merge, rebase, cherry-pick, revert or bisect in progress lives in the admin
  # dir and goes with the checkout; the operation could not be resumed.
  for _s in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
    [ -e "$_gd/$_s" ] && { printf '%s' 'operation-in-progress'; return; }
  done
  git -C "$_wt" -c core.quotepath=off status --porcelain -uall > "$changed" 2>/dev/null ||
    { printf '%s' 'status-unreadable'; return; }
  _n=$(wc -l < "$changed")
  # Parking stores the changes as git objects; a tree this large is almost always
  # build output nobody ignored, and copying it into .git defeats the point of
  # reclaiming the disk. Checked before the activity scan, which stats each path.
  [ "$_n" -gt 2000 ] && { printf '%s' 'too-many-changes-to-park'; return; }
  recently_touched "$_wt" $((now - _grace * 86400)) && { printf '%s' 'within-grace'; return; }
  if [ "$_n" -gt 0 ]; then
    _why=$(unparkable); [ -n "$_why" ] && { printf '%s' "$_why"; return; }
    printf '%s' 'park:uncommitted-changes'; return
  fi
  if ! _ch=$(git -C "$_wt" cherry "$_ref" HEAD 2>/dev/null); then
    printf '%s' 'merge-state-unknown'; return
  fi
  if [ -n "$_ch" ] && [ "$(printf '%s\n' "$_ch" | grep -c '^+')" -ne 0 ]; then
    _why=$(unparkable); [ -n "$_why" ] && { printf '%s' "$_why"; return; }
    printf '%s' 'park:unmerged-commits'; return
  fi
  if [ -n "$(merges_with_changes "$_wt" "$_ref..HEAD")" ]; then
    _why=$(unparkable); [ -n "$_why" ] && { printf '%s' "$_why"; return; }
    printf '%s' 'park:merge-with-changes'; return
  fi
  printf '%s' ''
}

# The tree the worktree holds right now, tracked edits and untracked files
# included, written through a throwaway index. `fresh` starts the index from
# HEAD; without it the index from the previous call is reused, so the check right
# before removal only rehashes files whose stat changed.
worktree_tree() {
  if [ "${2:-}" = fresh ]; then
    rm -f "$parkidx"
    GIT_INDEX_FILE=$parkidx git -C "$1" read-tree HEAD 2>/dev/null || return 1
  fi
  GIT_INDEX_FILE=$parkidx git -C "$1" add -A . 2>/dev/null &&
    GIT_INDEX_FILE=$parkidx git -C "$1" write-tree 2>/dev/null
}

# Snapshot an idle worktree's work into refs/wip/<name> in the repo and print the
# ref. Uncommitted and untracked (not ignored) files become one commit on top of
# HEAD, built in a throwaway index so neither the branch nor the worktree's own
# index moves. The ref lives in the shared object store, so it outlives the
# checkout, is never pushed, and `git worktree add <path> refs/wip/<name>` brings
# the work back. A ref already holding the same tree (a run cut off before the
# removal) is reused, so an interrupted sweep does not mint a new ref nightly.
park() {
  _repo=$1; _wt=$2; _name=$3
  git check-ref-format "refs/wip/$_name" 2>/dev/null || return 1
  _head=$(git -C "$_wt" rev-parse -q --verify HEAD 2>/dev/null) || return 1
  _tip=$_head
  _tree=$(worktree_tree "$_wt" fresh) || return 1
  if [ "$_tree" != "$(git -C "$_wt" rev-parse "$_head^{tree}" 2>/dev/null)" ]; then
    _tip=$(git -C "$_wt" -c user.name=worktree-sweep -c user.email=worktree-sweep@localhost \
      commit-tree "$_tree" -p "$_head" \
      -m "wip: $_name, parked by worktree-sweep on $(hostname -s 2>/dev/null) $(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null) || return 1
  fi
  _wipref="refs/wip/$_name"
  if _old=$(git -C "$_repo" rev-parse -q --verify "$_wipref^{tree}" 2>/dev/null); then
    [ "$_old" = "$_tree" ] && { printf '%s' "$_wipref"; return 0; }
    _wipref="$_wipref-$now"
  fi
  git -C "$_repo" update-ref "$_wipref" "$_tip" 2>/dev/null || return 1
  [ "$(git -C "$_repo" rev-parse "$_wipref^{tree}" 2>/dev/null)" = "$_tree" ] || return 1
  printf '%s' "$_wipref"
}

sweep_repo() {
  repo=$1
  ref=$(default_ref "$repo") || { echo "skip (no default ref): $repo"; return 0; }
  wtdir="$repo/.agents/worktrees"
  [ -d "$wtdir" ] || return 0

  for wt in "$wtdir"/*/; do
    out_of_time && return 0
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
      ''|park:*|reclaim:*) ;;
      *)
        held=$((held + 1)); echo "$reason" >> "$reasons"
        [ "$DRY_RUN" = 1 ] && echo "held ($reason): $name"
        continue ;;
    esac

    if [ "$DRY_RUN" = 1 ]; then
      case $reason in
        park:*) echo "would park (${reason#park:}): $name"; parked=$((parked + 1)) ;;
        reclaim:*) echo "would reclaim (${reason#reclaim:}): $name"; swept=$((swept + 1)) ;;
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
    mentioned_since_scan "$wt" && again=recent-session
    if [ "$again" != "$reason" ]; then
      held=$((held + 1))
      echo "held (changed during sweep: ${again:-landed}): $name"
      continue
    fi

    case $reason in
      park:*)
        if ! wipref=$(park "$repo" "$wt" "$name"); then
          held=$((held + 1)); echo "failed or changed during sweep" >> "$reasons"; echo "held (could not park): $name"; continue
        fi
        # Salvage BEFORE the last look, so a write during the (up to 100 MB) copy
        # is caught by it rather than lost.
        if ! salv=$(salvage_ignored "$repo" "$wt"); then
          held=$((held + 1)); echo "failed or changed during sweep" >> "$reasons"; echo "held (ignored files not salvaged: $salv, kept $wipref): $name"; continue
        fi
        [ -n "$salv" ] && echo "$name: $salv"
        # Last look after the snapshot: anything written since would not be in
        # the ref, so the checkout stays (the ref is harmless and kept).
        snapshot_cwds
        if [ "$(blockers_for "$wt" "$ref" "$GRACE_DAYS")" != "$reason" ] ||
           [ "$(worktree_tree "$wt")" != "$(git -C "$repo" rev-parse "$wipref^{tree}" 2>/dev/null)" ]; then
          held=$((held + 1)); echo "failed or changed during sweep" >> "$reasons"; echo "held (changed while parking, kept $wipref): $name"; continue
        fi
        # --force only because the tree may be dirty; every byte of it is in the
        # ref, checked against the live tree just above. The branch is not touched.
        if git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1; then
          echo "parked: $name -> $wipref ($repo)"
          parked=$((parked + 1))
          [ "$PRESERVE" = 1 ] && echo "$name: $(publish_park "$repo" "$wipref" "$ref" "$name" "$branch")"
        else
          held=$((held + 1)); echo "failed or changed during sweep" >> "$reasons"; echo "held (git refused removal, kept $wipref): $name"
        fi
        continue ;;
    esac

    # A checkout killed mid-`worktree add` has no index, so every file reads as
    # untracked and a plain remove refuses it; --force is safe only because
    # is_abandoned_checkout re-proved, just above, no commit and no write since
    # its creation. It has nothing ignored to salvage.
    force=
    case $reason in
      reclaim:abandoned-checkout)
        git -C "$repo" worktree unlock "$wt" >/dev/null 2>&1 || true
        force=--force ;;
      *)
        if ! salv=$(salvage_ignored "$repo" "$wt"); then
          held=$((held + 1)); echo "failed or changed during sweep" >> "$reasons"; echo "held (ignored files not salvaged: $salv): $name"; continue
        fi
        [ -n "$salv" ] && echo "$name: $salv" ;;
    esac

    # No --force, so git refuses a tree with uncommitted changes. That is NOT an
    # independent check on the thing that matters: worktree removal does not look
    # at the commit graph, so a branch carrying an unmerged commit is removed
    # without complaint as long as the tree is clean (verified in review). The
    # remaining window is an agent COMMITTING between the re-read above and this
    # call, which leaves a clean tree and would let the deletion below destroy it.
    if git -C "$repo" worktree remove $force "$wt" >/dev/null 2>&1; then
      # FINAL proof, taken after the worktree is gone so no further commit can
      # land on it, and read from the BRANCH ref (which survives removal). Only a
      # branch still provably patch-equivalent upstream is deleted; anything else
      # is kept as a recoverable ref and reported.
      if [ "$branch" != "HEAD" ]; then
        if final=$(git -C "$repo" cherry "$ref" "$branch" 2>/dev/null) &&
           { [ -z "$final" ] || [ "$(printf '%s\n' "$final" | grep -c '^+')" -eq 0 ]; } &&
           [ -z "$(merges_with_changes "$repo" "$ref..$branch")" ]; then
          # The plain delete refuses a rebase-merged branch (it tests
          # reachability and the SHAs were rewritten), so fall back to the forced
          # form — only here, where patch-id has just re-proven the work landed.
          git -C "$repo" branch -d "$branch" >/dev/null 2>&1 ||
            git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
        else
          echo "kept branch (gained unmerged commits during sweep): $branch"
        fi
      fi
      echo "reclaimed${reason:+ (${reason#reclaim:})}: $name ($repo)"
      swept=$((swept + 1))
    else
      echo "held (git refused removal): $name"
      held=$((held + 1))
    fi
  done
  git -C "$repo" worktree prune >/dev/null 2>&1 || true

  # Parked work a previous run did not settle (gh unreachable, or the -R bug in
  # 532e520 that read every repo as not private) is published now. Each ref is
  # judged once per content: refs/wip-checked/<name> records the outcome.
  # At most RETRY_CAP per repo per run, so the first night does not open every
  # old park at once; judged against a freshly fetched default branch so the
  # pushed range is only what never landed.
  if [ "$PRESERVE" = 1 ] && [ "$DRY_RUN" != 1 ] &&
     git -C "$repo" for-each-ref --format='%(refname) %(objectname)' refs/wip/ > "$scratch" 2>/dev/null && [ -s "$scratch" ]; then
    $TO git -C "$repo" fetch -q origin </dev/null >/dev/null 2>&1 || true
    cp "$scratch" "$tarfile"
    _tries=0
    while read -r _wr _ws; do
      out_of_time && break
      [ "$_tries" -ge "$RETRY_CAP" ] && { echo "retry cap reached in $repo; the rest waits for the next run"; break; }
      _wn=${_wr#refs/wip/}
      [ "$(git -C "$repo" rev-parse -q --verify "refs/wip-checked/$_wn" 2>/dev/null)" = "$_ws" ] && continue
      _tries=$((_tries + 1))
      echo "$_wn: $(publish_park "$repo" "$_wr" "$ref" "$_wn" "(parked earlier)" </dev/null)"
    done < "$tarfile"
  fi
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

snapshot_cwds
# Transcripts named in the grace window, scanned once for every tree on the box.
# The scan stamp is taken BEFORE the list is built, so a transcript written during
# the scan is seen again by the pre-mutation check, never missed.
stamp_at "$gracestamp" $((now - GRACE_DAYS * 86400)) || { echo "could not set the grace stamp — skipping"; exit 1; }
touch "$scanstamp"
list_recent_transcripts "$gracestamp" > "$transcripts"
while IFS= read -r _c; do
  for _w in "$_c"/*/; do [ -d "$_w" ] && printf '%s\n' "${_w%/}"; done
done < "$wtlist" > "$patfile"
build_mentioned || { echo "could not scan transcripts — skipping"; exit 1; }

# --preserve publishes, so it needs a signed-in gh; without one, parking still
# keeps the work locally and nothing is pushed.
if [ "$PRESERVE" = 1 ] && [ "$DRY_RUN" != 1 ] && ! $TO gh auth status >/dev/null 2>&1; then
  echo "preserve off: gh is not signed in on $host; parked work stays local"
  PRESERVE=0
fi

while IFS= read -r wtdir; do
  out_of_time && { echo "stopped after ${BUDGET_SECONDS}s; the rest waits for the next run"; break; }
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

echo "worktree-sweep on $host: reclaimed=$swept parked=$parked held=$held"
# Why trees were kept. A bare "held=150" hid for weeks that most were checkouts
# nothing could ever reclaim.
[ -s "$reasons" ] && sort "$reasons" | uniq -c | sort -rn | sed 's/^ */  held: /'
exit 0
