#!/usr/bin/env bash
# Proves the registered hooks/ entrypoint reaches the canonical rule guard and
# fails closed if neither its checkout-relative nor installed-system target is
# available.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
ENTRY="$DIR/../main-branch-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

REPO="$TMP/primary"
mkdir -p "$REPO"
git -c init.defaultBranch=main -C "$REPO" init -q
git -c user.email=t@example.test -c user.name=t -C "$REPO" commit --allow-empty -qm init
payload=$(jq -n --arg p "$REPO/new.txt" '{tool_name:"Write",cwd:"/tmp",tool_input:{file_path:$p}}')
set +e
out=$(printf '%s' "$payload" | AGENTS_NO_AUTO_WORKTREE=1 "$ENTRY" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'PRIMARY working tree'; then
  ok "registered entrypoint invokes canonical guard"
else
  bad "registered entrypoint: expected canonical denial rc=2, got rc=$rc [$out]"
fi

# Copy only the entrypoint away from the repository and point real-home at an
# empty root: neither lookup can resolve, so the entrypoint itself must deny.
mkdir -p "$TMP/isolated/hooks/pre-tool-use" "$TMP/empty-home"
cp "$ENTRY" "$TMP/isolated/hooks/pre-tool-use/main-branch-guard.sh"
chmod +x "$TMP/isolated/hooks/pre-tool-use/main-branch-guard.sh"
set +e
out=$(printf '%s' '{}' | HOME="$TMP/version-home" AGENTS_REAL_HOME="$TMP/empty-home" \
  "$TMP/isolated/hooks/pre-tool-use/main-branch-guard.sh" 2>&1)
rc=$?
set -e
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'canonical rule guard not found'; then
  ok "registered entrypoint fails closed when canonical guard is absent"
else
  bad "missing canonical guard: expected fail-closed rc=2, got rc=$rc [$out]"
fi

printf '\nmain-branch-guard-registration: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
