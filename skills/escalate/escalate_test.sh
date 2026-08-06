#!/usr/bin/env bash
# Tests for the system escalate skill — the channel-agnostic ladder.
#
# Hermetic: the owner profile is pointed at a temp owner.md via $OWNER_PROFILE, and `openclaw`
# is stubbed on PATH so no real message is sent. The rung-detection, --check
# report, config-missing degradation, and dry-run planning are all exercised
# without touching a real channel. The live send->watch->call path is verified by
# a wiring test with the user, not here.

HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/escalate.sh"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT

fail=0
check()    { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$3] got [$2]"; fail=1; fi; }
contains() { if printf '%s' "$2" | grep -qF "$3"; then echo "ok   - $1"; else echo "FAIL - $1: missing [$3]"; fail=1; fi; }
absent()   { if printf '%s' "$2" | grep -qF "$3"; then echo "FAIL - $1: unexpected [$3]"; fail=1; else echo "ok   - $1"; fi; }

# --- stubs: openclaw present, host=local so on_host runs bash -c locally ------
mkdir -p "$SANDBOX/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/bin/openclaw"; chmod +x "$SANDBOX/bin/openclaw"
export PATH="$SANDBOX/bin:$PATH"

# --- 1. No profile -> cannot reach the user ----------------------------------
export OWNER_PROFILE="$SANDBOX/none.md"        # does not exist
out="$(bash "$SH" --check 2>&1)"; rc=$?
check "no-profile --check exits 0" "$rc" "0"
contains "no-profile ceiling is NONE" "$out" "ceiling: NONE"
out="$(bash "$SH" "blocked on x" 2>&1)"; rc=$?
check "no message rung -> exit 3 (cannot reach user)" "$rc" "3"
contains "no message rung says so" "$out" "cannot reach the user"

# --- 2. Profile with a message rung but NO call rung (graceful degradation) ---
cat > "$SANDBOX/msg-only.md" <<'MD'
---
name: Test
channels:
  - id: telegram
    transport: openclaw
    host: local
    account: default
    target: "1234567890"
    watch: true
policy:
  normal: [telegram]
default_severity: normal
---
Test owner.
MD
export OWNER_PROFILE="$SANDBOX/msg-only.md"
out="$(bash "$SH" --check 2>&1)"
contains "message rung READY" "$out" "message (telegram via openclaw@local -> 1234567890): READY"
contains "call rung NOT READY (no call.cmd)" "$out" "call: NOT READY"
contains "ceiling is message-only, no phone rung" "$out" "no phone rung"

# 2b. Missing message text -> exit 2 regardless of config.
out="$(bash "$SH" 2>&1)"; rc=$?
check "missing message exits 2" "$rc" "2"

# 2c. Dry-run reflects the message rung + a message-only ceiling (no call).
out="$(bash "$SH" "publish creds locked" --context "PR #145" --dry-run 2>&1)"; rc=$?
check "dry-run exits 0" "$rc" "0"
contains "dry-run announces nothing sent" "$out" "DRY-RUN"
contains "dry-run carries the blocker" "$out" "publish creds locked"
contains "dry-run carries the context" "$out" "PR #145"
contains "dry-run ceiling is message-only" "$out" "MESSAGE-only"
absent  "dry-run does not claim a call" "$out" "CALL via"

# --- 3. Config WITH a call rung present (cmd + sibling config.json) -----------
mkdir -p "$SANDBOX/mcli"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/mcli/call.sh"; chmod +x "$SANDBOX/mcli/call.sh"
echo '{}' > "$SANDBOX/mcli/config.json"
cat > "$SANDBOX/full.md" <<MD
---
name: Test
channels:
  - id: telegram
    transport: openclaw
    host: local
    account: default
    target: "1234567890"
    watch: true
  - id: call
    transport: twilio
    cmd: $SANDBOX/mcli/call.sh
    intrusive: true
policy:
  normal: [telegram, call@15m]
default_severity: normal
---
Test owner.
MD
export OWNER_PROFILE="$SANDBOX/full.md"
out="$(bash "$SH" --check 2>&1)"
contains "call rung READY when cmd + config.json present" "$out" "call ($SANDBOX/mcli/call.sh): READY"
# ceiling mentions CALL (full ladder) — watch may be absent (no local ingress DB),
# so accept either 'MESSAGE + WATCH + CALL' or a message+call ceiling.
contains "full-ladder ceiling mentions CALL" "$out" "CALL"

# 3b. Dry-run with a call rung -> ceiling promises the call.
out="$(bash "$SH" "creds locked" --dry-run 2>&1)"
contains "dry-run with call rung promises a call" "$out" "CALL via $SANDBOX/mcli/call.sh"

# 3c. --no-call suppresses the call rung even when it is READY.
out="$(bash "$SH" "creds locked" --no-call --dry-run 2>&1)"
contains "no-call forces a message-only ceiling" "$out" "MESSAGE-only"

# --- 4. Send path (openclaw stubbed): returns 0, issues the send, no block ----
LOGDIR="$SANDBOX/log"; mkdir -p "$LOGDIR"
cat > "$SANDBOX/bin/openclaw" <<STUB
#!/usr/bin/env bash
echo "openclaw \$*" >> "$LOGDIR/openclaw.calls"
exit 0
STUB
chmod +x "$SANDBOX/bin/openclaw"
export OWNER_PROFILE="$SANDBOX/msg-only.md"
start=$(date +%s)
out="$(bash "$SH" "creds locked" --no-call --wait 1s --poll 1s 2>&1)"; rc=$?
elapsed=$(( $(date +%s) - start ))
check "send path returns 0" "$rc" "0"
contains "send path issued the openclaw send" "$(cat "$LOGDIR/openclaw.calls" 2>/dev/null)" "message send"
contains "send path confirms watcher launch" "$out" "watcher up"
if [ "$elapsed" -le 3 ]; then echo "ok   - escalate returns immediately (does not block on the watcher)"; else echo "FAIL - blocked ${elapsed}s"; fail=1; fi
sleep 2   # let the 1s --no-call watcher finish so no process lingers

exit $fail
