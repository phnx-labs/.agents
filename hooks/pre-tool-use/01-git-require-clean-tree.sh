#!/bin/bash
# PreToolUse hook: block git pull/rebase/autostash when working tree is dirty.
# Fast path uses pure-bash pattern matching (no forks) so non-git Bash calls
# add ~2ms. Only git-ish commands pay for jq + git status.

IFS= read -rd '' input

case "$input" in
  *'"command":"git '*|*'"command":"timeout '*|*'"command":"gtimeout '*|*'--autostash'*) ;;
  *) exit 0 ;;
esac

# --- portable JSON field extractor (jq -> node -> python) -------------------
# --- shared JSON field extractor -------------------------------------------
# _json_field lives in hooks/lib/json-field.sh (one definition; formerly copied
# into 12 hook scripts). Source it relative to this script, fall back to the
# absolute system-install path, then verify it is defined — this guard blocks
# pull/rebase on a dirty tree, so if it cannot parse it must refuse rather than
# allow (fail CLOSED, exit 2). ${0%/*} (POSIX, no subprocess) locates the lib
# even when PATH carries no coreutils.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../lib/json-field.sh" "${HOME}/.agents/.system/hooks/lib/json-field.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../lib/json-field.sh
    . "$_cand"
    if command -v _json_field >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v _json_field >/dev/null 2>&1; then
  echo "git-require-clean-tree: shared json-field lib not found — refusing git pull/rebase unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/json-field.sh is present." >&2
  exit 2
fi

_hook_skip_plan_mode "$input" && exit 0

# --- shared timeout-wrapper peeler ------------------------------------------
# `timeout 5 git pull origin main` would otherwise bypass the dirty-tree check
# because `timeout` is the first token. The peeler lives in hooks/lib/git-parse.sh.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../lib/git-parse.sh" "${HOME}/.agents/.system/hooks/lib/git-parse.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../lib/git-parse.sh
    . "$_cand"
    if command -v git_peel_timeout_wrapper >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v git_peel_timeout_wrapper >/dev/null 2>&1; then
  echo "git-require-clean-tree: shared git-parse lib not found — refusing git pull/rebase unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/git-parse.sh is present." >&2
  exit 2
fi

# --- friction self-report ---------------------------------------------------
# This hook exits 2 before any `agents` process exists, so it cannot emit
# in-process. Fires the hidden recorder in the background, fully fail-open,
# so a missing/slow CLI never breaks the guard's hot path.
report_friction() {  # $1=failureId  $2=error-message
  [ -z "${AGENTS_DISABLE_FRICTION_LOG:-}" ] || return 0
  (agents _internal friction --surface guard --id "$1" \
    --error "$2" --command "$cmd" || true) </dev/null >/dev/null 2>&1 &
}

# Claude/Codex/Kimi/Cursor/Droid: tool_input.command; Grok: toolInput.command.
if ! cmd=$(_json_field "$input" tool_input.command); then
  echo "git-require-clean-tree: no JSON parser succeeded (malformed payload or jq/node/python unavailable) — refusing git pull/rebase unchecked (fail-closed)." >&2
  exit 2
fi
[ -z "$cmd" ] && cmd=$(_json_field "$input" toolInput.command) || true

# Peel any leading timeout/gtimeout wrapper so the prefix match sees the real
# git pull/rebase/autostash command.
cmd=$(git_peel_timeout_wrapper "$cmd")

case "$cmd" in
  "git pull"*|"git rebase"*|*" git pull"*|*" git rebase"*|*"--autostash"*) ;;
  *) exit 0 ;;
esac

cwd=$(_json_field "$input" cwd) || cwd=""
[ -z "$cwd" ] && cwd=$(_json_field "$input" workspaceRoot) || true
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

[ -z "$(git status --porcelain 2>/dev/null)" ] && exit 0

deny_reason="Blocked: working tree is dirty. git pull/rebase/autostash on a dirty tree can destroy uncommitted work. Commit (or manually stash) first, then retry."
echo "$deny_reason" >&2
report_friction "git.pull-rebase-dirty-tree" "$deny_reason"
exit 2
