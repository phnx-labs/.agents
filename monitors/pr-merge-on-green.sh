#!/bin/sh
# Poll helper for the pr-merge-on-green built-in (RUSH-2848).
#
# The daemon evaluates this from a non-repo cwd, so every `gh` invocation must
# name its repository explicitly — never `gh pr list` without `--repo`.
# Listing uses `gh search prs` (cwd-independent). Per-PR detail uses
# `gh pr view --repo <owner/name>`. Verdict reuse is pr-verdict.py, the same
# check merge-guard.sh runs (APPROVED review, OR a non-carried APPROVE in a
# COMMENTED review body or an issue comment).
#
# Usage:
#   pr-merge-on-green.sh            # live poll: print "owner/repo#n ..." (or empty)
#   pr-merge-on-green.sh --select   # stdin: one gh-pr-view JSON object; print
#                                   # owner/repo#n if CI-green AND verdict-ok
set -eu

# This fleet exports CLICOLOR_FORCE/FORCE_COLOR, and gh then paints --json
# with ANSI even on a pipe. jq refuses `^[1;37m{`. Drop the force so every
# gh --json payload is parseable (RUSH-2848 live miss: 20 PRs listed, jq
# died, empty observation).
unset CLICOLOR_FORCE || true
unset FORCE_COLOR || true
unset GH_FORCE_TTY || true
export CLICOLOR=0
export NO_COLOR=1
export GH_NO_COLOR=1
export GH_PAGER=cat

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERDICT="$DIR/../rules/subrules/gh-merge-guard/pr-verdict.py"
OWNER_FILE="$DIR/../rules/subrules/gh-merge-guard/trusted-owner-ids"

# owner-mode resolver (PHNX-3950). Best-effort source; absent -> owner-mode OFF
# (strict), same posture as merge-guard.sh. Resolve ONCE here: this daemon lists
# only `--author @me`, so the authenticated identity is constant across every PR
# in a tick. gh api user is cached, so even the fresh `--select` subprocess per
# PR pays it at most once an hour.
for _cand in "$DIR/../hooks/lib/owner-mode.sh" "${HOME}/.agents/.system/hooks/lib/owner-mode.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../hooks/lib/owner-mode.sh
    . "$_cand"
    if command -v _resolve_owner_mode >/dev/null 2>&1; then break; fi
  fi
done
unset _cand || true
if command -v _resolve_owner_mode >/dev/null 2>&1; then
  OWNER_MODE=$(_resolve_owner_mode "$OWNER_FILE" 2>/dev/null)
else
  OWNER_MODE=0
fi
case "$OWNER_MODE" in 1) ;; *) OWNER_MODE=0 ;; esac

ci_green() {
  # Same rollup predicate the built-in YAML used to inline. Vacuous-true on an
  # empty rollup is the pre-existing contract — do not widen it here.
  printf '%s' "$1" | jq -e '
    all(.statusCheckRollup[]?;
      (.conclusion // .state // .status // "") | ascii_upcase
      | . == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED")
  ' >/dev/null 2>&1
}

repo_of() {
  printf '%s' "$1" | jq -r '
    .repository.nameWithOwner
    // .repository
    // ( .url | capture("github.com/(?<r>[^/]+/[^/]+)/").r )
    // empty
  ' 2>/dev/null
}

number_of() {
  printf '%s' "$1" | jq -r '.number // empty' 2>/dev/null
}

verdict_ok() {
  reviews=$(printf '%s' "$1" | jq -c '.reviews // []')
  comments=$(printf '%s' "$1" | jq -c '.comments // []')
  # PHNX-3236: this daemon only ever lists PRs `--author @me` (see the live
  # poll below), so the PR author is ALWAYS this same shared fleet identity —
  # the exact shape of the self-merge bypass. Pass it through so pr-verdict.py
  # excludes anything authored by that identity before looking for a verdict.
  author=$(printf '%s' "$1" | jq -r '.author.login // empty')
  [ -n "$author" ] || return 1
  # base64-encode each segment: a review/comment body quoting this file's own
  # marker text would otherwise corrupt a plain-text split — see
  # pr-verdict.py's module docstring.
  # 4th segment is owner-mode (PHNX-3950): when this fleet's identity is a
  # trusted owner, its own code-reviewer APPROVE clears the verdict (all other
  # gates — carried/negation/code-fence — still apply) so the auto-merger stops
  # deadlocking every PR onto the human owner. Off by default.
  result=$(printf '%s\n---AGENTS-SPLIT---\n%s\n---AGENTS-SPLIT---\n%s\n---AGENTS-SPLIT---\n%s' \
      "$(printf '%s' "$reviews" | base64 | tr -d '\n')" \
      "$(printf '%s' "$comments" | base64 | tr -d '\n')" \
      "$(printf '%s' "$author" | base64 | tr -d '\n')" \
      "$(printf '%s' "$OWNER_MODE" | base64 | tr -d '\n')" \
    | python3 "$VERDICT" 2>/dev/null) || return 1
  [ "$result" = "ok" ]
}

select_one() {
  raw=$(cat)
  [ -n "$raw" ] || return 0
  repo=$(repo_of "$raw")
  num=$(number_of "$raw")
  [ -n "$repo" ] && [ -n "$num" ] || return 0
  if ci_green "$raw" && verdict_ok "$raw"; then
    printf '%s#%s\n' "$repo" "$num"
  fi
}

if [ "${1:-}" = "--select" ]; then
  select_one
  exit 0
fi

# Live poll. Swallow gh/jq failures so a broken tick is an empty observation
# (`mode: every` would otherwise fire on an error string).
list=$(gh search prs --author @me --state open --sort updated --limit 20 --json number,repository 2>/dev/null) || exit 0
printf '%s' "$list" | jq -e 'type == "array"' >/dev/null 2>&1 || exit 0

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '%s' "$list" | jq -c '.[]' > "$tmp" 2>/dev/null || exit 0

out=""
while IFS= read -r item || [ -n "$item" ]; do
  [ -n "$item" ] || continue
  num=$(printf '%s' "$item" | jq -r '.number // empty')
  repo=$(printf '%s' "$item" | jq -r '.repository.nameWithOwner // empty')
  [ -n "$num" ] && [ -n "$repo" ] || continue
  view=$(gh pr view "$num" --repo "$repo" --json number,url,statusCheckRollup,reviews,comments,author 2>/dev/null) || continue
  view=$(printf '%s' "$view" | jq -c --arg repo "$repo" '. + {repository: {nameWithOwner: $repo}}' 2>/dev/null) || continue
  sel=$(printf '%s' "$view" | sh "$DIR/pr-merge-on-green.sh" --select || true)
  [ -n "$sel" ] && out="$out$sel "
done < "$tmp"

printf '%s' "$out"
