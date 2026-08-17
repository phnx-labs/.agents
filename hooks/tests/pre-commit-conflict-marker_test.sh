#!/bin/bash
# Tests the pre-commit conflict-marker gate. Real git, real merge conflicts, the
# real hook — no mocking. Mirrors pre-commit-agents-path-policy_test.sh's scaffold.
#
# The thing most needing a pin is the ANCHOR. Loosening the pattern to a bare
# `grep -q '<<<<<<<'`, or dropping the trailing space, silently re-breaks the
# case where a file legitimately discusses conflicts or embeds markers in a code
# block — and nothing else in the repo would notice.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../../.githooks/pre-commit"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.name "Hook Test"
git -C "$TMP_DIR" config user.email "hook-test@example.com"
mkdir -p "$TMP_DIR/.git-hooks"
cp "$HOOK" "$TMP_DIR/.git-hooks/pre-commit"
chmod +x "$TMP_DIR/.git-hooks/pre-commit"
git -C "$TMP_DIR" config core.hooksPath .git-hooks

pass=0 fail=0
check() {
    if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); echo "ok   - $1"
    else fail=$((fail + 1)); echo "FAIL - $1: expected exit [$3], got [$2]"; fi
}
commit_status() {
    # Reset first so each case is hermetic. A blocked commit leaves its file
    # staged, and without this a later case could pass on a contaminated index
    # rather than on its own fixture.
    git -C "$TMP_DIR" reset -q
    git -C "$TMP_DIR" add "$@" >/dev/null 2>&1
    git -C "$TMP_DIR" commit -m "probe" >/dev/null 2>&1
    echo $?
}

printf 'seed\n' > "$TMP_DIR/seed.txt"
git -C "$TMP_DIR" add seed.txt
git -C "$TMP_DIR" commit -q -m "seed"

# --- A: markers produced by a REAL git merge conflict, not hand-written --------
git -C "$TMP_DIR" checkout -q -b side
printf 'from side\n' > "$TMP_DIR/note.md"
git -C "$TMP_DIR" add note.md
git -C "$TMP_DIR" commit -q -m "side"
git -C "$TMP_DIR" checkout -q master 2>/dev/null || git -C "$TMP_DIR" checkout -q main
printf 'from main\n' > "$TMP_DIR/note.md"
git -C "$TMP_DIR" add note.md
git -C "$TMP_DIR" commit -q -m "main"
git -C "$TMP_DIR" merge side >/dev/null 2>&1   # expected to conflict
grep -q '^<<<<<<< ' "$TMP_DIR/note.md" || { echo "FAIL - fixture: git wrote no conflict"; exit 1; }
check "a real git conflict is blocked" "$(commit_status note.md)" "1"

# --- B: the same file, resolved, must commit ----------------------------------
printf 'from main\nfrom side\n' > "$TMP_DIR/note.md"
check "the same file resolved commits" "$(commit_status note.md)" "0"

# --- C: the anchor must not over-block legitimate content ---------------------
# Prose about conflicts, plus markers indented inside a fenced code block — the
# exact content a documentation change to this very hook would carry.
{
    printf 'We resolved a merge conflict yesterday.\n\n'
    printf 'The hook looks for these:\n\n'
    printf '    <<<<<<< HEAD\n    =======\n    >>>>>>> other\n'
} > "$TMP_DIR/doc.md"
check "prose and indented markers are not blocked" "$(commit_status doc.md)" "0"

# --- D: the trailing space is load-bearing ------------------------------------
# Git always writes "<<<<<<< " with a space before the ref name. Requiring it means
# a run of the same characters at column 0 — an ASCII divider, quoted mail depth
# markers — is not mistaken for a conflict. Without the space these get blocked.
{
    printf '<<<<<<<<<<<<<<<< section divider\n'
    printf '>>>>>>>>>>>>>>>> end divider\n'
} > "$TMP_DIR/art.md"
check "marker characters at column 0 that are not markers pass" "$(commit_status art.md)" "0"

# --- E: the index is what matters, not the working tree ----------------------
# Stage a half-resolved file, then clean the worktree copy. A working-tree check
# would pass this; the committed content would still carry markers.
printf 'a\n<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> other\nb\n' > "$TMP_DIR/staged.md"
git -C "$TMP_DIR" add staged.md >/dev/null 2>&1
printf 'a\nx\ny\nb\n' > "$TMP_DIR/staged.md"          # worktree now clean
git -C "$TMP_DIR" commit -m "probe" >/dev/null 2>&1
check "a clean worktree does not excuse a dirty index" "$?" "1"

# --- F: a lone separator, the middle marker of a half-resolution --------------
# Deleting the outer two markers and leaving '=======' still corrupts the file,
# and in Markdown it renders as a setext H1 rather than failing loudly.
git -C "$TMP_DIR" reset -q
printf 'Heading text\n=======\nbody\n' > "$TMP_DIR/half.md"
check "a lone separator left by a half-resolution is blocked" "$(commit_status half.md)" "1"

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
