#!/usr/bin/env bash
# Tests for 08-stop-judge.py — run: bash 08-stop-judge_test.sh
# Executes the real hook against transcripts in Claude Code's record shapes, with
# stub `claude`, `secrets`, and `browser` executables first on PATH. The stubs
# stand in for the model and the credential store only, so no test reaches the
# network or a real model. Each case runs under its own HOME and reads the rows
# the hook wrote to its real SQLite database. The hook judges in a detached
# child, so each case times the foreground, then waits for the child's row.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../08-stop-judge.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
BIN="$TMP/bin"; mkdir -p "$BIN"

cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf 'token=%s thinking=%s cwd=%s\n' "${CLAUDE_CODE_OAUTH_TOKEN:-}" "${MAX_THINKING_TOKENS:-}" "$PWD" >> "$STUB_LOG"
printf 'env ep=%s child=%s acctkey=%s\n' "${CLAUDE_CODE_ENTRYPOINT:-}" "${STOP_JUDGE_CHILD:-}" "${STOP_JUDGE_ACCOUNT_KEY:-}" >> "$STUB_LOG"
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@" > "$STUB_LOG.argv"
cat > "$STUB_LOG.stdin"
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
case "${STUB_MODE:-items}" in
  sleep) sleep 30; exit 0 ;;
  garbage) result='Nothing to extract here, sorry.' ;;
  *) result="$STUB_ITEMS" ;;
esac
python3 -c 'import json,sys; print(json.dumps({"type":"result","is_error":False,"result":sys.argv[1],"usage":{"input_tokens":1500,"cache_read_input_tokens":200,"output_tokens":120}}))' "$result"
STUB

cat > "$BIN/secrets" <<'STUB'
#!/usr/bin/env bash
printf 'secrets %s\n' "$*" >> "$STUB_LOG"
if [ "$1" = list ]; then printf '%s\n' "$STUB_BUNDLES"; exit 0; fi
if [ "$1" = exec ] && [ "$2" = auth ] && [ "$3" = -- ]; then
  shift 3
  export CLAUDE_CODE_OAUTH_TOKEN_ALPHA_AT_EXAMPLE_DOT_COM=tok-alpha
  export CLAUDE_CODE_OAUTH_TOKEN_OWNER_AT_EXAMPLE_DOT_ORG=tok-owner
  exec "$@"
fi
exit 1
STUB

cat > "$BIN/browser" <<'STUB'
#!/usr/bin/env bash
printf '[{"name":"agent-profile"}]\n'
STUB
chmod +x "$BIN/claude" "$BIN/secrets" "$BIN/browser"

FILE_AUTH='[{"name":"auth","backend":"file"},{"name":"stripe.com","backend":"file"},{"name":"__claude__","backend":"file"}]'
NO_AUTH='[{"name":"stripe.com","backend":"keychain"}]'
MARK='ZEBRA-QUOKKA-7731'   # appears in request, final message, and quotes; must never reach the DB

LIB='
import json
def u(text): print(json.dumps({"type":"user","message":{"role":"user","content":text}}))
def meta(text): print(json.dumps({"type":"user","isMeta":True,"message":{"role":"user","content":text}}))
def a_text(t): print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":t}]}}))
def a_tool(i,name="Bash",cmd=""): print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":i,"name":name,"input":{"command":cmd}}]}}))
def res(i): print(json.dumps({"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":i,"content":"ok"}]}}))
'
WORKED="$LIB
u('please land the fix ZEBRA-QUOKKA-7731')
a_tool('t1','Read'); res('t1'); a_tool('t2','Bash','gh pr view 12'); res('t2')"
IDLE="$LIB
u('what is the status of ZEBRA-QUOKKA-7731?')
meta('<system-reminder>not the owner</system-reminder>')
a_tool('t1','TodoWrite'); res('t1')"

item() {  # item <kind> <actor> [credential]
  printf '{"items":[{"kind":"%s","actor":"%s","quote":"%s said this","object":"#12","host":"","credential":"%s"}]}' \
    "$1" "$2" "$MARK" "${3:-}"
}

# run_hook <case> <entrypoint> <transcript-python> <payload-extra-json> [VAR=value ...]
# Sets RC and FG_MS (foreground wall time). Unless NOWAIT=1, then waits up to 10s
# for the detached child's row and sets SETTLE_MS (start to row). HOME is $TMP/<case>.
run_hook() {
  local name="$1" ep="$2" gen="$3" extra="$4"; shift 4
  local home="$TMP/$name" t="$TMP/$name.jsonl" start end
  mkdir -p "$home/cfg"
  printf '{"oauthAccount":{"emailAddress":"owner@example.org"}}' > "$home/cfg/.claude.json"
  python3 -c "$gen" > "$t"
  python3 -c '
import json,sys
p={"session_id":"sess-1","hook_event_name":"Stop","stop_hook_active":False,"transcript_path":sys.argv[1],
   "last_assistant_message":"Done. Merge PR #12 when ready - ZEBRA-QUOKKA-7731."}
p.update(json.loads(sys.argv[2])); print(json.dumps(p))' "$t" "$extra" > "$TMP/$name.payload"
  start=$(python3 -c 'import time;print(int(time.time()*1000))')
  env -u CLAUDE_CODE_EXECPATH -u CLAUDE_CODE_OAUTH_TOKEN HOME="$home" PATH="$BIN:$PATH" \
    CLAUDE_CODE_ENTRYPOINT="$ep" CLAUDE_CONFIG_DIR="$home/cfg" STUB_LOG="$home/stub.log" \
    STUB_BUNDLES="$FILE_AUTH" STUB_ITEMS='{"items":[]}' "$@" \
    bash -c 'if [ -n "${CLAUDE_PARENT:-}" ]; then exec -a "$CLAUDE_PARENT" bash -c "python3 \"\$0\" < \"\$1\"" "$0" "$1"; else exec python3 "$0" < "$1"; fi' \
      "${HOOK_OVERRIDE:-$HOOK}" "$TMP/$name.payload" > "$TMP/$name.out" 2>&1
  RC=$?
  end=$(python3 -c 'import time;print(int(time.time()*1000))')
  FG_MS=$((end - start))
  [ "${NOWAIT:-0}" = 1 ] && return
  python3 - "$home/.agents/.history/hooks/system.stop-judge/state.db" <<'PY'
import os, sqlite3, sys, time
deadline = time.time() + 10
while time.time() < deadline:
    if os.path.exists(sys.argv[1]):
        try:
            if sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM judgments").fetchone()[0]:
                break
        except sqlite3.Error:
            pass
    time.sleep(0.05)
PY
  end=$(python3 -c 'import time;print(int(time.time()*1000))')
  SETTLE_MS=$((end - start))
}

pending() {  # pending <case> -> handoff files still on disk
  ls "$TMP/$1/.agents/.cache/state/hooks/system.stop-judge/pending" 2>/dev/null | tr '\n' ' '
}

row() {  # row <case> -> "would_block|reason|outcome|item_kinds|background_live" of the latest row
  python3 - "$TMP/$1/.agents/.history/hooks/system.stop-judge/state.db" <<'PY'
import os, sqlite3, sys
if not os.path.exists(sys.argv[1]):
    print("no-db"); sys.exit()
r = sqlite3.connect(sys.argv[1]).execute(
    "SELECT would_block, reason, outcome, item_kinds, background_live FROM judgments ORDER BY id DESC LIMIT 1").fetchone()
print("|".join(str(v) for v in r) if r else "no-row")
PY
}

check() {  # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1: expected [$2] got [$3]"; fi
}
check_silent_exit0() {  # the hook never blocks and never writes to stdout/stderr
  check "$1 exit" 0 "$RC"
  check "$1 output" "" "$(cat "$TMP/$1.out")"
}

# Headless runs are machine prompts: skipped, no model call, no DB.
NOWAIT=1 run_hook headless sdk-cli "$WORKED" '{}' STUB_ITEMS="$(item merge_or_approve_pr owner)"
check_silent_exit0 headless
check headless "no-db" "$(row headless)"
check "headless no model call" "" "$(cat "$TMP/headless/stub.log" 2>/dev/null)"

# Continuing from a Stop block, or nothing said: skipped.
NOWAIT=1 run_hook continuing cli "$WORKED" '{"stop_hook_active":true}'
check continuing "no-db" "$(row continuing)"
NOWAIT=1 run_hook empty-final cli "$WORKED" '{"last_assistant_message":"   "}'
check empty-final "no-db" "$(row empty-final)"
check "skips leave no handoff" "" "$(pending headless)$(pending continuing)$(pending empty-final)"

# Detached: the foreground returns at once while the model call is still running,
# and the child's row lands when it finishes. The handoff file is gone after.
run_hook detached cli "$WORKED" '{}' STUB_SLEEP=5 STUB_ITEMS="$(item merge_or_approve_pr owner)"
check_silent_exit0 detached
check "detached foreground fast" yes "$([ "$FG_MS" -lt 500 ] && echo yes || echo "no(${FG_MS}ms)")"
check "detached row after the model call" yes "$([ "$SETTLE_MS" -ge 5000 ] && echo yes || echo "no(${SETTLE_MS}ms)")"
check detached "1|merge_or_approve_pr|ok|merge_or_approve_pr|0" "$(row detached)"
check "detached handoff removed" "" "$(pending detached)"

# No investigation tool since the owner's message (bookkeeping does not count).
run_hook zero-tools cli "$IDLE" '{}' STUB_ITEMS="$(item done_claim agent)"
check_silent_exit0 zero-tools
check zero-tools "1|zero-tools|ok|done_claim|0" "$(row zero-tools)"

# The owner is asked to merge a PR.
run_hook merge cli "$WORKED" '{}' STUB_ITEMS="$(item merge_or_approve_pr owner)"
check_silent_exit0 merge
check merge "1|merge_or_approve_pr|ok|merge_or_approve_pr|0" "$(row merge)"

# An announced step with nothing in flight would block ...
run_hook announced cli "$WORKED" '{"background_tasks":[],"session_crons":[]}' \
  STUB_ITEMS="$(item announced_not_taken agent)"
check announced "1|announced_not_taken|ok|announced_not_taken|0" "$(row announced)"
# ... but a live background task from the Stop payload will wake the agent.
run_hook announced-bg cli "$WORKED" \
  '{"background_tasks":[{"id":"b1","type":"shell","status":"running","description":"poll CI"}],"session_crons":[]}' \
  STUB_ITEMS="$(item announced_not_taken agent)"
check announced-bg "0|pass|ok|announced_not_taken|1" "$(row announced-bg)"
run_hook announced-cron cli "$WORKED" \
  '{"session_crons":[{"id":"c1","schedule":"*/10 * * * *","recurring":true,"prompt":"check"}]}' \
  STUB_ITEMS="$(item announced_not_taken agent)"
check announced-cron "0|pass|ok|announced_not_taken|1" "$(row announced-cron)"
# A step that belongs to CI or a release train is not the agent's to take.
run_hook announced-other cli "$WORKED" '{}' STUB_ITEMS="$(item announced_not_taken other)"
check announced-other "0|pass|ok|announced_not_taken|0" "$(row announced-other)"

# Owner decisions never block.
run_hook scope cli "$WORKED" '{}' STUB_ITEMS="$(item decide_scope owner)"
check scope "0|pass|ok|decide_scope|0" "$(row scope)"

# A credential ask blocks only when a bundle on this machine covers it.
run_hook cred-covered cli "$WORKED" '{}' STUB_ITEMS="$(item provide_credential owner 'Stripe secret key')"
check cred-covered "1|provide_credential|ok|provide_credential|0" "$(row cred-covered)"
run_hook cred-uncovered cli "$WORKED" '{}' STUB_ITEMS="$(item provide_credential owner 'VPN password')"
check cred-uncovered "0|pass|ok|provide_credential|0" "$(row cred-uncovered)"

# A blocker that needs a human's biometrics is excused; an unverified one is not.
run_hook blocker-touchid cli "$WORKED" '{}' STUB_ITEMS="$(item blocker_claim owner 'Touch ID')"
check blocker-touchid "0|pass|ok|blocker_claim|0" "$(row blocker-touchid)"
run_hook blocker cli "$WORKED" '{}' STUB_ITEMS="$(item blocker_claim owner)"
check blocker "1|blocker_claim|ok|blocker_claim|0" "$(row blocker)"

# A kind outside the rubric is stored as "other", never as model text.
run_hook odd-kind cli "$WORKED" '{}' STUB_ITEMS='{"items":[{"kind":"ZEBRA-QUOKKA-7731 free text","actor":"agent"}]}'
check odd-kind "0|pass|ok|other|0" "$(row odd-kind)"

# The model replied with no JSON object.
run_hook parse-fail cli "$WORKED" '{}' STUB_MODE=garbage
check_silent_exit0 parse-fail
check parse-fail "0|unjudged|parse-fail||0" "$(row parse-fail)"
# Zero tools is still judged when the model fails: it needs no items.
run_hook parse-fail-idle cli "$IDLE" '{}' STUB_MODE=garbage
check parse-fail-idle "1|zero-tools|parse-fail||0" "$(row parse-fail-idle)"

# A hung model call is killed (its whole process group) at the timeout.
run_hook timeout cli "$WORKED" '{}' STUB_MODE=sleep STOP_JUDGE_TIMEOUT_S=1
check_silent_exit0 timeout
check timeout "0|unjudged|timeout||0" "$(row timeout)"
check "timeout bounded" yes "$([ "$SETTLE_MS" -lt 5000 ] && echo yes || echo "no(${SETTLE_MS}ms)")"

# No token in the env and no file-backed auth bundle: no model call.
run_hook no-auth cli "$WORKED" '{}' STUB_BUNDLES="$NO_AUTH"
check_silent_exit0 no-auth
check no-auth "0|unjudged|no-auth||0" "$(row no-auth)"
check "no-auth no model call" "" "$(grep '^token=' "$TMP/no-auth/stub.log")"

# Auth: the session account's setup-token from the file-backed bundle, run from
# the empty cwd with thinking off, no session persistence, and no tools.
run_hook auth-bundle cli "$WORKED" '{}' STUB_ITEMS="$(item decide_scope owner)"
check "auth-bundle account token" "token=tok-owner thinking=0 cwd=$TMP/auth-bundle/.agents/.cache/state/hooks/system.stop-judge/cwd" \
  "$(grep '^token=' "$TMP/auth-bundle/stub.log")"
# argv pins the isolation flags and carries no message text and no key name: the
# snapshot goes on stdin, the preferred key name through the env (then unset).
check "auth-bundle argv" "ok" "$(python3 - "$TMP/auth-bundle/stub.log.argv" "$MARK" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
def pair(flag, value): return any(a[i] == flag and a[i + 1] == value for i in range(len(a) - 1))
bad = [n for n, ok in [
    ("setting-sources", pair("--setting-sources", "project")), ("tools", pair("--tools", "")),
    ("model", pair("--model", "claude-haiku-4-5")), ("no-persist", "--no-session-persistence" in a),
    ("json", pair("--output-format", "json")), ("no-marker", not any(sys.argv[2] in x for x in a)),
    ("no-snapshot", not any("SNAPSHOT" in x for x in a))] if not ok]
print(",".join(bad) or "ok")
PY
)"
check "auth-bundle prompt on stdin" "yes" "$(head -c 9 "$TMP/auth-bundle/stub.log.stdin" | grep -q 'SNAPSHOT:' \
  && grep -q "$MARK" "$TMP/auth-bundle/stub.log.stdin" && echo yes)"
check "auth-bundle key name not in any argv" "" "$(grep -o 'OWNER_AT_EXAMPLE[A-Z_]*' "$TMP/auth-bundle/stub.log" "$TMP/auth-bundle/stub.log.argv")"
# The nested claude is marked as a machine prompt and as this hook's child.
check "auth-bundle judge env" "env ep=sdk-cli child=1 acctkey=" "$(grep '^env ' "$TMP/auth-bundle/stub.log")"
# Unknown account: the first key.
run_hook auth-first cli "$WORKED" '{}' CLAUDE_CONFIG_DIR="$TMP/nowhere"
check "auth-first token" "token=tok-alpha" "$(grep -o '^token=[^ ]*' "$TMP/auth-first/stub.log")"
# A token already in the env is used directly; the secrets store is not touched for it.
run_hook auth-env cli "$WORKED" '{}' CLAUDE_CODE_OAUTH_TOKEN=tok-env
check "auth-env token" "token=tok-env" "$(grep -o '^token=[^ ]*' "$TMP/auth-env/stub.log")"
check "auth-env no exec" "" "$(grep 'secrets exec' "$TMP/auth-env/stub.log")"

# A credential matches a bundle only through the item's credential/object, on
# service aliases: generic labels (prod, share, personal, auth) never match.
BUNDLES_WIDE='[{"name":"auth","backend":"file"},{"name":"prod.db"},{"name":"share"},{"name":"personal"},{"name":"npmjs.com"},{"name":"stripe.com"}]'
for c in "production database password" "share the Slack invite" "personal preference" "authorize"; do
  n="cred-$(printf '%s' "$c" | tr -cs 'A-Za-z' '-')"
  run_hook "$n" cli "$WORKED" '{}' STUB_BUNDLES="$BUNDLES_WIDE" STUB_ITEMS="$(item provide_credential owner "$c")"
  check "$n" "0|pass|ok|provide_credential|0" "$(row "$n")"
done
run_hook cred-npm cli "$WORKED" '{}' STUB_BUNDLES="$BUNDLES_WIDE" STUB_ITEMS="$(item provide_credential owner NPM_TOKEN)"
check cred-npm "1|provide_credential|ok|provide_credential|0" "$(row cred-npm)"
run_hook cred-quote-only cli "$WORKED" '{}' STUB_BUNDLES="$BUNDLES_WIDE" \
  STUB_ITEMS='{"items":[{"kind":"provide_credential","actor":"owner","quote":"paste the Stripe key here","object":"","credential":""}]}'
check cred-quote-only "0|pass|ok|provide_credential|0" "$(row cred-quote-only)"

# The judge's own nested run, or anything else carrying the child sentinel, is ignored.
NOWAIT=1 run_hook sentinel cli "$WORKED" '{}' STOP_JUDGE_CHILD=1 STUB_ITEMS="$(item merge_or_approve_pr owner)"
check_silent_exit0 sentinel
check "sentinel no handoff dir" "no" "$([ -d "$TMP/sentinel/.agents/.cache/state/hooks/system.stop-judge/pending" ] && echo yes || echo no)"
check sentinel "no-db" "$(row sentinel)"

# --judge only consumes files from pending/.
mkdir -p "$TMP/outside"; cp "$TMP/merge.payload" "$TMP/outside/stop-x.json"
HOME="$TMP/outside" python3 "$HOOK" --judge "$TMP/outside/stop-x.json"; RC=$?
check "judge outside pending exit" 0 "$RC"
check "judge outside pending untouched" yes "$([ -f "$TMP/outside/stop-x.json" ] && echo yes)"
check "judge outside pending no db" "no-db" "$(row outside)"

# An unclaimed handoff older than 5 minutes is swept; a fresh one is left alone.
P="$TMP/sweep/.agents/.cache/state/hooks/system.stop-judge/pending"; mkdir -p "$P"
echo '{}' > "$P/stop-old.json"; echo '{}' > "$P/stop-fresh.json"
python3 -c 'import os,sys,time; t=time.time()-600; os.utime(sys.argv[1],(t,t))' "$P/stop-old.json"
run_hook sweep cli "$WORKED" '{}'
check "sweep stale handoff" "stop-fresh.json " "$(pending sweep)"
rm -f "$P/stop-fresh.json"

# A handoff that cannot be written is removed, not left holding a partial payload.
mkdir -p "$TMP/dumpfail"
( ulimit -f 0; env -u CLAUDE_CODE_EXECPATH -u CLAUDE_CODE_OAUTH_TOKEN HOME="$TMP/dumpfail" PATH="$BIN:$PATH" \
    CLAUDE_CODE_ENTRYPOINT=cli STUB_LOG="$TMP/dumpfail/stub.log" python3 "$HOOK" < "$TMP/merge.payload" ) \
  > "$TMP/dumpfail.out" 2>&1; RC=$?
check_silent_exit0 dumpfail
check "dumpfail no handoff" "" "$(pending dumpfail)"

# At most two judges run at once; a third records skipped-busy without a model call.
S="$TMP/busy/.agents/.cache/state/hooks/system.stop-judge/slots"; mkdir -p "$S"
python3 -c '
import fcntl, sys, time
held = [open(p, "a") for p in sys.argv[2:]]
for h in held: fcntl.flock(h, fcntl.LOCK_EX)
open(sys.argv[1], "w").close(); time.sleep(30)' "$TMP/busy.held" "$S/slot-0.lock" "$S/slot-1.lock" &
holder=$!
for _ in $(seq 100); do [ -f "$TMP/busy.held" ] && break; sleep 0.05; done
run_hook busy cli "$WORKED" '{}' STUB_ITEMS="$(item merge_or_approve_pr owner)"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
check busy "0|unjudged|skipped-busy||0" "$(row busy)"
check "busy no model call" "" "$(grep '^token=' "$TMP/busy/stub.log" 2>/dev/null)"

# Every child consumed its handoff file.
left=""
for d in "$TMP"/*/.agents/.cache/state/hooks/system.stop-judge/pending; do
  [ -n "$(ls "$d")" ] && left="$left ${d#"$TMP"/}"
done
check "no handoff left in any case" "" "$left"

# Privacy: rows hold codes and a hash, never message, request, or quote text.
leaks=""
for db in "$TMP"/*/.agents/.history/hooks/system.stop-judge/state.db*; do
  if grep -aq "$MARK" "$db"; then leaks="$leaks ${db#"$TMP"/}"; fi
done
check "no message text in any db" "" "$leaks"
check "final message hash" \
  "$(python3 -c 'import hashlib;print(hashlib.sha256("Done. Merge PR #12 when ready - ZEBRA-QUOKKA-7731.".encode()).hexdigest())')" \
  "$(python3 -c 'import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute("SELECT final_sha256 FROM judgments").fetchone()[0])' \
     "$TMP/merge/.agents/.history/hooks/system.stop-judge/state.db")"
check "manifest names only" "auth,stripe.com|agent-profile" \
  "$(python3 -c 'import json,sys;m=json.load(open(sys.argv[1]));print(",".join(m["bundles"])+"|"+",".join(m["profiles"]))' \
     "$TMP/merge/.agents/.cache/state/hooks/system.stop-judge/manifest.json")"

# Installed layout: hook copied into <version>/home/.claude/hooks/, its claude only at
# <version>/node_modules/.bin/claude, no CLAUDE_CODE_EXECPATH, no claude on PATH. This is
# what a live hook sees; before claude_binary() it recorded error/no-claude.
VER="$TMP/versions/claude/9.9.9"; mkdir -p "$VER/home/.claude/hooks" "$VER/node_modules/.bin"
cp "$HOOK" "$VER/home/.claude/hooks/08-stop-judge.py"
cp "$HERE/../../lib/credential_catalog.py" "$VER/home/.claude/hooks/credential_catalog.py"
cp "$BIN/claude" "$VER/node_modules/.bin/claude"
NOCLAUDE="$TMP/noclaude"; mkdir -p "$NOCLAUDE"; ln -sf "$BIN/secrets" "$NOCLAUDE/secrets"; ln -sf "$BIN/browser" "$NOCLAUDE/browser"
HOOK_OVERRIDE="$VER/home/.claude/hooks/08-stop-judge.py" \
  run_hook installed-layout cli "$WORKED" '{}' STUB_ITEMS="$(item merge_or_approve_pr owner)" PATH="$NOCLAUDE:/usr/bin:/bin"
check installed-layout "1|merge_or_approve_pr|ok|merge_or_approve_pr|0" "$(row installed-layout)"

# Per-account home: the hook lives at accounts/claude/<id>/.claude/hooks/, so neither
# CLAUDE_CODE_EXECPATH, the version-home layout, nor PATH finds claude. The claude that
# fired the hook is its ancestor process; the foreground finds it there and hands it to the
# detached child. Before that fallback, live rows on this layout read error/no-claude.
ACCT="$TMP/accounts/claude/acct-1/.claude/hooks"; mkdir -p "$ACCT" "$TMP/acctbin"
cp "$HOOK" "$ACCT/08-stop-judge.py"; cp "$HERE/../../lib/credential_catalog.py" "$ACCT/"
cp "$BIN/claude" "$TMP/acctbin/claude"
NOCLAUDE2="$TMP/noclaude2"; mkdir -p "$NOCLAUDE2"; ln -sf "$BIN/secrets" "$NOCLAUDE2/secrets"; ln -sf "$BIN/browser" "$NOCLAUDE2/browser"
# Run the hook under a parent whose argv[0] is the stub claude's absolute path.
HOOK_OVERRIDE="$ACCT/08-stop-judge.py" CLAUDE_PARENT="$TMP/acctbin/claude" \
  run_hook account-home cli "$WORKED" '{}' STUB_ITEMS="$(item merge_or_approve_pr owner)" PATH="$NOCLAUDE2:/usr/bin:/bin"
check account-home "1|merge_or_approve_pr|ok|merge_or_approve_pr|0" "$(row account-home)"

echo "08-stop-judge: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
