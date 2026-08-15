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
git -C "$TMP_DIR" add .agents/plans/plan.html
git -C "$TMP_DIR" commit -q -m "tracked reviewed plan"

mkdir -p "$TMP_DIR/.agents/artifacts"
printf 'local artifact\n' > "$TMP_DIR/.agents/artifacts/output.html"
NEWLINE_PATH=$'.agents/artifacts/line\nbreak.html'
printf 'newline artifact\n' > "$TMP_DIR/$NEWLINE_PATH"
git -C "$TMP_DIR" add .agents/artifacts/output.html "$NEWLINE_PATH"

set +e
ADD_OUTPUT=$(git -C "$TMP_DIR" commit -m "must fail" 2>&1)
ADD_STATUS=$?
set -e

if [[ $ADD_STATUS -eq 0 ]]; then
    echo "FAIL: staged .agents/ addition was committed" >&2
    exit 1
fi
if [[ "$ADD_OUTPUT" != *"Commit blocked: .agents/ contains local agent output outside tracked .agents/plans/."* ]]; then
    echo "FAIL: missing path-policy refusal for .agents/ addition" >&2
    echo "$ADD_OUTPUT" >&2
    exit 1
fi
if [[ "$ADD_OUTPUT" != *".agents/artifacts/output.html"* ]]; then
    echo "FAIL: refusal did not name the staged .agents/ addition" >&2
    echo "$ADD_OUTPUT" >&2
    exit 1
fi
if [[ "$ADD_OUTPUT" != *"$NEWLINE_PATH"* ]]; then
    echo "FAIL: refusal did not name the staged .agents/ path containing a newline" >&2
    echo "$ADD_OUTPUT" >&2
    exit 1
fi

git -C "$TMP_DIR" commit -q --no-verify -m "fixture: track local artifact"
rm "$TMP_DIR/.agents/artifacts/output.html"
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
if [[ "$DELETE_OUTPUT" != *".agents/artifacts/output.html"* ]]; then
    echo "FAIL: refusal did not name the staged .agents/ deletion" >&2
    echo "$DELETE_OUTPUT" >&2
    exit 1
fi

echo "PASS: pre-commit tracks reviewed plans and blocks other .agents/ additions/deletions"
