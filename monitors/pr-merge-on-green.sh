#!/bin/sh
# Poll helper for the pr-merge-on-green built-in (RUSH-2848).
#
# The daemon evaluates this from a non-repo cwd, so every `gh` invocation must
# name its repository explicitly — never `gh pr list` without `--repo`.
# Listing uses `gh search prs` (cwd-independent). Per-PR detail uses
# `gh pr view --repo <owner/name>`. Verdict reuse is pr-verdict.py, the same
# check merge-guard.sh runs (APPROVED review OR a non-carried APPROVE comment).
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
  result=$(printf '%s\n---AGENTS-SPLIT---\n%s' "$reviews" "$comments" | python3 "$VERDICT" 2>/dev/null) || return 1
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
  view=$(gh pr view "$num" --repo "$repo" --json number,url,statusCheckRollup,reviews,comments 2>/dev/null) || continue
  view=$(printf '%s' "$view" | jq -c --arg repo "$repo" '. + {repository: {nameWithOwner: $repo}}' 2>/dev/null) || continue
  sel=$(printf '%s' "$view" | sh "$DIR/pr-merge-on-green.sh" --select || true)
  [ -n "$sel" ] && out="$out$sel "
done < "$tmp"

printf '%s' "$out"
