#!/bin/sh
# hooks/lib/owner-mode.sh — shared "owner-mode" resolver for the merge path
# (PHNX-3950). Sourced, never executed.
#
# WHY. Every fleet agent authenticates as ONE shared GitHub identity, so
# pr-verdict.py's self-author exclusion (PHNX-3236) is unsatisfiable under it:
# the code-reviewer's APPROVE is always "self-authored" and every PR deadlocks
# onto the human owner (repro: PR #432, merged by hand). owner-mode tells
# pr-verdict.py to KEEP every laundering/negation/code-fence gate but stop
# dropping same-login verdicts — used ONLY when the authenticated identity is a
# trusted fleet owner.
#
# TRUST SOURCE. A trusted owner is a numeric GitHub user id, merged from three
# places (a '#' starts a comment; blank lines ignored):
#   * env AGENTS_MERGE_TRUSTED_OWNER_IDS (whitespace/newline separated);
#   * the USER-LAYER file ${HOME}/.agents/trusted-owner-ids — where a fleet opts
#     ITSELF in. It lives OUTSIDE the pull-only system mirror (~/.agents/.system),
#     so it survives `agents repo pull system` and is never shared upstream;
#   * the system-layer file passed by the caller
#     (rules/subrules/gh-merge-guard/trusted-owner-ids) — SHIPPED EMPTY as a
#     documented template so the upstream mirror grants no fleet by default.
# Numeric ids are rename-proof and are exactly the ruleset's exempt bypass
# actor_id, so GitHub already restricts unreviewed merges to this same identity
# server-side — owner-mode never grants more than GitHub already allows; it only
# stops the LOCAL guard/auto-merger from false-blocking that identity.
#
# SAFE DEFAULT. No env and empty/missing files => NO trusted ids => owner-mode
# is always "0" and NO network call is made. This is the shipped-mirror default
# for every other fleet: zero behavior change until a fleet opts in with its own
# id. Any resolution failure (gh error, timeout, unauth) also yields "0" — the
# strict, block-by-default direction, never a fail-open to self-merge.
#
# _resolve_owner_login <trusted_ids_file>  -> prints the authenticated GitHub
# LOGIN if the authenticated numeric id is a trusted owner, else prints nothing.
#
# owner-mode engages ONLY for a PR whose OWN AUTHOR equals this login — the
# caller compares `pr_author` against it. That distinction is load-bearing: a
# trusted owner merging a THIRD PARTY's PR must NOT get that party's own
# self-approval counted as a verdict (doing so would reopen the PHNX-3236
# self-merge laundering for third-party PRs). "A trusted identity is running the
# merge" is NOT the same as "this PR was opened by the trusted owner"; only the
# latter is the shared-identity self-review case owner-mode exists for. Empty
# output => owner-mode never engages.

# Portable 3s timeout around the single `gh api user` call (macOS ships neither
# `timeout` nor `gtimeout` by default; fall back to unbounded, same posture the
# merge-guard verdict probe already accepts for gh calls). Prints "<id> <login>"
# (a GitHub login never contains a space, so a single space separator is
# unambiguous).
_om_gh_user() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 3 gh api user --jq '"\(.id) \(.login)"' --cache 3600s 2>/dev/null
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 3 gh api user --jq '"\(.id) \(.login)"' --cache 3600s 2>/dev/null
  else
    gh api user --jq '"\(.id) \(.login)"' --cache 3600s 2>/dev/null
  fi
}

_resolve_owner_login() {
  _om_sys_file=$1
  _om_ids=""
  # env first
  if [ -n "${AGENTS_MERGE_TRUSTED_OWNER_IDS:-}" ]; then
    _om_ids="$AGENTS_MERGE_TRUSTED_OWNER_IDS"
  fi
  # then the files (strip '#' comments): user-layer opt-in, then shipped template
  for _om_file in "${HOME}/.agents/trusted-owner-ids" "$_om_sys_file"; do
    if [ -n "$_om_file" ] && [ -f "$_om_file" ]; then
      _om_file_ids=$(sed 's/#.*//' "$_om_file" 2>/dev/null | tr '\n\t' '  ')
      _om_ids="$_om_ids $_om_file_ids"
    fi
  done
  # No trusted id configured anywhere -> no owner, no network call.
  case "$_om_ids" in
    *[0-9]*) ;;
    *) return 0 ;;
  esac
  # Guard the substitution so a gh failure (auth refresh, rate limit, network)
  # degrades to "no owner" instead of aborting a `set -e` caller
  # (pr-merge-on-green.sh runs under `set -eu`) mid-poll.
  _om_user=$(_om_gh_user) || _om_user=""
  [ -n "$_om_user" ] || return 0
  _om_id=${_om_user%% *}
  _om_login=${_om_user#* }
  # id must be purely numeric; login must be a real GitHub login (alnum + '-').
  case "$_om_id" in ''|*[!0-9]*) return 0 ;; esac
  case "$_om_login" in ''|*[!A-Za-z0-9-]*) return 0 ;; esac
  for _om_id_t in $_om_ids; do
    if [ "$_om_id_t" = "$_om_id" ]; then
      printf '%s' "$_om_login"
      return 0
    fi
  done
  return 0
}
