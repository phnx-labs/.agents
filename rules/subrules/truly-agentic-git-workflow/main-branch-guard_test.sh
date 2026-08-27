#!/usr/bin/env bash
# Test for main-branch-guard.sh (PreToolUse guard on file tools + Bash).
#
# Exercises the real script over real stdin JSON against REAL throwaway git
# repos (no mocking): a PRIMARY working tree on its default branch (deny) AND on a
# feature branch (deny — the whole primary tree is protected, not just default),
# a LINKED worktree (allow — where all agent work belongs), gitignored and non-git
# paths (allow), and worktree-add base freshness. Verifies both the
# Write/Edit/NotebookEdit path and the `git commit|add` Bash path.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
GUARD="$DIR/main-branch-guard.sh"
pass=0
fail=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export HOME="$TMP/home"; mkdir -p "$HOME"   # isolate from user gitconfig

git_q() { git -c user.email=t@t.dev -c user.name=t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

# 1. Repo on default branch `main` (no remote -> exercises main/master fallback).
MAIN_REPO="$TMP/main_repo"
mkdir -p "$MAIN_REPO"; git_q -C "$MAIN_REPO" init
git_q -C "$MAIN_REPO" commit --allow-empty -m init
mkdir -p "$MAIN_REPO/sub"; echo x > "$MAIN_REPO/tracked.txt"
# Gitignored runtime paths inside MAIN_REPO (memory/scratch). A write to a
# gitignored path can never be committed, so the guard must ALLOW it even on the
# default branch — this is what the harness memory dir (.history/) relies on.
printf '.history/\nscratch/\n' > "$MAIN_REPO/.gitignore"
git_q -C "$MAIN_REPO" add .gitignore
git_q -C "$MAIN_REPO" commit -m gitignore
mkdir -p "$MAIN_REPO/.history/memory" "$MAIN_REPO/scratch"
# A TRACKED file force-added UNDER a gitignored dir. `git check-ignore` consults
# the index, so it reports this as NOT ignored ("tracked wins") — the guard must
# still DENY it. Locks in the index-consultation guarantee: defends against a
# future `check-ignore --no-index` refactor that would silently flip this to
# IGNORED and start allowing edits to tracked source on the default branch.
echo y > "$MAIN_REPO/scratch/forced.txt"
git_q -C "$MAIN_REPO" add -f scratch/forced.txt
git_q -C "$MAIN_REPO" commit -m forced

# 2. Repo on a feature branch (no remote -> not main/master -> allow).
FEAT_REPO="$TMP/feat_repo"
mkdir -p "$FEAT_REPO"; git_q -C "$FEAT_REPO" init
git_q -C "$FEAT_REPO" commit --allow-empty -m init
git_q -C "$FEAT_REPO" checkout -b feat/x
echo x > "$FEAT_REPO/tracked.txt"

# 3. Cloned repo whose default branch is `trunk` (exercises origin/HEAD path).
BARE="$TMP/origin.git"
git_q init --bare -b trunk "$BARE"
CLONE="$TMP/clone"
git_q clone "$BARE" "$CLONE"
git_q -C "$CLONE" commit --allow-empty -m init
git_q -C "$CLONE" push -u origin trunk
git_q -C "$CLONE" remote set-head origin trunk
echo x > "$CLONE/tracked.txt"
# feature branch inside the same clone (default is trunk, so this must allow)
CLONE_FEAT="$TMP/clone_feat"
git_q clone "$BARE" "$CLONE_FEAT"
git_q -C "$CLONE_FEAT" remote set-head origin trunk
git_q -C "$CLONE_FEAT" checkout -b feat/y

# 4. Plain non-git directory.
NOGIT="$TMP/plain"; mkdir -p "$NOGIT"; echo x > "$NOGIT/file.txt"

# 5. A REAL linked worktree off MAIN_REPO, on a feature branch (allow).
WT_LINK="$TMP/wt_link"
git_q -C "$MAIN_REPO" worktree add -b wt-feat "$WT_LINK"
echo x > "$WT_LINK/tracked.txt"

# 6. Clone whose default is `trunk` (origin/HEAD) but checked out on a local
#    `main` branch — must be protected by the main/master clause (stale/mispointed
#    origin/HEAD must never expose main).
CLONE_MAIN="$TMP/clone_main"
git_q clone "$BARE" "$CLONE_MAIN"
git_q -C "$CLONE_MAIN" remote set-head origin trunk
git_q -C "$CLONE_MAIN" checkout -b main

# run_guard <want_exit> <desc> <json> [cwd]
run_guard() {
  want=$1; desc=$2; json=$3
  _dir="${4:-.}"
  (cd "$_dir" && printf '%s' "$json" | "$GUARD") >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s (want exit %s, got %s)\n' "$desc" "$want" "$got"
  fi
}

wj() { # write-tool json: <tool> <field> <path> [cwd]
  jq -n --arg t "$1" --arg f "$2" --arg p "$3" --arg cwd "${4:-}" \
    '{tool_name:$t, cwd:$cwd, tool_input:{($f):$p}}'
}
bj() { # bash json: <cmd> [cwd]
  jq -n --arg c "$1" --arg cwd "${2:-}" '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}'
}
# Grok CLI camelCase variants (toolName / toolInput) — harness portability.
wjc() { # camelCase write-tool json: <tool> <field> <path> [cwd]
  jq -n --arg t "$1" --arg f "$2" --arg p "$3" --arg cwd "${4:-}" \
    '{toolName:$t, cwd:$cwd, toolInput:{($f):$p}}'
}
bjc() { # camelCase bash json: <cmd> [cwd]
  jq -n --arg c "$1" --arg cwd "${2:-}" '{toolName:"Bash", cwd:$cwd, toolInput:{command:$c}}'
}

# --- File tools: DENY on default branch (exit 2) ---
run_guard 2 "Write tracked file on main"        "$(wj Write file_path "$MAIN_REPO/tracked.txt")"
run_guard 2 "Write NEW file in new subdir on main" "$(wj Write file_path "$MAIN_REPO/sub/new/deep.txt")"
run_guard 2 "Edit file on main"                  "$(wj Edit file_path "$MAIN_REPO/tracked.txt")"
run_guard 2 "NotebookEdit on main"               "$(wj NotebookEdit notebook_path "$MAIN_REPO/nb.ipynb")"
run_guard 2 "Write on cloned trunk default"      "$(wj Write file_path "$CLONE/tracked.txt")"
run_guard 2 "Write relative path, cwd on main"   "$(wj Write file_path "tracked.txt" "$MAIN_REPO")"

# --- File tools: PRIMARY tree on ANY branch is DENIED (exit 2) ---
# The whole primary working tree is off limits, not just the default branch —
# a feature branch checked out IN the user's main checkout is the review-2704
# strand-the-tree trap. Only LINKED worktrees / non-git / gitignored allow.
run_guard 2 "Write on primary-tree feature branch is BLOCKED"       "$(wj Write file_path "$FEAT_REPO/tracked.txt")"
run_guard 2 "Write on clone primary-tree feature branch is BLOCKED" "$(wj Write file_path "$CLONE_FEAT/z.txt")"
run_guard 0 "Write in non-git dir"               "$(wj Write file_path "$NOGIT/file.txt")"
run_guard 0 "Write to /tmp scratch"              "$(wj Write file_path "$TMP/loose.txt")"
# The core bug case, runnable everywhere (no cygpath): a drive-letter path OUTSIDE
# any repo, with a POSIX cwd on main. Before the fix the drive-letter path fell to
# the relative branch, got concatenated onto cwd, and dirname walked back up to the
# main repo -> false deny. These two run on Linux/macOS CI, where the Windows-cwd
# cases below are skipped.
# Run these from the primary tree so the dirname collapse lands in a protected
# cwd; without the drive-letter POSIX early-exit the guard would falsely deny.
run_guard 0 "Write drive-letter path (forward slash) outside repo, POSIX cwd on main" \
  "$(wj Write file_path "C:/completely/external/nonexistent/path/file.txt" "$MAIN_REPO")" "$MAIN_REPO"
run_guard 0 "Write drive-letter path (backslash) outside repo, POSIX cwd on main" \
  "$(wj Write file_path "C:\\completely\\external\\nonexistent\\path\\file.txt" "$MAIN_REPO")" "$MAIN_REPO"

# The drive-letter exemption above must not become an escape hatch. A missing
# drive root is necessary but NOT sufficient: `..` climbs out of the fake drive
# segment, so `C:/../tracked.txt` resolves to `<cwd>/tracked.txt` — a real file
# in the primary tree. Reproduced before the fix: the guard exited 0 and a
# standard mkdir-then-write overwrote the tracked file, against a guard whose own
# header says "No exceptions, no escape hatch — by design".
run_guard 2 "Write drive-letter path with .. traversal into the primary tree" \
  "$(wj Write file_path "C:/../tracked.txt" "$MAIN_REPO")" "$MAIN_REPO"
run_guard 2 "Write drive-letter path with backslash .. traversal" \
  "$(wj Write file_path "C:\\..\\tracked.txt" "$MAIN_REPO")" "$MAIN_REPO"

# --- Windows-style paths: drive-letter-rooted, backslash or forward-slash ---
# separated paths (as sent by Claude Code / other harnesses running natively on
# Windows) must be recognized as absolute, never concatenated onto cwd. Real
# bug: a Windows absolute path like `I:\tmp\out.html` or `I:/tmp/out.html`,
# paired with a Windows-style cwd, fell through the old `/*`-only check into the
# relative branch, producing a bogus `<cwd>/I:\tmp\out.html` that `dirname`
# walked back up to cwd itself — misreporting an edit to a file completely
# outside the repo as "on the default branch of <repo>".
if command -v cygpath >/dev/null 2>&1; then
  MAIN_REPO_WIN=$(cygpath -w "$MAIN_REPO")
  MAIN_REPO_WIN_FS=$(printf '%s' "$MAIN_REPO_WIN" | tr '\\' '/')

  # DENY: Windows-style absolute path pointing INSIDE the repo, on main.
  run_guard 2 "Write Windows absolute path (backslash) on main" \
    "$(wj Write file_path "$MAIN_REPO_WIN\\tracked.txt")"
  run_guard 2 "Write Windows absolute path (forward slash, drive letter) on main" \
    "$(wj Write file_path "$MAIN_REPO_WIN_FS/tracked.txt")"
  # DENY: relative file_path + Windows-style (backslash) cwd on main — exercises
  # the cwd-normalization half of the fix.
  run_guard 2 "Write relative path, Windows-style cwd on main" \
    "$(wj Write file_path "tracked.txt" "$MAIN_REPO_WIN")"
  # Bash `git -C <windows-path> commit` must resolve the same way.
  run_guard 2 "git -C Windows-style path commit" \
    "$(bj "git -C \"$MAIN_REPO_WIN\" commit -m x")"

  # ALLOW: Windows-style absolute path pointing OUTSIDE the repo, even with a
  # Windows-style cwd rooted on main — this is the exact bug scenario above.
  run_guard 0 "Write Windows absolute path (forward slash) outside repo, Windows cwd on main" \
    "$(wj Write file_path "C:/completely/external/nonexistent/path/file.txt" "$MAIN_REPO_WIN")"
  run_guard 0 "Write Windows absolute path (backslash) outside repo, Windows cwd on main" \
    "$(wj Write file_path "C:\\completely\\external\\nonexistent\\path\\file.txt" "$MAIN_REPO_WIN")"
fi

# --- File tools: ALLOW gitignored paths even on the default branch (exit 0) ---
# A gitignored path can never be committed, so writing it can't land on main.
run_guard 0 "Write gitignored .history/ on main"    "$(wj Write file_path "$MAIN_REPO/.history/memory/note.md")"
run_guard 0 "Write gitignored scratch/ on main"     "$(wj Write file_path "$MAIN_REPO/scratch/tmp.txt")"
run_guard 0 "Write NEW gitignored deep path on main" "$(wj Write file_path "$MAIN_REPO/.history/versions/x/deep/new.md")"
run_guard 0 "Edit gitignored file on main"          "$(wj Edit file_path "$MAIN_REPO/scratch/tmp.txt")"
run_guard 0 "Write gitignored relative, cwd on main" "$(wj Write file_path "scratch/rel.txt" "$MAIN_REPO")"
# A TRACKED (non-ignored) path in the same repo must still DENY — the exemption
# is gitignore-scoped, not a blanket bypass.
run_guard 2 "Write tracked file still denied (ignore-scoped)" "$(wj Write file_path "$MAIN_REPO/tracked.txt")"
run_guard 2 "Write force-added tracked file under ignored dir" "$(wj Write file_path "$MAIN_REPO/scratch/forced.txt")"

# --- Bash git commit/add: DENY on default branch (exit 2) ---
run_guard 2 "git -C main commit"                 "$(bj "git -C $MAIN_REPO commit -m x")"
run_guard 2 "git commit, cwd on main"            "$(bj "git commit -m x" "$MAIN_REPO")"
run_guard 2 "git add, cwd on main"               "$(bj "git add ." "$MAIN_REPO")"
run_guard 2 "git -C clone(trunk) commit"         "$(bj "git -C $CLONE commit -m x")"
run_guard 2 "sh -c wrapped commit on main"       "$(bj "sh -c \"git -C $MAIN_REPO commit -m x\"")"
run_guard 2 "chained cd/commit on main"          "$(bj "echo hi && git commit -m x" "$MAIN_REPO")"

# --- Bash git commit/add: PRIMARY tree on ANY branch DENIED; non-checked ops allowed ---
run_guard 2 "git -C primary-tree feature branch commit is BLOCKED"       "$(bj "git -C $FEAT_REPO commit -m x")"
run_guard 2 "git commit on clone primary-tree feature branch is BLOCKED" "$(bj "git commit -m x" "$CLONE_FEAT")"
run_guard 0 "git status on main (not checked)"     "$(bj "git status" "$MAIN_REPO")"
run_guard 0 "git push on main (not checked here)"  "$(bj "git push" "$MAIN_REPO")"
run_guard 0 "git commit in non-git cwd"          "$(bj "git commit -m x" "$NOGIT")"
run_guard 0 "non-git bash on main (fast path)"   "$(bj "echo hello" "$MAIN_REPO")"
run_guard 0 "ls with no git token"               "$(bj "ls -la" "$MAIN_REPO")"

# --- Bash write destinations: policy follows the destination, never cwd ---
run_guard 2 "cp destination in primary tree from parent cwd" \
  "$(bj "cp /tmp/source '$MAIN_REPO/content-source-materials-2026-08-10.md'" "$TMP")"
run_guard 2 "scp local-form destination in primary tree" \
  "$(bj "scp -q /tmp/refocus-brief.md '$MAIN_REPO/refocus-brief.md'" "$NOGIT")"
run_guard 2 "shell redirect destination in primary tree" \
  "$(bj "cat > '$MAIN_REPO/notes.md'" "$NOGIT")"
run_guard 0 "documented plan readback destination /tmp" \
  "$(bj "scp '$MAIN_REPO/plan.html' /tmp/ && open /tmp/plan.html" "$MAIN_REPO")"
run_guard 0 "write destination under repo-nested worktree path wins first" \
  "$(bj "cat > '$MAIN_REPO/.agents/worktrees/fix-x/notes.md'" "$MAIN_REPO")"
run_guard 0 "write destination under agent home" \
  "$(bj "cat > '$HOME/.agents/notes.md'" "$MAIN_REPO")"

# --- Extra edge cases (from review) ---
run_guard 0 "Write in real linked worktree (feat)" "$(wj Write file_path "$WT_LINK/tracked.txt")"
run_guard 0 "git commit in real linked worktree"   "$(bj "git commit -m x" "$WT_LINK")"
run_guard 2 "git -C <relative> commit, cwd=TMP"    "$(bj "git -C main_repo commit -m x" "$TMP")"
run_guard 2 "local 'main' under trunk-default clone" "$(bj "git commit -m x" "$CLONE_MAIN")"
run_guard 2 "Write on local 'main' under trunk default" "$(wj Write file_path "$CLONE_MAIN/f.txt")"

# --- worktree add -b/-B base freshness ($CLONE has origin/trunk + local trunk) ---
# DENY: new-branch worktree from an implicit base (current HEAD).
run_guard 2 "worktree add -b, implicit base"       "$(bj "git -C $CLONE worktree add -b feat/z $TMP/wt_implicit")"
# DENY: new-branch worktree based on a LOCAL branch (the stale trap).
run_guard 2 "worktree add -b, local-branch base"   "$(bj "git -C $CLONE worktree add -b feat/z2 $TMP/wt_local trunk")"
run_guard 2 "worktree add -B, local-branch base"   "$(bj "git -C $CLONE worktree add -B feat/z3 $TMP/wt_localB trunk")"
# ALLOW: new-branch worktree based on a remote-tracking ref (the required form).
# Clone just created origin/trunk — mtime is fresh under the default 900s max age.
run_guard 0 "worktree add -b, origin/ base"        "$(bj "git -C $CLONE worktree add -b feat/z4 $TMP/wt_remote origin/trunk")"
# ALLOW: non-creating worktree add (materialize an existing ref) is not checked.
run_guard 0 "worktree add (no -b) existing ref"    "$(bj "git -C $CLONE worktree add $TMP/wt_nob origin/trunk")"
# ALLOW: worktree list / other subcommands untouched.
run_guard 0 "worktree list"                        "$(bj "git -C $CLONE worktree list")"
# ALLOW: -b with a raw commit SHA is a deliberate, explicit base.
CLONE_SHA=$(git -C "$CLONE" rev-parse HEAD)
run_guard 0 "worktree add -b, explicit SHA base"   "$(bj "git -C $CLONE worktree add -b feat/z5 $TMP/wt_sha $CLONE_SHA")"
# DENY: glued short option `-bNAME` / `-BNAME` must still register as creating.
run_guard 2 "worktree add -bNAME, implicit base"   "$(bj "git -C $CLONE worktree add -bglued1 $TMP/wt_g1")"
run_guard 2 "worktree add -bNAME, local base"      "$(bj "git -C $CLONE worktree add -bglued2 $TMP/wt_g2 trunk")"
run_guard 2 "worktree add -BNAME, local base"      "$(bj "git -C $CLONE worktree add -Bglued3 $TMP/wt_g3 trunk")"
# ALLOW: glued short option with a remote base is still fine.
run_guard 0 "worktree add -bNAME, origin/ base"    "$(bj "git -C $CLONE worktree add -bglued4 $TMP/wt_g4 origin/trunk")"
# DENY: abbreviated / fully-qualified LOCAL ref forms resolve to refs/heads/*.
run_guard 2 "worktree add -b, heads/ local ref"    "$(bj "git -C $CLONE worktree add -b feat/q1 $TMP/wt_q1 heads/trunk")"
run_guard 2 "worktree add -b, refs/heads/ ref"     "$(bj "git -C $CLONE worktree add -b feat/q2 $TMP/wt_q2 refs/heads/trunk")"
# ALLOW: fully-qualified REMOTE ref resolves to refs/remotes/*.
run_guard 0 "worktree add -b, refs/remotes/ ref"   "$(bj "git -C $CLONE worktree add -b feat/q3 $TMP/wt_q3 refs/remotes/origin/trunk")"
# DENY: --force interleaved before -b with a local base still caught.
run_guard 2 "worktree add --force -b, local base"  "$(bj "git -C $CLONE worktree add --force -b feat/q4 $TMP/wt_q4 trunk")"

# --- Real freshness (age), not form-only origin/* ---
# Age the remote-tracking ref + FETCH_HEAD to simulate a days-stale origin/trunk.
# --path-format=absolute: plain --git-path is cwd-relative and would touch the wrong file.
_REF_PATH=$(git -C "$CLONE" rev-parse --path-format=absolute --git-path refs/remotes/origin/trunk)
_FH_PATH=$(git -C "$CLONE" rev-parse --path-format=absolute --git-path FETCH_HEAD)
# touch -t is portable (GNU + BSD); 2020-01-01 is well past any default max age.
[ -f "$_REF_PATH" ] && touch -t 202001011200 "$_REF_PATH"
[ -f "$_FH_PATH" ] && touch -t 202001011200 "$_FH_PATH"
run_guard 2 "worktree add -b, stale origin/ base"  "$(bj "git -C $CLONE worktree add -b feat/stale $TMP/wt_stale origin/trunk")"
# A no-op fetch does not always bump ref mtime; re-touch to "now" to model a
# successful refresh (the production path is: agent runs fetch, then worktree add).
touch "$_REF_PATH" 2>/dev/null
touch "$_FH_PATH" 2>/dev/null
run_guard 0 "worktree add -b, origin/ after refresh" "$(bj "git -C $CLONE worktree add -b feat/fresh $TMP/wt_fresh origin/trunk")"
# AGENTS_WORKTREE_FETCH_MAX_AGE_SEC=0 disables the age check (form-only escape).
[ -f "$_REF_PATH" ] && touch -t 202001011200 "$_REF_PATH"
[ -f "$_FH_PATH" ] && touch -t 202001011200 "$_FH_PATH"
AGENTS_WORKTREE_FETCH_MAX_AGE_SEC=0 run_guard 0 "worktree add -b, age check disabled" \
  "$(bj "git -C $CLONE worktree add -b feat/age0 $TMP/wt_age0 origin/trunk")"
# Restore fresh mtimes so later origin/* ALLOW cases (camelCase suite) stay green.
touch "$_REF_PATH" 2>/dev/null
touch "$_FH_PATH" 2>/dev/null

# --- -C variable resolution (RUSH-2743): compound/heredoc/multiline -m -------
# Real false blocks (2026-08-15): `git -C "$WT" commit` in a compound command
# was judged against the SESSION CWD because the unexpanded `$WT` produced a
# nonexistent path and git_facts_load's ancestor walk collapsed it to cwd.
# ALLOW: var -C pointing at a linked worktree, assignment in the same command.
run_guard 0 "var -C to linked worktree (compound)" "$(bj "WT=$WT_LINK
git -C \"\$WT\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# ALLOW: chained assignments (WT=\$T/...) resolve through the store.
run_guard 0 "chained var -C to linked worktree" "$(bj "T=$TMP
WT=\$T/wt_link
git -C \"\$WT\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# ALLOW: braced form \${WT}.
run_guard 0 "braced var -C to linked worktree" "$(bj "WT=$WT_LINK
git -C \"\${WT}\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# ALLOW: multiline -m in a compound command with a var -C (the da27ed6f shape).
run_guard 0 "var -C + multiline -m to linked worktree" "$(bj "WT=$WT_LINK
git -C \"\$WT\" commit -m \"fix: subject

- body line one
- body line two\"" "$MAIN_REPO")" "$MAIN_REPO"
# ALLOW: heredoc in the chain; body must not parse as commands, and the var -C
# commit after it must resolve. The body line is a literal `git commit` that
# would deny against the primary cwd if not stripped.
run_guard 0 "heredoc chain + var -C commit" "$(bj "WT=$WT_LINK
cat > $TMP/hd.txt <<EOF
git commit -m body-line-not-a-command
EOF
git -C \"\$WT\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# DENY: a QUOTED `<<TAG` is string data, not a heredoc opener — it must not
# swallow the `git commit` that follows (reviewer finding on #329: the
# quote-unaware stripper turned this deny into an allow). The trailing bare
# `EOF` line makes the phantom heredoc TERMINATED on a quote-unaware parser —
# the shape that actually swallowed the commit (rc=0 on the vulnerable guard);
# without it the unterminated-flush path denies there too and pins nothing.
run_guard 2 "quoted <<TAG does not open a heredoc" "$(bj "echo \"text <<EOF\" > $TMP/q.txt
git commit -m x
EOF" "$MAIN_REPO")" "$MAIN_REPO"
run_guard 2 "single-quoted <<TAG does not open a heredoc" "$(bj "echo 'text <<EOF' > $TMP/q2.txt
git commit -m x
EOF" "$MAIN_REPO")" "$MAIN_REPO"
# DENY: an UNTERMINATED heredoc keeps its lines (conservative — fail toward
# the old behavior), so a body `git commit` still checks against cwd.
run_guard 2 "unterminated heredoc body still parsed" "$(bj "cat <<EOF
git commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# DENY: var -C pointing AT a primary tree — real expansion, not cwd blame:
# cwd here is TMP (not a repo), so only expansion can produce this deny.
run_guard 2 "var -C to PRIMARY tree denies from non-repo cwd" "$(bj "REPO=$MAIN_REPO
git -C \"\$REPO\" commit -m x" "$TMP")" "$TMP"
# DENY: \$(git rev-parse --show-toplevel) / \$(pwd) are cwd-equivalent — the
# recipe idiom must still deny in a primary checkout.
run_guard 2 "rev-parse toplevel var -C in primary cwd" "$(bj "REPO=\$(git rev-parse --show-toplevel)
git -C \"\$REPO\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
run_guard 2 "pwd var -C in primary cwd" "$(bj "REPO=\$(pwd)
git -C \"\$REPO\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# ALLOW: unresolvable command-substitution var — fail toward the parsed
# target, never the session cwd (git itself errors on the bogus path).
run_guard 0 "unresolvable \$(mktemp) var -C" "$(bj "WT=\$(mktemp -d)
git -C \"\$WT\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# ALLOW: undefined var -C (set outside the command string).
run_guard 0 "undefined var -C" "$(bj "git -C \"\$UNDEFINED_MBG_X\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# ALLOW: nonexistent literal -C target — the parsed target rules, not cwd.
run_guard 0 "nonexistent literal -C" "$(bj "git -C /nonexistent/mbg-2743 commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# DENY: last assignment wins — a literal overwritten by an unresolvable one
# tombstones the name (allow), and the reverse re-resolves; lock the former.
run_guard 0 "last assignment wins (tombstone)" "$(bj "REPO=$MAIN_REPO
REPO=\$(mktemp -d)
git -C \"\$REPO\" commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# DENY: env-prefix form is NOT an assignment segment — unchanged behavior.
run_guard 2 "env-prefix git commit still checked" "$(bj "FOO=1 git commit -m x" "$MAIN_REPO")" "$MAIN_REPO"
# DENY: var -C + worktree add with an implicit base — expansion feeds the
# worktree check too, so the shape-based deny still fires.
run_guard 2 "var -C worktree add -b implicit base" "$(bj "REPO=$CLONE
git -C \"\$REPO\" worktree add -b feat/v2743 $TMP/wt_v2743" "$TMP")" "$TMP"

# --- Harness portability: Grok CLI camelCase payloads (toolName/toolInput) ---
# The old snake_case-only extraction resolved empty under Grok and fail-OPEN'd,
# killing the default-branch choke point. These must behave exactly like their
# snake_case twins above.
run_guard 2 "camelCase Write tracked file on main"  "$(wjc Write file_path "$MAIN_REPO/tracked.txt")"
run_guard 2 "camelCase Edit file on main"           "$(wjc Edit file_path "$MAIN_REPO/tracked.txt")"
run_guard 2 "camelCase NotebookEdit on main"        "$(wjc NotebookEdit notebook_path "$MAIN_REPO/nb.ipynb")"
run_guard 2 "camelCase Write relative, cwd on main" "$(wjc Write file_path "tracked.txt" "$MAIN_REPO")"
run_guard 2 "camelCase Write on primary-tree feature branch is BLOCKED" "$(wjc Write file_path "$FEAT_REPO/tracked.txt")"
run_guard 0 "camelCase Write gitignored on main"    "$(wjc Write file_path "$MAIN_REPO/scratch/tmp.txt")"
run_guard 2 "camelCase git commit, cwd on main"     "$(bjc "git commit -m x" "$MAIN_REPO")"
run_guard 2 "camelCase git -C main commit"          "$(bjc "git -C $MAIN_REPO commit -m x")"
run_guard 2 "camelCase git commit on primary-tree feature branch is BLOCKED" "$(bjc "git -C $FEAT_REPO commit -m x")"
run_guard 2 "camelCase worktree add -b, local base" "$(bjc "git -C $CLONE worktree add -b feat/cc1 $TMP/wt_cc1 trunk")"
run_guard 0 "camelCase worktree add -b, origin base" "$(bjc "git -C $CLONE worktree add -b feat/cc2 $TMP/wt_cc2 origin/trunk")"

# --- Submodule: its working dir is PRIMARY-tree content, not a linked worktree.
# A submodule's `.git` is a FILE (like a linked worktree) but points into
# `.git/modules/`, not `.git/worktrees/` — so it must be DENIED, not allowed.
SUBSRC="$TMP/subsrc"; mkdir -p "$SUBSRC"; git_q -C "$SUBSRC" init
git_q -C "$SUBSRC" commit --allow-empty -m s
SUPER="$TMP/super"; mkdir -p "$SUPER"; git_q -C "$SUPER" init
git_q -C "$SUPER" commit --allow-empty -m init
git -c protocol.file.allow=always -c user.email=t@t.dev -c user.name=t -C "$SUPER" submodule add "$SUBSRC" sub >/dev/null 2>&1
git_q -C "$SUPER" commit -m addsub
if [ -f "$SUPER/sub/.git" ]; then
  run_guard 2 "Write inside a submodule (primary-tree content, not a worktree)" "$(wj Write file_path "$SUPER/sub/f.txt")"
  run_guard 2 "git commit inside a submodule"                                    "$(bj "git commit -m x" "$SUPER/sub")"
fi

# --- Version skew (regression for the fail-open BLOCKER): this guard sourced with
# a STALE git-facts.sh (present but lacking git_facts_in_primary_tree) must FAIL
# SAFE via the git-fork fallback, not fall through to allow. Uses a fake install
# layout so the guard's relative candidate resolves to the stale lib.
FAKE="$TMP/fake"; mkdir -p "$FAKE/rules/subrules/truly-agentic-git-workflow" "$FAKE/hooks/lib"
cp "$GUARD" "$FAKE/rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh"
printf '#!/bin/sh\ngit_facts_on_default() { return 1; }\n' > "$FAKE/hooks/lib/git-facts.sh"
FAKE_GUARD="$FAKE/rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh"
# FEAT_REPO is a PRIMARY tree on a feature branch — only the NEW primary-tree
# logic denies it, so this proves the fork fallback (not the stale fn) protects it.
_sk=$(printf '%s' "$(bj "git commit -m x" "$FEAT_REPO")" | HOME="$TMP/home" "$FAKE_GUARD" >/dev/null 2>&1; echo $?)
if [ "$_sk" -eq 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL: stale-lib version skew still blocks primary feature-branch commit (want 2, got %s)\n' "$_sk"; fi

# --- Self-healing worktree. The refusal should hand over a directory that already
# exists, not just a recipe. Three properties, and the last two are the ones that
# make it safe to put a mutation inside a guard.
AWT="$TMP/awt"; mkdir -p "$AWT"
git_q init "$AWT"; git_q -C "$AWT" commit --allow-empty -m init
UP="$TMP/awt-upstream"; git_q init --bare "$UP"
git_q -C "$AWT" remote add origin "$UP"
git_q -C "$AWT" push -u origin HEAD
git_q -C "$AWT" remote set-head origin --auto

_out=$(printf '%s' "$(wj Write file_path "$AWT/f.txt")" | \
  AGENTS_AGENT_NAME=claude AGENTS_SESSION_ID=abcdef12-dead-beef "$GUARD" 2>&1 >/dev/null; true)
_made=$(ls -d "$AWT"/.agents/worktrees/*-abcdef12 2>/dev/null | head -1)

# 1. it created the worktree and named it in the refusal
if [ -n "$_made" ] && [ -d "$_made" ] && printf '%s' "$_out" | grep -q "$_made"; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL: self-healing worktree not created or not named in the refusal\n'
fi

# 1b. the name carries harness + date + hhmm + session chunk, in that order
if basename "${_made:-none}" | grep -Eq '^claude-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}-abcdef12$'; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL: worktree name not <harness>-<date>-<hhmm>-<session8>: %s\n' "$(basename "${_made:-none}")"
fi

# 2. it still BLOCKS. A convenience that stops denying is a hole, not a feature.
_rc=$(printf '%s' "$(wj Write file_path "$AWT/f.txt")" | \
  AGENTS_AGENT_NAME=claude AGENTS_SESSION_ID=abcdef12-dead-beef "$GUARD" >/dev/null 2>&1; echo $?)
if [ "$_rc" -eq 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL: self-healing path stopped blocking (want 2, got %s)\n' "$_rc"; fi

# 3. a second block REUSES it. Reuse matches on the SESSION chunk, not the whole
# name, so it must hold even when a later block computes a different HHMM.
_before=$(git -C "$AWT" worktree list | wc -l)
printf '%s' "$(wj Edit file_path "$AWT/g.txt")" | \
  AGENTS_AGENT_NAME=claude AGENTS_SESSION_ID=abcdef12-dead-beef "$GUARD" >/dev/null 2>&1
_after=$(git -C "$AWT" worktree list | wc -l)
if [ "$_before" -eq "$_after" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL: second block created another worktree (%s -> %s)\n' "$_before" "$_after"; fi

# 3b. a DIFFERENT session gets its own — reuse is scoped, not global
printf '%s' "$(wj Write file_path "$AWT/i.txt")" | \
  AGENTS_AGENT_NAME=claude AGENTS_SESSION_ID=99999999-cafe "$GUARD" >/dev/null 2>&1
if [ -n "$(ls -d "$AWT"/.agents/worktrees/*-99999999 2>/dev/null | head -1)" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL: a second session did not get its own worktree\n'
fi

# 4. opt-out honored, and the fallback recipe returns
_off=$(printf '%s' "$(wj Write file_path "$AWT/h.txt")" | AGENTS_NO_AUTO_WORKTREE=1 AGENTS_SESSION_ID=zz "$GUARD" 2>&1 >/dev/null; true)
if printf '%s' "$_off" | grep -q 'worktree add -b <slug>' && [ ! -d "$AWT/.agents/worktrees/agent-zz" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); printf 'FAIL: AGENTS_NO_AUTO_WORKTREE did not fall back to the recipe\n'
fi

# 5. an un-creatable worktree (no origin/HEAD) must NOT stop the refusal
NOUP="$TMP/noup"; git_q init "$NOUP"; git_q -C "$NOUP" commit --allow-empty -m init
_rc=$(printf '%s' "$(wj Write file_path "$NOUP/f.txt")" | AGENTS_SESSION_ID=nohead "$GUARD" >/dev/null 2>&1; echo $?)
if [ "$_rc" -eq 2 ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL: guard stopped blocking when the worktree could not be made (want 2, got %s)\n' "$_rc"; fi

printf -- '---\nmain-branch-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
