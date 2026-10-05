#!/usr/bin/env bash
# Tests for 12-repo-freshness.py — run: bash 12-repo-freshness_test.sh
# Real git: a bare "origin", a primary clone, and a linked worktree, all in a temp dir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../12-repo-freshness.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
pass=0; fail=0
check() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
run() { printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$1" | python3 "$HOOK"; }

git init -q --bare -b main "$T/origin.git"
git clone -q "$T/origin.git" "$T/clone" 2>/dev/null
( cd "$T/clone" && echo a > a.txt && git add a.txt && git commit -qm a && git push -q origin main )
git clone -q "$T/origin.git" "$T/other" 2>/dev/null
( cd "$T/other" && echo b > b.txt && git add b.txt && git commit -qm b && git push -q origin main )

# 1. clean primary checkout, behind -> fast-forwarded and told so
out=$(run "$T/clone/a.txt")
check "ff-clean-behind" '[ -f "$T/clone/b.txt" ] && printf "%s" "$out" | grep -q "Fast-forwarded"'

# 2. within the window -> silent, no git work
( cd "$T/other" && echo c > c.txt && git add c.txt && git commit -qm c && git push -q origin main )
out=$(run "$T/clone/a.txt")
check "window-silent" '[ -z "$out" ] && [ ! -f "$T/clone/c.txt" ]'

# 3. window expired, dirty tree -> not touched, agent told how far behind
export REPO_FRESHNESS_WINDOW_SEC=0
echo dirty >> "$T/clone/a.txt"
out=$(run "$T/clone/a.txt")
check "dirty-not-touched" '[ ! -f "$T/clone/c.txt" ] && grep -q dirty "$T/clone/a.txt"'
check "dirty-told" 'printf "%s" "$out" | grep -q "1 commit(s) behind origin/main" && printf "%s" "$out" | grep -q "uncommitted changes"'
( cd "$T/clone" && git checkout -q -- a.txt )

# 4. local commits + behind -> not rewritten, told about local commits
( cd "$T/clone" && echo l > l.txt && git add l.txt && git commit -qm local )
out=$(run "$T/clone/a.txt")
check "diverged-told" 'printf "%s" "$out" | grep -q "1 local commit(s)" && [ ! -f "$T/clone/c.txt" ]'

# 5. linked worktree -> skipped entirely
git -C "$T/clone" worktree add -q -b feat "$T/wt" origin/main 2>/dev/null
out=$(run "$T/wt/a.txt")
check "worktree-skipped" '[ -z "$out" ]'

# 6. not a repo, and malformed input -> silent, exit 0
out=$(run "$T/home"); rc=$?
check "non-repo" '[ -z "$out" ] && [ $rc -eq 0 ]'
out=$(printf 'not json' | python3 "$HOOK"); rc=$?
check "malformed" '[ -z "$out" ] && [ $rc -eq 0 ]'

# --- review findings (PR #487) ---------------------------------------------
fresh_pair() {  # $1 = name; makes origin + primary clone behind by one commit adding "$2"
  git init -q --bare -b main "$T/$1.git"
  git clone -q "$T/$1.git" "$T/$1" 2>/dev/null
  ( cd "$T/$1" && echo a > a.txt && git add a.txt && git commit -qm a && git push -q origin main )
  git clone -q "$T/$1.git" "$T/$1-up" 2>/dev/null
  ( cd "$T/$1-up" && mkdir -p "$(dirname "$2")" && echo tracked > "$2" && git add "$2" && git commit -qm up && git push -q origin main )
}

# 7. untracked file collides with an incoming tracked file -> git refuses; note gives git's reason
fresh_pair col b.txt
echo mine > "$T/col/b.txt"
out=$(run "$T/col/a.txt")
check "untracked-collision-reason" 'printf "%s" "$out" | grep -q "git refused the fast-forward" && ! printf "%s" "$out" | grep -q "0 local commit" && grep -q mine "$T/col/b.txt"'

# 8. IGNORED local file that upstream now tracks -> never overwritten
fresh_pair ign b.cfg
printf 'b.cfg\n' > "$T/ign/.git/info/exclude"; echo precious > "$T/ign/b.cfg"
out=$(run "$T/ign/a.txt")
check "ignored-file-protected" 'grep -q precious "$T/ign/b.cfg" && printf "%s" "$out" | grep -q "overwrite ignored local file"'

# 9. six concurrent tool calls in one window -> exactly one does the work
unset REPO_FRESHNESS_WINDOW_SEC
fresh_pair race r.txt
for i in 1 2 3 4 5 6; do run "$T/race/a.txt" > "$T/race-out.$i" & done; wait
notes=$(cat "$T"/race-out.* | grep -c "repo-freshness")
check "concurrent-single-claim" '[ "$notes" -eq 1 ] && [ -f "$T/race/r.txt" ]'
export REPO_FRESHNESS_WINDOW_SEC=0

# 10. Bash payload (no file path) uses the session cwd; camelCase toolInput (Grok) is read
fresh_pair bsh x.txt
out=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"%s"}' "$T/bsh" | python3 "$HOOK")
check "bash-cwd" '[ -f "$T/bsh/x.txt" ] && printf "%s" "$out" | grep -q Fast-forwarded'
fresh_pair cml y.txt
out=$(printf '{"toolName":"Read","toolInput":{"filePath":"%s"}}' "$T/cml/a.txt" | python3 "$HOOK")
check "camelcase-payload" '[ -f "$T/cml/y.txt" ]'

# 11. state lives under the hook-state convention
check "state-path" '[ -d "$HOME/.agents/.cache/state/hooks/repo-freshness" ]'

echo "repo-freshness: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
