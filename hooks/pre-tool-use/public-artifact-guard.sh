#!/bin/sh
# public-artifact-guard — PreToolUse hook on Bash.
#
# Blocks `git add` / `git commit` of confidential business strategy into a
# repo's `.agents/artifacts/` directory, which is COMMITTED by design and on an
# OSS repo is therefore PUBLIC.
#
# Why this exists (RUSH-3033): the agi-cli GTM/monetization strategy -- real
# revenue figures, a "~no users" assessment, competitor intel, pricing model,
# launch plan -- was committed to `.agents/artifacts/` on the public agents-cli
# repo and was world-readable for about two days. The files were removed from
# the tip, but git history still carries them, and strategy intel is not a
# rotatable secret. This guard is item 3 of that ticket's remediation: stop the
# next one at the tool boundary instead of discovering it two days later.
#
# The failure mode is structural, not careless. Two documented rules compose
# badly: `.agents/artifacts/<date>/` is "durable output, committed", while
# `.agents/scratch/` is gitignored -- so an agent writing a "durable" strategy
# doc puts it on the public path by following instructions. Meanwhile the
# session-recap workflow tells agents to commit any uncommitted work they find,
# including other sessions'. A 2026-08-22 sweep found exactly that pending: an
# internal monetization strategy and a 1147-line copy of the operator's private
# global ruleset sitting untracked in the public tree, one `git add -A` away.
#
# What it does NOT key on: `surface: internal` frontmatter. That field names the
# PRODUCT surface a plan touches (internal / cli / web / native / api /
# workflow), not its confidentiality -- ordinary architecture plans carry it, so
# keying on it would deny the common case and train everyone to bypass the
# guard. It keys on strategy-shaped FILENAMES (the approach RUSH-3033 itself
# proposes) plus an explicit `confidential: true` frontmatter opt-in.
#
# Exits 0 (allow) or 2 (deny, message on stderr).
#
# Out of scope, deliberately:
#   - `git add -A` / `git add .` / `git commit -a`: the paths are not in the
#     command, so there is nothing to introspect at hook time. Same boundary
#     large-file-add-guard draws. Those are caught by review, not here.
#   - Private repos: visibility needs a network call (`gh repo view`) on a hot
#     path that must stay fast and offline-safe. A confidential strategy doc
#     does not belong in a tracked artifacts dir of ANY repo -- private repos
#     get forked, made public, and shared. Use `.agents/scratch/` instead.

set -eu

input=$(cat)
# Fast path: must mention git and a staging/commit verb.
case "$input" in
  *git*add*|*git*commit*|*git*stage*) ;;
  *) exit 0 ;;
esac

# Portable JSON field (jq -> node -> python). Claude/Codex: tool_input.command;
# Grok: toolInput.command. Empty on both -> not a shell tool, allow.
_json_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r "(.$2) // empty" 2>/dev/null; return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{let o=JSON.parse(s);for(const k of process.argv[1].split("."))o=(o==null?null:o[k]);process.stdout.write(o==null?"":String(o))}catch(e){}})' "$2" 2>/dev/null; return 0
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$1" | "$_py" -c 'import json,sys
try: o=json.load(sys.stdin)
except Exception: o=None
for k in sys.argv[1].split("."):
    o=o.get(k) if isinstance(o,dict) else None
sys.stdout.write("" if o is None else str(o))' "$2" 2>/dev/null
    return 0
  done
  return 1
}

if ! cmd=$(_json_field "$input" tool_input.command); then
  printf 'public-artifact-guard: no JSON parser (jq/node/python) — refusing the staging command unchecked (fail-closed).\n' >&2
  exit 2
fi
[ -z "$cmd" ] && cmd=$(_json_field "$input" toolInput.command) || true
[ -z "$cmd" ] && exit 0

# --- friction self-report ---------------------------------------------------
# Guard hooks exit 2 before any `agents` process exists, so they cannot emit
# in-process. Fire the hidden recorder in the background, fully fail-open.
report_friction() {  # $1=failureId  $2=error-message
  [ -z "${AGENTS_DISABLE_FRICTION_LOG:-}" ] || return 0
  _friction_cmd=$cmd
  (agents _internal friction --surface guard --id "$1" \
    --error "$2" --command "$_friction_cmd" || true) </dev/null >/dev/null 2>&1 &
}

# Structured denial (RUSH-2295) — same shape as git-guard / rm-guard.
emit_deny() {  # $1=path  $2=why
  report_friction "artifacts.confidential-publish" "$2"
  printf 'blocked_op: %s\nreason: %s\ndo_this_instead: %s\n' \
    "artifacts.confidential-publish" \
    "$1 — $2. .agents/artifacts/ is COMMITTED by design, so on an OSS repo this is published to the world (RUSH-3033: exactly this leaked GTM strategy for ~2 days, and git history still carries it)." \
    "Confidential business material does not belong on a tracked path. Move it to .agents/scratch/ (gitignored) or a PRIVATE repo, then stage the rest. If this file is genuinely publishable, rename it away from the strategy-document pattern or drop 'confidential: true' from its frontmatter — do not work around the guard." >&2
}

# A strategy-shaped basename. Deliberately narrow: it names the document CLASS
# that leaked (RUSH-3033 lists gtm-strategy, how-winners-charge, pricing-models,
# monetize, launch-venues, github-stars-playbook, supply-vs-demand,
# byo-subscription), not every business-adjacent word. A plan about billing CODE
# is engineering and must still be committable.
is_strategy_name() {
  case $(printf '%s' "${1##*/}" | tr '[:upper:]' '[:lower:]') in
    *gtm*|*go-to-market*|*monetiz*|*pricing-model*|*how-winners-charge*) return 0 ;;
    *launch-venue*|*stars-playbook*|*supply-vs-demand*|*byo-subscription*) return 0 ;;
    *competitive-landscape*|*competitor-intel*|*revenue-model*|*fundrais*) return 0 ;;
  esac
  return 1
}

# An explicit frontmatter opt-in, for material the filename does not betray.
# Only the leading frontmatter block is read, so the phrase appearing in prose
# (e.g. this guard's own docs) does not trip it.
has_confidential_frontmatter() {
  [ -f "$1" ] || return 1
  case "$1" in *.md|*.markdown|*.mdx|*.html|*.yaml|*.yml) ;; *) return 1 ;; esac
  # `exit` in awk still runs END, so END must not hard-code the status or it
  # overrides the match — carry the result in a flag instead.
  head -20 "$1" 2>/dev/null | awk '
    NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR>1 && /^---[[:space:]]*$/ { exit }
    tolower($0) ~ /^confidential:[[:space:]]*(true|yes)[[:space:]]*$/ { found=1; exit }
    END { exit (found ? 0 : 1) }
  ' && return 0
  return 1
}

check_path() {
  _p=$1
  # Quoted globs reach git unexpanded; nothing to inspect.
  case "$_p" in *\**|*\?*|*\[*) return 0 ;; esac
  # Only guard the artifacts dir — the one documented as committed.
  case "$_p" in */.agents/artifacts/*|.agents/artifacts/*) ;; *) return 0 ;; esac

  if is_strategy_name "$_p"; then
    emit_deny "$_p" "reads as a confidential business-strategy document"
    exit 2
  fi
  if has_confidential_frontmatter "$_p"; then
    emit_deny "$_p" "declares 'confidential: true' in its frontmatter"
    exit 2
  fi
  return 0
}

# Walk the command's words; skip flags and the git verbs themselves.
# shellcheck disable=SC2086
for word in $cmd; do
  case "$word" in
    -*|git|add|commit|stage|/*/git) continue ;;
  esac
  check_path "$word"
done

exit 0
