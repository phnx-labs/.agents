#!/usr/bin/env bash
# Tests for 09-git-pull-forward.sh — clean-tree fast-forward only.
set -euo pipefail

DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
HOOK="$DIR/../09-git-pull-forward.sh"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   — $1"; }
bad()  { fail=$((fail+1)); echo "FAIL — $1"; }

# Remote (bare) + clone
git -C "$ROOT" init --bare remote.git >/dev/null 2>&1
git -C "$ROOT" clone remote.git work >/dev/null 2>&1
REPO="$ROOT/work"
git -C "$REPO" config user.email "t@example.com"
git -C "$REPO" config user.name "test"
echo base > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -m base >/dev/null 2>&1
git -C "$REPO" push -u origin HEAD >/dev/null 2>&1
# default branch name
BR=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)

run_hook() {
  # $1 = json cwd payload path component
  local cwd_json
  cwd_json=$(printf '{"cwd":"%s"}' "$1")
  printf '%s' "$cwd_json" | bash "$HOOK" >/dev/null 2>&1 || true
}

# 1. Behind remote by 1 commit, clean → ff
git -C "$ROOT" clone remote.git other >/dev/null 2>&1
git -C "$ROOT/other" config user.email "t@example.com"
git -C "$ROOT/other" config user.name "test"
echo next > "$ROOT/other/b.txt"
git -C "$ROOT/other" add b.txt
git -C "$ROOT/other" commit -m next >/dev/null 2>&1
git -C "$ROOT/other" push origin "HEAD:$BR" >/dev/null 2>&1

before=$(git -C "$REPO" rev-parse HEAD)
run_hook "$REPO"
after=$(git -C "$REPO" rev-parse HEAD)
if [ "$before" != "$after" ] && [ -f "$REPO/b.txt" ]; then
  ok "clean + behind → fast-forward"
else
  bad "clean + behind → fast-forward (before=$before after=$after)"
fi

# 2. Dirty tree → no pull
echo dirt > "$REPO/dirty.txt"
before=$(git -C "$REPO" rev-parse HEAD)
# advance remote again
echo third > "$ROOT/other/c.txt"
git -C "$ROOT/other" add c.txt
git -C "$ROOT/other" commit -m third >/dev/null 2>&1
git -C "$ROOT/other" push origin "HEAD:$BR" >/dev/null 2>&1
run_hook "$REPO"
after=$(git -C "$REPO" rev-parse HEAD)
if [ "$before" = "$after" ] && [ ! -f "$REPO/c.txt" ]; then
  ok "dirty tree → skip"
else
  bad "dirty tree → skip"
fi
rm -f "$REPO/dirty.txt"

# 3. Local commit not on remote → skip (would diverge)
echo local > "$REPO/local.txt"
git -C "$REPO" add local.txt
git -C "$REPO" commit -m local >/dev/null 2>&1
before=$(git -C "$REPO" rev-parse HEAD)
run_hook "$REPO"
after=$(git -C "$REPO" rev-parse HEAD)
if [ "$before" = "$after" ]; then
  ok "local-only commits → skip"
else
  bad "local-only commits → skip"
fi

# 4. Opt-out env
export AGENTS_NO_GIT_PULL_FORWARD=1
# reset local commit so we'd otherwise be behind again — but opt-out must skip
git -C "$REPO" reset --hard "origin/$BR" >/dev/null 2>&1
echo fourth > "$ROOT/other/d.txt"
git -C "$ROOT/other" add d.txt
git -C "$ROOT/other" commit -m fourth >/dev/null 2>&1
git -C "$ROOT/other" push origin "HEAD:$BR" >/dev/null 2>&1
before=$(git -C "$REPO" rev-parse HEAD)
run_hook "$REPO"
after=$(git -C "$REPO" rev-parse HEAD)
if [ "$before" = "$after" ]; then
  ok "AGENTS_NO_GIT_PULL_FORWARD=1 → skip"
else
  bad "AGENTS_NO_GIT_PULL_FORWARD=1 → skip"
fi
unset AGENTS_NO_GIT_PULL_FORWARD

echo "----"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
