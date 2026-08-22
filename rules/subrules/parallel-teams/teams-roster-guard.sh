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

# --- portable JSON field extractor (jq -> python3) ---------------------------
_json_field() { # $1=json $2=snake.path $3=camel.path
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r "((.$2) // (.${3:-$2})) // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
import json, sys
paths = [p.split(".") for p in sys.argv[1:] if p]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for path in paths:
    cur = data
    ok = True
    for key in path:
        if isinstance(cur, dict) and key in cur:
            cur = cur[key]
        else:
            ok = False
            break
    if ok and isinstance(cur, str) and cur:
        print(cur)
        break
' "$2" "${3:-}" 2>/dev/null
  else
    return 1
  fi
}

cmd=$(_json_field "$input" "tool_input.command" "toolInput.command") || exit 0
[ -n "$cmd" ] || exit 0

# Only actual `agents teams add <team> <harness> ...` invocations at a command
# position (start / after ; & | && || or $( ) — not a grep pattern or prose.
case "$cmd" in
  *"agents teams add"*|*"ag teams add"*) : ;;
  *) exit 0 ;;
esac

# Stated reason clears the guard before any computation.
case "$cmd" in
  *single-harness:*|*single_harness:*) exit 0 ;;
esac

# Extract team + harness from the first `agents teams add` occurrence.
set -- $(printf '%s\n' "$cmd" | sed -nE 's/.*\b(agents|ag) teams add[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+).*/\2 \3/p' | head -1)
team="${1:-}"
harness="${2:-}"
[ -n "$team" ] && [ -n "$harness" ] || exit 0
# Flags in either slot mean an unusual invocation shape — stay out of the way.
case "$team$harness" in -*) exit 0 ;; esac

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
