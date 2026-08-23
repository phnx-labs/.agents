#!/bin/sh
# no-pr-footer/footer-guard.sh — PreToolUse(Bash) guard.
#
# Blocks `gh pr create|edit`, `gh issue create|edit`, and `git commit` whose
# inline body carries the "Generated with Claude Code" promo footer. Muqsit's
# standing rule: that line is garbage and must never reach a PR/issue/commit.
#
# Reads the hook JSON from stdin, extracts the tool command via jq. Claude Code
# sends it under snake_case .tool_input.command; Grok CLI sends camelCase
# .toolInput.command — read either so the footer block works on both harnesses.
# Exits 0 (allow) or 2 (deny, message on stderr). Only inline bodies are seen;
# a footer injected via --body-file is invisible here (acceptable — the common
# failure mode in the retro was an inline --body heredoc).
input=$(cat)

# Fast path: ignore anything that isn't a gh pr/issue or git commit command.
case "$input" in
  *"gh pr "*|*"gh issue "*|*"git commit"*) ;;
  *) exit 0 ;;
esac

# --- shared JSON field extractor -------------------------------------------
# _json_field lives in hooks/lib/json-field.sh (one definition; formerly copied
# into 12 hook scripts). Source it relative to this script, fall back to the
# absolute system-install path, then verify it is defined. The command already
# matched the gh/git fast path, so if the guard cannot parse it must refuse it
# unchecked rather than let a footer slip (fail CLOSED, exit 2). ${0%/*} (POSIX,
# no subprocess) locates the lib even when PATH carries no coreutils.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../../../hooks/lib/json-field.sh" "${HOME}/.agents/.system/hooks/lib/json-field.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../../../hooks/lib/json-field.sh
    . "$_cand"
    if command -v _json_field >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v _json_field >/dev/null 2>&1; then
  printf '%s\n' 'footer-guard: shared json-field lib not found — refusing the gh/git command unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/json-field.sh is present.' >&2
  exit 2
fi

if ! cmd=$(_json_field "$input" tool_input.command toolInput.command); then
  # No JSON parser available — fail CLOSED. The command already matched the
  # gh/git fast path above, so refuse it unchecked rather than let a footer slip.
  printf '%s\n' 'footer-guard: no JSON parser (jq/node/python) available — refusing the gh/git command unchecked (fail-closed). Ensure node or jq is on PATH.' >&2
  exit 2
fi
[ -n "$cmd" ] || exit 0

# Only the body-bearing subcommands.
case "$cmd" in
  *"gh pr create"*|*"gh pr edit"*|*"gh issue create"*|*"gh issue edit"*|*"git commit"*) ;;
  *) exit 0 ;;
esac

# Detect the promo footer in any of its forms.
case "$cmd" in
  *"Generated with"*"Claude Code"*|*"claude.com/claude-code"*|*"claude.ai/code"*|*"🤖 Generated"*)
    printf '%s\n' 'Blocked: remove the "Generated with Claude Code" footer from the body. Muqsit'\''s standing rule — that promo line is garbage and must never appear in PR/issue/commit bodies. Delete the line and retry.' >&2
    exit 2
    ;;
esac
exit 0
