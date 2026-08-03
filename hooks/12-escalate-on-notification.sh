#!/usr/bin/env bash
# Notification hook: when an agent raises a "needs the user" notification, reach
# the user OUT-OF-BAND per their owner profile (~/.agents/owner.md) instead of it
# only lighting a menu-bar dot the user never sees. This is the escalation
# TRIGGER — no `escalate` command for the agent to invoke; its existing
# need-you signal is what fires the ladder (message -> watch -> call).
#
# OPT-IN AND SAFE: does nothing unless owner.md sets `auto_escalate: true`. So it
# ships inert and can never auto-spam before the owner turns it on and
# wiring-tests it. Deduped per session with a cooldown so a burst of
# notifications escalates at most once per window. Fires escalate.sh in the
# background and returns immediately; fail-open on any error.
#
# stdin: the Notification event JSON (session_id, hook_event_name, message).
set -uo pipefail

input="$(cat)"

parsed="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("session_id","") or "")
    print(d.get("hook_event_name","") or "")
    print(" ".join(str(d.get("message","") or "").split()))
except Exception:
    print(""); print(""); print("")' 2>/dev/null || printf '\n\n\n')"

sid="$(printf '%s' "$parsed" | sed -n 1p)"
event="$(printf '%s' "$parsed" | sed -n 2p)"
msg="$(printf '%s' "$parsed" | sed -n 3p)"

# Only the Notification event, and only with a session id.
[ "$event" = "Notification" ] || exit 0
[ -n "$sid" ] || exit 0

# Paths are overridable for tests; default to the real fleet locations.
OWNER="${OWNER_PROFILE:-$HOME/.agents/owner.md}"
# Resolve the skill the way resources resolve everywhere else: user layer first,
# then system. Defaulting to the USER layer alone was a silent kill switch -- the
# escalate skill ships in the SYSTEM layer (.system/skills/escalate), so the
# `-x` guard below matched nothing on every box and this hook has never once run.
if [ -n "${ESCALATE_SKILL_DIR:-}" ]; then
  SKILL="$ESCALATE_SKILL_DIR"
elif [ -x "$HOME/.agents/skills/escalate/escalate.sh" ]; then
  SKILL="$HOME/.agents/skills/escalate"
else
  SKILL="$HOME/.agents/.system/skills/escalate"
fi
[ -f "$OWNER" ] || exit 0
[ -x "$SKILL/escalate.sh" ] || exit 0

# Opt-in gate: escalate ONLY if owner.md turned it on.
auto="$(python3 "$SKILL/owner.py" "$OWNER" 2>/dev/null \
  | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("auto_escalate", False))
except Exception: print(False)' 2>/dev/null || echo False)"
case "$auto" in True|true|1) ;; *) exit 0 ;; esac

# Dedup: at most one escalation per session per cooldown window.
dir="${ESCALATE_STATE_DIR:-$HOME/.agents/.cache/state/escalate-fired}"; mkdir -p "$dir" 2>/dev/null || exit 0
mark="$dir/$sid"; cooldown=600; now="$(date +%s)"
if [ -f "$mark" ]; then
  last="$(cat "$mark" 2>/dev/null || echo 0)"
  [ $(( now - last )) -lt "$cooldown" ] && exit 0
fi
printf '%s' "$now" > "$mark"

# Fire the ladder in the background per the owner's policy; return immediately.
[ -n "$msg" ] || msg="an agent needs you (see the session)"
nohup bash "$SKILL/escalate.sh" "$msg" >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
