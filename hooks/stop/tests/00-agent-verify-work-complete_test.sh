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
HOOK="$HERE/../00-agent-verify-work-complete.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export VERIFY_WORK_STATE_DB="$SANDBOX/verify-work-state.db"

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

# --- agents stub -------------------------------------------------------------
# The hook's argue-past cap fires a REAL `agents feed post --blocked` (a
# fail-loud owner delivery) on its third fire. AP5 exercises exactly that
# branch, so without this stub every test run sends the owner an iMessage
# (RUSH-3010). Log the invocation so AP5 can assert the post instead.
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${AGENTS_STUB_LOG:?}"
STUB
chmod +x "$SANDBOX/bin/agents"
export AGENTS_STUB_LOG="$SANDBOX/agents.log"
: > "$AGENTS_STUB_LOG"

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
      create|create+view|create+watch|create+nativemon|create+monitor|create+monitor-err|create+dispatch|create+dispatch+monarm|create+grepdispatch)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_create1","name":"Bash","input":{"command":"cd /repo && gh pr create --title widget"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_create1","content":[{"type":"text","text":"https://github.com/acme/widgets/pull/42\n"}]}]}}'
        ;;
    esac
    case "$1" in
      create+watch)
        # LEGACY / REJECTED (RUSH-2394): in-process `gh pr checks --watch` is a
        # child of the agent and dies when a headless agent exits. Kept as a
        # fixture so the gate test proves it no longer clears the stop.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_watch1","name":"Bash","input":{"command":"gh pr checks 42 --watch --fail-fast","run_in_background":true}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_watch1","content":[{"type":"text","text":"watching CI in background"}]}]}}'
        ;;
      create+nativemon)
        # Durable native re-invoke: a Monitor tool_use the harness owns; it
        # outlives the agent (RUSH-2394). Replaces the removed agents pr land.
        # The paired non-error tool_result is REQUIRED — invoked is not armed
        # (2026-08-15: a claimed watcher whose arm failed counted as live).
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_natmon1","name":"Monitor","input":{"source":"gh pr checks 42","condition":"green","action":"merge on green"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_natmon1","content":[{"type":"text","text":"monitor armed"}]}]}}'
        ;;
      create+monitor)
        # A ScheduleWakeup that re-invokes the agent when CI settles, with its
        # successful tool_result (see create+nativemon note).
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_mon1","name":"ScheduleWakeup","input":{"delaySeconds":300,"reason":"re-check CI and merge on green"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_mon1","content":[{"type":"text","text":"wakeup scheduled"}]}]}}'
        ;;
      create+monitor-err)
        # The arm FAILED — a ScheduleWakeup whose tool_result is an error is not
        # a watcher, whatever the final message claims.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_monE","name":"ScheduleWakeup","input":{"delaySeconds":300,"reason":"re-check CI"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_monE","is_error":true,"content":[{"type":"text","text":"Error: scheduler unavailable"}]}]}}'
        ;;
    esac
    case "$1" in
      create+dispatch|create+dispatch+monarm)
        # The session DISPATCHED a child agent (dispatch-shaped: --no-follow).
        # The f045b577 failure shape: dispatch, then stop on the word "handoff".
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_disp1","name":"Bash","input":{"command":"agents run claude \"Mission: finish PR 42\" --mode auto --name widget-child --timeout 120m --no-follow"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_disp1","content":[{"type":"text","text":"[agents] running claude@2.1.217 (session child01)"}]}]}}'
        ;;
    esac
    case "$1" in
      create+dispatch+monarm)
        # Dispatch AND a durable daemon-owned watcher armed on the child PR —
        # the recipe the block message teaches. Non-error result required.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_monarm1","name":"Bash","input":{"command":"agents monitors add pr-merge-on-green --pr https://github.com/acme/widgets/pull/42"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_monarm1","content":[{"type":"text","text":"monitor added"}]}]}}'
        ;;
      create+grepdispatch)
        # The dispatch marker appears ONLY inside a grep pattern — must NOT
        # count as a real dispatch (same false positive class as the swarm gate).
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_gd1","name":"Bash","input":{"command":"grep -cE \"agents run .*--no-follow|agents teams start\" /tmp/transcript.jsonl"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_gd1","content":[{"type":"text","text":"2"}]}]}}'
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
      inherited-repo-scope)
        # The session drives an inherited PR using a repo-scoped bare number.
        # extract_ref must synthesize a URL from --repo so the state check hits
        # the right repository instead of re-resolving the bare number against cwd.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_rs1","name":"Bash","input":{"command":"gh pr merge 42 --repo acme/widgets --rebase --delete-branch"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_rs1","content":[{"type":"text","text":"merge attempted"}]}]}}'
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
      browser)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_b1","name":"Bash","input":{"command":"agents browser open https://example.test/app"}}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_b2","name":"Bash","input":{"command":"agents browser screenshot"}}]}}'
        ;;
      research)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_r1","name":"Read","input":{"file_path":"/repo/src/widget.ts"}}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_r2","name":"Grep","input":{"pattern":"Widget","path":"/repo"}}]}}'
        ;;
      ticket-create)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_t1","name":"Bash","input":{"command":"linear create --title widget-follow-up"}}]}}'
        ;;
      review-submit)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_rev1","name":"Bash","input":{"command":"gh pr review https://github.com/acme/widgets/pull/42 --approve"}}]}}'
        ;;
      repo-write)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_edit1","name":"Edit","input":{"file_path":"/repo/src/widget.ts","old_string":"old","new_string":"new"}}]}}'
        ;;
    esac
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 2"}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 3"}]}}'
  } > "$t"
  echo "$t"
}

run_hook() {   # $1 transcript, $2 last message, $3 stop_hook_active
  python3 - "$1" "$2" "$3" <<'PY' | bash "$HOOK" >/dev/null 2>"$SANDBOX/stderr"
import hashlib, json, sys
fixture_id = "fixture-" + hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16]
print(json.dumps({
    "session_id": fixture_id,
    "launch_id": fixture_id,
    "agent": "claude",
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
grep -q "STOP —" "$SANDBOX/stderr" && echo "ok   - block message present" || { echo "FAIL - no gate message"; fail=1; }

# 2. Created PR, MERGED -> allow
rc=$(FAKE_GH_STATE=MERGED run_hook "$T" "Merged and cleaned up." false)
check "merged PR allows stop" "$rc" "0"

# 3. Created PR, OPEN, but explicit handoff in final message -> allow
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is handed off to the release watcher, which owns the PR from here." false)
check "open PR with explicit handoff allows stop" "$rc" "0"

# 4. Handoff words only as a substring of another word -> still blocks
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "The build handoffs are documented; waiting on review." false)
check "handoff-substring does not escape the gate" "$rc" "2"

# --- dispatch-is-not-a-handoff (f045b577, 2026-08-21) ------------------------
# An orchestrator that dispatched agents (`agents run … --no-follow`) may not
# clear the open-PR check on the handoff phrase alone — it handed its own
# children to themselves ("completion contract = PR merged or named handoff",
# no watcher armed). Phrase + durable watcher still passes.
TD=$(mk_transcript create+dispatch)

# D1. Dispatch + open PR + the measured handoff phrasing, no watcher -> block.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TD" "RUSH-42 is dispatched to session child01; completion contract = PR merged or named handoff. I'm done unless it surfaces a blocker." false)
check "dispatch + handoff phrase without a watcher blocks" "$rc" "2"
grep -qi "you own what you spawn" "$SANDBOX/stderr" && echo "ok   - block message teaches you-own-what-you-spawn" || { echo "FAIL - no dispatch-ownership message"; fail=1; }
grep -qi "agents monitors add" "$SANDBOX/stderr" && echo "ok   - block message names the watcher recipe" || { echo "FAIL - block message omits the watcher recipe"; fail=1; }

# D2. Same dispatch but a successful `agents monitors add` armed -> allow.
#     Also locks in monitors-add counting as durable watcher evidence at all.
TDM=$(mk_transcript create+dispatch+monarm)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TDM" "PR #42 is handed off to the armed pr-merge-on-green monitor, which owns the PR from here." false)
check "dispatch + armed agents monitors add allows stop" "$rc" "0"

# D3. Dispatch marker only inside a grep pattern -> NOT a dispatch; the plain
#     handoff escape still applies (same anti-false-positive as the swarm gate).
TDG=$(mk_transcript create+grepdispatch)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TDG" "PR #42 is handed off to the release watcher, which owns the PR from here." false)
check "grep FOR dispatch markers does not suppress the handoff escape" "$rc" "0"

# 4b. Open PR blocked on a genuine external blocker WITH a durable finish path -> allow
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is blocked on a GitHub Actions 503 outage failing CI — a ScheduleWakeup will merge on green when CI recovers." false)
check "external blocker + durable ScheduleWakeup phrasing allows stop" "$rc" "0"

# 4b2. REGRESSION (RUSH-2394): blocked-on + in-process gh pr checks --watch is NOT durable.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is blocked on CI — watcher: background gh pr checks --watch will finish it." false)
check "external blocker + in-process gh pr checks --watch still blocks (RUSH-2394)" "$rc" "2"

# 4c. Open PR blocked on a pending user action (Touch ID / review) WITHOUT a
#     filed --blocked receipt -> block. An owner-only gate is real, but a
#     hand-back that never reached the owner's feed/phone is a silent stop
#     (RUSH-3013 ownership directive); the receipt-pass variant is OWN5 below.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is blocked on your Touch ID to sign the release; awaiting your merge." false)
check "owner-targeted stop without a filed receipt blocks" "$rc" "2"

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

# 4h. Abandonment prose: 'blocked on ...' + bare 'monitor' (no ScheduleWakeup
#     tool, not the pr-merge-on-green monitor) -> still blocks. 'I'll monitor CI'
#     is ordinary prose, not a durable finish path; the nextstep tokens stay
#     specific so this cannot clear the non-evidence-gated blocker escape.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Blocked on flaky CI; I'll monitor it and merge once it settles." false)
check "blocked-on + bare 'monitor' prose still blocks" "$rc" "2"

# 5. stop_hook_active -> allow (no loops)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "still waiting" true)
check "stop_hook_active bypasses gate" "$rc" "0"

# 6. PR URL mentioned but session never ran pr create (review-only) -> allow
T2=$(mk_transcript review)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T2" "Review finished, feedback posted." false)
check "reviewing someone else's PR does not block" "$rc" "0"

# 6a. Positive non-code outcomes must not be converted into code delivery merely
# because their final message uses completion language inside a Git cwd.
TBROWSER=$(mk_transcript browser)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TBROWSER" "Done. The external app record is present and the screenshot verifies it." false)
check "browser-only completion does not trigger code delivery" "$rc" "0"

TRESEARCH=$(mk_transcript research)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TRESEARCH" "Done. The diagnostic found the parser boundary and cited the source." false)
check "read-only diagnostic completion does not trigger code delivery" "$rc" "0"

TTICKET=$(mk_transcript ticket-create)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TTICKET" "Done. The requested implementation ticket is open with full context." false)
check "ticket creation does not demand closing the requested ticket" "$rc" "0"

TREVIEW=$(mk_transcript review-submit)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TREVIEW" "Done. I submitted the review; the author's PR remains open." false)
check "review-only completion does not inherit merge ownership" "$rc" "0"

# 6b. A tracked repository write is positive delivery evidence even without a
# PR, so a done claim still receives the delivery/self-audit gates.
TWRITE=$(mk_transcript repo-write)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TWRITE" "All done. The widget behavior is complete." false)
check "repository mutation keeps delivery completion gates active" "$rc" "2"

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
grep -q 'agents feed post.*--level important' "$SANDBOX/stderr" && echo "ok   - completion post is phone-worthy" || { echo "FAIL - completion post is not important"; fail=1; }
grep -qi "you claimed this work is done" "$SANDBOX/stderr" && echo "ok   - done-claim gate cites the original request" || { echo "FAIL - no done-claim gate message"; fail=1; }

# 8a. The concise completion nudge keeps only the load-bearing instructions.
grep -qi "verify before stopping" "$SANDBOX/stderr" && echo "ok   - check requires verification before stopping" || { echo "FAIL - check omits verification instruction"; fail=1; }
grep -qi "Re-check every ask this session" "$SANDBOX/stderr" && echo "ok   - check requires a full-session audit" || { echo "FAIL - check omits the full-session audit"; fail=1; }
grep -qi "agents feed post" "$SANDBOX/stderr" && echo "ok   - check requests one completion update" || { echo "FAIL - check omits the completion update"; fail=1; }

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
grep -q "edit-mode swarm" "$SANDBOX/stderr" && echo "ok   - swarm gate names itself + the seam" || { echo "FAIL - no swarm gate message"; fail=1; }

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
grep -q "edit-mode swarm and are claiming" "$SANDBOX/stderr" && { echo "FAIL - swarm gate false-fired on a grep"; fail=1; } || echo "ok   - no swarm gate on a search-only session"

# --- genuine-user-message extraction (skip harness noise) -------------------
# A session opened with `j <dir>` (a `!`-prefix bash-input) must NOT have that
# quoted as "the original request" — the done-claim gate must skip
# <bash-input>/<bash-stdout> turns and quote the first real prose ask instead.
NT="$SANDBOX/noise-transcript.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"<bash-input>j agents-cli</bash-input>"}}'
  echo '{"type":"user","message":{"role":"user","content":"<bash-stdout>/home/user/src/agents-cli</bash-stdout><bash-stderr></bash-stderr>"}}'
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
grep -qi "created or worked" "$SANDBOX/stderr" && echo "ok   - inherited-PR gate names created-or-worked" || { echo "FAIL - inherited gate message not updated"; fail=1; }

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

# A6. A repo-scoped bare-number PR ref must not collapse into a same-numbered PR
#     in the session cwd repo. extract_ref should synthesize a URL from --repo so
#     the state check hits the right repository instead of re-resolving the bare
#     number against cwd.
TRS=$(mk_transcript inherited-repo-scope)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TRS" "Merged the PR in acme/widgets." false)
check "repo-scoped inherited PR still OPEN blocks" "$rc" "2"
grep -q "acme/widgets/pull/42" "$SANDBOX/stderr" && echo "ok   - repo-scoped gate names the qualified PR URL" || { echo "FAIL - gate did not name qualified PR URL"; fail=1; }

# --- parking / offer-instead-of-do done-gate (Fix B) ------------------------
# A session that PARKS the obvious next step behind the user ('want me to…',
# 'on your go', 'say the word') instead of doing it must be challenged, even
# though those phrases are in neither the done-signal list nor the swarm list.
# Uses a plain transcript (no PR, no swarm) with >2 assistant turns.
TP=$(mk_transcript plain)

# B1. 'want me to … on your go' parking -> the self-audit gate must fire.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "Want me to build the current main into a .vsix and install it? I can do it on your go." false)
check "parking 'want me to … on your go' blocks for self-audit" "$rc" "2"
grep -qi "you claimed this work is done" "$SANDBOX/stderr" && echo "ok   - parking routes through the self-audit GATE" || { echo "FAIL - parking did not reach the self-audit gate"; fail=1; }

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

# --- stand-down / ownership-handback (chatbot-mode) -------------------------
# The agent deliberates about ownership and refuses to drive work it was asked
# to do ("#1642 is yours, not mine to drive", "handing it back and standing
# clear"), often citing a sibling session. F1: coordinate-and-continue, never
# stand-down. These route through the self-audit gate like the parking idioms.

# S1. 'is yours, not mine to drive' stand-down -> the self-audit gate fires.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "I've got the disposition clear: #1642 is yours, not mine to drive. I'm standing clear." false)
check "stand-down 'yours not mine to drive' blocks for self-audit" "$rc" "2"
grep -qi "you claimed this work is done" "$SANDBOX/stderr" && echo "ok   - stand-down routes through the self-audit gate" || { echo "FAIL - stand-down did not reach the self-audit gate"; fail=1; }

# S2. 'handing it back and standing clear' stand-down -> fires.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "The other session can take it from here — handing it back and standing down." false)
check "stand-down 'handing it back / standing down' blocks" "$rc" "2"

# S3. LEGIT handoff by naming an owner -> must NOT trip the stand-down patterns.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "Landed and handed off to the release watcher, which owns the follow-up from here." false)
check "legit handoff-by-naming-owner does not trip stand-down" "$rc" "0"

# S4. Ordinary use of 'back' (rolled back) -> must NOT fire (no stand-down idiom).
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "Rolled back the migration; the schema is on the prior revision now." false)
check "ordinary 'rolled back' prose does not trip stand-down" "$rc" "0"

# S5. 'handing it back to you' (to the human) -> fires (the tightened pattern).
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "This one is above my pay grade — handing it back to you to decide." false)
check "stand-down 'handing it back to you' blocks" "$rc" "2"

# S6. 'handing it back to the main thread' (async prose) -> must NOT fire. This
#     is the reviewer-found false positive: returning control to a technical
#     entity is not a stand-down. The pattern now requires a HUMAN target.
rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "Each handler now awaits the result before handing it back to the main thread; tests pass." false)
check "async 'handing it back to the main thread' does not trip stand-down" "$rc" "0"

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
grep -q "close out the delivery" "$SANDBOX/stderr" && echo "ok   - delivery gate names itself" || { echo "FAIL - delivery gate message missing"; fail=1; }
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
grep -q "no docs and CHANGELOG update" "$SANDBOX/stderr" && echo "ok   - delivery check flags missing docs and CHANGELOG" || { echo "FAIL - delivery check did not flag docs/changelog"; fail=1; }

# D4. User-facing change + only CHANGELOG updated -> still blocks; docs and
#     CHANGELOG are separate requirements.
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/no-ticket FAKE_GIT_FILES=$'CHANGELOG.md\nsrc/widget.js' run_hook "$TD_UF" "Merged the new flag. Evidence: screenshot /tmp/flag.png." false)
check "user-facing change with only CHANGELOG still blocks" "$rc" "2"
grep -q "no docs update" "$SANDBOX/stderr" && echo "ok   - delivery check requires docs separately" || { echo "FAIL - delivery check did not require docs separately"; fail=1; }

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
grep -q "Release/live verification incomplete" "$SANDBOX/stderr" && echo "ok   - delivery check flags missing release/live verification" || { echo "FAIL - delivery check did not flag release"; fail=1; }

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

# D8b. State is a precision aid, not a safety dependency. If its schema cannot
# be read, a done claim retains the pre-state delivery-chain enforcement.
STATE_MISMATCH="$SANDBOX/state-mismatch.db"
sqlite3 "$STATE_MISMATCH" "create table meta(key text primary key,value text not null); insert into meta values('schema_version','999');"
rc=$(VERIFY_WORK_STATE_DB="$STATE_MISMATCH" FAKE_GIT_BRANCH=feature/RUSH-1234 FAKE_LINEAR_STATE=Todo run_hook "$TWRITE" "All done. The widget is complete." false)
check "state evaluation failure preserves delivery enforcement" "$rc" "2"
grep -q "close out the delivery" "$SANDBOX/stderr" && echo "ok   - state failure reaches delivery gate" || { echo "FAIL - state failure weakened delivery gate"; fail=1; }

# D9. Probe error (linear crashes/returns garbage) -> fail open.
cat > "$SANDBOX/bin/linear" <<'STUB'
#!/usr/bin/env bash
echo "garbage"
exit 1
STUB
chmod +x "$SANDBOX/bin/linear"
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/RUSH-1234 run_hook "$TD" "All done. The widget is merged." false)
check "linear probe error fails open to the older self-audit gate" "$rc" "2"
grep -q "close out the delivery" "$SANDBOX/stderr" && { echo "FAIL - delivery gate did not fail open on linear error"; fail=1; } || echo "ok   - delivery gate fails open on linear error"

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

# D11. `linear tasks <id>` (a bare READ — checking state, triaging, incidental
#      research) must NOT count as "this delivery references the ticket", even
#      at a genuine merge finish-line. No PR, no branch tie, no done-claim
#      wording (avoids the older self-audit gate) — a `git merge` sets
#      delivery_activity and "Merged." supplies the finish-line phrase, so the
#      delivery gate itself runs; the only thing pointing at RUSH-7777 is the
#      read command, so it must not fire. Mirrors the existing `gh pr view`
#      (VIEW is not WORK) distinction above. >=3 assistant turns clears the
#      short-Q&A skip (turn_count <= 2).
TREAD="$SANDBOX/ticket-read.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"What does the browser skill do?"}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Looking into it"}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_gm1","name":"Bash","input":{"command":"git merge origin/feature/no-ticket"}}]}}'
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_gm1","content":[{"type":"text","text":"merge made by recursive strategy"}]}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_lread1","name":"Bash","input":{"command":"linear tasks RUSH-7777"}}]}}'
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_lread1","content":[{"type":"text","text":"RUSH-7777  Some unrelated ticket\n  Status: Todo"}]}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"It drives real browsers over CDP."}]}}'
} > "$TREAD"
rc=$(FAKE_GH_STATE=MERGED FAKE_LINEAR_STATE=Todo run_hook "$TREAD" "Merged." false)
check "bare 'linear tasks <id>' read does not fire the delivery gate" "$rc" "0"

# D12. `linear update <id>` (a WRITE — a real status/comment change) still
#      correctly flags an open ticket. Same shape as D11 but the command is an
#      update, and the ticket is still open, so a merge finish-line stop must
#      still block on it.
TWRITE="$SANDBOX/ticket-write.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"Note progress on RUSH-8888."}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Posting a comment"}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_gm2","name":"Bash","input":{"command":"git merge origin/feature/no-ticket"}}]}}'
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_gm2","content":[{"type":"text","text":"merge made by recursive strategy"}]}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_lwrite1","name":"Bash","input":{"command":"linear update RUSH-8888 --comment \"partial progress\""}}]}}'
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_lwrite1","content":[{"type":"text","text":"Comment added to RUSH-8888."}]}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Left a progress note."}]}}'
} > "$TWRITE"
rc=$(FAKE_GH_STATE=MERGED FAKE_LINEAR_STATE=Todo run_hook "$TWRITE" "Merged." false)
check "'linear update <id>' write still flags an open ticket" "$rc" "2"
grep -q "RUSH-8888" "$SANDBOX/stderr" && echo "ok   - delivery gate cites the written-to ticket" || { echo "FAIL - delivery gate did not cite the written-to ticket"; fail=1; }

# --- command-handback gate --------------------------------------------------
# The "No, you release it.." failure: the session wrote a runnable script to a
# temp path AND the final message tells the user to run it. Fires only when BOTH
# hold, and exempts a genuine user-only gate (biometric / interactive login).
THB=$(mk_transcript handback)

# H1. Wrote /tmp/release.sh (Write tool) + "run it when ready" -> block.
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "I've prepared the release at /tmp/release-1.20.82.sh — run it when ready for a single paste." false)
check "temp-script write + 'run it' handoff blocks" "$rc" "2"
grep -q "runnable script" "$SANDBOX/stderr" && echo "ok   - handback gate names itself" || { echo "FAIL - no handback gate message"; fail=1; }

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

# --- command-cue precision (false positives observed live) ------------------
# The session had written helper scripts to /tmp earlier (THB), but the final
# message is about pasting text into a FORM / sending a MESSAGE, not running a
# command. RUN alone matched these ('paste that', 'you just paste it'), so the
# gate false-fired. It must now require a command cue (script/.sh/shell/terminal).

# H7. Temp script written, but final message says paste a blurb into a job
#     application form (no command cue) -> allow (not a runnable-command handback).
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "Fastest move: paste that blurb into the Mercor application, then hit apply." false)
check "paste-into-a-form directive does not fire handback gate" "$rc" "0"

# H8. Temp script written, but final message tells the user to send an email
#     reply (no command cue; 'hit send' is a user-only action) -> allow.
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "The reply's on your clipboard; paste it in, attach the resume, and hit send." false)
check "send-a-message directive does not fire handback gate" "$rc" "0"

# H9. Command cue present (shell) BUT the directive is to send a message ->
#     exempt (sending under the user's identity is theirs to do). -> allow.
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "Paste it into your shell if you like, then hit send on the reply." false)
check "message-send is exempted even with a shell cue" "$rc" "0"

# H10. RECALL GUARD: a plain 'just run it when you're ready' after a temp-script
#      write names no command cue but IS the canonical handback -> still block.
#      (Excluding false-positive shapes, rather than demanding a positive command
#      cue, is what keeps this real case firing.)
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "I've prepared the release; just run it when you're ready." false)
check "plain 'run it when ready' handback still blocks (recall preserved)" "$rc" "2"

# --- Fix 2 / RUSH-2394: only a DURABLE lander / monitor is a valid stop -------
# W1. REGRESSION: Open PR + in-process `gh pr checks --watch` (run_in_background)
#     + watcher phrasing -> BLOCK. That child dies when a headless agent exits
#     and strands the PR (observed on PR #2334 / #2352).
TW=$(mk_transcript create+watch)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TW" "Not idling — the live background watcher owns the next step and re-invokes me on green." false)
check "open PR + in-process gh pr checks --watch still blocks (RUSH-2394)" "$rc" "2"

# W1b. Open PR + durable native `Monitor` tool_use + monitor phrasing -> allow.
TD=$(mk_transcript create+nativemon)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TD" "Not idling — a Monitor owns the next step and will merge on green." false)
check "open PR + native Monitor tool_use allows stop" "$rc" "0"

# W2. Open PR + a ScheduleWakeup monitor tool_use + poller phrasing -> allow.
TM=$(mk_transcript create+monitor)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TM" "A ScheduleWakeup is set to re-invoke me when CI settles; the poller owns the merge." false)
check "open PR + ScheduleWakeup monitor allows stop" "$rc" "0"

# W3. REGRESSION (RUSH-2473 evidence gate): the removed `agents pr land` command
#     STRING in the message + NO ScheduleWakeup/Monitor tool_use this session ->
#     still blocks. Phrasing (even the old lander command) never clears the gate.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "agents pr land --detach owns the next step and will merge on green." false)
check "removed agents-pr-land phrasing WITHOUT a real tool_use still blocks" "$rc" "2"

# --- Fix 3: plan mode / reviewer-down context awareness ---------------------
# P1. Open PR the session cannot advance because plan mode forbids push/merge.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is open but I cannot push or merge it — plan mode forbids that right now." false)
check "plan mode (cannot push/merge) allows stop on an open PR" "$rc" "0"

# P1b. Incidental mention of 'plan mode' with no can't/forbid cue -> still blocks.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "I sketched a plan mode of attack; PR #42 CI is still running." false)
check "incidental 'plan mode' phrase without a forbid cue still blocks" "$rc" "2"

# P2. Automated reviewer down + "needs you to click merge" is NOT a valid stop —
#     agent must spawn a subagent review and merge itself, not hand the merge to the user.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 CI is green but prix-cloud is down (no reviewer posted). It now needs you to click merge." false)
check "reviewer down + needs-you still blocks (spawn subagent review, do not hand off)" "$rc" "2"

# P2b. REGRESSION: 'no ci failures' / 'no ci blocking' is abandonment prose.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "No CI failures detected. Your approval would help get this merged." false)
check "'no ci failures' + 'your approval' still blocks" "$rc" "2"
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "No CI blocking this merge, your sign-off is all that's needed." false)
check "'no ci blocking' + 'your sign-off' still blocks" "$rc" "2"

# P2c. No automated reviewer configured + needs-you is also not a stop — spawn subagent review.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "This repo has no reviewer configured, so PR #42 now needs you to merge it." false)
check "'no reviewer configured' + needs-you still blocks (spawn subagent review)" "$rc" "2"

# P2d. Reviewer down but PR explicitly handed to a named owner/session still allows stop.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 CI is green but prix-cloud is down. Handed off to the code-review session, which owns the PR from here." false)
check "reviewer down + explicit named handoff allows stop" "$rc" "0"

# --- Repeated-gate strategy guidance after the 3rd fire on the same item -----
# A transcript that already carries N prior open-PR fires (real isMeta 'Stop hook
# feedback:' shape), so the current stop is the (N+1)th on the same open PR.
mk_looped() {   # $1 = number of prior open-PR fires already in the transcript
  local t="$SANDBOX/looped-$RANDOM.jsonl" i
  {
    echo '{"type":"user","message":{"role":"user","content":"Implement the widget and open a PR for it"}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_lc1","name":"Bash","input":{"command":"gh pr create --title widget"}}]}}'
    echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_lc1","content":[{"type":"text","text":"https://github.com/acme/widgets/pull/42\n"}]}]}}'
    i=0
    while [ "$i" -lt "$1" ]; do
      echo '{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\n[~/.claude/hooks/00-agent-verify-work-complete.sh]: STOP GATE: This session created OR worked pull request(s) that are still OPEN:\n\nhttps://github.com/acme/widgets/pull/42\n"}}'
      echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"still driving it"}]}}'
      i=$((i + 1))
    done
  } > "$t"
  echo "$t"
}

# D1. First fire (0 prior) blocks WITHOUT repeated-gate guidance.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "CI is green, waiting for the reviewer." false)
check "first open-PR fire blocks" "$rc" "2"
grep -qi "this is block number" "$SANDBOX/stderr" && { echo "FAIL - repeat guidance fired on the 1st block"; fail=1; } || echo "ok   - no repeat guidance on the 1st fire"

# D2. Third fire (2 prior) still blocks and suggests a context-led tactic change.
TL=$(mk_looped 2)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TL" "CI still running, waiting." false)
check "3rd open-PR fire still blocks" "$rc" "2"
grep -qi "block 3 this session" "$SANDBOX/stderr" && echo "ok   - repeat guidance appears on the 3rd fire" || { echo "FAIL - no repeat guidance on the 3rd fire"; fail=1; }
grep -qi "cannot move without the owner" "$SANDBOX/stderr" && echo "ok   - guidance teaches the owner-gated exit, not 'change tactics'" || { echo "FAIL - repeat guidance lacks the owner-gated exit"; fail=1; }

# D3. Second fire (1 prior) does NOT yet add repeat guidance.
TL1=$(mk_looped 1)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TL1" "still waiting on CI." false)
check "2nd open-PR fire still blocks" "$rc" "2"
grep -qi "this is block number" "$SANDBOX/stderr" && { echo "FAIL - repeat guidance fired on the 2nd block (threshold is 3rd)"; fail=1; } || echo "ok   - no repeat guidance on the 2nd fire"

# --- Task-list keep-moving gate (RUSH-2113 A + B) ----------------------------
# The session's OWN checklist is the strongest "stopped too early" signal. A stop
# with pending / in_progress items and no named owner is premature; a genuine
# question, plan mode, a named blocker, an explicit handoff, or a LIVE background
# watcher that owns the remaining step are all legitimate stops.
#
# Fixtures build the real Claude tool_use shape for the checklist tools
# (TaskCreate / TaskUpdate, and the snapshot TodoWrite). No PR is created, so
# ONLY this gate can fire — its block message is tagged "STOP GATE (keep moving)".
mk_tasks() {   # $1 selects checklist state
  local t="$SANDBOX/tasks-$RANDOM.jsonl"
  {
    echo '{"type":"user","message":{"role":"user","content":"Build the widget: write the parser, then wire it up"}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tc1","name":"TaskCreate","input":{"subject":"Write the parser","description":"parse the input"}}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tc2","name":"TaskCreate","input":{"subject":"Wire it up","description":"connect to the pipeline"}}]}}'
    case "$1" in
      one-remaining)
        # task 1 done, task 2 still in_progress -> one item remains.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu2","name":"TaskUpdate","input":{"taskId":"2","status":"in_progress"}}]}}'
        ;;
      all-done)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu2","name":"TaskUpdate","input":{"taskId":"2","status":"completed"}}]}}'
        ;;
      watcher-remaining)
        # one item left AND a durable native ScheduleWakeup this session owns it
        # (RUSH-2394). Replaces the removed agents pr land --detach. The paired
        # non-error tool_result is required — invoked is not armed (2026-08-15).
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tw1","name":"ScheduleWakeup","input":{"delaySeconds":300,"reason":"re-check CI and merge PR 42 on green"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tw1","content":[{"type":"text","text":"wakeup scheduled"}]}]}}'
        ;;
    esac
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"progress"}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"more progress"}]}}'
  } > "$t"
  echo "$t"
}

# E1. Pending checklist + a plain declarative stop -> keep-moving block.
TK=$(mk_tasks one-remaining)
rc=$(run_hook "$TK" "The parser is written and pushed to the branch." false)
check "pending checklist + declarative stop blocks" "$rc" "2"
grep -qi "task list still has" "$SANDBOX/stderr" && echo "ok   - keep-moving gate identifies itself" || { echo "FAIL - keep-moving gate not the one that fired"; fail=1; }
grep -qi "Wire it up" "$SANDBOX/stderr" && echo "ok   - keep-moving gate names the next item" || { echo "FAIL - keep-moving gate omits the next item"; fail=1; }

# E2. Every item completed -> no keep-moving block (neutral wrap-up allows stop).
TKD=$(mk_tasks all-done)
rc=$(run_hook "$TKD" "The parser is written and the wiring is in place." false)
check "all checklist items complete allows stop" "$rc" "0"

# E3. Pending checklist but the final message is a genuine question -> allow.
rc=$(run_hook "$TK" "The parser is written. Which layout should the wiring use, tabs or spaces?" false)
check "pending checklist + clarifying question allows stop" "$rc" "0"

# E4. Pending checklist + an explicit named handoff -> allow.
rc=$(run_hook "$TK" "Parser written; the ui session takes over from here and owns the task." false)
check "pending checklist + explicit handoff allows stop" "$rc" "0"

# E5. Pending checklist + a genuine external blocker (biometric) -> allow.
rc=$(run_hook "$TK" "Parser written. Wiring is blocked on your Touch ID to sign the artifact." false)
check "pending checklist + named external blocker allows stop" "$rc" "0"

# E6. Pending checklist + a durable ScheduleWakeup + watcher phrasing -> allow (RUSH-2394).
TKW=$(mk_tasks watcher-remaining)
rc=$(run_hook "$TKW" "A ScheduleWakeup owns the merge and will merge on green." false)
check "pending checklist + durable ScheduleWakeup owns it allows stop" "$rc" "0"

# E7. Durable-watcher PHRASING (even the removed agents pr land command) but no
# real ScheduleWakeup/Monitor tool_use this session -> still block (evidence-
# gated, so the gate can't be talked out of firing) (RUSH-2473).
rc=$(run_hook "$TK" "Parser written; agents pr land --detach will merge on green." false)
check "watcher phrasing without a real tool_use still blocks" "$rc" "2"

# E8. No checklist at all -> the gate never fires.
TNONE=$(mk_transcript plain)
rc=$(run_hook "$TNONE" "The parser is written and pushed to the branch." false)
check "no checklist allows stop (gate never fires)" "$rc" "0"

# E9. stop_hook_active short-circuits the whole hook (fires at most once).
rc=$(run_hook "$TK" "The parser is written and pushed to the branch." true)
check "keep-moving gate respects stop_hook_active" "$rc" "0"

# E10. De-escalation: a 3rd keep-moving fire on the same session still blocks but
# adds the context-led strategy guidance.
mk_tasks_looped() {   # $1 = number of prior keep-moving fires
  local t="$SANDBOX/tasks-loop-$RANDOM.jsonl" i
  {
    echo '{"type":"user","message":{"role":"user","content":"Build the widget: write the parser, then wire it up"}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tc1","name":"TaskCreate","input":{"subject":"Write the parser","description":"d"}}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tc2","name":"TaskCreate","input":{"subject":"Wire it up","description":"d"}}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress"}}]}}'
    i=0
    while [ "$i" -lt "$1" ]; do
      echo '{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\n[~/.claude/hooks/00-agent-verify-work-complete.sh]: STOP GATE (keep moving): Your task list still has 2 unfinished item(s).\n"}}'
      echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"still working"}]}}'
      i=$((i + 1))
    done
  } > "$t"
  echo "$t"
}
TKL=$(mk_tasks_looped 2)
rc=$(run_hook "$TKL" "The parser is written and pushed." false)
check "3rd keep-moving fire still blocks" "$rc" "2"
grep -qi "block 3 this session" "$SANDBOX/stderr" && echo "ok   - keep-moving repeat guidance appears on the 3rd fire" || { echo "FAIL - no repeat guidance on the 3rd keep-moving fire"; fail=1; }

# --- todo-progress.py folding (unit) -----------------------------------------
# The helper folds snapshot checklist tools + Claude TaskCreate/TaskUpdate the
# same way the CLI's extractTodoProgressFromEvents does.
TODO="$HERE/../todo-progress.py"

# TaskCreate x2 + one set in_progress -> remaining 1, next is the pending one.
rc_json=$(python3 "$TODO" "$TK")
echo "$rc_json" | grep -q '"remaining": 1' && echo "ok   - todo-progress folds TaskCreate/TaskUpdate remaining" || { echo "FAIL - todo-progress wrong remaining ($rc_json)"; fail=1; }
echo "$rc_json" | grep -q '"next": "Wire it up"' && echo "ok   - todo-progress reports the next item" || { echo "FAIL - todo-progress wrong next ($rc_json)"; fail=1; }

# All completed -> remaining 0.
rc_json=$(python3 "$TODO" "$TKD")
echo "$rc_json" | grep -q '"remaining": 0' && echo "ok   - todo-progress reports zero remaining when all done" || { echo "FAIL - todo-progress nonzero when all done ($rc_json)"; fail=1; }

# A snapshot TodoWrite (Claude) is folded too.
TSNAP="$SANDBOX/snap-$RANDOM.jsonl"
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tw","name":"TodoWrite","input":{"todos":[{"content":"alpha","status":"completed"},{"content":"beta","status":"in_progress"},{"content":"gamma","status":"pending"}]}}]}}' > "$TSNAP"
rc_json=$(python3 "$TODO" "$TSNAP")
{ echo "$rc_json" | grep -q '"total": 3' && echo "$rc_json" | grep -q '"remaining": 2'; } && echo "ok   - todo-progress folds a TodoWrite snapshot" || { echo "FAIL - todo-progress mis-folds snapshot ($rc_json)"; fail=1; }

# Fail-open: a missing transcript yields a zero result, never an error.
rc_json=$(python3 "$TODO" "/no/such/file.jsonl")
echo "$rc_json" | grep -q '"total": 0' && echo "ok   - todo-progress fails open on a missing transcript" || { echo "FAIL - todo-progress did not fail open ($rc_json)"; fail=1; }

# --- 2026-08-15 hardening: argue-past ramp, errored watchers, evasion replay ---

# AP1. Retried stop restating the ea913c60 evasion verbatim -> block again.
T=$(mk_transcript create)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Merged, not released — and that's the correct stopping point, not a gap." true)
check "argue-past: 'correct stopping point' on retry blocks" "$rc" "2"
grep -q "stand-down phrase" "$SANDBOX/stderr" && echo "ok   - argue-past names the evasion" || { echo "FAIL - no argue-past message"; fail=1; }

# AP2. Retried stop restating the 6805bf66 evasion -> block again.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Restating for the gate: RUSH-2719 stays open by design and is not mine to close." true)
check "argue-past: 'stays open by design / not mine to close' on retry blocks" "$rc" "2"

# AP3. Retried stop citing the permission classifier as a hand-back -> block again.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "The permission classifier bars me from executing it; run the deploy from your terminal." true)
check "argue-past: 'permission classifier bars me' on retry blocks" "$rc" "2"

# AP4. An ordinary retry with no evasion phrase keeps the old behavior -> allow.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Continuing: merged the fix and closed the ticket with proof." true)
check "argue-past: plain retry without evasion phrase still passes" "$rc" "0"

# AP5. Cap: after two prior argue-past fires the retry passes (never wedge).
TCAP="$SANDBOX/transcript-cap-$RANDOM.jsonl"
cp "$T" "$TCAP"
echo '{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback: STOP — this stop was already blocked, and the retry restates a stand-down phrase"}}' >> "$TCAP"
echo '{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback: STOP — this stop was already blocked, and the retry restates a stand-down phrase"}}' >> "$TCAP"
rc=$(FAKE_GH_STATE=OPEN run_hook "$TCAP" "Merged, not released — and that's the correct stopping point." true)
check "argue-past: capped after two prior fires (never wedges)" "$rc" "0"
grep -q -- 'feed post .*Argued past 3 stop blocks.*--blocked' "$AGENTS_STUB_LOG" \
  && echo "ok   - capped pass files the fail-loud feed post (via stub, never a real delivery)" \
  || { echo "FAIL - third argue-past fire did not file the --blocked feed post"; fail=1; }

# AP6. An honest, EVIDENCED wrap-up that happens to contain a listed phrase —
#      "nothing needs you" plus a merged-PR URL and quoted health output — must
#      pass the ramp (reviewer repro: phrase-only matching blocked it and then
#      filed a false --blocked feed post).
rc=$(FAKE_GH_STATE=MERGED run_hook "$T" "PR merged: https://github.com/acme/widgets/pull/42 and health check returned 200 OK. Nothing needs you." true)
check "argue-past: evidenced honest wrap-up passes the ramp" "$rc" "0"

# EW1. Errored ScheduleWakeup arm + watcher phrasing + open PR -> still blocks.
TE=$(mk_transcript create+monitor-err)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TE" "A ScheduleWakeup is set to re-invoke me when CI settles; the poller owns the merge." false)
check "errored watcher arm does not clear the open-PR gate" "$rc" "2"

# RP1. First-stop replay of the fe1b0f93 stand-down (not a retry) -> blocks.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "1.22.40 is already in flight as PR #2664, owned by two live sessions under RUSH-2639 — someone else's in-flight work, not mine to take. Nothing needs you." false)
check "stand-down deferral to unverified sessions does not escape the open-PR gate" "$rc" "2"

# --- Ownership-is-absolute (RUSH-3013): conflicts are never hand-backable; ------
# --- the only non-merge exit is an owner-only gate with a checked receipt. ------

# OWN1. Conflict-shaped handoff never clears the open-PR gate, even with the
#       accepted handoff phrase present.
T=$(mk_transcript create)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Handing this off — merge conflicts with main need resolving before this can land." false)
check "ownership: conflict-shaped handoff still blocks" "$rc" "2"
grep -q "This PR is YOURS" "$SANDBOX/stderr" && echo "ok   - ownership-first message present" || { echo "FAIL - ownership message missing"; fail=1; }

# OWN2. HANDOFF sentinel without any receipt: prose alone never passes.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "HANDOFF: the owner — approval only they can grant." false)
check "ownership: HANDOFF line without receipt blocks" "$rc" "2"

# OWN3. HANDOFF sentinel + --blocked feed receipt on disk -> owner-gated pass.
FAKEHOME="$SANDBOX/home"
SID="fixture-$(printf '%s' "$T" | sha256sum | cut -c1-16)"
mkdir -p "$FAKEHOME/.agents/.history/feed"
printf '{"blocked":true}' > "$FAKEHOME/.agents/.history/feed/block-${SID}.json"
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN run_hook "$T" "HANDOFF: the owner — repo policy gate only they can clear; ask filed via feed post --blocked." false)
check "ownership: HANDOFF + --blocked receipt passes (owner-gated)" "$rc" "0"

# OWN4. A receipt cannot launder an agent-fixable state: conflict reason still blocks.
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN run_hook "$T" "HANDOFF: the owner — merge conflicts with main; please resolve them." false)
check "ownership: receipt cannot launder a conflict handback" "$rc" "2"

# OWN5. Biometric owner-only gate WITH the filed receipt -> allow (4c's pair).
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is blocked on your Touch ID to sign the release; ask filed via feed post --blocked. HANDOFF: the owner — Touch ID signing, feed block record filed." false)
check "ownership: biometric gate + --blocked receipt allows stop" "$rc" "0"

# OWN6. Reviewer repro: HONEST resolved-state narration must not trip the
#       agent_fixable veto — 'fixed the failing tests and resolved merge
#       conflicts' is completed work, and the receipted handoff still passes.
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN run_hook "$T" "Fixed the failing tests and resolved merge conflicts with main; CI is green and docs are written. Ask filed via feed post --blocked. HANDOFF: the owner — repo policy gate only they can clear." false)
check "ownership: resolved-state narration does not trip the fixable veto" "$rc" "0"

# OWN7. Mixed sentence: resolution verb in one sentence does not launder a
#       LIVE blocker stated in another.
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN run_hook "$T" "Resolved the lint errors. There are still merge conflicts with main. HANDOFF: the owner — please take it from here." false)
check "ownership: live conflict in its own sentence still blocks" "$rc" "2"

exit $fail
