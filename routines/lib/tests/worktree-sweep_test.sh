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

# Backdate a worktree past the grace window (the sweep reads dir mtime).
age() { touch -d '30 days ago' "$1" 2>/dev/null || touch -t 202601010000 "$1"; }

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

case "$out" in *"would reclaim: merged"*) ok "dry-run reclaims the rebase-merged worktree (patch-id, not ancestry)";;
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

echo "---"
echo "worktree-sweep: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
