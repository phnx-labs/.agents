#!/usr/bin/env bash
# Tests for 00-agent-verify-work-complete.sh. The hook decides only on facts:
#
#   open-pr      an owned PR is still OPEN and no durable watcher, filed
#                --blocked receipt, or payload plan mode covers it
#   live-team    RUNNING teammates with nothing armed to re-invoke the agent
#   keep-moving  unfinished checklist items with no durable watcher, no
#                AskUserQuestion/ExitPlanMode as the last tool, no plan mode
#   delivery     a done-claim or PR finish line on a session with delivery
#                evidence that has not closed the Linear/docs/release loop
#
# Prose in the final message (handoffs, blockers, parking, stand-downs) never
# clears or trips a check; the removal pins below assert exactly that.
#
# Fixtures use the REAL Claude Code transcript shape: tool_use blocks (with
# the command) paired to tool_result blocks (with the PR URL) by tool_use_id.
# gh, git, and linear are stubbed via a PATH shim so no network is touched.

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../lib/test-sqlite.sh
. "$HERE/../../lib/test-sqlite.sh"
HOOK="$HERE/../00-agent-verify-work-complete.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export VERIFY_WORK_STATE_DB="$SANDBOX/verify-work-state.db"

# --- gh stub ---------------------------------------------------------------
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal gh stub. `gh pr view --json state,mergeable,statusCheckRollup` is the
# open-PR probe (FAKE_GH_STATE / FAKE_GH_MERGEABLE / FAKE_GH_CHECKS);
# `gh pr view --json title,body,headRefName` is used by the delivery gate.
case "$*" in
  *state,mergeable,statusCheckRollup*)
    # The open-PR probe: live state plus the conflict / red-check facts a
    # --blocked receipt may never cover.
    case "$*" in *pull/99*) st=OPEN ;; *) st="${FAKE_GH_STATE:-OPEN}" ;; esac
    printf '{"state":"%s","mergeable":"%s","statusCheckRollup":%s}\n' \
      "$st" "${FAKE_GH_MERGEABLE:-MERGEABLE}" "${FAKE_GH_CHECKS:-[]}" ;;
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
# No check posts to the feed any more, but keep a logging stub on PATH so a
# regression that shells out to `agents` can never reach a real owner feed
# (RUSH-3010: an earlier test run delivered real iMessages that way).
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${AGENTS_STUB_LOG:?}"
STUB
chmod +x "$SANDBOX/bin/agents"
export AGENTS_STUB_LOG="$SANDBOX/agents.log"
: > "$AGENTS_STUB_LOG"

export PATH="$SANDBOX/bin:$PATH"

# Fixture session cwd. The hook input's `cwd` is what the delivery chain uses
# to resolve a repo when the transcript carries no directory hints — never the
# test runner's own cwd, so the suite gives the same result from any directory.
FIXTURE_CWD_REPO="$SANDBOX/cwdrepo"
mkdir -p "$FIXTURE_CWD_REPO/.git"
export FIXTURE_CWD_REPO

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
      create|create+view|create+watch|create+nativemon|create+monitor|create+monitor-err|create+dispatch|create+dispatch+monarm|create+dispatch+amoff|create+grepdispatch)
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
      create+dispatch|create+dispatch+monarm|create+dispatch+amoff)
        # The session DISPATCHED a child agent (dispatch-shaped: --no-follow).
        # The f045b577 failure shape: dispatch, then stop on the word "handoff".
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_disp1","name":"Bash","input":{"command":"agents run claude \"Mission: finish PR 42\" --mode auto --name widget-child --timeout 120m --no-follow"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_disp1","content":[{"type":"text","text":"[agents] running claude@2.1.217 (session child01)"}]}]}}'
        ;;
    esac
    case "$1" in
      create+dispatch+monarm)
        # Dispatch AND the child PR handed to GitHub auto-merge — the recipe
        # the block message teaches. Non-error result required.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_monarm1","name":"Bash","input":{"command":"agents projects prs automerge widgets --repo acme/widgets --number 42 --sha abc123"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_monarm1","content":[{"type":"text","text":"auto-merge enabled"}]}]}}'
        ;;
      create+dispatch+amoff)
        # Auto-merge turned OFF is the opposite of a handoff.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_amoff1","name":"Bash","input":{"command":"agents projects prs automerge widgets --repo acme/widgets --number 42 --off"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_amoff1","content":[{"type":"text","text":"auto-merge disabled"}]}]}}'
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
    case "$1" in
      liveteam|liveteam+tick)
        # RUSH-3022 (515b71e1): an edit-mode team is up and a REAL status probe
        # showed RUNNING teammates; a tick notification (the wake) then arrives.
        # The +tick variant re-arms a fresh background tick after that wake.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_lt1","name":"Bash","input":{"command":"agents teams start resume-cli --watch"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_lt1","content":[{"type":"text","text":"team started"}]}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_lts1","name":"Bash","input":{"command":"agents teams status resume-cli 2>&1 | head -20"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_lts1","content":[{"type":"text","text":"Team resume-cli  (2 working, 1 done, 0 failed, 0 stopped)\n  apicleanup  (711859e5)  RUNNING - 6.3 minutes - 94 tools\n  artifacts   (cfde0b82)  RUNNING - 5.7 minutes - 12 tools"}]}]}}'
        echo '{"type":"user","message":{"role":"user","content":"<task-notification>\n<task-id>bgtick1</task-id>\n<status>completed</status>\n<summary>Background command Tick-1 completed (exit code 0)</summary>\n</task-notification>"}}'
        ;;
      grepstatus)
        # RUSH-3022 false-positive pin: the status/RUNNING markers appear ONLY
        # inside grep patterns and their output — never a real invocation.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_gs1","name":"Bash","input":{"command":"grep -cE \"agents teams status|agents teams start\" /tmp/transcript.jsonl"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_gs1","content":[{"type":"text","text":"7"}]}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_gs2","name":"Bash","input":{"command":"grep -A2 RUNNING /tmp/transcript.jsonl | head -5"}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_gs2","content":[{"type":"text","text":"  apicleanup  (711859e5)  RUNNING - 6.3 minutes - 94 tools"}]}]}}'
        ;;
    esac
    case "$1" in
      liveteam+tick)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_lt2","name":"Bash","input":{"command":"sleep 300; agents teams status resume-cli; echo TICK done","run_in_background":true}}]}}'
        echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_lt2","content":[{"type":"text","text":"Command running in background with ID: bgtick2. Output is being written to: /tmp/tasks/bgtick2.output. You will be notified when it completes."}]}]}}'
        ;;
    esac
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 2"}]}}'
    echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"step 3"}]}}'
  } > "$t"
  echo "$t"
}

run_hook() {   # $1 transcript, $2 last message, $3 stop_hook_active, [$4 permission_mode]
  python3 - "$1" "$2" "$3" "${4:-}" <<'PY' | bash "$HOOK" >/dev/null 2>"$SANDBOX/stderr"
import hashlib, json, os, sys
fixture_id = "fixture-" + hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16]
payload = {
    "session_id": fixture_id,
    "launch_id": fixture_id,
    "agent": "claude",
    "transcript_path": sys.argv[1],
    "cwd": os.environ["FIXTURE_CWD_REPO"],
    "last_assistant_message": sys.argv[2],
    "stop_hook_active": sys.argv[3] == "true",
}
if sys.argv[4]:
    payload["permission_mode"] = sys.argv[4]
if os.environ.get("FIXTURE_BG_TASKS"):
    payload["background_tasks"] = json.loads(os.environ["FIXTURE_BG_TASKS"])
print(json.dumps(payload))
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

# 3. Created PR, OPEN, a prose handoff in the final message -> still blocks.
#    Naming an owner in prose is not a fact; only a watcher/receipt/plan mode is.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is handed off to the release watcher, which owns the PR from here." false)
check "open PR with a prose-only handoff blocks" "$rc" "2"

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
grep -qi "agents projects prs automerge" "$SANDBOX/stderr" && echo "ok   - block message names the watcher recipe" || { echo "FAIL - block message omits the watcher recipe"; fail=1; }

# D2. Same dispatch but a successful `agents projects prs automerge` -> allow.
#     Also locks in automerge counting as durable watcher evidence at all.
TDM=$(mk_transcript create+dispatch+monarm)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TDM" "PR #42 is handed to GitHub auto-merge, which owns the PR from here." false)
check "dispatch + enabled automerge allows stop" "$rc" "0"

# D2b. `automerge --off` disarms auto-merge, so it is not watcher evidence.
TDO=$(mk_transcript create+dispatch+amoff)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TDO" "PR #42 is handed to GitHub auto-merge, which owns the PR from here." false)
check "dispatch + automerge --off still blocks" "$rc" "2"

# D3. Dispatch marker only inside a grep pattern -> NOT a dispatch, so the
#     block carries no dispatch recipe (command-position anchor).
TDG=$(mk_transcript create+grepdispatch)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TDG" "Waiting on CI for PR #42." false)
check "grep FOR dispatch markers still blocks the open PR" "$rc" "2"
grep -qi "you own what you spawn" "$SANDBOX/stderr" && { echo "FAIL - grep FOR dispatch markers counted as a dispatch"; fail=1; } || echo "ok   - grep FOR dispatch markers is not a dispatch"

# 4b2. REGRESSION (RUSH-2394): blocked-on + in-process gh pr checks --watch is NOT durable.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is blocked on CI — watcher: background gh pr checks --watch will finish it." false)
check "external blocker + in-process gh pr checks --watch still blocks (RUSH-2394)" "$rc" "2"

# 4c. Open PR blocked on a pending user action (Touch ID / review) WITHOUT a
#     filed --blocked receipt -> block. An owner-only gate is real, but a
#     hand-back that never reached the owner's feed/phone is a silent stop
#     (RUSH-3013 ownership directive); the receipt-pass variant is OWN3 below.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is blocked on your Touch ID to sign the release; awaiting your merge." false)
check "owner-targeted stop without a filed receipt blocks" "$rc" "2"

# 4d. Former phrase escapes no longer clear an open PR. Every message below
#     passed (exit 0) under the phrase-matching gate; none carries a fact.
for prose in \
  "PR #42 is blocked on a GitHub Actions 503 outage failing CI — a ScheduleWakeup will merge on green when CI recovers." \
  "PR #42 is open but I cannot push or merge it — plan mode forbids that right now." \
  "PR #42 CI is green but the reviewer is down. Handed off to the code-review session, which owns the PR from here." \
  "Not idling — the poller owns the merge and re-invokes me on green." \
  "Owner-gated: only the owner can approve the branch policy." ; do
  rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "$prose" false)
  check "prose escape no longer clears an open PR: ${prose:0:48}" "$rc" "2"
done

# 5. stop_hook_active -> allow (no loops)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "still waiting" true)
check "stop_hook_active bypasses gate" "$rc" "0"

# 6. PR URL mentioned but session never ran pr create (review-only) -> allow
T2=$(mk_transcript review)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T2" "Review finished, feedback posted." false)
check "reviewing someone else's PR does not block" "$rc" "0"

# 6a. Positive non-code outcomes must not be converted into code delivery merely
# because their final message makes a done-claim inside a Git cwd.
TBROWSER=$(mk_transcript browser)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TBROWSER" "All done. The external app record is present and the screenshot verifies it." false)
check "browser-only completion does not trigger code delivery" "$rc" "0"

TRESEARCH=$(mk_transcript research)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TRESEARCH" "All done. The diagnostic found the parser boundary and cited the source." false)
check "read-only diagnostic completion does not trigger code delivery" "$rc" "0"

TTICKET=$(mk_transcript ticket-create)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TTICKET" "All done. The requested implementation ticket is open with full context." false)
check "ticket creation does not demand closing the requested ticket" "$rc" "0"

TREVIEW=$(mk_transcript review-submit)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TREVIEW" "All done. I submitted the review; the author's PR remains open." false)
check "review-only completion does not inherit merge ownership" "$rc" "0"

# 6b. A tracked repository write is positive delivery evidence even without a
# PR (D8c below drives a done-claim on it into the delivery chain).
TWRITE=$(mk_transcript repo-write)

# 7. Session created pull/42 (merged) AND viewed someone else's pull/99 (open)
#    -> allow: the viewed PR must not be attributed to this session
T3=$(mk_transcript create+view)
rc=$(FAKE_GH_STATE=MERGED run_hook "$T3" "My PR is merged; review of #99 posted." false)
check "mixed create+review only gates the created PR" "$rc" "0"

# 8. Done-claim with a merged PR and a clean delivery chain -> allow. The
#    generic self-audit ("re-check every ask") that used to block every
#    done-claim is gone; only the delivery chain's concrete demands remain.
rc=$(FAKE_GH_STATE=MERGED run_hook "$T" "All done. The widget feature is merged." false)
check "done-claim with a clean delivery chain allows stop" "$rc" "0"
grep -qi "you claimed this work is done" "$SANDBOX/stderr" && { echo "FAIL - self-audit message still emitted"; fail=1; } || echo "ok   - no self-audit message"
if grep -qiE "syntax error|command substitution" "$SANDBOX/stderr"; then echo "FAIL - hook emits a shell syntax error"; fail=1; else echo "ok   - no shell syntax error on the done-claim path"; fi

# --- removed phrase-triggered checks (swarm) --------------------------------
# The swarm integration check fired on wrap-up phrasing alone and was never
# scored. A swarm session's completion wording must no longer block.
TS=$(mk_transcript swarm)
rc=$(FAKE_GH_STATE=MERGED run_hook "$TS" "The factory work you asked for is done and merged. All three tracks landed end-to-end." false)
check "swarm wrap-up phrasing no longer blocks" "$rc" "0"
grep -q "edit-mode swarm" "$SANDBOX/stderr" && { echo "FAIL - swarm check still fires"; fail=1; } || echo "ok   - no swarm check message"

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

# --- removed phrase-triggered checks (parking / stand-down) -----------------
# Parking ('want me to…', 'on your go') and stand-down ('not mine to drive',
# 'standing clear') idioms routed into the self-audit block by wording alone.
# With no fact behind them they must no longer block.
TP=$(mk_transcript plain)
for prose in \
  "Want me to build the current main into a .vsix and install it? I can do it on your go." \
  "Should I proceed with releasing the build now?" \
  "I've got the disposition clear: #1642 is yours, not mine to drive. I'm standing clear." \
  "The other session can take it from here — handing it back and standing down." ; do
  rc=$(FAKE_GH_STATE=OPEN run_hook "$TP" "$prose" false)
  check "parking/stand-down prose no longer blocks: ${prose:0:40}" "$rc" "0"
done

TSHORT="$SANDBOX/short.jsonl"
{
  echo '{"type":"user","message":{"role":"user","content":"Can you look at the config and tell me if it is valid?"}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Looking"}]}}'
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"It is valid."}]}}'
} > "$TSHORT"

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

# D8c. session_cwd is the SOLE repo resolver (RUSH-3016, review SHOULD): the
#      repo-write transcript carries no cd / git -C / --repo command and no
#      repo_path hint, so the transcript scan yields nothing — only the hook
#      input's cwd (FIXTURE_CWD_REPO, injected by run_hook) can resolve the
#      repo. Deleting the session_cwd branch in _find_repo_path must fail this.
rc=$(FAKE_GIT_BRANCH=feature/RUSH-1234 FAKE_LINEAR_STATE=Todo run_hook "$TWRITE" "All done. The widget is complete." false)
check "session-cwd-only repo resolution reaches the delivery gate" "$rc" "2"
grep -q "close out the delivery" "$SANDBOX/stderr" && echo "ok   - delivery gate fired via session cwd alone" || { echo "FAIL - delivery gate not reached via session cwd alone"; fail=1; }

# D9. Probe error (linear crashes/returns garbage) -> fail open.
cat > "$SANDBOX/bin/linear" <<'STUB'
#!/usr/bin/env bash
echo "garbage"
exit 1
STUB
chmod +x "$SANDBOX/bin/linear"
rc=$(FAKE_GH_STATE=MERGED FAKE_GIT_BRANCH=feature/RUSH-1234 run_hook "$TD" "All done. The widget is merged." false)
check "linear probe error fails open (allows stop)" "$rc" "0"
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
#      wording — a `git merge` sets delivery_activity and "Merged." supplies the
#      finish-line phrase, so the delivery gate itself runs; the only thing
#      pointing at RUSH-7777 is the read command, so it must not fire. Mirrors
#      the existing `gh pr view` (VIEW is not WORK) distinction above.
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

# --- removed phrase-triggered checks (command handback) ----------------------
# The handback check matched 'run it' prose after a /tmp script write; it went
# 0 for 4 on its own measured demand. It must no longer block.
THB=$(mk_transcript handback)
rc=$(FAKE_GH_STATE=MERGED run_hook "$THB" "I've prepared the release at /tmp/release-1.20.82.sh — run it when ready for a single paste." false)
check "temp-script 'run it' prose no longer blocks" "$rc" "0"
grep -q "runnable script" "$SANDBOX/stderr" && { echo "FAIL - handback check still fires"; fail=1; } || echo "ok   - no handback check message"

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

# --- plan mode is read from the Stop payload, never the prose ----------------
# P1. permission_mode=plan in the payload: the agent cannot push/merge -> allow.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 CI is still running." false plan)
check "payload permission_mode=plan allows stop on an open PR" "$rc" "0"

# P1b. Any other mode, plus plan-mode prose -> still blocks (wording is not mode).
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "PR #42 is open but plan mode forbids merging." false default)
check "plan-mode prose under a non-plan payload mode still blocks" "$rc" "2"

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
# with pending / in_progress items blocks unless a FACT covers it: a durable
# watcher armed this session, AskUserQuestion/ExitPlanMode as the last tool, or
# permission_mode=plan in the payload. Questions, handoffs, and blockers in
# prose do not clear it.
#
# Fixtures build the real Claude tool_use shape for the checklist tools
# (TaskCreate / TaskUpdate, and the snapshot TodoWrite). No PR is created, so
# ONLY this gate can fire.
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
      ask-remaining)
        # one item left and the agent's LAST tool call asked the user.
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"aq1","name":"AskUserQuestion","input":{"questions":[{"question":"Tabs or spaces?"}]}}]}}'
        ;;
      exitplan-remaining)
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"TaskUpdate","input":{"taskId":"1","status":"completed"}}]}}'
        echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"ep1","name":"ExitPlanMode","input":{"plan":"wire it up"}}]}}'
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

# E3. Pending checklist + a question asked only in PROSE -> still blocks; the
#     question has to go through AskUserQuestion to be a structural handoff.
rc=$(run_hook "$TK" "The parser is written. Which layout should the wiring use, tabs or spaces?" false)
check "pending checklist + prose-only question blocks" "$rc" "2"

# E4. Pending checklist + AskUserQuestion as the last tool call -> allow.
TKA=$(mk_tasks ask-remaining)
rc=$(run_hook "$TKA" "Asked which layout to use." false)
check "pending checklist + AskUserQuestion last tool allows stop" "$rc" "0"

# E5. Pending checklist + ExitPlanMode as the last tool call -> allow.
TKP=$(mk_tasks exitplan-remaining)
rc=$(run_hook "$TKP" "Plan presented for approval." false)
check "pending checklist + ExitPlanMode last tool allows stop" "$rc" "0"

# E5b. Pending checklist + payload permission_mode=plan -> allow.
rc=$(run_hook "$TK" "The parser is written." false plan)
check "pending checklist + payload plan mode allows stop" "$rc" "0"

# E5c. Pending checklist + prose handoff / blocker -> still blocks.
rc=$(run_hook "$TK" "Parser written; the ui session takes over from here and owns the task. Wiring is blocked on your Touch ID." false)
check "pending checklist + prose handoff/blocker still blocks" "$rc" "2"

# E6. Pending checklist + a durable ScheduleWakeup armed -> allow (RUSH-2394).
TKW=$(mk_tasks watcher-remaining)
rc=$(run_hook "$TKW" "Wiring is next." false)
check "pending checklist + durable ScheduleWakeup armed allows stop" "$rc" "0"

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

# --- loop protection: a retried stop always passes ---------------------------
# The argue-past ramp re-blocked retries by phrase and was never measured. A
# retry (stop_hook_active=true) now passes whatever it says.
T=$(mk_transcript create)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Merged, not released — and that's the correct stopping point, not a gap." true)
check "retry restating a former stand-down phrase passes" "$rc" "0"
grep -q "stand-down phrase" "$SANDBOX/stderr" && { echo "FAIL - argue-past ramp still fires"; fail=1; } || echo "ok   - no argue-past message"

# EW1. Errored ScheduleWakeup arm + watcher phrasing + open PR -> still blocks.
TE=$(mk_transcript create+monitor-err)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TE" "A ScheduleWakeup is set to re-invoke me when CI settles; the poller owns the merge." false)
check "errored watcher arm does not clear the open-PR gate" "$rc" "2"

# RP1. First-stop replay of the fe1b0f93 stand-down (not a retry) -> blocks.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "1.22.40 is already in flight as PR #2664, owned by two live sessions under RUSH-2639 — someone else's in-flight work, not mine to take. Nothing needs you." false)
check "stand-down deferral to unverified sessions does not escape the open-PR gate" "$rc" "2"


# --- live-team tick gate (RUSH-3022) -----------------------------------------
# An orchestrator with RUNNING teammates may not stop unless a fresh background
# tick was armed THIS turn (after the last wake) or a durable watcher exists.
# Session 515b71e1 recapped through five ticks, deferred to --watch loops that
# can never fire on a single merge, and let the chain die.

# LT1. Live team + recap-park final message + no tick armed after the wake -> block.
TLT=$(mk_transcript liveteam)
rc=$(run_hook "$TLT" "Nothing needs my intervention — the teammates own their merges. I'll surface on the next real event (a merge) rather than another status recap." false)
check "live team with no fresh tick blocks" "$rc" "2"
grep -q "RUNNING teammates" "$SANDBOX/stderr" && echo "ok   - live-team gate teaches the tick recipe" || { echo "FAIL - no live-team gate message"; fail=1; }

# LT2. Live team + a background tick armed THIS turn (after the wake) -> allow.
TLTT=$(mk_transcript liveteam+tick)
rc=$(run_hook "$TLTT" "Tick armed for ~5 min; apicleanup and artifacts still RUNNING. On the next wake I merge whatever is green." false)
check "live team with a fresh tick armed this turn allows stop" "$rc" "0"

# LT3. Status/RUNNING markers only inside grep patterns and their output -> the
#      live-team gate must NOT fire (same false-positive class as grepteams).
TGS=$(mk_transcript grepstatus)
rc=$(run_hook "$TGS" "Search finished; no live teams found in that transcript." false)
check "grep FOR status markers does not trip the live-team gate" "$rc" "0"
grep -q "RUNNING teammates" "$SANDBOX/stderr" && { echo "FAIL - live-team gate false-fired on a grep"; fail=1; } || echo "ok   - no live-team gate on a search-only session"

# --- Owned open PR: prose HANDOFF vs an on-disk --blocked receipt ------------

# OWN1. Conflict-shaped handoff never clears the open-PR gate.
T=$(mk_transcript create)
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "Handing this off — merge conflicts with main need resolving before this can land." false)
check "ownership: conflict-shaped handoff still blocks" "$rc" "2"
grep -q "This PR is YOURS" "$SANDBOX/stderr" && echo "ok   - ownership-first message present" || { echo "FAIL - ownership message missing"; fail=1; }
grep -q "feed post" "$SANDBOX/stderr" && echo "ok   - block names the --blocked receipt as the owner-only exit" || { echo "FAIL - block omits the receipt exit"; fail=1; }

# OWN2. An owned open PR with only a prose HANDOFF line and no watcher or
#       receipt -> blocks. The sentinel line is prose, not a fact.
rc=$(FAKE_GH_STATE=OPEN run_hook "$T" "HANDOFF: the owner — approval only they can grant." false)
check "ownership: HANDOFF line without receipt blocks" "$rc" "2"

# OWN3. The same open PR with a --blocked feed receipt on disk for THIS
#       session -> passes, whatever the final message says.
FAKEHOME="$SANDBOX/home"
SID="fixture-$(printf '%s' "$T" | sha256sum | cut -c1-16)"
mkdir -p "$FAKEHOME/.agents/.history/feed"
printf '{"blocked":true}' > "$FAKEHOME/.agents/.history/feed/block-${SID}.json"
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN run_hook "$T" "HANDOFF: the owner — approval only they can grant." false)
check "ownership: --blocked receipt on disk passes the open PR" "$rc" "0"
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN run_hook "$T" "Waiting for approval." false)
check "ownership: receipt passes without any HANDOFF wording" "$rc" "0"

# OWN4. A receipt filed by a DIFFERENT session does not cover this one.
TOTHER=$(mk_transcript create)
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN run_hook "$TOTHER" "HANDOFF: the owner — approval only they can grant." false)
check "ownership: another session's receipt does not cover this PR" "$rc" "2"

# --- done-claim matching: a list ending in '; done.' is not a claim -----------
# The bare 'done.' entry matched inside list items and drove repo-mutating
# sessions into the delivery chain. The setup below blocks on an open ticket
# the moment a real done-claim is made (positive control), so the list case
# proves it is the matcher, not the setup, that changed.
TLIST=$(mk_transcript repo-write)
rc=$(FAKE_GIT_BRANCH=feature/RUSH-1234 FAKE_LINEAR_STATE=Todo run_hook "$TLIST" "Status:
- parser: written; done.
- wiring: written; done!" false)
check "a list ending '; done.' triggers nothing" "$rc" "0"
[ -s "$SANDBOX/stderr" ] && { echo "FAIL - '; done.' list produced block text"; fail=1; } || echo "ok   - '; done.' list produces no block text"
rc=$(FAKE_GIT_BRANCH=feature/RUSH-1234 FAKE_LINEAR_STATE=Todo run_hook "$TLIST" "All done. The widget is complete." false)
check "positive control: a real done-claim on the same setup reaches the delivery chain" "$rc" "2"
grep -q "close out the delivery" "$SANDBOX/stderr" && echo "ok   - positive control hit the delivery chain" || { echo "FAIL - positive control did not reach the delivery chain"; fail=1; }
rc=$(FAKE_GIT_BRANCH=feature/RUSH-1234 FAKE_LINEAR_STATE=Todo run_hook "$TLIST" "Overall done-ness is tracked in the ticket; the widget is half built." false)
check "done-claim phrases match on word boundaries only" "$rc" "0"

# OWN5. A receipt never covers agent-fixable facts: an owned open PR whose
#       mergeable state is CONFLICTING still blocks with the receipt on disk,
#       and the block says conflicts are the agent's own work.
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN FAKE_GH_MERGEABLE=CONFLICTING run_hook "$T" "Waiting for approval." false)
check "ownership: receipt does not clear a CONFLICTING PR" "$rc" "2"
grep -q "your own work" "$SANDBOX/stderr" && echo "ok   - conflict block names the work as the agent's" || { echo "FAIL - conflict block message missing"; fail=1; }

# OWN6. Same for red checks (a failed CheckRun or an errored status context).
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN FAKE_GH_CHECKS='[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"}]' run_hook "$T" "Waiting for approval." false)
check "ownership: receipt does not clear a PR with a failing check" "$rc" "2"
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN FAKE_GH_CHECKS='[{"context":"ci/legacy","state":"ERROR"}]' run_hook "$T" "Waiting for approval." false)
check "ownership: receipt does not clear a PR with an errored status" "$rc" "2"

# OWN7. Green, mergeable checks with the receipt -> still passes.
rc=$(HOME="$FAKEHOME" FAKE_GH_STATE=OPEN FAKE_GH_CHECKS='[{"name":"test","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"lint","status":"IN_PROGRESS","conclusion":""}]' run_hook "$T" "Waiting for approval." false)
check "ownership: receipt clears a mergeable PR with green or pending checks" "$rc" "0"

# --- watcher freshness: only a watcher armed for the CURRENT goal counts -----
# The goal boundary is the byte offset verify-work-state.py records when the
# owner sends a message. A watcher armed before that message covered the old
# ask, not this one.
STATE_PY="$HERE/../verify-work-state.py"
record_boundary() {   # $1 transcript — record an owner prompt at its current end
  python3 - "$1" <<'PY' | python3 "$STATE_PY" record-prompt >/dev/null
import hashlib, json, sys
fid = "fixture-" + hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16]
print(json.dumps({"session_id": fid, "launch_id": fid, "agent": "claude",
                  "prompt": "new ask", "transcript_path": sys.argv[1]}))
PY
}
arm_wakeup() {   # $1 transcript, $2 id — append a successfully armed ScheduleWakeup
  echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"'"$2"'","name":"ScheduleWakeup","input":{"delaySeconds":300,"reason":"re-check CI"}}]}}' >> "$1"
  echo '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"'"$2"'","content":[{"type":"text","text":"wakeup scheduled"}]}]}}' >> "$1"
}

# WF1. Open PR, watcher armed BEFORE the owner's latest message -> blocks.
# The first stop (before the new message) passes on that watcher and records
# the PR in the session-owned ledger, which is how ownership survives a prompt.
TWF=$(mk_transcript create+monitor)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TWF" "Watcher armed; waiting on CI." false)
check "open PR + watcher armed for the current goal passes" "$rc" "0"
record_boundary "$TWF"
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"on it"}]}}' >> "$TWF"
rc=$(FAKE_GH_STATE=OPEN run_hook "$TWF" "Still waiting on CI." false)
check "open PR + watcher armed before the latest owner message blocks" "$rc" "2"

# WF2. Same PR, watcher re-armed AFTER that message -> passes.
arm_wakeup "$TWF" toolu_wf2
rc=$(FAKE_GH_STATE=OPEN run_hook "$TWF" "Still waiting on CI." false)
check "open PR + watcher armed after the latest owner message passes" "$rc" "0"

# BG1-3. Interactive sessions: running background_tasks in the Stop payload are a
# durable watcher (the harness re-invokes the agent when they finish). Headless runs
# stay excluded (RUSH-2394), and an empty list is no watcher.
TBG=$(mk_transcript create)
rc=$(CLAUDE_CODE_ENTRYPOINT=cli FIXTURE_BG_TASKS='[{"id":"b1","status":"running"}]' FAKE_GH_STATE=OPEN run_hook "$TBG" "Merge waiter running in the background." false)
check "interactive + open PR + running background task passes" "$rc" "0"
rc=$(CLAUDE_CODE_ENTRYPOINT=sdk-cli FIXTURE_BG_TASKS='[{"id":"b1","status":"running"}]' FAKE_GH_STATE=OPEN run_hook "$TBG" "Merge waiter running in the background." false)
check "headless + open PR + background task still blocks" "$rc" "2"
rc=$(CLAUDE_CODE_ENTRYPOINT=cli FIXTURE_BG_TASKS='[]' FAKE_GH_STATE=OPEN run_hook "$TBG" "Nothing running." false)
check "interactive + open PR + empty background_tasks still blocks" "$rc" "2"
rc=$(CLAUDE_CODE_ENTRYPOINT=cli FIXTURE_BG_TASKS='[{"id":"b1","status":"running"}]' FAKE_GH_STATE=OPEN FAKE_GH_MERGEABLE=CONFLICTING run_hook "$TBG" "Waiting on a background job." false)
check "interactive + running background task does not excuse a CONFLICTING PR" "$rc" "2"
grep -q "conflicts or failing checks" "$SANDBOX/stderr" && echo "ok   - conflicting-PR message names the agent's own work" || { echo "FAIL - conflicting-PR message missing"; fail=1; }

# WF3. Keep-moving: a pre-boundary watcher no longer covers unfinished items.
TKF=$(mk_tasks watcher-remaining)
record_boundary "$TKF"
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"on it"}]}}' >> "$TKF"
rc=$(run_hook "$TKF" "Wiring is next." false)
check "pending checklist + watcher armed before the latest owner message blocks" "$rc" "2"
grep -q "AskUserQuestion" "$SANDBOX/stderr" && { echo "FAIL - keep-moving message recommends AskUserQuestion"; fail=1; } || echo "ok   - keep-moving message does not recommend AskUserQuestion"
grep -q "feed post" "$SANDBOX/stderr" && echo "ok   - keep-moving message names the --blocked ask" || { echo "FAIL - keep-moving message omits the --blocked ask"; fail=1; }
arm_wakeup "$TKF" toolu_wf3
rc=$(run_hook "$TKF" "Wiring is next." false)
check "pending checklist + watcher armed after the latest owner message passes" "$rc" "0"

# WF4. Keep-moving: a --blocked receipt on disk for this session covers it.
TKR=$(mk_tasks one-remaining)
SIDK="fixture-$(printf '%s' "$TKR" | sha256sum | cut -c1-16)"
printf '{"blocked":true}' > "$FAKEHOME/.agents/.history/feed/block-${SIDK}.json"
rc=$(HOME="$FAKEHOME" run_hook "$TKR" "Wiring needs the owner's credential." false)
check "pending checklist + --blocked receipt passes" "$rc" "0"

# CAP1/CAP2. Identical-state cap (RUSH-3032 item a): with 2 prior fires in
# the transcript, the FIRST evaluation of a given state blocks; a SECOND
# evaluation of the byte-identical state (same transcript, same message —
# evidence hash unchanged in the state db) records identical-state-capped
# and passes. Fresh state db so decision history starts empty.
export VERIFY_WORK_STATE_DB="$SANDBOX/cap-state.db"
TCAPL=$(mk_looped 2)
rc=$(FAKE_GH_STATE=OPEN run_hook "$TCAPL" "CI is green, waiting for the reviewer." false)
check "identical-state: first evaluation still blocks" "$rc" "2"
rc=$(FAKE_GH_STATE=OPEN run_hook "$TCAPL" "CI is green, waiting for the reviewer." false)
check "identical-state: unchanged state after 2 fires is capped (passes)" "$rc" "0"
export VERIFY_WORK_STATE_DB="$SANDBOX/verify-work-state.db"

exit $fail
