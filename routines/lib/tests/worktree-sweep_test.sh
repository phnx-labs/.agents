#!/usr/bin/env bash
# Tests for routines/lib/worktree-sweep.sh — real repos, real worktrees, real
# merges. No mocks.
#
# This script DELETES worktrees and branches, and review of the abandoned CLI
# version of the same logic found three ways it could destroy the work it exists
# to protect. Each of those is pinned here as a case that FAILS against the buggy
# behaviour: the rebase-merge/patch-id gate, the fail-closed status probe, the
# path-boundary compare, and the re-read before mutating.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SWEEP="$HERE/../worktree-sweep.sh"
# Production runs this via `sh` (dash on the Linux boxes), NOT bash. An earlier
# revision passed this suite under bash while being a syntax error under dash —
# `done < <(find ...)` — so the routine had never run on any box. Drive it
# through the real interpreter, and pin that both parse it.
SH=$(command -v dash 2>/dev/null || command -v sh)
pass=0; fail=0

ok()   { echo "ok   - $1"; pass=$((pass+1)); }
bad()  { echo "FAIL - $1"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: wanted '$3', got '$2'"; fi; }

# The interpreter gate comes FIRST: a syntax error under the production shell
# makes every behaviour case below meaningless.
if "$SH" -n "$SWEEP" 2>/dev/null; then ok "parses under the production shell ($SH)"; else bad "SYNTAX ERROR under $SH — the routine could never run"; fi
if bash -n "$SWEEP" 2>/dev/null; then ok "parses under bash"; else bad "syntax error under bash"; fi

G=(-c user.email=t@t.dev -c user.name=t -c init.defaultBranch=main)
git_q() { git "${G[@]}" "$@" >/dev/null 2>&1; }

# NOT under /tmp: main-branch-guard treats a git primary there as protected
# (PHNX-2732), and these fixtures write into their own checkouts.
BASE=$(mktemp -d "$HOME/.agents-wtsweep-test-XXXXXX")
trap 'rm -rf "$BASE"' EXIT

ORIGIN="$BASE/origin.git"
REPO="$BASE/repo"
git_q init --bare -b main "$ORIGIN"
git_q clone "$ORIGIN" "$REPO"
echo one > "$REPO/a.txt"
# Real repos ignore .agents/; without it the `add .` below commits each worktree
# as a gitlink, and every later worktree inherits a phantom submodule.
printf '.agents/\n' > "$REPO/.gitignore"
git_q -C "$REPO" add .
git_q -C "$REPO" commit -m init
git_q -C "$REPO" push -u origin main
mkdir -p "$REPO/.agents/worktrees"

# Backdate a worktree past the grace window: the directory, every file in it, and
# its per-worktree HEAD and reflog, which is everything the sweep reads as activity.
backdate() { touch -h -d '30 days ago' "$@" 2>/dev/null || touch -h -t 202601010000 "$@"; }
age() {
  find "$1" -exec sh -c 'touch -h -d "30 days ago" "$@" 2>/dev/null || touch -h -t 202601010000 "$@"' _ {} +
  gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 0
  for f in "$gd/HEAD" "$gd/logs/HEAD" "$gd/ORIG_HEAD"; do [ -e "$f" ] && backdate "$f"; done
  return 0
}

new_wt() { # <name> <branch>
  git_q -C "$REPO" worktree add -b "$2" "$REPO/.agents/worktrees/$1" origin/main
}

# --- fixture 1: rebase-merged (SHAs rewritten) -> must be reclaimed ----------
new_wt merged feat/merged
echo feature > "$REPO/.agents/worktrees/merged/b.txt"
git_q -C "$REPO/.agents/worktrees/merged" add .
git_q -C "$REPO/.agents/worktrees/merged" commit -m 'add b'
# Advance main first so the replayed patch lands on a DIFFERENT parent, i.e. a
# genuinely different SHA — which is what a real rebase-merge produces. Without
# this the patch replays to an identical SHA and the case tests nothing.
echo moved > "$REPO/unrelated.txt"
git_q -C "$REPO" add .
git_q -C "$REPO" commit -m 'main moved on'
git "${G[@]}" -C "$REPO/.agents/worktrees/merged" format-patch -1 --stdout > "$BASE/p.patch" 2>/dev/null
git_q -C "$REPO" am "$BASE/p.patch"
git_q -C "$REPO" push origin main
git_q -C "$REPO" fetch origin
age "$REPO/.agents/worktrees/merged"

# Ancestry must disagree with patch-id here, or the fixture is not exercising it.
if git "${G[@]}" -C "$REPO" merge-base --is-ancestor feat/merged origin/main 2>/dev/null; then
  bad "fixture: rebase-merged branch should NOT be an ancestor (fixture is not testing the trap)"
else
  ok "fixture: rebase-merged branch is not an ancestor (ancestry would call it unmerged)"
fi

# --- fixture 2: unpushed work -> must be held -------------------------------
new_wt unpushed feat/unpushed
echo secret > "$REPO/.agents/worktrees/unpushed/c.txt"
git_q -C "$REPO/.agents/worktrees/unpushed" add .
git_q -C "$REPO/.agents/worktrees/unpushed" commit -m 'never pushed'
age "$REPO/.agents/worktrees/unpushed"

# --- fixture 3: dirty tree -> must be held ----------------------------------
new_wt dirty feat/dirty
echo scratch > "$REPO/.agents/worktrees/dirty/uncommitted.txt"
age "$REPO/.agents/worktrees/dirty"

# --- fixture 4: fresh but merged -> held by the grace window ----------------
new_wt fresh feat/fresh

# --- fixture 4b: idle by directory age, but a file was edited just now --------
# The directory mtime moves only when a top-level entry is added or removed, so
# an agent editing an existing file read as idle. It must be held, not parked.
new_wt editing feat/editing
echo draft > "$REPO/.agents/worktrees/editing/a.txt"
age "$REPO/.agents/worktrees/editing"
echo "still typing" > "$REPO/.agents/worktrees/editing/a.txt"

# --- fixture 4c: everything old, but a process sits inside -------------------
# An agent can idle for days between turns; its shell's cwd is the tell.
new_wt occupied feat/occupied
echo wip > "$REPO/.agents/worktrees/occupied/w.txt"
age "$REPO/.agents/worktrees/occupied"

# --- review findings on parking: each must be HELD, checkout intact ----------
W="$REPO/.agents/worktrees"
# A nested repo in an untracked dir: `add -A` would keep only a gitlink.
new_wt nested feat/nested
git_q init -b main "$W/nested/inner"
echo inner > "$W/nested/inner/i.txt"; git_q -C "$W/nested/inner" add .; git_q -C "$W/nested/inner" commit -m inner
echo unsaved > "$W/nested/inner/u.txt"
age "$W/nested"
# A submodule: its edits and unpushed commits are not in the parent's tree.
SUBORIGIN="$BASE/sub-origin"
git_q init -b main "$SUBORIGIN"; echo s > "$SUBORIGIN/s"; git_q -C "$SUBORIGIN" add .; git_q -C "$SUBORIGIN" commit -m s
new_wt submod feat/submod
git_q -C "$W/submod" -c protocol.file.allow=always submodule add "$SUBORIGIN" sm
git_q -C "$W/submod" commit -m 'add submodule'
echo edited > "$W/submod/sm/s"
age "$W/submod"
# Ignored local config is never committed, so --force would delete it: it is
# copied to ~/.agents-swept/<date>/<repo>/<tree>/ first, then the tree is parked.
new_wt envcfg feat/envcfg
printf '.env\n' > "$W/envcfg/.gitignore"
echo SECRET=1 > "$W/envcfg/.env"
age "$W/envcfg"
# A merge in progress lives in the admin dir and would be lost.
new_wt merging feat/merging
echo m > "$W/merging/m.txt"
age "$W/merging"
git -C "$W/merging" rev-parse HEAD > "$(git -C "$W/merging" rev-parse --absolute-git-dir)/MERGE_HEAD"
# 2100 files in one untracked dir: one porcelain line without -uall.
new_wt bulky feat/bulky
mkdir -p "$W/bulky/out"
i=0; while [ $i -lt 2100 ]; do : > "$W/bulky/out/f$i"; i=$((i+1)); done
age "$W/bulky"
# A file deep in an untracked dir edited now: the dir's mtime does not move.
new_wt deepedit feat/deepedit
mkdir -p "$W/deepedit/notes/sub"; echo v1 > "$W/deepedit/notes/sub/n.txt"
age "$W/deepedit"
echo v2 > "$W/deepedit/notes/sub/n.txt"
# A name git C-quotes cannot be stat'd from porcelain: unjudgeable, so held.
new_wt quoted feat/quoted
echo q > "$W/quoted/q\"u"
age "$W/quoted"
(cd "$REPO/.agents/worktrees/occupied/" && exec sleep 300) &
OCCUPANT=$!
trap 'kill "$OCCUPANT" 2>/dev/null; rm -rf "$BASE"' EXIT
sleep 1

# --- fixture 5+6: prefix pair, both merged, to pin boundary matching --------
new_wt fix-110 feat/fix-110
new_wt fix-1103 feat/fix-1103
age "$REPO/.agents/worktrees/fix-110"
age "$REPO/.agents/worktrees/fix-1103"

# The allowlist matches on remote.origin.url, so the in-scope fixture needs an
# in-scope URL — but only NOW, after every fixture push is done: rewriting it
# earlier points `push origin main` at a nonexistent GitHub repo, main never
# advances, and the "merged" fixture stops being merged. Remote-tracking refs
# already fetched stay valid, which is all the sweep reads.
git_q -C "$REPO" remote set-url origin "git@github.com:phnx-labs/fixture-repo.git"

# ---------------------------------------------------------------- dry run ---
out=$("$SH" "$SWEEP" --home "$BASE" --grace-days 3 --dry-run 2>&1)

case "$out" in *"would reclaim: merged"*) ok "dry-run reclaims the rebase-merged worktree (patch-id, not ancestry)";;
  *) bad "dry-run missed the rebase-merged worktree: $out";; esac
case "$out" in *"would park (unmerged-commits): unpushed"*) ok "dry-run parks idle unpushed work";;
  *) bad "dry-run did not plan to park idle unpushed work: $out";; esac
case "$out" in *"would park (uncommitted-changes): dirty"*) ok "dry-run parks an idle dirty tree";;
  *) bad "dry-run did not plan to park the idle dirty tree: $out";; esac
case "$out" in *"held (within-grace): editing"*) ok "dry-run holds a tree whose file was edited just now (not the dir mtime)";;
  *) bad "dry-run did not hold the recently edited tree: $out";; esac
case "$out" in *"held (in-use): occupied"*) ok "dry-run holds a tree a process is sitting in";;
  *) bad "dry-run did not hold the occupied tree: $out";; esac
for pair in "nested-repo:nested" "has-submodules:submod" \
            "operation-in-progress:merging" "too-many-changes-to-park:bulky" \
            "within-grace:deepedit" "within-grace:quoted"; do
  case "$out" in *"held (${pair%%:*}): ${pair#*:}"*) ok "dry-run holds ${pair#*:} (${pair%%:*})";;
    *) bad "dry-run did not hold ${pair#*:} as ${pair%%:*}: $(printf '%s\n' "$out" | grep ": ${pair#*:}$")";; esac
done
case "$out" in *"held (within-grace): fresh"*) ok "dry-run holds a worktree inside the grace window";;
  *) bad "dry-run did not hold the fresh worktree: $out";; esac

# A dry run must not have touched anything.
[ -d "$REPO/.agents/worktrees/merged" ] && ok "dry-run removed nothing" || bad "dry-run deleted a worktree"

# ------------------------------------------------------------- real sweep ---
out=$("$SH" "$SWEEP" --home "$BASE" --grace-days 3 2>&1)

[ ! -d "$REPO/.agents/worktrees/merged" ] && ok "merged worktree removed" || bad "merged worktree survived"
[ ! -d "$REPO/.agents/worktrees/unpushed" ] && ok "idle unpushed checkout reclaimed" || bad "idle unpushed checkout survived"
check "UNPUSHED WORK PARKED: refs/wip/unpushed is the branch tip" \
  "$(git -C "$REPO" rev-parse -q --verify refs/wip/unpushed 2>/dev/null)" "$(git -C "$REPO" rev-parse feat/unpushed)"
[ ! -d "$REPO/.agents/worktrees/dirty" ] && ok "idle dirty checkout reclaimed" || bad "idle dirty checkout survived"
check "UNCOMMITTED WORK PARKED: refs/wip/dirty holds the untracked file" \
  "$(git -C "$REPO" show refs/wip/dirty:uncommitted.txt 2>/dev/null)" "scratch"
check "parked commit sits on the branch tip, branch itself untouched" \
  "$(git -C "$REPO" rev-parse refs/wip/dirty^ 2>/dev/null)" "$(git -C "$REPO" rev-parse feat/dirty)"
case "$out" in *"parked: dirty -> refs/wip/dirty"*) ok "parking is reported with its ref";;
  *) bad "no 'parked:' line naming the ref: $out";; esac
[ -d "$REPO/.agents/worktrees/editing" ] && ok "recently edited worktree preserved" || bad "recently edited worktree destroyed"
[ -d "$REPO/.agents/worktrees/occupied" ] && ok "OCCUPIED WORKTREE PRESERVED" || bad "worktree with a live process inside was removed"
for n in nested submod merging bulky deepedit quoted; do
  [ -d "$REPO/.agents/worktrees/$n" ] && ok "$n checkout preserved" || bad "$n checkout was removed"
done
check "nested repo's uncommitted file survives" "$(cat "$REPO/.agents/worktrees/nested/inner/u.txt" 2>/dev/null)" "unsaved"
check "submodule edit survives" "$(cat "$REPO/.agents/worktrees/submod/sm/s" 2>/dev/null)" "edited"
check "ignored .env is SALVAGED before the tree is parked" "$(cat "$BASE/.agents-swept/"*/repo/envcfg/.env 2>/dev/null)" "SECRET=1"
[ "$(stat -c %a "$BASE/.agents-swept" 2>/dev/null || stat -f %Lp "$BASE/.agents-swept")" = 700 ] &&
  ok "the salvage directory is private (700)" || bad "salvage directory is not 0700"
kill "$OCCUPANT" 2>/dev/null
[ -d "$REPO/.agents/worktrees/fresh" ]    && ok "in-grace worktree preserved" || bad "in-grace worktree destroyed"

# The rebase-merged branch must be gone: `-d` refuses it (rewritten SHAs), so the
# `-D` fallback has to fire, gated on patch-id having proven the work landed.
if [ -z "$(git "${G[@]}" -C "$REPO" branch --list feat/merged)" ]; then
  ok "merged branch deleted (the -D fallback fired after patch-id proof)"
else
  bad 'merged branch survived: -d refused it and the -D fallback did not fire'
fi
# The branch holding unpushed work must still exist.
if [ -n "$(git "${G[@]}" -C "$REPO" branch --list feat/unpushed)" ]; then
  ok "UNPUSHED BRANCH PRESERVED"
else
  bad "unpushed branch was deleted — commits lost"
fi

# Both prefix-pair worktrees were merged and aged, so both go; the point is that
# neither took the other's place, and both branches resolved independently.
if [ ! -d "$REPO/.agents/worktrees/fix-110" ] && [ ! -d "$REPO/.agents/worktrees/fix-1103" ]; then
  ok "prefix pair (fix-110 / fix-1103) both handled on their own identity"
else
  bad "prefix pair mishandled: fix-110=$([ -d "$REPO/.agents/worktrees/fix-110" ] && echo present || echo gone) fix-1103=$([ -d "$REPO/.agents/worktrees/fix-1103" ] && echo present || echo gone)"
fi

# ------------------------------------------- fail closed on unreadable state --
# A worktree whose git dir cannot be read must be HELD, not treated as clean.
# This is the index.lock case: an unreadable status is the tree most likely to
# be holding a live agent's work.
new_wt broken feat/broken
age "$REPO/.agents/worktrees/broken"
mv "$REPO/.agents/worktrees/broken/.git" "$REPO/.agents/worktrees/broken/.git-hidden"
out=$("$SH" "$SWEEP" --home "$BASE" --grace-days 3 2>&1)
if [ -d "$REPO/.agents/worktrees/broken" ]; then
  ok "unreadable git state HELD, not swept (fails closed)"
else
  bad "unreadable git state was swept — fail-open"
fi
mv "$REPO/.agents/worktrees/broken/.git-hidden" "$REPO/.agents/worktrees/broken/.git" 2>/dev/null || true

# ------------------------------------------------ no default ref => no action --
NOREMOTE="$BASE/noremote"
git_q init -b main "$NOREMOTE"
echo x > "$NOREMOTE/f.txt"; git_q -C "$NOREMOTE" add .; git_q -C "$NOREMOTE" commit -m init
mkdir -p "$NOREMOTE/.agents/worktrees"
git_q -C "$NOREMOTE" worktree add -b feat/x "$NOREMOTE/.agents/worktrees/x"
age "$NOREMOTE/.agents/worktrees/x"
out=$("$SH" "$SWEEP" --home "$BASE" --grace-days 3 2>&1)
if [ -d "$NOREMOTE/.agents/worktrees/x" ]; then
  ok "repo with no default ref is skipped, not swept"
else
  bad "swept a repo with no default ref to compare against"
fi

# --- BLOCKER A: allowlist gates the blast radius --------------------------
# Discovery matches directory SHAPE, so without an allowlist this reaches any
# checkout using worktree law — including personal repos. Proven on the real box:
# $HOME/.agents (muqsitnawaz/.agents) has a clean 48-day-old `blog-engine`
# worktree. A merged+clean+aged worktree in an OUT-OF-SCOPE repo must survive.
OUTSIDE="$BASE/personal"
git_q init --bare -b main "$BASE/personal-origin.git"
git_q clone "$BASE/personal-origin.git" "$OUTSIDE"
echo hi > "$OUTSIDE/a.txt"; git_q -C "$OUTSIDE" add .; git_q -C "$OUTSIDE" commit -m init
# PUSH FIRST, so origin/main exists and default_ref() succeeds. Without this the
# repo is skipped as "no default ref" before the allowlist is ever consulted, and
# the assertion below passes even with the allowlist disabled — it would be
# testing nothing (caught in review).
git_q -C "$OUTSIDE" push -u origin main
mkdir -p "$OUTSIDE/.agents/worktrees"
git_q -C "$OUTSIDE" worktree add -b feat/blog "$OUTSIDE/.agents/worktrees/blog-engine"
age "$OUTSIDE/.agents/worktrees/blog-engine"
# Only NOW make it out-of-scope, so the allowlist is the sole reason it survives.
git_q -C "$OUTSIDE" remote set-url origin "git@github.com:someone-else/personal-blog.git"
out=$("$SH" "$SWEEP" --home "$BASE" --grace-days 3 2>&1)
if [ -d "$OUTSIDE/.agents/worktrees/blog-engine" ]; then
  ok "OUT-OF-SCOPE repo untouched (allowlist gates blast radius)"
else
  bad "swept a repo outside the allowlist — personal work destroyed"
fi
case "$out" in *"not in allowlist"*) ok "out-of-scope repo is reported, not silently skipped";;
  *) bad "no allowlist message for the out-of-scope repo: $out";; esac

# An allowlisted org appearing as a NESTED path segment on an unrelated host must
# NOT match. An unanchored '[:/]phnx-labs/' let
# https://gitlab.example.com/mirror-of/phnx-labs/x.git through, and the worktree
# was destructively swept (demonstrated in review).
NESTED="$BASE/nested"
git_q init --bare -b main "$BASE/nested-origin.git"
git_q clone "$BASE/nested-origin.git" "$NESTED"
echo n > "$NESTED/f.txt"; git_q -C "$NESTED" add .; git_q -C "$NESTED" commit -m init
git_q -C "$NESTED" push -u origin main
mkdir -p "$NESTED/.agents/worktrees"
git_q -C "$NESTED" worktree add -b feat/n "$NESTED/.agents/worktrees/nested-victim"
age "$NESTED/.agents/worktrees/nested-victim"
git_q -C "$NESTED" remote set-url origin "https://gitlab.example.com/mirror-of/phnx-labs/x.git"
out=$("$SH" "$SWEEP" --home "$BASE" --grace-days 3 2>&1)
if [ -d "$NESTED/.agents/worktrees/nested-victim" ]; then
  ok "org as a NESTED path segment on another host is denied (anchored allowlist)"
else
  bad "allowlist bypassed by a nested org path — repo swept"
fi

# A DotAgents config repo is never swept even when its org IS allowlisted.
CFG="$BASE/dotagents"
git_q init --bare -b main "$BASE/dotagents-origin.git"
git_q clone "$BASE/dotagents-origin.git" "$CFG"
git_q -C "$CFG" remote set-url origin "git@github.com:muqsitnawaz/.agents.git"
echo x > "$CFG/f.txt"; git_q -C "$CFG" add .; git_q -C "$CFG" commit -m init
mkdir -p "$CFG/.agents/worktrees"
git_q -C "$CFG" worktree add -b feat/cfg "$CFG/.agents/worktrees/cfgwt"
age "$CFG/.agents/worktrees/cfgwt"
out=$("$SH" "$SWEEP" --home "$BASE" --grace-days 3 2>&1)
if [ -d "$CFG/.agents/worktrees/cfgwt" ]; then
  ok "DotAgents config repo untouched despite allowlisted org"
else
  bad "swept a DotAgents config repo"
fi

# --- the branch-delete RACE the final re-check exists to close ---------------
# `git worktree remove` (no --force) refuses only on UNCOMMITTED changes; it never
# looks at the commit graph. So an agent that COMMITS between the pre-removal
# re-check and the removal leaves a clean tree, the removal succeeds, and an
# unconditional delete would then destroy that commit.
#
# Reproduced deterministically with a `git` shim on PATH that lands a commit on
# the branch at the instant the sweep calls `worktree remove`, then forwards to
# real git. Without this case the guard can be reverted to an unconditional
# delete and the whole suite still passes (verified in review) — i.e. the fix
# would have no regression protection at all.
RACE_REPO="$BASE/racerepo"
git_q init --bare -b main "$BASE/race-origin.git"
git_q clone "$BASE/race-origin.git" "$RACE_REPO"
echo r > "$RACE_REPO/f.txt"; git_q -C "$RACE_REPO" add .; git_q -C "$RACE_REPO" commit -m init
git_q -C "$RACE_REPO" push -u origin main
mkdir -p "$RACE_REPO/.agents/worktrees"
git_q -C "$RACE_REPO" worktree add -b feat/race "$RACE_REPO/.agents/worktrees/racewt" origin/main
age "$RACE_REPO/.agents/worktrees/racewt"
git_q -C "$RACE_REPO" remote set-url origin "git@github.com:phnx-labs/race-fixture.git"

SHIMDIR="$BASE/shim"; mkdir -p "$SHIMDIR"
REALGIT=$(command -v git)
cat > "$SHIMDIR/git" <<SHIM
#!/bin/sh
# On the removal of the race worktree ONLY, land a commit on its branch first —
# exactly the window the final re-check must catch. Everything else passes through.
for a in "\$@"; do
  if [ "\$a" = "$RACE_REPO/.agents/worktrees/racewt" ]; then
    case " \$* " in
      *" worktree remove "*)
        "$REALGIT" -C "$RACE_REPO/.agents/worktrees/racewt" \
          -c user.email=t@t.dev -c user.name=t commit --allow-empty -q -m "race commit" 2>/dev/null
        ;;
    esac
  fi
done
exec "$REALGIT" "\$@"
SHIM
chmod +x "$SHIMDIR/git"

out=$(PATH="$SHIMDIR:$PATH" "$SH" "$SWEEP" --home "$BASE" --grace-days 3 2>&1)
if [ -n "$(git "${G[@]}" -C "$RACE_REPO" branch --list feat/race)" ]; then
  ok "RACE: branch that gained a commit mid-sweep is KEPT, not deleted"
else
  bad "RACE: branch deleted despite gaining an unmerged commit — work destroyed"
fi
case "$out" in *"gained unmerged commits during sweep"*)
    ok "RACE: the kept branch is reported, not silently skipped";;
  *) bad "RACE: no 'gained unmerged commits' message: $out";; esac

# =========================================== abandoned checkouts, transcripts,
# .agents-keep, merge commits, salvage, signals and --preserve. A separate home:
# its repos fetch from an allowlisted GitHub URL but push to a local bare repo.
P="$BASE/p"; mkdir -p "$P"
REALGIT=$(command -v git)
HOST=$(hostname -s 2>/dev/null || echo unknown)
mkrepo() { # <name> -> $P/<name>, origin $P/<name>.git
  git_q init --bare -b main "$P/$1.git"
  git_q clone "$P/$1.git" "$P/$1"
  echo x > "$P/$1/f.txt"; git_q -C "$P/$1" add .; git_q -C "$P/$1" commit -m init
  git_q -C "$P/$1" push -u origin main
  mkdir -p "$P/$1/.agents/worktrees"
  git_q -C "$P/$1" remote set-url origin "git@github.com:phnx-labs/wtsweep-fixture-$1.git"
  git_q -C "$P/$1" remote set-url --push origin "$P/$1.git"
}
wt_in() { git_q -C "$P/$1" worktree add -b "feat/$2" "$P/$1/.agents/worktrees/$2" origin/main; }
WT() { echo "$P/$1/.agents/worktrees/$2"; }
sweep() { "$SH" "$SWEEP" --home "$P" --grace-days 3 "$@" 2>&1; }
mkrepo r

# A `git worktree add` killed mid-checkout: "initializing" lock, no index.
wt_in r abandoned
age "$(WT r abandoned)"
GD=$(git -C "$(WT r abandoned)" rev-parse --absolute-git-dir)
rm -f "$GD/index"; : > "$GD/index.lock"; echo initializing > "$GD/locked"
# The same shape, but a file was written a day after it was created.
wt_in r written
age "$(WT r written)"
GD2=$(git -C "$(WT r written)" rev-parse --absolute-git-dir)
rm -f "$GD2/index"; echo initializing > "$GD2/locked"
echo later > "$(WT r written)/later.txt"
touch -d '20 days ago' "$(WT r written)/later.txt" 2>/dev/null || touch -t 202601200000 "$(WT r written)/later.txt"
dry=$(sweep --dry-run)
out=$(sweep)
[ ! -d "$(WT r abandoned)" ] && ok "ABANDONED checkout (no index, 'initializing' lock) reclaimed" || bad "abandoned checkout survived: $(printf '%s\n' "$dry" | grep -E ': (abandoned|written)$')"
[ -d "$(WT r written)" ] && ok "an abandoned-looking tree written after creation is HELD" || bad "a tree with later writes was force-removed"

# Named in a recent transcript: an agent working on it by absolute path.
wt_in r mentioned
age "$(WT r mentioned)"
mkdir -p "$P/.claude/projects/x"
printf '{"tool_input":{"file_path":"%s/f.txt"}}\n' "$(WT r mentioned)" > "$P/.claude/projects/x/s.jsonl"
# A harness config or the activity feed naming it is not a session working on it.
wt_in r configured
age "$(WT r configured)"
mkdir -p "$P/.agents/.history/versions/claude/9.9.9/home" "$P/.agents/.history/activity"
printf '{"projects":{"%s":{}}}\n' "$(WT r configured)" > "$P/.agents/.history/versions/claude/9.9.9/home/.claude.json"
printf '{"event":"worktree.created","path":"%s"}\n' "$(WT r configured)" > "$P/.agents/.history/activity/a.jsonl"
out=$(sweep --dry-run)
case "$out" in *"held (recent-session): mentioned"*) ok "a tree named in a RECENT TRANSCRIPT is held";;
  *) bad "recent transcript mention not detected: $out";; esac
case "$out" in *"would reclaim: configured"*) ok "a harness CONFIG or the activity feed naming a tree does not hold it";;
  *) bad "config/activity mention held the tree: $(printf '%s\n' "$out" | grep ': configured$')";; esac
mv "$P/.agents" "$BASE/p-agents-done"

# A session that names many trees at once (a disk survey, an inventory) is not
# working in any of them: its mentions do not hold.
for i in 1 2 3 4 5 6; do wt_in r surveyed$i; age "$(WT r surveyed$i)"; done
mkdir -p "$P/.claude/projects/y"
for i in 1 2 3 4 5 6; do printf 'du -sh %s\n' "$(WT r surveyed$i)"; done > "$P/.claude/projects/y/survey.jsonl"
out=$(sweep --dry-run)
case "$out" in *"would reclaim: surveyed3"*) ok "a SURVEY naming more than 5 trees does not hold them";;
  *) bad "a survey's mentions held the tree: $(printf '%s\n' "$out" | grep ': surveyed3$')";; esac
mv "$P/.claude" "$BASE/p-claude-survey-done"
rm -rf "$P/.claude"

# .agents-keep opts one tree out.
wt_in r kept
: > "$(WT r kept)/.agents-keep"
age "$(WT r kept)"
out=$(sweep --dry-run)
case "$out" in *"held (keep-marker): kept"*) ok ".agents-keep holds the tree";; *) bad ".agents-keep ignored: $out";; esac

# Work that lives only in a MERGE commit: `git cherry` skips merges, so the old
# check called it landed and deleted the branch (reproduced in review).
git_q -C "$P/r" commit --allow-empty -m 'main moves'; git_q -C "$P/r" push origin main; git_q -C "$P/r" fetch origin
wt_in r evil
git_q -C "$(WT r evil)" reset -q --hard origin/main~1
git_q -C "$(WT r evil)" merge --no-ff --no-commit origin/main
echo only-here > "$(WT r evil)/unique.txt"; git_q -C "$(WT r evil)" add unique.txt
git_q -C "$(WT r evil)" commit -m 'merge with an extra file'
age "$(WT r evil)"
# A plain catch-up merge adds nothing: that tree has landed.
wt_in r catchup
git_q -C "$(WT r catchup)" reset -q --hard origin/main~1
git_q -C "$(WT r catchup)" merge --no-ff -m 'catch up' origin/main
age "$(WT r catchup)"
out=$(sweep --dry-run)
case "$out" in *"would park (merge-with-changes): evil"*) ok "work only in a MERGE commit is parked, never treated as landed";;
  *) bad "merge-only work misjudged: $(printf '%s\n' "$out" | grep ': evil$')";; esac
case "$out" in *"would reclaim: catchup"*) ok "a plain catch-up merge does not hold a landed tree";;
  *) bad "catch-up merge held the tree: $(printf '%s\n' "$out" | grep ': catchup$')";; esac

# Gitignored files that are not caches are salvaged; caches are not.
wt_in r ign
age "$(WT r ign)"
printf 'precious.txt\nnode_modules/\n' > "$(WT r ign)/.git-info-exclude"
printf 'precious.txt\nnode_modules/\n' >> "$(git -C "$(WT r ign)" rev-parse --git-common-dir)/info/exclude"
echo keep-me > "$(WT r ign)/precious.txt"; mkdir -p "$(WT r ign)/node_modules/x"; echo junk > "$(WT r ign)/node_modules/x/i.js"
rm -f "$(WT r ign)/.git-info-exclude"
age "$(WT r ign)"
out=$(sweep)
if [ ! -d "$(WT r ign)" ] && [ "$(cat "$P/.agents-swept/"*/r/ign/precious.txt 2>/dev/null)" = keep-me ]; then
  ok "a GITIGNORED file is salvaged before a landed tree is removed"
else
  bad "ignored file not salvaged: $out"
fi
[ ! -e "$P/.agents-swept/"*/r/ign/node_modules ] && ok "caches are not salvaged" || bad "node_modules was salvaged"

# A TERM mid-sweep ends the run. A handler that only cleaned up let the script
# carry on with its inputs deleted, removing fresh trees (reproduced in review).
wt_in r term-fresh
SLOW="$BASE/slowshim"; mkdir -p "$SLOW"
cat > "$SLOW/git" <<SHIM
#!/bin/sh
case " \$* " in *" worktree list "*) sleep 2 ;; esac
exec "$REALGIT" "\$@"
SHIM
chmod +x "$SLOW/git"
PATH="$SLOW:$PATH" "$SH" "$SWEEP" --home "$P" --grace-days 3 > "$BASE/term.out" 2>&1 & TPID=$!
sleep 1; kill -TERM "$TPID" 2>/dev/null; wait "$TPID"; trc=$?
[ "$trc" -ne 0 ] && ok "TERM ends the run (exit $trc)" || bad "the run kept going after TERM"
[ -d "$(WT r term-fresh)" ] && ok "a fresh tree survives a TERM mid-run" || bad "fresh tree removed after TERM: $(cat "$BASE/term.out")"

# --preserve parks first (the work is safe locally whatever happens next), then
# publishes only what passes the checks to a repo confirmed PRIVATE. A stand-in
# `gh` answers auth, repo visibility (FAKE_GH_PRIVATE) and PRs; pushes go to the
# fixture's local bare origin, so the publish path runs for real.
FAKEGH="$BASE/fakegh"; mkdir -p "$FAKEGH"
cat > "$FAKEGH/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view") echo "${FAKE_GH_PRIVATE:-false}" ;;
  "pr list") : ;;
  "pr create") echo "https://example.invalid/pull/1" ;;
  *) exit 1 ;;
esac
GH
chmod +x "$FAKEGH/gh"
psweep() { PATH="$FAKEGH:$PATH" sweep --preserve "$@"; }
wip_on_origin() { "$REALGIT" -C "$P/r.git" rev-parse -q --verify "refs/heads/wip/$HOST/$1" >/dev/null 2>&1; }

# Not confirmed private: parked locally, nothing pushed.
wt_in r pubpublic
echo work > "$(WT r pubpublic)/work.txt"
age "$(WT r pubpublic)"
out=$(FAKE_GH_PRIVATE=false psweep)
check "--preserve still PARKS locally first" "$(git -C "$P/r" show refs/wip/pubpublic:work.txt 2>/dev/null)" "work"
case "$out" in *"pubpublic: not published (phnx-labs/wtsweep-fixture-r is not confirmed private)"*)
    ok "nothing is published unless gh confirms the repo private";;
  *) bad "no private-repo refusal: $(printf '%s\n' "$out" | grep pubpublic)";; esac
wip_on_origin pubpublic && bad "pushed to a repo not confirmed private" || ok "no wip branch for a repo not confirmed private"

# Private, clean: pushed to wip/<host>/<name> and a draft PR opened.
wt_in r pubok
echo work > "$(WT r pubok)/work.txt"
age "$(WT r pubok)"
# Each way a secret or junk could ride along, all on a private repo.
wt_in r pubsecret
echo TOKEN=x > "$(WT r pubsecret)/.env.local"
age "$(WT r pubsecret)"
wt_in r pubinline
printf 'token = "ghp_%s"\n' abcdefghijklmnopqrstuvwxyz0123456789 > "$(WT r pubinline)/notes.txt"
age "$(WT r pubinline)"
wt_in r pubspace
# Committed: an untracked name with a space is quoted by `git status`, so the
# activity check already holds such a tree as unjudgeable.
printf 'k = "ghp_%s"\n' abcdefghijklmnopqrstuvwxyz0123456789 > "$(WT r pubspace)/my notes.txt"
git_q -C "$(WT r pubspace)" add "my notes.txt"; git_q -C "$(WT r pubspace)" commit -m notes
age "$(WT r pubspace)"
# A key committed and then deleted is still in the pushed history.
wt_in r pubhist
echo 'AKIAABCDEFGHIJKLMNOP' > "$(WT r pubhist)/hist.txt"
git_q -C "$(WT r pubhist)" add hist.txt; git_q -C "$(WT r pubhist)" commit -m add
git_q -C "$(WT r pubhist)" rm -q hist.txt; git_q -C "$(WT r pubhist)" commit -m remove
age "$(WT r pubhist)"
wt_in r pubhistenv
echo S=1 > "$(WT r pubhistenv)/.env"
git_q -C "$(WT r pubhistenv)" add -f .env; git_q -C "$(WT r pubhistenv)" commit -m add
git_q -C "$(WT r pubhistenv)" rm -q .env; git_q -C "$(WT r pubhistenv)" commit -m remove
age "$(WT r pubhistenv)"
# A big blob in history, and a key among 3,000 committed files (no path list on
# any command line).
wt_in r pubbig
head -c 6000000 /dev/zero > "$(WT r pubbig)/big.bin"
git_q -C "$(WT r pubbig)" add big.bin; git_q -C "$(WT r pubbig)" commit -m big
git_q -C "$(WT r pubbig)" rm -q big.bin; git_q -C "$(WT r pubbig)" commit -m unbig
age "$(WT r pubbig)"
wt_in r pubmany
mkdir -p "$(WT r pubmany)/many"
i=0; while [ $i -lt 3000 ]; do echo "$i" > "$(WT r pubmany)/many/a-rather-long-file-name-to-fill-the-argument-list-$i.txt"; i=$((i+1)); done
echo 'AKIAABCDEFGHIJKLMNOP' > "$(WT r pubmany)/many/a-rather-long-file-name-to-fill-the-argument-list-1500.txt"
git_q -C "$(WT r pubmany)" add many; git_q -C "$(WT r pubmany)" commit -m many
age "$(WT r pubmany)"
out=$(FAKE_GH_PRIVATE=true psweep)
case "$out" in *"pubok: published: https://example.invalid/pull/1"*) ok "a clean parked tree on a private repo is PUBLISHED as a draft PR";;
  *) bad "clean tree not published: $(printf '%s\n' "$out" | grep pubok)";; esac
check "the published branch carries the work" "$("$REALGIT" -C "$P/r.git" show "wip/$HOST/pubok:work.txt" 2>/dev/null)" "work"
for pair in "suspect file names:pubsecret" "suspect file contents:pubinline" "suspect file contents:pubspace" \
            "suspect file contents:pubhist" "suspect file names:pubhistenv" "a file over 5 MB:pubbig" \
            "suspect file contents:pubmany"; do
  n=${pair#*:}; why=${pair%%:*}
  case "$out" in *"$n: not published ($why)"*) ok "not published: $n ($why)";;
    *) bad "$n was not refused as '$why': $(printf '%s\n' "$out" | grep "^$n:")";; esac
  wip_on_origin "$n" && bad "$n was PUSHED" || ok "nothing pushed for $n"
done

# The summary says why trees were kept.
out=$(sweep --dry-run)
case "$out" in *"  held: "*) ok "the run summary lists hold reasons";; *) bad "no hold reasons in the summary: $out";; esac

echo "---"
echo "worktree-sweep: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
