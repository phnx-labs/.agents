#!/bin/bash
set -euo pipefail

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

printf 'normal\n' > "$TMP_DIR/normal.txt"
git -C "$TMP_DIR" add normal.txt
git -C "$TMP_DIR" commit -q -m "normal commit"

mkdir -p "$TMP_DIR/.agents/plans"
printf 'local plan\n' > "$TMP_DIR/.agents/plans/plan.html"
NEWLINE_PATH=$'.agents/plans/line\nbreak.html'
printf 'newline plan\n' > "$TMP_DIR/$NEWLINE_PATH"
git -C "$TMP_DIR" add .agents/plans/plan.html "$NEWLINE_PATH"

set +e
ADD_OUTPUT=$(git -C "$TMP_DIR" commit -m "must fail" 2>&1)
ADD_STATUS=$?
set -e

if [[ $ADD_STATUS -eq 0 ]]; then
    echo "FAIL: staged .agents/ addition was committed" >&2
    exit 1
fi
if [[ "$ADD_OUTPUT" != *"Commit blocked: .agents/ contains local agent output and must not be tracked."* ]]; then
    echo "FAIL: missing path-policy refusal for .agents/ addition" >&2
    echo "$ADD_OUTPUT" >&2
    exit 1
fi
if [[ "$ADD_OUTPUT" != *".agents/plans/plan.html"* ]]; then
    echo "FAIL: refusal did not name the staged .agents/ addition" >&2
    echo "$ADD_OUTPUT" >&2
    exit 1
fi
if [[ "$ADD_OUTPUT" != *"$NEWLINE_PATH"* ]]; then
    echo "FAIL: refusal did not name the staged .agents/ path containing a newline" >&2
    echo "$ADD_OUTPUT" >&2
    exit 1
fi

git -C "$TMP_DIR" commit -q --no-verify -m "fixture: track local plan"
rm "$TMP_DIR/.agents/plans/plan.html"
rm "$TMP_DIR/$NEWLINE_PATH"
git -C "$TMP_DIR" add -u .agents

set +e
DELETE_OUTPUT=$(git -C "$TMP_DIR" commit -m "must also fail" 2>&1)
DELETE_STATUS=$?
set -e

if [[ $DELETE_STATUS -eq 0 ]]; then
    echo "FAIL: staged .agents/ deletion was committed" >&2
    exit 1
fi
if [[ "$DELETE_OUTPUT" != *".agents/plans/plan.html"* ]]; then
    echo "FAIL: refusal did not name the staged .agents/ deletion" >&2
    echo "$DELETE_OUTPUT" >&2
    exit 1
fi

echo "PASS: pre-commit blocks staged .agents/ additions and deletions, and allows unrelated commits"
