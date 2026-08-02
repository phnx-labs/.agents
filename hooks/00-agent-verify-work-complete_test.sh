#!/usr/bin/env bash
# Tests for the open-PR abandonment and delivery-chain gates in
# 00-agent-verify-work-complete.sh.
#
# The gate must block a Stop when the session created a PR that is still OPEN
# and the final message has no explicit handoff — and must also block when a
# delivery ends without closing the Linear loop, docs/CHANGELOG, or release.
#
# Fixtures use the REAL Claude Code transcript shape: tool_use blocks (with
# the command) paired to tool_result blocks (with the PR URL) by tool_use_id.
# gh, git, and linear are stubbed via a PATH shim so no network is touched.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/00-agent-verify-work-complete.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# --- gh stub ---------------------------------------------------------------
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal gh stub. `gh pr view --json state --jq .state` is used by the open-PR
# gate and expects a bare state string; `gh pr view --json title,body,headRefName`
# is used by the delivery gate and expects JSON.
case "$*" in
  *pull/99*)                          echo "OPEN" ;;
  *title,body,headRefName*)           echo "${FAKE_GH_JSON:-}" ;;
  *--json*)                           echo "${FAKE_GH_STATE:-OPEN}" ;;
  *)                                  echo "${FAKE_GH_STATE:-OPEN}" ;;
esac
STUB
chmod +x "$SANDBOX/bin/gh"

# --- git stub --------------------------------------------------------------
# The hook runs git commands against the repo it infers from the transcript.
# Stub them so tests are hermetic and not affected by the worktree branch name.
cat > "$SANDBOX/bin/git" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --abbrev-ref HEAD") echo "${FAKE_GIT_BRANCH:-feature/no-ticket}" ;;
  "merge-base"*)                 echo "${FAKE_GIT_BASE:-abc123}" ;;
  "log"*)                        echo "${FAKE_GIT_LOG:-}" ;;
  "diff --name-only"*)           echo "${FAKE_GIT_FILES:-}" ;;
  "diff HEAD~5..HEAD -- package.json") echo "${FAKE_GIT_PKGDIFF:-}" ;;
  "describe --tags --abbrev=0")  echo "${FAKE_GIT_TAG:-}" ;;
  *)                             echo "" ;;
esac
STUB
chmod +x "$SANDBOX/bin/git"

# --- linear stub -----------------------------------------------------------
# Returns configurable state for any RUSH-XXXX ticket.
cat > "$SANDBOX/bin/linear" <<'STUB'
#!/usr/bin/env bash
ticket=$(echo "$*" | grep -oE 'RUSH-[0-9]+' | head -1)
state="${FAKE_LINEAR_STATE:-Done}"
title="Fake ticket"
printf '{"state":{"name":"%s"},"title":"%s"}\n' "$state" "$title"
STUB
chmod +x "$SANDBOX/bin/linear"

export PATH="$SANDBOX/bin:$PATH"

# Defaults so existing merged-PR tests pass the delivery gate.
export FAKE_GH_JSON='{"title":"Widget","body":"","headRefName":"feature/no-ticket"}'
export FAKE_GIT_BRANCH="feature/no-ticket"
export FAKE_GIT_BASE="abc123"
export FAKE_GIT_FILES=""
export FAKE_LINEAR_STATE="Done"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected exit [$3] got [$2]"; fail=1; fi; }

# Transcript lines in the real harness shape. $1 selects the tool activity:
#   create      — session runs gh pr create; result carries pull/42
#   review      — session only views someone else's pull/42
#   create+view — session creates pull/42 AND views someone else's pull/99
mk_transcript() {
  local t="$SANDBOX/transcript-$RANDOM.jsonl"
  {
    echo '{"type":"user","message":{"role":"user","content":"Please implement the widget and open a PR for it"}}'
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
      inherited)
        # No `gh pr create` this session — a PRIOR session opened pull/42; THIS
        # session drives it (merge/checks), so it is responsible for it.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_chk1","name":"Bash","input":{"command":"gh pr checks https://github.com/acme/widgets/pull/42 --watch"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_chk1","content":[{"type":"text","text":"all checks passing"}]}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_mrg1","name":"Bash","input":{"command":"gh pr merge https://github.com/acme/widgets/pull/42 --rebase"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_mrg1","content":[{"type":"text","text":"merge attempted"}]}]}}'
        ;;
      inherited-view)
        # A single incidental `gh pr view` of an unrelated OPEN PR (pull/99) —
        # no create, no merge/checks. Must NOT attribute the PR to this session.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_iv1","name":"Bash","input":{"command":"gh pr view https://github.com/acme/widgets/pull/99 --json state"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_iv1","content":[{"type":"text","text":"glanced at pull/99 for context"}]}]}}'
        ;;
      inherited-observer)
        # Reviewer / CI-watcher that only OBSERVES an inherited OPEN PR (checks +
        # review), never drives it to merge. Observer verbs are not ownership, so
        # the session is NOT responsible and stopping with the ball in the author's
        # court is correct. Locks the WORK-regex scope.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_obs1","name":"Bash","input":{"command":"gh pr checks https://github.com/acme/widgets/pull/42 --watch"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_obs1","content":[{"type":"text","text":"checks green; author will merge"}]}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_obs2","name":"Bash","input":{"command":"gh pr review https://github.com/acme/widgets/pull/42 --request-changes -b nit"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_obs2","content":[{"type":"text","text":"requested changes"}]}]}}'
        ;;
    esac
    case "$1" in
      swarm)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_team1","name":"Bash","input":{"command":"agents teams start factory-remote --watch"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_team1","content":[{"type":"text","text":"team started"}]}]}}'
        ;;
      grepteams)
        # Marker strings appear ONLY as a grep pattern being searched for — this
        # must NOT count as running a swarm (the false positive this test pins).
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_grep1","name":"Bash","input":{"command":"grep -cE \"agents teams start|agents teams create|teams add[^\\\"]*--mode edit\" /tmp/transcript.jsonl"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_grep1","content":[{"type":"text","text":"2"}]}]}}'
        ;;
      handback)
        # The session materialized a runnable script under /tmp via the Write
        # tool — the exact shape of the "No, you release it.." failure.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_wr1","name":"Write","input":{"file_path":"/tmp/release-1.20.82.sh","content":"#!/usr/bin/env bash\nset -euo pipefail\ngit -C /repo merge --ff-only origin/main\n"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_wr1","content":[{"type":"text","text":"File created at /tmp/release-1.20.82.sh"}]}]}}'
        ;;
      handback-shell)
        # Same failure, but the script is written via a shell redirect/heredoc
        # (cat > /tmp/x.sh) rather than the Write tool.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_sh1","name":"Bash","input":{"command":"cat > /tmp/deploy.sh <<EOF\n#!/usr/bin/env bash\nrush deploy\nEOF\nchmod +x /tmp/deploy.sh"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_sh1","content":[{"type":"text","text":"wrote /tmp/deploy.sh"}]}]}}'
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

# 8b. Regression: first_user_msg is extracted via `python3 -c "..."` inside $(...).
#     A backtick in that python string is re-parsed by bash as a nested command
#     substitution and throws "command substitution: syntax error" at runtime — the
#     gate's exit code stays correct, so ONLY a stderr check catches it. The prior
#     run (line above) exercised that path; assert it left no shell error behind.
if grep -qiE "syntax error|command substitution" "$SANDBOX/stderr"; then echo "FAIL - hook emits a shell syntax error (backtick inside the python3 -c block)"; fail=1; else echo "ok   - no shell syntax error from the first_user_msg substitution"; fi

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

# 13b. Marker strings appear ONLY inside a grep pattern (searching a transcript),
#      not as a real `agents teams` invocation -> swarm gate must NOT fire. This
#      is the false positive that fired on the session hardening this very hook.
TG=$(mk_transcript grepteams)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TG" "All three tracks landed end-to-end." false)
check "grep FOR the marker strings does not trip the swarm gate" "$rc" "0"
grep -q "STOP GATE (swarm)" "$SANDBOX/stderr" && { echo "FAIL - swarm gate false-fired on a grep"; fail=1; } || echo "ok   - no swarm gate on a search-only session"

# --- genuine-user-message extraction (skip harness noise) -------------------
# A session opened with `j <dir>` (a `!`-prefix bash-input) must NOT have that
# quoted as "the original request" — the done-claim gate must skip
# <bash-input>/<bash-stdout> turns and quote the first real prose ask instead.
NT="$SANDBOX/noise-transcript.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"<bash-input>j agents-cli</bash-input>"}}'
  echo '{"type":"user","message":{"role":"user","content":"<bash-stdout>/home/muqsit/src/agents-cli</bash-stdout><bash-stderr></bash-stderr>"}}'
  echo '{"type":"user","message":{"role":"user","content":"<system-reminder>The user named this session AGI Factory.</system-reminder>"}}'
  echo '{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}'
  echo '{"type":"user","message":{"role":"user","content":"Please refactor the auth module and add end-to-end tests for the login flow."}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 2"}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 3"}]}}'
} > "$NT"

# 14. Done-claim on a noise-led transcript -> blocks, and quotes the REAL ask.
rc=$(FAKE_GH_STATE=MERGED run_hook "$NT" "All done. The auth refactor is complete." false)
check "done-claim on noise-led transcript blocks" "$rc" "2"
grep -q "refactor the auth module" "$SANDBOX/stderr" && echo "ok   - gate quotes the real ask, not the jump command" || { echo "FAIL - gate did not quote the real ask"; fail=1; }
if grep -qE "bash-input|system-reminder|Request interrupted" "$SANDBOX/stderr"; then echo "FAIL - gate leaked harness noise"; fail=1; else echo "ok   - gate does not leak bash-input/system-reminder/interrupt noise"; fi

# --- inherited-PR gate (Fix A) ----------------------------------------------
# A session may INHERIT an open PR a prior session created, drive it
# (gh pr checks/merge), and then try to stop with it unmerged. That PR is never
# in this transcript's `pr create` result, so the create-only gate was blind;
# the worked-PR signal must now catch it.
TI=$(mk_transcript inherited)

# A1. Inherited PR still OPEN (session ran gh pr merge/checks, no create),
#     no handoff -> the gate must fire even though this session never created it.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TI" "CI is green and it is reviewed. Presenting the merge choice: 1) merge 2) hold." false)
check "inherited open PR (worked, not created) blocks" "$rc" "2"
grep -q "created OR worked" "$SANDBOX/stderr" && echo "ok   - inherited-PR gate names created-or-worked" || { echo "FAIL - inherited gate message not updated"; fail=1; }

# A2. Same inherited PR but MERGED -> allow (the gate checks live state, not
#     mere presence, so a session that actually merged it can stop).
rc=$(FAKE_GH_STATE=MERGED run_hook "$TI" "Merged it and cleaned up the branch." false)
check "inherited PR that is merged allows stop" "$rc" "0"

# A3. Inherited PR OPEN but explicit handoff -> the existing escape still applies.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TI" "PR #42 is handed off to the release watcher, which owns the PR from here." false)
check "inherited open PR with explicit handoff allows stop" "$rc" "0"

# A4. A single incidental `gh pr view` of an unrelated OPEN PR (no create, no
#     merge/checks) -> must NOT be attributed to this session -> allow.
TV=$(mk_transcript inherited-view)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TV" "Glanced at #99 for context; nothing owed here." false)
check "incidental single view of an unrelated PR does not block" "$rc" "0"

# A5. A reviewer/watcher that only OBSERVED an inherited OPEN PR (gh pr checks +
#     review, never merge/rebase) -> observer verbs are not ownership, so it must
#     NOT be attributed -> allow. Locks the WORK-regex scope to merge-driving verbs.
TOB=$(mk_transcript inherited-observer)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TOB" "Reviewed pull/42 and left change requests for the author." false)
check "inherited PR only observed (checks/review) allows stop" "$rc" "0"

# --- parking / offer-instead-of-do done-gate (Fix B) ------------------------
# A session that PARKS the obvious next step behind the user ('want me to…',
# 'on your go', 'say the word') instead of doing it must be challenged, even
# though those phrases are in neither the done-signal list nor the swarm list.
# Uses a plain transcript (no PR, no swarm) with >2 assistant turns.
TP=$(mk_transcript plain)

# B1. 'want me to … on your go' parking -> the self-audit gate must fire.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "Want me to build the current main into a .vsix and install it? I can do it on your go." false)
check "parking 'want me to … on your go' blocks for self-audit" "$rc" "2"
grep -q "You claimed this work is done" "$SANDBOX/stderr" && echo "ok   - parking routes through the self-audit GATE" || { echo "FAIL - parking did not reach the self-audit gate"; fail=1; }

# B2. A GENUINE clarifying question that offers alternatives -> must NOT fire
#     (the agent legitimately cannot pick between the options).
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "Which environment should I target for the deploy — dev or prod?" false)
check "genuine either/or intent question does not trip parking gate" "$rc" "0"

# B3. 'should I proceed' with no alternatives offered -> parking -> fire.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "Should I proceed with releasing the build now?" false)
check "parking 'should I proceed' (no choice offered) blocks" "$rc" "2"

# B4. A plain status report with none of the parking idioms -> must NOT fire.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "The refactor landed in commit abc123; tests were not run yet." false)
check "plain status report (no parking idiom) allows stop" "$rc" "0"

# B5. Parking phrasing but only 2 turns (short Q&A) -> must NOT fire (turn gate).
TSHORT="$SANDBOX/short.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"Can you look at the config and tell me if it is valid?"}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Looking"}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Want me to fix it? Say the word."}]}}'
} > "$TSHORT"
rc=$(FAKE_GH_STATE=OPEN run_hook "$TSHORT" "Want me to fix it? Say the word." false)
check "parking phrasing in a <=2-turn session does not block" "$rc" "0"

# --- delivery-chain close-the-loop gate (RUSH-2073) ---------------------------
# Fixtures for the new delivery gate. The gate must fire on done-claims and on
# PR merge/release finish-line stops, and must check Linear, docs/CHANGELOG,
# release, and related tickets.

FAKE_REPO="$SANDBOX/fakerepo"
mkdir -p "$FAKE_REPO/.git"

mk_delivery_transcript() {
  local first_msg="${1:-Please implement the widget and open a PR for it}"
  local repo_dir="${2:-$FAKE_REPO}"
  local t="$SANDBOX/delivery-$RANDOM.jsonl"
  {
    echo "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"$first_msg\"}}"
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working on it"}]}}'
    echo "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_create1\",\"name\":\"Bash\",\"input\":{\"command\":\"cd $repo_dir && gh pr create --title widget\"}}]}}"
    echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_create1","content":[{"type":"text","text":"https://github.com/acme/widgets/pull/42\n"}]}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 2"}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 3"}]}}'
  } > "$t"
  echo "$t"
}

# D1. Done-claim + open Linear ticket in branch name -> delivery gate blocks.
TD=$(mk_delivery_transcript "Please implement the widget")
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/RUSH-1234 FAKE_LINEAR_STATE=Todo run_hook "$TD" "All done. The widget is merged." false)
check "done-claim + open ticket in branch name blocks" "$rc" "2"
grep -q "STOP GATE (delivery)" "$SANDBOX/stderr" && echo "ok   - delivery gate names itself" || { echo "FAIL - delivery gate message missing"; fail=1; }
grep -q "RUSH-1234" "$SANDBOX/stderr" && echo "ok   - delivery gate cites the open ticket" || { echo "FAIL - delivery gate did not cite ticket"; fail=1; }

# D2. PR finish-line + ticket closed + evidence -> delivery gate allows stop.
#     This avoids generic done-claim wording so the older self-audit gate does
#     not intentionally fire after the delivery gate passes.
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/RUSH-1234 FAKE_LINEAR_STATE=Done run_hook "$TD" "Merged RUSH-1234. Evidence: tests passed." false)
check "finish-line + closed ticket + evidence allows delivery stop" "$rc" "0"

# D3. User-facing change + no docs/CHANGELOG -> blocks.
TD_UF=$(mk_delivery_transcript "Please add a new --flag command to the widget")
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/no-ticket FAKE_GIT_FILES=src/widget.js run_hook "$TD_UF" "Merged the new flag." false)
check "user-facing change without docs/CHANGELOG blocks" "$rc" "2"
grep -q "missing docs and CHANGELOG" "$SANDBOX/stderr" && echo "ok   - delivery gate flags missing docs and CHANGELOG" || { echo "FAIL - delivery gate did not flag docs/changelog"; fail=1; }

# D4. User-facing change + only CHANGELOG updated -> still blocks; docs and
#     CHANGELOG are separate requirements.
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/no-ticket FAKE_GIT_FILES=$'CHANGELOG.md\nsrc/widget.js' run_hook "$TD_UF" "Merged the new flag. Evidence: screenshot /tmp/flag.png." false)
check "user-facing change with only CHANGELOG still blocks" "$rc" "2"
grep -q "missing docs" "$SANDBOX/stderr" && echo "ok   - delivery gate requires docs separately" || { echo "FAIL - delivery gate did not require docs separately"; fail=1; }

# D4b. User-facing change + docs + CHANGELOG + evidence -> allows.
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/no-ticket FAKE_GIT_FILES=$'README.md\nCHANGELOG.md\nsrc/widget.js' run_hook "$TD_UF" "Merged the new flag. Evidence: screenshot /tmp/flag.png." false)
check "user-facing change with docs + CHANGELOG + evidence allows delivery stop" "$rc" "0"

# D5. Independently-shippable change + no release evidence -> blocks.
SHIP_REPO="$SANDBOX/shiprepo"
mkdir -p "$SHIP_REPO/.git"
echo '{"name":"widget","version":"1.0.0"}' > "$SHIP_REPO/package.json"
TD_SHIP=$(mk_delivery_transcript "Please release the widget extension" "$SHIP_REPO")
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/no-ticket FAKE_GIT_FILES=src/widget.js FAKE_GIT_TAG="" run_hook "$TD_SHIP" "Merged. The extension is ready to publish." false)
check "shippable change without release evidence blocks" "$rc" "2"
grep -q "release/live verification is incomplete" "$SANDBOX/stderr" && echo "ok   - delivery gate flags missing release/live verification" || { echo "FAIL - delivery gate did not flag release"; fail=1; }

# D6. Independently-shippable change + release + live version check -> allows.
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/no-ticket FAKE_GIT_FILES=$'README.md\nCHANGELOG.md\nsrc/widget.js' FAKE_GIT_TAG=v1.1.0 run_hook "$TD_SHIP" "Merged and released v1.1.0. Verified live: npm view widget version -> 1.1.0." false)
check "shippable change with release + live check allows delivery stop" "$rc" "0"

# D7. PR body links a related ticket that is still open -> blocks.
FAKE_GH_JSON_REL='{"title":"Widget fix","body":"Closes RUSH-1234. Relates to RUSH-5678.","headRefName":"feature/RUSH-1234"}'
TD_REL=$(mk_delivery_transcript "Please fix the widget")
rc=$(FAKE_GH_STATE=MERGED FAKE_GH_JSON="$FAKE_GH_JSON_REL" FAKE_LINEAR_STATE=Todo run_hook "$TD_REL" "Merged. RUSH-1234 is closed." false)
check "open related ticket in PR body blocks" "$rc" "2"
grep -q "RUSH-5678" "$SANDBOX/stderr" && echo "ok   - delivery gate cites related ticket" || { echo "FAIL - delivery gate did not cite related ticket"; fail=1; }

# D8. Plain question (no done-claim, no PR) -> delivery gate must NOT fire.
rc=$(run_hook "$TSHORT" "The config looks valid." false)
check "plain question does not fire delivery gate" "$rc" "0"

# D9. Probe error (linear crashes/returns garbage) -> fail open.
cat > "$SANDBOX/bin/linear" <<'STUB'
#!/usr/bin/env bash
echo "garbage"
exit 1
STUB
chmod +x "$SANDBOX/bin/linear"
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/RUSH-1234 run_hook "$TD" "All done. The widget is merged." false)
check "linear probe error fails open to the older self-audit gate" "$rc" "2"
grep -q "STOP GATE (delivery)" "$SANDBOX/stderr" && { echo "FAIL - delivery gate did not fail open on linear error"; fail=1; } || echo "ok   - delivery gate fails open on linear error"

cat > "$SANDBOX/bin/linear" <<'STUB'
#!/usr/bin/env bash
ticket=$(echo "$*" | grep -oE 'RUSH-[0-9]+' | head -1)
state="${FAKE_LINEAR_STATE:-Done}"
title="Fake ticket"
printf '{"state":{"name":"%s"},"title":"%s"}\n' "$state" "$title"
STUB
chmod +x "$SANDBOX/bin/linear"

# D10. Delivery activity can come from a raw git merge, not only gh PR commands.
TGIT="$SANDBOX/git-merge-transcript.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"Please ship RUSH-2468 from the release branch."}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working"}]}}'
  echo "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_gitmerge\",\"name\":\"Bash\",\"input\":{\"command\":\"cd $FAKE_REPO && git merge origin/release/RUSH-2468\"}}]}}"
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_gitmerge","content":[{"type":"text","text":"merge made by recursive strategy"}]}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 2"}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 3"}]}}'
} > "$TGIT"
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=release/RUSH-2468 FAKE_LINEAR_STATE=Todo run_hook "$TGIT" "Merged RUSH-2468." false)
check "git merge finish-line triggers delivery gate" "$rc" "2"
grep -q "RUSH-2468" "$SANDBOX/stderr" && echo "ok   - git merge delivery gate cites ticket" || { echo "FAIL - git merge delivery gate missed ticket"; fail=1; }

# --- command-handback gate --------------------------------------------------
# The "No, you release it.." failure: the session wrote a runnable script to a
# temp path AND the final message tells the user to run it. Fires only when BOTH
# hold, and exempts a genuine user-only gate (biometric / interactive login).
THB=$(mk_transcript handback)

# H1. Wrote /tmp/release.sh (Write tool) + "run it when ready" -> block.
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "I've prepared the release at /tmp/release-1.20.82.sh — run it when ready for a single paste." false)
check "temp-script write + 'run it' handoff blocks" "$rc" "2"
grep -q "STOP GATE (handback)" "$SANDBOX/stderr" && echo "ok   - handback gate names itself" || { echo "FAIL - no handback gate message"; fail=1; }

# H2. Same temp script, but the final message reports the agent RAN it -> allow
#     (no directive to the user; running it yourself is the whole point).
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "Ran the release script myself; v1.20.82 is published and verified live." false)
check "temp-script write but agent ran it allows stop" "$rc" "0"

# H3. Temp script + a directive that names a GENUINE user-only gate -> allow.
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "The signing step needs your Touch ID — run it when you're at the machine to approve the biometric prompt." false)
check "temp-script handoff exempted for a user-only biometric gate" "$rc" "0"

# H4. Directive to run, but NO temp script was written this session -> allow
#     (a bare 'run it' with no prepared script is not the hand-back this catches;
#     avoids nagging ordinary prose). Uses the plain transcript.
TPL=$(mk_transcript plain)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TPL" "Once CI is green, run it to cut the tag." false)
check "'run it' with no temp script written does not fire handback gate" "$rc" "0"

# H5. Temp script + directive but stop_hook_active -> allow (no loops).
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "Run it when ready." true)
check "handback gate respects stop_hook_active" "$rc" "0"

# H6. Shell-redirect form (cat > /tmp/deploy.sh) + "paste it" -> block.
THBS=$(mk_transcript handback-shell)
rc=$(FAKE_GH_STATE=MERGED run_hook "$THBS" "The deploy is scripted at /tmp/deploy.sh — paste it into your shell to ship." false)
check "shell-redirect temp script + 'paste it' blocks" "$rc" "2"

exit $fail
