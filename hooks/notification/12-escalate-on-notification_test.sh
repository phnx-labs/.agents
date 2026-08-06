#!/usr/bin/env bash
# Tests for 12-escalate-on-notification.sh — the opt-in escalation trigger.
#
# Hermetic: OWNER_PROFILE / ESCALATE_SKILL_DIR / ESCALATE_STATE_DIR are pointed at
# a sandbox, and escalate.sh is STUBBED to record its invocation instead of
# sending anything. The key safety property under test: the hook is INERT unless
# owner.md opts in (auto_escalate: true), and it dedups within a cooldown.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/12-escalate-on-notification.sh"
# owner.py lives with the skill; the stub skill dir needs it for the opt-in read.
# The test sits in hooks/notification/, so the repo-root skills/ dir is two levels up.
REAL_OWNERPY="$(cd "$HERE/../../skills/escalate" && pwd)/owner.py"

SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$3] got [$2]"; fail=1; fi; }

# Stub skill: a recording escalate.sh + the real owner.py (for the opt-in parse).
SKILL="$SANDBOX/skill"; mkdir -p "$SKILL"
cat > "$SKILL/escalate.sh" <<STUB
#!/usr/bin/env bash
echo "FIRED: \$*" >> "$SANDBOX/fired.log"
STUB
chmod +x "$SKILL/escalate.sh"
cp "$REAL_OWNERPY" "$SKILL/owner.py"

STATE="$SANDBOX/state"
export ESCALATE_SKILL_DIR="$SKILL" ESCALATE_STATE_DIR="$STATE"

owner_optout="$SANDBOX/optout.md"
cat > "$owner_optout" <<'MD'
---
name: Test
channels:
  - id: telegram
    transport: openclaw
    host: local
    target: "1234567890"
policy: { normal: [telegram] }
default_severity: normal
---
MD
owner_optin="$SANDBOX/optin.md"
cat > "$owner_optin" <<'MD'
---
name: Test
auto_escalate: true
channels:
  - id: telegram
    transport: openclaw
    host: local
    target: "1234567890"
policy:
  normal: [telegram]
default_severity: normal
---
MD

fire() { # fire <event> <owner.md> <session-id> ; returns hook exit code
  local rc
  printf '{"session_id":"%s","hook_event_name":"%s","message":"blocked on the release"}' "$3" "$1" \
    | OWNER_PROFILE="$2" bash "$HOOK"; rc=$?
  # The hook fires escalate.sh in the BACKGROUND (non-blocking in production), so
  # wait for the stub to land in fired.log before the caller inspects it — this
  # makes both the "did fire" and "did NOT fire" assertions deterministic.
  sleep 1
  echo "$rc"
}

# 1. Non-Notification event -> no-op, nothing fired.
: > "$SANDBOX/fired.log"
rc=$(fire "Stop" "$owner_optin" "s1"); check "non-Notification event exits 0" "$rc" "0"
check "non-Notification event does not fire" "$(wc -l < "$SANDBOX/fired.log")" "0"

# 2. Notification but owner.md did NOT opt in -> inert (the safe default).
: > "$SANDBOX/fired.log"; rm -rf "$STATE"
rc=$(fire "Notification" "$owner_optout" "s2"); check "opt-out owner exits 0" "$rc" "0"
check "opt-out owner does NOT escalate (safe default)" "$(wc -l < "$SANDBOX/fired.log")" "0"

# 3. Notification + owner opted in -> fires escalate.sh with the agent's message.
: > "$SANDBOX/fired.log"; rm -rf "$STATE"
rc=$(fire "Notification" "$owner_optin" "s3"); check "opt-in Notification exits 0" "$rc" "0"
if grep -q "FIRED: blocked on the release" "$SANDBOX/fired.log"; then echo "ok   - opt-in escalates with the agent's message"; else echo "FAIL - opt-in did not fire escalate.sh"; fail=1; fi

# 4. Dedup: a second Notification for the same session within cooldown -> no re-fire.
: > "$SANDBOX/fired.log"
rc=$(fire "Notification" "$owner_optin" "s3"); check "dedup second event exits 0" "$rc" "0"
check "dedup suppresses a second escalation in-window" "$(wc -l < "$SANDBOX/fired.log")" "0"

# 5. A different session still escalates (dedup is per-session).
: > "$SANDBOX/fired.log"
rc=$(fire "Notification" "$owner_optin" "s4"); check "new session exits 0" "$rc" "0"
if grep -q "FIRED:" "$SANDBOX/fired.log"; then echo "ok   - a different session still escalates"; else echo "FAIL - per-session dedup blocked a new session"; fail=1; fi

# 6. Missing owner.md -> no-op.
: > "$SANDBOX/fired.log"; rm -rf "$STATE"
rc=$(fire "Notification" "$SANDBOX/nope.md" "s5"); check "missing owner.md exits 0" "$rc" "0"
check "missing owner.md does not fire" "$(wc -l < "$SANDBOX/fired.log")" "0"

# 7. DEFAULT skill resolution, with ESCALATE_SKILL_DIR UNSET.
#
# Every case above forces ESCALATE_SKILL_DIR, so none of them exercises the
# default path -- which is how the skill dir defaulted to the USER layer while
# the skill actually ships in the SYSTEM layer, silently disabling this hook on
# every machine. This case pins the real resolution order by building a fake
# HOME with the skill in the SYSTEM layer ONLY, exactly as the fleet has it.
#
# Fails on the old default (`$HOME/.agents/skills/escalate`): the `-x` guard
# finds nothing there and the hook exits before escalating.
FAKEHOME="$SANDBOX/home"
SYS_SKILL="$FAKEHOME/.agents/.system/skills/escalate"
mkdir -p "$SYS_SKILL"
cp "$SKILL/escalate.sh" "$SYS_SKILL/escalate.sh"; chmod +x "$SYS_SKILL/escalate.sh"
cp "$REAL_OWNERPY" "$SYS_SKILL/owner.py"
[ -e "$FAKEHOME/.agents/skills/escalate" ] && { echo "FAIL - fixture leaked a user-layer skill"; fail=1; }

: > "$SANDBOX/fired.log"; rm -rf "$STATE"
rc=$(printf '{"session_id":"s6","hook_event_name":"Notification","message":"system-layer resolution"}' \
  | env -u ESCALATE_SKILL_DIR HOME="$FAKEHOME" OWNER_PROFILE="$owner_optin" ESCALATE_STATE_DIR="$STATE" \
    bash "$HOOK" >/dev/null 2>&1; echo $?)
check "system-layer skill resolves with no override (exit)" "$rc" "0"
# The stub writes to $SANDBOX/fired.log via an absolute path, so it records
# regardless of the fake HOME.
sleep 0.3
if grep -q "FIRED: system-layer resolution" "$SANDBOX/fired.log"; then
  echo "ok   - resolves the skill from the SYSTEM layer when no override is set"
else
  echo "FAIL - system-layer skill was not resolved (the layer bug this fixes)"; fail=1
fi

# 8. User layer still WINS over system when both exist (documented order).
USER_SKILL="$FAKEHOME/.agents/skills/escalate"
mkdir -p "$USER_SKILL"
cat > "$USER_SKILL/escalate.sh" <<STUB
#!/usr/bin/env bash
echo "USERLAYER: \$*" >> "$SANDBOX/fired.log"
STUB
chmod +x "$USER_SKILL/escalate.sh"
cp "$REAL_OWNERPY" "$USER_SKILL/owner.py"

: > "$SANDBOX/fired.log"; rm -rf "$STATE"
printf '{"session_id":"s7","hook_event_name":"Notification","message":"prefers user layer"}' \
  | env -u ESCALATE_SKILL_DIR HOME="$FAKEHOME" OWNER_PROFILE="$owner_optin" ESCALATE_STATE_DIR="$STATE" \
    bash "$HOOK" >/dev/null 2>&1
sleep 0.3
if grep -q "USERLAYER: prefers user layer" "$SANDBOX/fired.log"; then
  echo "ok   - user layer wins over system when both are present"
else
  echo "FAIL - resolution did not prefer the user layer"; fail=1
fi

exit $fail
