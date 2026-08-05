#!/usr/bin/env bash
# Tests for 04-session-identity.sh — the merged identity hook. Exercises all
# three jobs against each agent's documented SessionStart delivery shape:
#   1) session metadata write (former 04)
#   2) per-pid registry enrichment (former 08)
#   3) Claude-harness-gated stdout injection (former 07)
#
# The hook is run via `bash "$HOOK"` so its `$PPID` resolves to THIS test shell
# (matching how Claude invokes the executable directly), letting us assert the
# metadata file keyed by our own pid and pre-seed a launcher registry entry the
# hook's ancestor walk will find.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/04-session-identity.sh"

# Hermetic HOME: the hook resolves every path via ~, and its registry ancestor
# walk checks ~/.agents/.cache/terminals/by-pid/<pid>.json. A sandbox HOME with
# no pre-seeded ancestor entries makes the walk deterministic (falls through to
# the parent pid) regardless of any live agent registry above the test process,
# and guarantees the test never touches the real session state.
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX"
REG="$HOME/.agents/.cache/terminals/by-pid"
SESS="$HOME/.agents/.cache/state/sessions"
SELF=$$
REG_FILE="$REG/$SELF.json"
META_FILE="$SESS/$SELF.json"
mkdir -p "$REG" "$SESS"

run()    { bash "$HOOK"; }   # $HOME is exported, so the hook uses the sandbox
fail=0
seed()   { printf '%s' "$1" > "$REG_FILE"; }
regfld() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$REG_FILE" "$1" 2>/dev/null; }
metafld(){ python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$META_FILE" "$1" 2>/dev/null; }
check()  { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$3] got [$2]"; fail=1; fi; }

cleanup() { rm -f "$REG_FILE" "$META_FILE"; }

# --- Job 1: metadata write ------------------------------------------------
cleanup
echo '{"session_id":"sid-meta","cwd":"/work"}' | bash "$HOOK" >/dev/null
check "metadata file written"            "$([ -f "$META_FILE" ] && echo yes)" "yes"
check "metadata session_id recorded"     "$(metafld session_id)"              "sid-meta"
check "metadata cwd recorded"            "$(metafld cwd)"                     "/work"

# --- Job 2: registry enrichment (ported from 08 test) ---------------------
# T1: stdin session_id enriches the launcher entry; launcher fields WIN.
seed '{"pid":'"$SELF"',"agent":"codex","cwd":"/orig","tmuxPane":"%9"}'
echo '{"session_id":"sid-stdin","cwd":"/ignored"}' | bash "$HOOK" >/dev/null
check "stdin session_id recorded"         "$(regfld sessionId)" "sid-stdin"
check "launcher agent preserved on merge" "$(regfld agent)"     "codex"
check "launcher cwd preserved on merge"   "$(regfld cwd)"       "/orig"

# T2: Grok delivers the id only via env.
seed '{"pid":'"$SELF"',"agent":"grok"}'
GROK_SESSION_ID="sid-grok" bash "$HOOK" < /dev/null >/dev/null
check "grok env session id recorded"      "$(regfld sessionId)" "sid-grok"
check "grok agent preserved"              "$(regfld agent)"     "grok"

# T3: no id anywhere -> must NOT invent one.
seed '{"pid":'"$SELF"',"agent":"codex"}'
printf '' | bash "$HOOK" >/dev/null
check "empty stdin leaves no sessionId"   "$(regfld sessionId)" ""

# T4: malformed JSON -> exit 0, no sessionId.
seed '{"pid":'"$SELF"',"agent":"codex"}'
echo 'not json {{' | bash "$HOOK" >/dev/null
check "malformed json leaves no sessionId" "$(regfld sessionId)" ""

# T5: no prior entry — hook creates a fresh entry keyed by an ephemeral pid and
# infers the agent from the env source. Find it via before/after diff.
rm -f "$REG_FILE"
ls "$REG" 2>/dev/null | sort > "/tmp/reg-before.$$"
GROK_SESSION_ID="sid-g2" bash "$HOOK" < /dev/null >/dev/null
ls "$REG" 2>/dev/null | sort > "/tmp/reg-after.$$"
newf="$(comm -13 "/tmp/reg-before.$$" "/tmp/reg-after.$$" | head -1)"
rm -f "/tmp/reg-before.$$" "/tmp/reg-after.$$"
NEW="$REG/$newf"
check "no prior entry: grok inferred"     "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("agent",""))' "$NEW" 2>/dev/null)"     "grok"
check "no prior entry: id recorded"       "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("sessionId",""))' "$NEW" 2>/dev/null)" "sid-g2"
[ -n "$newf" ] && rm -f "$NEW"

# --- Job 3: Claude-harness-gated stdout injection -------------------------
# I1: CLAUDECODE set -> emit additionalContext carrying the session id.
cleanup
out="$(echo '{"session_id":"sid-inject","transcript_path":"/t.jsonl"}' | CLAUDECODE=1 bash "$HOOK")"
got_sid="$(printf '%s' "$out" | python3 -c 'import json,sys;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)"
check "claude: injects session id"  "$got_sid" "Your current session id is sid-inject. Session transcript: /t.jsonl"

# I2: CLAUDECODE unset -> no stdout (non-Claude agents must not see the JSON).
cleanup
out="$(echo '{"session_id":"sid-x","cwd":"/w"}' | env -u CLAUDECODE bash "$HOOK")"
check "non-claude: no stdout injection" "$out" ""

cleanup
[ "$fail" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
