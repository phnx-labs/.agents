#!/usr/bin/env bash
# escalate.sh — reach the user out-of-band and climb an escalation ladder until
# you get their attention. The ONE move an agent makes when it is genuinely
# blocked and has exhausted self-serve: it does NOT stop in the chat window (a
# note in an empty room — the user is almost never watching it). Instead it
#
#   1. sends a MESSAGE on the loudest configured channel,
#   2. watches for a reply (where the channel supports it), and
#   3. climbs to the next rung — ending in a PHONE CALL, the best rung — if no
#      reply arrives within --wait.
#
# The ladder is universal; the RUNGS are per-user config. This skill ships in the
# system layer with NO personal data. Each user drops a small config naming their
# channels; the skill auto-detects which rungs are actually live and DEGRADES
# GRACEFULLY — if the phone rung is not set up, it uses the loudest available and
# REPORTS HONESTLY how far up the ladder it got. It never claims "escalated" when
# it only whispered.
#
# Config: ~/.agents/escalate.json  (see --check for what is / isn't wired)
#   {
#     "host":     "local",                    // where openclaw + the call cmd live ("local" = this box)
#     "telegram": { "account": "default", "target": "<your-telegram-chat-id>" },
#     "call":     { "cmd": "~/.agents/skills/<your-call-cmd>/call.sh" }
#   }
#
# Usage:
#   escalate.sh "<one-line blocker>" [--wait 15m] [--context <detail>] \
#               [--no-call] [--poll 30s] [--dry-run]
#   escalate.sh --check          # print which rungs are live on this box
#
# Returns immediately after sending + launching the watcher. Exit 0 on send;
# non-zero only if NO message rung is configured (it cannot reach the user).
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
# The owner profile (~/.agents/owner.md) is the single source of truth. owner.py
# parses its frontmatter stdlib-only (no PyYAML — not on every box) and emits the
# JSON this skill reads. $OWNER_PROFILE overrides the path (used by tests).
CFG="${OWNER_PROFILE:-$HOME/.agents/owner.md}"
OWNER_JSON="$(python3 "$SKILL_DIR/owner.py" "$CFG" 2>/dev/null || echo '{}')"

# --- owner-profile reader (dotted key over the derived JSON) ------------------
cfg() { # cfg <dotted.key>
  printf '%s' "$OWNER_JSON" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print(''); sys.exit(0)
cur=d
for k in '$1'.split('.'):
    if isinstance(cur,dict) and k in cur: cur=cur[k]
    else: print(''); sys.exit(0)
print(cur if not isinstance(cur,(dict,list)) else '')
" 2>/dev/null || echo ""
}

# expand a leading ~ to $HOME
expand() { case "$1" in "~/"*) echo "$HOME/${1#\~/}";; *) echo "$1";; esac; }

# run a command on the configured host ("local" or empty -> this box)
HOST="$(cfg host)"
on_host() { # on_host "<remote shell cmd>"
  if [ -z "$HOST" ] || [ "$HOST" = "local" ]; then bash -c "$1"; else ssh "$HOST" "$1"; fi
}

TG_ACCOUNT="$(cfg telegram.account)"; TG_ACCOUNT="${TG_ACCOUNT:-default}"
TG_TARGET="$(cfg telegram.target)"
CALL_CMD="$(expand "$(cfg call.cmd)")"
DB="~/.openclaw/state/openclaw.sqlite"
STATE_DIR="$HOME/.agents/.cache/state/escalate"

# --- rung detection ----------------------------------------------------------
# message rung (telegram via openclaw): openclaw reachable on host AND a target.
msg_ready() { [ -n "$TG_TARGET" ] && on_host "command -v openclaw >/dev/null 2>&1"; }
# reply-watch: the openclaw ingress DB exists on host.
watch_ready() { on_host "test -f $DB"; }
# call rung: a call cmd is configured, present, and (if it has a sibling
# config.json convention) that config exists — i.e. the transport is set up.
call_ready() {
  [ -n "$CALL_CMD" ] || return 1
  on_host "test -x '$CALL_CMD'" || return 1
  # muqsit-cli/twilio convention: creds live in config.json next to the cmd.
  local cdir; cdir="$(dirname "$CALL_CMD")"
  on_host "test -f '$cdir/config.json'"
}

# --- --check: readiness report ----------------------------------------------
if [ "${1:-}" = "--check" ]; then
  echo "escalate readiness  (config: $CFG$( [ -f "$CFG" ] || echo ' — MISSING'))"
  if msg_ready; then echo "  message (telegram via openclaw@${HOST:-local} -> ${TG_TARGET}): READY"
  else echo "  message: NOT READY — $( [ -z "$TG_TARGET" ] && echo 'no telegram.target in config' || echo "openclaw not found on ${HOST:-local}")"; fi
  if watch_ready; then echo "  reply-watch (openclaw ingress DB): READY"
  else echo "  reply-watch: NOT READY — ingress DB not found on ${HOST:-local}"; fi
  if call_ready; then echo "  call (${CALL_CMD}): READY"
  else echo "  call: NOT READY — $( [ -z "$CALL_CMD" ] && echo 'no call.cmd in config' || echo 'cmd or its config.json (creds) missing')"; fi
  if msg_ready && call_ready; then echo "  => ceiling: MESSAGE + WATCH + CALL (full ladder)"
  elif msg_ready; then echo "  => ceiling: MESSAGE$( watch_ready && echo ' + WATCH') (no phone rung — will re-ping, not call)"
  else echo "  => ceiling: NONE — cannot reach the user; add ~/.agents/escalate.json"; fi
  exit 0
fi

# --- arg parsing -------------------------------------------------------------
MSG=""; WAIT="15m"; POLL="30s"; CONTEXT=""; NO_CALL=0; DRYRUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wait)    WAIT="$2"; shift 2 ;;
    --poll)    POLL="$2"; shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --no-call) NO_CALL=1; shift ;;
    --dry-run) DRYRUN=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    -*)        echo "escalate: unknown flag $1" >&2; exit 2 ;;
    *)         if [ -z "$MSG" ]; then MSG="$1"; else MSG="$MSG $1"; fi; shift ;;
  esac
done
[ -z "$MSG" ] && { echo "escalate: a one-line blocker message is required" >&2; exit 2; }

# No message rung at all -> we genuinely cannot reach the user. Say so loudly;
# do not pretend to have escalated.
if ! msg_ready; then
  echo "escalate: NO message channel is configured on this box — cannot reach the user." >&2
  echo "  run 'escalate.sh --check' and add ~/.agents/escalate.json (host + telegram.target)." >&2
  exit 3
fi

CAN_CALL=0; { [ "$NO_CALL" -eq 0 ] && call_ready; } && CAN_CALL=1

to_secs() { local v="$1"; case "$v" in *h) echo $(( ${v%h}*3600 ));; *m) echo $(( ${v%m}*60 ));; *s) echo "${v%s}";; *) echo "$v";; esac; }
WAIT_S="$(to_secs "$WAIT")"; POLL_S="$(to_secs "$POLL")"

# --- compose the message (short — a pointer, not the payload) ----------------
BODY="Blocked, need you: ${MSG}"
[ -n "$CONTEXT" ] && BODY="${BODY}
${CONTEXT}"
if [ "$CAN_CALL" -eq 1 ]; then BODY="${BODY}
Reply here or I'll call in ${WAIT}."
else BODY="${BODY}
(reply when you can — no phone rung set up, I'll re-ping in ${WAIT})"; fi

if [ "$DRYRUN" -eq 1 ]; then
  echo "escalate DRY-RUN — no message sent, no call placed."
  echo "  message rung: telegram via openclaw@${HOST:-local} -> ${TG_TARGET} (account ${TG_ACCOUNT})"
  printf '  body: %s\n' "$(printf '%s' "$BODY" | tr '\n' ' ')"
  echo "  watch: $( watch_ready && echo "poll ingress every ${POLL_S}s for up to ${WAIT_S}s" || echo 'NOT available (no ingress DB)')"
  echo "  ceiling: $( [ "$CAN_CALL" -eq 1 ] && echo "CALL via ${CALL_CMD} if no reply" || echo 'MESSAGE-only (no phone rung) — will re-ping, not call')"
  exit 0
fi

# --- baseline on the DB host's clock (python3, not `date +%N` — macOS-safe) ---
if watch_ready; then T_MS="$(on_host "python3 -c 'import time;print(int(time.time()*1000))'")"; else T_MS=""; fi

# --- send the message (base64 through the shell so the body can't break quoting)
B64="$(printf '%s' "$BODY" | base64 | tr -d '\n')"
on_host "openclaw message send --channel telegram --account ${TG_ACCOUNT} --target ${TG_TARGET} --message \"\$(printf %s '$B64' | base64 -d)\"" >/dev/null

# --- launch the bounded watcher, detached ------------------------------------
mkdir -p "$STATE_DIR"; LOG="${STATE_DIR}/$(date +%s)-$$.log"
HOSTPFX=""; { [ -n "$HOST" ] && [ "$HOST" != "local" ]; } && HOSTPFX="ssh $HOST "
nohup bash -c '
  set -uo pipefail
  RUN="'"$HOSTPFX"'"; DB="'"$DB"'"; TGT="'"$TG_TARGET"'"; ACC="'"$TG_ACCOUNT"'"; T_MS="'"$T_MS"'"
  WAIT_S='"$WAIT_S"'; POLL_S='"$POLL_S"'; CAN_CALL='"$CAN_CALL"'
  CALL_CMD="'"$CALL_CMD"'"; MSG="'"$MSG"'"; WATCHABLE='"$( watch_ready && echo 1 || echo 0 )"'
  start_s=$(date +%s)
  replied() {
    [ "$WATCHABLE" = 1 ] || return 1
    local n; n="$(${RUN}sqlite3 $DB "SELECT COUNT(*) FROM channel_ingress_events WHERE channel_id='"'"'telegram'"'"' AND lane_key='"'"'telegram:$TGT'"'"' AND received_at > $T_MS" 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ]
  }
  while :; do
    sleep "$POLL_S"
    if replied; then echo "$(date -u +%FT%TZ) reply detected — standing down" >>"'"$LOG"'"; exit 0; fi
    [ $(( $(date +%s) - start_s )) -ge "$WAIT_S" ] && break
  done
  if [ "$CAN_CALL" = 1 ]; then
    echo "$(date -u +%FT%TZ) no reply — placing call" >>"'"$LOG"'"
    ${RUN}bash "$CALL_CMD" "This is an agent. $MSG. Check Telegram for details." >>"'"$LOG"'" 2>&1 \
      || ${RUN}openclaw message send --channel telegram --account "$ACC" --target "$TGT" --message "Could not reach you by call. Still blocked: $MSG" >>"'"$LOG"'" 2>&1
  else
    echo "$(date -u +%FT%TZ) no reply, no phone rung — re-pinging (loudest available)" >>"'"$LOG"'"
    ${RUN}openclaw message send --channel telegram --account "$ACC" --target "$TGT" --message "STILL BLOCKED (no phone escalation configured): $MSG" >>"'"$LOG"'" 2>&1 || true
  fi
' >/dev/null 2>&1 &
disown $! 2>/dev/null || true

if [ "$CAN_CALL" -eq 1 ]; then CEIL="will call in ${WAIT} if no reply"
else CEIL="NO phone rung configured — will re-ping in ${WAIT} (this is as loud as I can get)"; fi
echo "escalate: message sent to the user via telegram; watcher up (${CEIL}; log ${LOG}). Keep working every other thread."
exit 0
