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
git_q -C "$REPO" add .
git_q -C "$REPO" commit -m init
git_q -C "$REPO" push -u origin main
mkdir -p "$REPO/.agents/worktrees"

# Backdate a worktree past the grace window: every file in it and in its git dir,
# since the sweep reads the newest change in either, not the directory's mtime.
age() {
  _gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)
  find "$1" ${_gd:+"$_gd"} -exec touch -d '30 days ago' {} + 2>/dev/null ||
    find "$1" ${_gd:+"$_gd"} -exec touch -t 202601010000 {} +
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

case "$out" in *"would reclaim (merged): merged"*) ok "dry-run reclaims the rebase-merged worktree (patch-id, not ancestry)";;
  *) bad "dry-run missed the rebase-merged worktree: $out";; esac
case "$out" in *"held (unmerged-commits): unpushed"*) ok "dry-run holds unpushed work";;
  *) bad "dry-run did not hold unpushed work: $out";; esac
case "$out" in *"held (uncommitted-changes): dirty"*) ok "dry-run holds a dirty tree";;
  *) bad "dry-run did not hold the dirty tree: $out";; esac
case "$out" in *"held (within-grace): fresh"*) ok "dry-run holds a worktree inside the grace window";;
  *) bad "dry-run did not hold the fresh worktree: $out";; esac

# A dry run must not have touched anything.
[ -d "$REPO/.agents/worktrees/merged" ] && ok "dry-run removed nothing" || bad "dry-run deleted a worktree"

# ------------------------------------------------------------- real sweep ---
out=$("$SH" "$SWEEP" --home "$BASE" --grace-days 3 2>&1)

[ ! -d "$REPO/.agents/worktrees/merged" ] && ok "merged worktree removed" || bad "merged worktree survived"
[ -d "$REPO/.agents/worktrees/unpushed" ] && ok "UNPUSHED WORK PRESERVED" || bad "unpushed work was destroyed"
[ -d "$REPO/.agents/worktrees/dirty" ]    && ok "dirty tree preserved"     || bad "dirty tree was destroyed"
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

# ================================================ in-use detection, abandoned
# checkouts and --preserve. A separate home so --preserve never tries to push
# the fixtures above to GitHub. Each repo's fetch URL is allowlisted, but its
# push URL is a local bare repo, so pushes are real.
P="$BASE/p"; mkdir -p "$P"
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
W() { echo "$P/$1/.agents/worktrees/$2"; }
sweep() { "$SH" "$SWEEP" --home "$P" --grace-days 3 "$@" 2>&1; }
mkrepo r

# An abandoned checkout: what a `git worktree add` killed mid-checkout leaves.
wt_in r abandoned
age "$(W r abandoned)"
GD=$(git -C "$(W r abandoned)" rev-parse --absolute-git-dir)
rm -f "$GD/index"; : > "$GD/index.lock"; echo initializing > "$GD/locked"
# Backdate after the edits: removing index moved the git dir's own mtime.
touch -d '30 days ago' "$GD/index.lock" "$GD/locked" "$GD" 2>/dev/null || touch -t 202601010000 "$GD/index.lock" "$GD/locked" "$GD"
# The same shape, but a file was written a day after it was created: not abandoned.
wt_in r written
age "$(W r written)"
GD2=$(git -C "$(W r written)" rev-parse --absolute-git-dir)
rm -f "$GD2/index"; echo initializing > "$GD2/locked"
touch -d '30 days ago' "$GD2/locked" "$GD2" 2>/dev/null || touch -t 202601010000 "$GD2/locked" "$GD2"
echo later > "$(W r written)/later.txt"
touch -d '20 days ago' "$(W r written)/later.txt" 2>/dev/null || touch -t 202601200000 "$(W r written)/later.txt"
out=$(sweep)
[ ! -d "$(W r abandoned)" ] && ok "ABANDONED checkout (no index, 'initializing' lock) reclaimed" || bad "abandoned checkout survived: $out"
[ -d "$(W r written)" ] && ok "abandoned-looking tree written after creation is HELD" || bad "a tree with later writes was force-removed"

# A merged, aged tree is held while ANY process sits in it — an idle agent's
# harness keeps its cwd there however long it waits.
wt_in r live
age "$(W r live)"
( cd "$(W r live)" && exec sleep 60 ) & LIVE_PID=$!
sleep 1
out=$(sweep --dry-run)
case "$out" in *"held (live-process): live"*) ok "a tree with a LIVE PROCESS inside is held";;
  *) bad "live process not detected: $out";; esac
kill "$LIVE_PID" 2>/dev/null; wait "$LIVE_PID" 2>/dev/null

# Held when a recent transcript names it: an agent working by absolute path.
wt_in r mentioned
age "$(W r mentioned)"
mkdir -p "$P/.claude/projects/x"
printf '{"cwd":"/elsewhere","tool_input":{"file_path":"%s/f.txt"}}\n' "$(W r mentioned)" > "$P/.claude/projects/x/s.jsonl"
out=$(sweep --dry-run)
case "$out" in *"held (recent-session): mentioned"*) ok "a tree named in a RECENT TRANSCRIPT is held";;
  *) bad "recent transcript mention not detected: $out";; esac
rm -rf "$P/.claude"

# An old directory with one file edited today is in use. The directory's own
# mtime, which the sweep used to read, does not move on an edit.
wt_in r edited
age "$(W r edited)"
touch "$(W r edited)/f.txt"
out=$(sweep --dry-run)
case "$out" in *"held (within-grace): edited"*) ok "a FILE EDITED inside the grace window holds the tree";;
  *) bad "a fresh edit in an old directory was not seen: $out";; esac

# A plain `git status` from anything (IDE, prompt, hook, the old sweep) rewrites
# the index and moves the git dir's mtime; that is not someone working there.
wt_in r statused
age "$(W r statused)"
git -C "$(W r statused)" status >/dev/null 2>&1
out=$(sweep --dry-run)
case "$out" in *"would reclaim (merged): statused"*) ok "an index refresh by git status does NOT make a tree look active";;
  *) bad "git status alone held the tree as active: $out";; esac

# A .agents-keep file opts a tree out.
wt_in r kept
age "$(W r kept)"
: > "$(W r kept)/.agents-keep"
out=$(sweep --dry-run)
case "$out" in *"held (keep-marker): kept"*) ok ".agents-keep holds the tree";;
  *) bad ".agents-keep ignored: $out";; esac

# Without --preserve, local-only work is held, as before.
wt_in r wip
echo work > "$(W r wip)/work.txt"
age "$(W r wip)"
out=$(sweep --dry-run)
case "$out" in *"held (uncommitted-changes): wip"*) ok "without --preserve, uncommitted work is held";;
  *) bad "uncommitted work not held without --preserve: $out";; esac

# --preserve would publish it...
out=$(sweep --preserve --dry-run)
case "$out" in *"would preserve as a draft PR, then remove: wip"*) ok "--preserve picks local-only work for a draft PR";;
  *) bad "--preserve did not pick the uncommitted work: $out";; esac
# ...but the fixture repo cannot be confirmed PRIVATE (it is not on GitHub), or
# gh is not signed in: either way nothing is pushed and the tree stays.
out=$(sweep --preserve)
git -C "$P/r.git" rev-parse -q --verify "refs/heads/wip/$HOST/wip" >/dev/null 2>&1 &&
  bad "pushed to a repo not confirmed private: $out" || ok "nothing pushed to a repo not confirmed private"
[ -d "$(W r wip)" ] && ok "with no PR opened, the tree is KEPT" || bad "tree removed although no PR was opened"

# Night 2 of a failed preserve: the work reached wip/<host>/<name> but no PR
# opened. Commits that only our own wip/ push holds still need their PR, so the
# tree is never dropped as "already on origin" (reproduced in review).
git_q -C "$(W r wip)" add -A; git_q -C "$(W r wip)" commit -m wip
git_q -C "$(W r wip)" push origin "HEAD:refs/heads/wip/$HOST/wip"
age "$(W r wip)"
out=$(sweep --preserve --dry-run)
case "$out" in *"would preserve as a draft PR, then remove: wip"*) ok "work only on a wip/ branch still needs its PR (not dropped)";;
  *) bad "work only on wip/ was not kept for a PR: $(printf "%s\n" "$out" | grep -E ": wip$")";; esac

# A tree whose every commit is already on origin loses only its local copy.
wt_in r pushed
echo p > "$(W r pushed)/p.txt"; git_q -C "$(W r pushed)" add .; git_q -C "$(W r pushed)" commit -m pushed
git_q -C "$(W r pushed)" push origin HEAD:refs/heads/feat/pushed
age "$(W r pushed)"
out=$(sweep --dry-run)
case "$out" in *"held (unmerged-commits): pushed"*) ok "without --preserve, pushed-but-unmerged is held";;
  *) bad "pushed-but-unmerged not held without --preserve: $out";; esac
out=$(sweep --preserve)
[ ! -d "$(W r pushed)" ] && ok "--preserve removes a tree whose commits are all on origin" || bad "pushed tree kept: $out"
[ -n "$(git -C "$P/r" branch --list feat/pushed)" ] && ok "its local branch is kept" || bad "pushed tree's branch deleted"

# A tree holding a likely secret is never published by a nightly job: at the top
# level, inside a NEW untracked directory (which `status` collapses to `?? cfg/`),
# or as a key in an ordinary-looking file.
wt_in r secret
echo TOKEN=x > "$(W r secret)/.env.local"
age "$(W r secret)"
wt_in r nested
mkdir -p "$(W r nested)/cfg"; echo SECRET=1 > "$(W r nested)/cfg/.env"; echo k > "$(W r nested)/cfg/id_rsa"
age "$(W r nested)"
wt_in r inline
printf 'token = "ghp_%s"\n' "abcdefghijklmnopqrstuvwxyz0123456789" > "$(W r inline)/notes.txt"
age "$(W r inline)"
out=$(sweep --preserve --dry-run)
case "$out" in *"held (suspect-files): secret"*) ok "a top-level .env file holds the tree";; *) bad "top-level .env not caught: $out";; esac
case "$out" in *"held (suspect-files): nested"*) ok "a .env inside a NEW untracked directory holds the tree";; *) bad "nested secret not caught: $out";; esac
case "$out" in *"held (suspect-files): inline"*) ok "a token inside an ordinary file holds the tree";; *) bad "inline token not caught: $out";; esac

# A STAGED large file is caught too (ls-files -m misses staged-and-unchanged).
wt_in r big
head -c 6000000 /dev/zero > "$(W r big)/big.bin"; git_q -C "$(W r big)" add big.bin
age "$(W r big)"
out=$(sweep --preserve --dry-run)
case "$out" in *"held (file over 5 MB): big"*) ok "a staged file over 5 MB holds the tree";; *) bad "staged big file not caught: $out";; esac

# Work that lives only in a MERGE commit: `git cherry` skips merges, so the old
# check called this branch landed and deleted it (reproduced in review).
wt_in r evil
git_q -C "$P/r" commit --allow-empty -m 'main moves'
git_q -C "$P/r" push origin main; git_q -C "$P/r" fetch origin
git_q -C "$(W r evil)" merge --no-ff --no-commit origin/main
echo only-here > "$(W r evil)/unique.txt"; git_q -C "$(W r evil)" add unique.txt
git_q -C "$(W r evil)" commit -m 'merge with an extra file'
age "$(W r evil)"
out=$(sweep)
[ -d "$(W r evil)" ] && ok "work that exists only in a MERGE commit is not treated as landed" || bad "a merge-only change was deleted: $out"

# Gitignored files are not caches: a removal salvages them first. Caches
# (node_modules and the like) are dropped.
wt_in r ign
printf 'precious.txt\nnode_modules/\n' > "$(W r ign)/.gitignore"
git_q -C "$(W r ign)" add .gitignore; git_q -C "$(W r ign)" commit -m ignore
git_q -C "$(W r ign)" push origin "HEAD:refs/heads/feat/ign"
git_q -C "$P/r" fetch origin
git_q -C "$P/r" merge -q --ff-only origin/feat/ign 2>/dev/null || git_q -C "$P/r" merge -q origin/feat/ign
git_q -C "$P/r" push origin main; git_q -C "$P/r" fetch origin
echo keep-me > "$(W r ign)/precious.txt"; mkdir -p "$(W r ign)/node_modules/x"; echo junk > "$(W r ign)/node_modules/x/i.js"
age "$(W r ign)"
out=$(sweep)
if [ ! -d "$(W r ign)" ] && [ "$(cat "$P/.agents-swept/"*/r/ign/precious.txt 2>/dev/null)" = keep-me ]; then
  ok "a GITIGNORED file is salvaged before the tree is removed"
else
  bad "ignored file not salvaged: $out"
fi
[ ! -e "$P/.agents-swept/"*/r/ign/node_modules ] && ok "caches are not salvaged" || bad "node_modules was salvaged"

# A TERM mid-sweep must end the run. A handler that only cleaned up let the script
# carry on with its stamp and transcript list deleted, removing fresh trees.
wt_in r term-fresh
SLOW="$BASE/slowshim"; mkdir -p "$SLOW"
cat > "$SLOW/git" <<SHIM
#!/bin/sh
case " \$* " in *" cherry "*) sleep 2 ;; esac
exec "$REALGIT" "\$@"
SHIM
chmod +x "$SLOW/git"
PATH="$SLOW:$PATH" "$SH" "$SWEEP" --home "$P" --grace-days 3 > "$BASE/term.out" 2>&1 & TPID=$!
sleep 1; kill -TERM "$TPID" 2>/dev/null; wait "$TPID"; trc=$?
[ "$trc" -ne 0 ] && ok "TERM ends the run (exit $trc)" || bad "the run kept going after TERM"
[ -d "$(W r term-fresh)" ] && ok "a fresh tree survives a TERM mid-run" || bad "fresh tree removed after TERM: $(cat "$BASE/term.out")"

# The summary says why trees were kept.
out=$(sweep --dry-run)
case "$out" in *"  held: "*) ok "the run summary lists hold reasons";; *) bad "no hold reasons in the summary: $out";; esac

echo "---"
echo "worktree-sweep: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
