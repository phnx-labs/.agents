#!/usr/bin/env bash
# Tests for the open-PR abandonment gate in 00-agent-verify-work-complete.sh.
# The gate must block a Stop when the session created a PR that is still OPEN
# and the final message has no explicit handoff — and allow everything else.
#
# Fixtures use the REAL Claude Code transcript shape: tool_use blocks (with
# the command) paired to tool_result blocks (with the PR URL) by tool_use_id.
# gh is stubbed via a PATH shim so no network is touched; the stub reports
# $FAKE_GH_STATE for most PRs, but pull/99 is always OPEN (someone else's).

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/00-agent-verify-work-complete.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# --- gh stub ---------------------------------------------------------------
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal gh stub: `gh pr view <url> --json state --jq .state`
case "$*" in
  *pull/99*) echo "OPEN" ;;
  *)         echo "${FAKE_GH_STATE:-OPEN}" ;;
esac
STUB
chmod +x "$SANDBOX/bin/gh"
export PATH="$SANDBOX/bin:$PATH"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected exit [$3] got [$2]"; fail=1; fi; }

# Transcript lines in the real harness shape. $1 selects the tool activity:
#   create      — session runs gh pr create; result carries pull/42
#   review      — session only views someone else's pull/42
#   create+view — session creates pull/42 AND views someone else's pull/99
mk_transcript() {
  local t="$SANDBOX/transcript-$RANDOM.jsonl"
  {
    echo '{"type":"user","message":{"role":"user","content":"Please implement the widget feature and open a PR for it"}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working on it"}]}}'
    case "$1" in
      create|create+view)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_create1","name":"Bash","input":{"command":"cd /repo && gh pr create --title widget"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_create1","content":[{"type":"text","text":"https://github.com/acme/widgets/pull/42\n"}]}]}}'
        ;;
    esac
    case "$1" in
      review)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_view1","name":"Bash","input":{"command":"gh pr view https://github.com/acme/widgets/pull/42 --json state"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_view1","content":[{"type":"text","text":"reviewing https://github.com/acme/widgets/pull/42 for someone else"}]}]}}'
        ;;
      create+view)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_view2","name":"Bash","input":{"command":"gh pr view https://github.com/acme/widgets/pull/99 --json state"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_view2","content":[{"type":"text","text":"https://github.com/acme/widgets/pull/99 is OPEN, reviewing it"}]}]}}'
        ;;
    esac
    case "$1" in
      swarm)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_team1","name":"Bash","input":{"command":"agents teams start factory-remote --watch"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_team1","content":[{"type":"text","text":"team started"}]}]}}'
        ;;
    esac
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 2"}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 3"}]}}'
  } > "$t"
  echo "$t"
}

run_hook() {   # $1 transcript, $2 last message, $3 stop_hook_active
  python3 - "$1" "$2" "$3" <<'PY' | bash "$HOOK" >/dev/null 2>"$SANDBOX/stderr"
import json, sys
print(json.dumps({
    "transcript_path": sys.argv[1],
    "last_assistant_message": sys.argv[2],
    "stop_hook_active": sys.argv[3] == "true",
}))
PY
  echo $?
}

# 1. Created PR, still OPEN, no handoff -> block (exit 2)
T=$(mk_transcript create)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "CI is green, waiting for the reviewer." false)
check "open PR without handoff blocks" "$rc" "2"
grep -q "STOP GATE" "$SANDBOX/stderr" && echo "ok   - block message names the gate" || { echo "FAIL - no gate message"; fail=1; }

# 2. Created PR, MERGED -> allow
rc=$(FAKE_GH_STATE=MERGED run_hook "$T" "Merged and cleaned up." false)
check "merged PR allows stop" "$rc" "0"

# 3. Created PR, OPEN, but explicit handoff in final message -> allow
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is handed off to the release watcher, which owns the PR from here." false)
check "open PR with explicit handoff allows stop" "$rc" "0"

# 4. Handoff words only as a substring of another word -> still blocks
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "The build handoffs are documented; waiting on review." false)
check "handoff-substring does not escape the gate" "$rc" "2"

# 4b. Open PR blocked on a genuine external blocker WITH a watcher -> allow
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is blocked on a GitHub Actions 503 outage failing CI — watcher: background gh pr checks --watch will merge on green when CI recovers." false)
check "external blocker + watcher allows stop" "$rc" "0"

# 4c. Open PR blocked on a pending user action (Touch ID / review) -> allow
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is blocked on your Touch ID to sign the release; awaiting your merge." false)
check "external blocker + awaited user action allows stop" "$rc" "0"

# 4d. Bare 'blocked on' with no next-step/watcher -> still blocks (no loophole)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "This is blocked on CI for now." false)
check "blocked-on without a next-step does not escape" "$rc" "2"

# 4e. Abandonment prose: 'blocked on ...' + 'your review is needed' -> still blocks.
#     Wanting a human review is not an external blocker the agent can't resolve.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "The PR is blocked on failing tests; your review is needed once they pass." false)
check "blocked-on + 'your review' still blocks (not an external blocker)" "$rc" "2"

# 4f. Abandonment prose: 'blocked on ...' + 'awaiting your approval' -> still blocks.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Blocked on the dependency bump — awaiting your approval." false)
check "blocked-on + 'awaiting your' still blocks" "$rc" "2"

# 4g. Abandonment prose: 'blocked on ...' + bare 'watching' -> still blocks
#     ('watching' alone does not imply a live gh pr checks --watch process).
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Blocked on flaky tests; I'm watching to see if they stabilize." false)
check "blocked-on + bare 'watching' still blocks" "$rc" "2"

# 5. stop_hook_active -> allow (no loops)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "still waiting" true)
check "stop_hook_active bypasses gate" "$rc" "0"

# 6. PR URL mentioned but session never ran pr create (review-only) -> allow
T2=$(mk_transcript review)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T2" "Review finished, feedback posted." false)
check "reviewing someone else's PR does not block" "$rc" "0"

# 7. Session created pull/42 (merged) AND viewed someone else's pull/99 (open)
#    -> allow: the viewed PR must not be attributed to this session
T3=$(mk_transcript create+view)
rc=$(FAKE_GH_STATE=MERGED run_hook "$T3" "My PR is merged; review of #99 posted." false)
check "mixed create+review only gates the created PR" "$rc" "0"

# 8. Done-claim gate: PR merged (abandonment gate passes) but the final message
#    claims done -> the self-audit gate must still fire. Exercises the nested
#    message.role/message.content extraction on the real transcript shape —
#    with the old top-level read the turn count was 0 and this never blocked.
rc=$(FAKE_GH_STATE=MERGED run_hook "$T" "All done. The widget feature is merged." false)
check "done-claim on real transcript shape blocks for self-audit" "$rc" "2"
grep -q "You claimed this work is done" "$SANDBOX/stderr" && echo "ok   - done-claim gate cites the original request" || { echo "FAIL - no done-claim gate message"; fail=1; }

# --- swarm integration gate -------------------------------------------------
# A session that ran an edit-mode swarm (`agents teams start`) may not stop on
# swarm-completion phrasing that the generic done-list doesn't catch.
TS=$(mk_transcript swarm)

# 9. Swarm ran + wrap-up phrasing ("done and merged") not in the generic list
#    -> the swarm gate must fire (generic done-gate would have exited 0).
rc=$(FAKE_GH_STATE=MERGED run_hook "$TS" "The factory work you asked for is done and merged. You can now text the fleet." false)
check "swarm 'done and merged' blocks for integration audit" "$rc" "2"
grep -q "STOP GATE (swarm)" "$SANDBOX/stderr" && echo "ok   - swarm gate names itself + the seam" || { echo "FAIL - no swarm gate message"; fail=1; }

# 10. Swarm ran + "landed end-to-end" wrap-up -> swarm gate fires.
rc=$(FAKE_GH_STATE=MERGED run_hook "$TS" "All three tracks landed. AGI Factory end-to-end status: shipped." false)
check "swarm 'all three tracks landed' blocks" "$rc" "2"

# 11. Swarm ran but the final message is NOT a completion claim -> allow.
rc=$(FAKE_GH_STATE=MERGED run_hook "$TS" "Track 2 is still running; I'm watching the digest teammate." false)
check "swarm session without a done-claim allows stop" "$rc" "0"

# 12. NO swarm in the transcript + swarm-only phrasing -> swarm gate must NOT
#     fire (the generic done-gate may still catch other phrasings, but "all
#     three tracks landed" is not in that list, so a non-swarm session allows).
rc=$(FAKE_GH_STATE=MERGED run_hook "$T" "All three tracks landed end-to-end." false)
check "non-swarm session does not trip the swarm gate" "$rc" "0"

# 13. Swarm ran + done-claim but stop_hook_active -> allow (no loops).
rc=$(FAKE_GH_STATE=MERGED run_hook "$TS" "The work is done and merged." true)
check "swarm gate respects stop_hook_active" "$rc" "0"

exit $fail
