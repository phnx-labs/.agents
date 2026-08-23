#!/bin/sh
# parallel-teams/teams-roster-guard.sh — PreToolUse(Bash) guard (RUSH-3020).
#
# Blocks the 3rd same-harness teammate added to one team when other harnesses
# are installed on THIS machine, unless the brief states a reason.
#
# Why: team rosters go monoculture by imitation, not intent — measured on a
# real fleet: 86% of recorded teammates were one harness while five others sat
# installed and idle, and 7 of 10 rosters were single-harness. Prose "mix
# vendors" guidance is advisory and loses; this guard is the enforcement the
# rules README requires ("a rule that only asks nicely is a suggestion").
#
# Fleet-agnostic by construction — everything is computed from this machine at
# run time; the script ships zero fleet-specific facts:
#   * installed harnesses  <- ~/.agents/.history/versions/<agent>/ (local
#     version homes). Fewer than 2 installed -> guard never fires.
#   * team roster          <- ~/.agents/.history/teams/agents/*/meta.json
#     (task_name + agent_type), the same records `agents teams add` persists.
# Harness-agnostic: a grok monoculture trips it the same as a claude one —
# the bias being corrected is self-similarity, not one vendor.
#
# Escape: a `single-harness: <reason>` token anywhere in the add command
# (put it in the teammate brief; it is stored with the roster on disk, so the
# exception is auditable later).
#
# Fail-open: any parse/read error exits 0 — this guard must never wedge a
# spawn. Exits 2 (deny, message on stderr) only on a provable 3rd same-harness
# add with alternatives installed and no reason stated.

input=$(cat)

# --- shared JSON field extractor -------------------------------------------
# _json_field lives in hooks/lib/json-field.sh (one definition; formerly copied
# into 12 hook scripts — the lib body is a superset of the local one, adding a
# node fallback between jq and python). Source it relative to this script, fall
# back to the absolute system-install path. This guard fails OPEN on a parse
# failure (it only advises on roster mix), so a missing lib skips quietly
# (exit 0). ${0%/*} (POSIX, no subprocess) locates the lib even when PATH
# carries no coreutils.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../../../hooks/lib/json-field.sh" "${HOME}/.agents/.system/hooks/lib/json-field.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../../../hooks/lib/json-field.sh
    . "$_cand"
    if command -v _json_field >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
command -v _json_field >/dev/null 2>&1 || exit 0

cmd=$(_json_field "$input" "tool_input.command" "toolInput.command") || exit 0
[ -n "$cmd" ] || exit 0

# Cheap substring pre-filter only — the real gates are the quote-parity
# check and command-position extraction below. Best-effort, like
# gh-merge-guard's SCOPE note: prose mentions (echo strings, comments,
# grep patterns, note appends) pass via quote parity + anchoring; a
# determined obfuscation could still slip a real invocation past a text
# rule — the enforcement backstop is the roster record itself, which any
# monoculture spawn writes to disk where audits and the fleet-delegation
# rule read it.
case "$cmd" in
  *"agents teams add"*|*"ag teams add"*) : ;;
  *) exit 0 ;;
esac

# Stated reason clears the guard before any computation.
case "$cmd" in
  *single-harness:*|*single_harness:*) exit 0 ;;
esac

# Quote parity: a marker inside an open quote is prose (an echo string, a
# heredoc line, a notes append), not an invocation. Count quotes BEFORE the
# first marker occurrence; odd means we are inside a quoted string — pass.
# This is a heuristic like merge-guard's SCOPE note, not a shell parser:
# balanced-quote prose before a real chained invocation still blocks
# correctly, and exotic nesting over-passes (fail-open direction).
_p1=${cmd%%"agents teams add"*}
_p2=${cmd%%"ag teams add"*}
prefix="$_p1"
[ ${#_p2} -lt ${#_p1} ] && prefix="$_p2"
dq=$(printf '%s' "$prefix" | tr -cd '"' | wc -c)
sq=$(printf '%s' "$prefix" | tr -cd "'" | wc -c)
[ $((dq % 2)) -eq 1 ] && exit 0
[ $((sq % 2)) -eq 1 ] && exit 0

# Extract team + harness from the first `agents teams add` at a COMMAND
# position: start of the command, or right after a shell separator (; & |,
# covering && and ||), a subshell open, or a newline. `echo "reminder:
# agents teams add x y"` has a quote/word before the marker and never
# matches; `cd wt && agents teams add x y` does.
set -- $(printf '%s\n' "$cmd" | sed -nE 's/^[[:space:]]*(env [^;&|(]*)?(agents|ag) teams add[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+).*/\3 \4/p; s/.*[;&|(][[:space:]]*(agents|ag) teams add[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+).*/\2 \3/p' | head -1)
team="${1:-}"
harness="${2:-}"
[ -n "$team" ] && [ -n "$harness" ] || exit 0
# A flag in the team slot means an unusual invocation shape — stay out of the
# way. (A flag in the harness slot is harmless: no real agent_type starts
# with '-' so the roster comparison below can never match it.)
case "$team" in -*) exit 0 ;; esac
case "$harness" in -*) exit 0 ;; esac

home_dir="${HOME:-}"
[ -n "$home_dir" ] || exit 0

# Fewer than two harnesses installed here -> mixing is impossible -> never fire.
installed=0
for d in "$home_dir/.agents/.history/versions"/*/; do
  [ -d "$d" ] && installed=$((installed + 1))
done
[ "$installed" -ge 2 ] || exit 0

# Count existing teammates of this team, and how many share the incoming harness.
records_dir="$home_dir/.agents/.history/teams/agents"
[ -d "$records_dir" ] || exit 0
count=0
same=0
for meta in "$records_dir"/*/meta.json; do
  [ -f "$meta" ] || continue
  t=$(_json_field "$(cat "$meta" 2>/dev/null)" "task_name") || continue
  [ "$t" = "$team" ] || continue
  count=$((count + 1))
  a=$(_json_field "$(cat "$meta" 2>/dev/null)" "agent_type") || continue
  [ "$a" = "$harness" ] && same=$((same + 1))
done

# Fires only when this add makes teammate #3+ AND every existing teammate
# already runs the incoming harness (pure monoculture; a mixed roster passes).
if [ "$count" -ge 2 ] && [ "$same" = "$count" ]; then
  n=$((count + 1))
  {
    echo "Blocked: this add makes team '$team' ${n}/${n} $harness while other"
    echo "harnesses are installed on this machine (see: agents view). Mix the"
    echo "roster — spread tracks across installed harnesses — or state the"
    echo "capability reason in the brief: 'single-harness: <constraint>'."
  } >&2
  exit 2
fi

exit 0
