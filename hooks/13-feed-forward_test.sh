#!/usr/bin/env bash
# Tests for 13-feed-forward.py — the event-driven feed->phone forwarder.
#
# Hermetic: owner profile + skill dir + state dir are pointed at a sandbox via
# env overrides, and `rush` is stubbed on PATH so nothing real sends. Safety
# properties under test: INERT unless owner.md opts in (forward_status: true);
# only a real `agents feed post` invocation forwards (not a grep/echo that
# mentions it); deduped per (session, text).

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/13-feed-forward.py"
REAL_OWNERPY="$(cd "$HERE/../skills/escalate" && pwd)/owner.py"

SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$3] got [$2]"; fail=1; fi; }

# Sandbox skill (owner.py) + state + a rush stub that records instead of sending.
SKILL="$SANDBOX/skill"; mkdir -p "$SKILL"; cp "$REAL_OWNERPY" "$SKILL/owner.py"
STATE="$SANDBOX/state"; LOG="$SANDBOX/sent.log"
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/rush" <<STUB
#!/usr/bin/env bash
case "\$1" in
  whoami) exit 0 ;;
  message) shift; echo "RUSH \$*" >> "$LOG"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$SANDBOX/bin/rush"
export PATH="$SANDBOX/bin:$PATH"
export ESCALATE_SKILL_DIR="$SKILL" FEED_FORWARD_STATE="$STATE"

# owner.md with host=local so the forward runs locally against the rush stub.
optout="$SANDBOX/optout.md"; optin="$SANDBOX/optin.md"
cat > "$optout" <<'MD'
---
name: Test
channels:
  - id: telegram
    transport: openclaw
    host: local
    target: "6078999250"
---
MD
cat > "$optin" <<'MD'
---
name: Test
forward_status: true
channels:
  - id: telegram
    transport: openclaw
    host: local
    target: "6078999250"
---
MD

fire() { # fire <owner.md> <session> <command>
  printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$2" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$3")" \
    | OWNER_PROFILE="$1" python3 "$HOOK"
  sleep 1   # let the backgrounded forward finish writing the log
}

# 1. opted OUT -> a real feed post does NOT forward.
: > "$LOG"; rm -rf "$STATE"
fire "$optout" s1 'agents feed post "shipped the thing"'
check "opt-out: no forward" "$(wc -l < "$LOG")" "0"

# 2. opted IN -> a real feed post forwards (via the rush stub).
: > "$LOG"; rm -rf "$STATE"
fire "$optin" s2 'agents feed post "shipped the thing, PR #149 needs review"'
check "opt-in: forwards once" "$(wc -l < "$LOG")" "1"
grep -q "shipped the thing" "$LOG" && echo "ok   - forwards the posted text" || { echo "FAIL - text not forwarded"; fail=1; }

# 3. a grep that merely MENTIONS 'agents feed post' -> must NOT forward.
: > "$LOG"; rm -rf "$STATE"
fire "$optin" s3 'grep -r "agents feed post" ~/.agents/hooks'
check "grep mentioning the phrase does not forward" "$(wc -l < "$LOG")" "0"

# 4. dedup: same (session,text) twice within cooldown -> forwards once.
: > "$LOG"; rm -rf "$STATE"
fire "$optin" s4 'agents feed post "done"'
fire "$optin" s4 'agents feed post "done"'
check "dedup: identical post forwards once" "$(wc -l < "$LOG")" "1"

# 5. non-Bash / non-feed-post -> no forward.
: > "$LOG"; rm -rf "$STATE"
fire "$optin" s5 'ls -la /tmp'
check "unrelated command does not forward" "$(wc -l < "$LOG")" "0"

# 6. a compound command that ends in a real feed post -> forwards.
: > "$LOG"; rm -rf "$STATE"
fire "$optin" s6 'git push && agents feed post "pushed and green"'
check "compound command with a real feed post forwards" "$(wc -l < "$LOG")" "1"

exit $fail
