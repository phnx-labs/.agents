#!/usr/bin/env bash
# Tests for 08-inject-repo-inflight.sh — the SessionStart in-flight injection.
# gh and agents are stubbed via PATH shims; no network, no real session state.
# The agents stub emits the real `agents sessions --active --json` row shape
# (activity/status/pidAlive/lastActivityMs/prLink/ticketId/topic).

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../08-inject-repo-inflight.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
check_contains() { if printf '%s' "$2" | grep -qF "$3"; then echo "ok   - $1"; else echo "FAIL - $1: output missing [$3]"; fail=1; fi; }
check_absent()   { if printf '%s' "$2" | grep -qF "$3"; then echo "FAIL - $1: output contains [$3]"; fail=1; else echo "ok   - $1"; fi; }
check_empty()    { if [ -z "$2" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected empty output, got [$2]"; fail=1; fi; }
# $3 must appear before $4 in the output (ranking order).
check_before()   {
  local pos_a pos_b
  pos_a=$(printf '%s' "$2" | grep -nF "$3" | head -1 | cut -d: -f1)
  pos_b=$(printf '%s' "$2" | grep -nF "$4" | head -1 | cut -d: -f1)
  if [ -n "$pos_a" ] && [ -n "$pos_b" ] && [ "$pos_a" -lt "$pos_b" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: expected [$3]($pos_a) before [$4]($pos_b)"; fail=1
  fi
}

run_hook() {   # $1 = cwd to report, $2 = session_id of the starting session
  printf '{"cwd": "%s", "session_id": "%s"}' "$1" "${2:-}" | bash "$HOOK" 2>/dev/null
}

# --- stubs -------------------------------------------------------------------
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf -- '- #12 fix the frobnicator (fix-frob)\n- #13 [draft] new dashboard (dash-v2)\n'
STUB
# JSON rows exercising every filter and rank path. In-project rows that are NOT
# `activity=="working"` (idle, waiting_input) or are parked (orphaned/abandoned/
# closed) or dead (pidAlive false) must be dropped. Two working rows in-project
# with different lastActivityMs prove ranking. A sibling repo whose path is a
# string prefix (agents vs agents-cli), an unrelated repo, and the starting
# session itself must all be excluded.
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *--json*--local*|*--local*--json*) : ;;
  *) echo "stub: expected --json --local, got: $*" >&2; exit 1 ;;
esac
cat <<EOF
[
  {"sessionId": "aaaa1111-0000", "kind": "claude", "cwd": "${FAKE_REPO}-cli", "status": "running", "activity": "working", "pidAlive": true, "lastActivityMs": 9999, "topic": "sibling repo (path-prefix collision)"},
  {"sessionId": "wrk11111-0000", "kind": "claude", "cwd": "${FAKE_REPO}", "status": "running", "activity": "working", "pidAlive": true, "lastActivityMs": 5000, "prLink": "https://github.com/o/r/pull/1948", "ticketId": "RUSH-2030", "topic": "older working agent in the main checkout"},
  {"sessionId": "wrk22222-0000", "kind": "codex", "cwd": "${FAKE_REPO}/.agents/worktrees/feat-x", "status": "running", "activity": "working", "pidAlive": true, "lastActivityMs": 8000, "topic": "newer working agent in a worktree"},
  {"sessionId": "idle3333-0000", "kind": "claude", "cwd": "${FAKE_REPO}", "status": "idle", "activity": "idle", "pidAlive": true, "lastActivityMs": 7000, "topic": "idle agent must be dropped"},
  {"sessionId": "wait4444-0000", "kind": "claude", "cwd": "${FAKE_REPO}", "status": "running", "activity": "waiting_input", "pidAlive": true, "lastActivityMs": 7500, "topic": "waiting on the user must be dropped"},
  {"sessionId": "orph5555-0000", "kind": "claude", "cwd": "${FAKE_REPO}", "status": "orphaned", "activity": "working", "pidAlive": true, "lastActivityMs": 7600, "topic": "orphaned but stale-working must be dropped"},
  {"sessionId": "dead6666-0000", "kind": "claude", "cwd": "${FAKE_REPO}", "status": "closed", "activity": "working", "pidAlive": false, "lastActivityMs": 7700, "topic": "dead process must be dropped"},
  {"sessionId": "elsew777-0000", "kind": "claude", "cwd": "/somewhere/else", "status": "running", "activity": "working", "pidAlive": true, "lastActivityMs": 9000, "topic": "unrelated repo"},
  {"sessionId": "self0000-0000", "kind": "claude", "cwd": "${FAKE_REPO}", "status": "running", "activity": "working", "pidAlive": true, "lastActivityMs": 9500, "topic": "the session being started"}
]
EOF
STUB
chmod +x "$SANDBOX/bin/gh" "$SANDBOX/bin/agents"
export PATH="$SANDBOX/bin:$PATH"

# --- 1. non-git cwd: silent -----------------------------------------------
mkdir -p "$SANDBOX/plain-dir"
out=$(run_hook "$SANDBOX/plain-dir")
check_empty "non-git cwd stays silent" "$out"

# --- 2. git repo with open PRs + working agents: injects the block -----------
REPO="$SANDBOX/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
# The hook resolves the project root via `--git-common-dir` (parent), which
# returns the physical path (/private/var/... on macOS, not the /var/... symlink
# the sandbox path carries). The stub's session cwds must use the same form.
REPO="$(cd "$(dirname "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)")" && pwd)"
export FAKE_REPO="$REPO"
out=$(run_hook "$REPO" "self0000-0000")
check_contains "header present"                 "$out" "In-flight in this repo"
check_contains "PR list injected"               "$out" "#12 fix the frobnicator"
check_contains "draft marker preserved"         "$out" "[draft] new dashboard"
check_contains "working agent in main listed"   "$out" "wrk11111"
check_contains "working agent in worktree listed" "$out" "wrk22222"
check_contains "PR number surfaced from prLink" "$out" "PR #1948"
check_contains "ticket id surfaced"             "$out" "RUSH-2030"
check_absent   "idle agent excluded"            "$out" "idle3333"
check_absent   "waiting_input agent excluded"   "$out" "wait4444"
check_absent   "orphaned agent excluded"        "$out" "orph5555"
check_absent   "dead-process agent excluded"    "$out" "dead6666"
check_absent   "sibling repo (path-prefix) excluded" "$out" "aaaa1111"
check_absent   "unrelated repo excluded"        "$out" "elsew777"
check_absent   "the starting session itself excluded" "$out" "self0000"
# Ranking: worktree agent (lastActivityMs 8000) outranks the main one (5000).
check_before   "ranked most-active first"       "$out" "wrk22222" "wrk11111"

# --- 2b. worktree cwd resolves to the same project ---------------------------
# A session started INSIDE a linked worktree must still see the main-checkout
# agent — the project anchor unifies them.
WT="$REPO/.agents/worktrees/feat-x"
git -C "$REPO" worktree add -q "$WT" -b feat-x >/dev/null 2>&1
out=$(run_hook "$WT" "self0000-0000")
check_contains "worktree cwd still sees main-checkout agent" "$out" "wrk11111"

# --- 3. cap + "N more" summary ----------------------------------------------
# Seven working agents in-project, cap is 5 → 5 rows + one "+2 more" line, and
# the summary hint names the most-active of the overflow.
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
rows=""
# lastActivityMs descending so ids map to rank: c7 (7000) is most active … c1 (1000) least.
for n in 1 2 3 4 5 6 7; do
  ms=$((n * 1000))
  rows="${rows}{\"sessionId\": \"cap0000${n}-0000\", \"kind\": \"claude\", \"cwd\": \"${FAKE_REPO}\", \"status\": \"running\", \"activity\": \"working\", \"pidAlive\": true, \"lastActivityMs\": ${ms}, \"topic\": \"worker number ${n}\"},"
done
printf '[%s]\n' "${rows%,}"
STUB
chmod +x "$SANDBOX/bin/agents"
rm -f "$SANDBOX/bin/gh"   # no PRs; isolate the sessions block
out=$(run_hook "$REPO")
check_contains "cap: most-active shown"    "$out" "cap00007"
check_contains "cap: 5th-active shown"     "$out" "cap00003"
check_absent   "cap: 6th-active hidden"    "$out" "cap00002"
check_absent   "cap: least-active hidden"  "$out" "cap00001"
check_contains "cap: overflow summarized"  "$out" "+ 2 more agents working on this project"
check_contains "cap: summary hints next"   "$out" "worker number 2"

# --- 4. gh absent, no active sessions: silent, exit 0 -------------------------
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
echo "[]"
STUB
chmod +x "$SANDBOX/bin/agents"
out=$(run_hook "$REPO"); rc=$?
[ "$rc" = "0" ] && echo "ok   - missing gh exits 0" || { echo "FAIL - missing gh rc=$rc"; fail=1; }
check_empty "missing gh with no sessions stays silent" "$out"

# --- 5. malformed session JSON: fail-open, silent ----------------------------
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
echo "not json {{{"
STUB
chmod +x "$SANDBOX/bin/agents"
out=$(run_hook "$REPO"); rc=$?
[ "$rc" = "0" ] && echo "ok   - malformed JSON exits 0" || { echo "FAIL - malformed JSON rc=$rc"; fail=1; }
check_empty "malformed session JSON stays silent" "$out"

exit $fail
