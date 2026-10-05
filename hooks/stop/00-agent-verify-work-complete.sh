#!/usr/bin/env bash
set -euo pipefail

# General-purpose Stop hook: blocks a stop only on FACTS the transcript, the
# Stop payload, GitHub, or the disk can prove — never on how the final message
# is phrased.
#
#   open-pr      a PR this session created or drove is still OPEN, and no
#                fresh durable watcher, plan mode, or filed --blocked receipt
#                (only for a PR without conflicts or red checks) covers it
#   live-team    teammates are RUNNING and nothing is armed to re-invoke you
#   keep-moving  the session's own checklist has unfinished items, and no
#                fresh durable watcher, filed --blocked receipt, last-tool
#                ExitPlanMode/AskUserQuestion, or plan mode covers them
#   delivery     a done-claim (or PR/merge finish line) on a session with real
#                delivery evidence, checked by verify-delivery-chain.py
#
# Exit 0 = allow stop
# Exit 2 = block stop, stderr becomes feedback to the agent

HERE="$(cd "$(dirname "$0")" && pwd)"

# Portable timeout: macOS ships neither `timeout` nor `gtimeout` by default.
_to() {
  if command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  else shift; "$@"
  fi
}

INPUT_JSON=$(cat)

# Loop protection: a blocked Stop is retried with stop_hook_active=true. Every
# check fires at most once per stop, so the retry always passes (below).
stop_active=$(echo "$INPUT_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(str(data.get('stop_hook_active', False)).lower())
" 2>/dev/null || echo "false")

# Extract transcript path, session id, and permission mode from the payload.
eval "$(echo "$INPUT_JSON" | python3 -c "
import json, sys, shlex
data = json.load(sys.stdin)
print('TRANSCRIPT_PATH=' + shlex.quote(str(data.get('transcript_path') or '')))
print('SESSION_ID=' + shlex.quote(str(data.get('session_id') or '')))
print('PERMISSION_MODE=' + shlex.quote(str(data.get('permission_mode') or data.get('permissionMode') or '')))
" 2>/dev/null)"

# No transcript — edge case, allow
if [ -z "${TRANSCRIPT_PATH:-}" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# Materialize this hook's session-owned state during the Stop invocation that
# already pays transcript-processing cost. Ordinary tool calls incur no new
# process or SQLite latency. State errors are guidance failures, never blockers.
state_eval=$(printf '%s' "$INPUT_JSON" | python3 "$HERE/verify-work-state.py" evaluate 2>/dev/null || echo '{}')
eval "$(printf '%s' "$state_eval" | python3 -c '
import json, shlex, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
print("STATE_DELIVERY_EVIDENCE=" + shlex.quote("yes" if data.get("delivery_evidence") is True else "no"))
print("STATE_GOAL_OFFSET=" + shlex.quote(str(data.get("transcript_offset") or 0)))
print("STATE_OWNED_PRS=" + shlex.quote("\n".join(str(value) for value in data.get("owned_prs", []))))
failed = bool(data.get("state_error")) or not isinstance(data.get("delivery_evidence"), bool)
print("STATE_EVAL_FAILED=" + shlex.quote("yes" if failed else "no"))
print("STATE_EVIDENCE_REPEAT=" + shlex.quote("yes" if data.get("evidence_repeat") is True else "no"))
' 2>/dev/null || printf '%s\n' 'STATE_DELIVERY_EVIDENCE=no' 'STATE_GOAL_OFFSET=0' 'STATE_OWNED_PRS=' 'STATE_EVAL_FAILED=yes' 'STATE_EVIDENCE_REPEAT=no')"

# --- check outcome recording ---------------------------------------------------
# Every check evaluation is recorded, not just the ones that block. Recording only
# blocks is why the events table held 325 rows and every single one read 'blocked':
# there was no denominator, so no check had a false-positive rate and no change to
# check logic could be shown to be an improvement.
#
# Batched deliberately. A stop evaluates many checks and most of them allow, but a
# bare `python3` start costs ~18ms before sqlite3 is even imported — a process per
# check would tax every stop on every machine for telemetry nobody reads in the
# moment. So callers accumulate and a single flush writes them through one
# connection on exit.
#
# Tradeoff, stated: a hard kill (SIGKILL, or the harness timing the hook out
# without a signal) loses the batch. That costs telemetry, never correctness — the
# block itself is the exit code, not the row.
CHECK_LOG=()

record_block() { # $1 check, $2 reason code  — blocked, the pre-existing contract
  CHECK_LOG+=("$1:blocked:$2")
}

record_check_ok() { # $1 check, $2 outcome (passed|skipped), $3 reason code
  CHECK_LOG+=("$1:$2:$3")
}

flush_check_log() {
  [ "${#CHECK_LOG[@]}" -eq 0 ] && return 0
  printf '%s' "$INPUT_JSON" | python3 "$HERE/verify-work-state.py" record-checks \
    ${CHECK_LOG[@]+"${CHECK_LOG[@]}"} >/dev/null 2>&1 || true
  CHECK_LOG=()
}
# EXIT flushes. INT/TERM must flush and then genuinely DIE: a signal handler that
# does not exit suppresses the signal's default terminate action, so the script
# would resume and run past the 20s timeout in agents.yaml. Reset the trap and
# re-raise so the process dies with the conventional 128+signal status.
trap flush_check_log EXIT
trap 'flush_check_log; trap - INT; kill -INT $$' INT
trap 'flush_check_log; trap - TERM; kill -TERM $$' TERM

# --- repeated-check guidance --------------------------------------------------
# Repeating the identical block text eventually stops adding information. On a
# 3rd+ matching fire, keep the proof standard unchanged but remind the agent to
# re-check live state and choose its own next tactic. Prior fires are read from
# the transcript and anchored to the injected 'Stop hook feedback:' prefix so a
# Read of this hook's source is never miscounted as a fire.
prior_fires() {   # $1 = a substring unique to the check's injected message
  python3 - "$TRANSCRIPT_PATH" "$1" <<'PY' 2>/dev/null || echo 0
import json, sys
path, marker = sys.argv[1], sys.argv[2]
n = 0
try:
    with open(path) as f:
        for raw in f:
            if 'Stop hook feedback' not in raw or marker not in raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            if rec.get('type') != 'user' or rec.get('isMeta') is not True:
                continue
            c = (rec.get('message') or {}).get('content')
            if isinstance(c, str) and c.startswith('Stop hook feedback:') and marker in c:
                n += 1
except Exception:
    pass
print(n)
PY
}

# Add lightweight strategy guidance when this check has already fired >=2 times
# this session on the same item (so this is the 3rd+). It supplements the normal
# block message and never weakens the check.
repeat_guidance() {   # $1 = human name of the repeated item, $2 = prior count
  local n="${2:-0}"
  [ "$n" -lt 2 ] && return 0
  cat >&2 <<GUIDANCE
NOTE — block $((n + 1)) this session for $1.
If this genuinely cannot move without the owner, file the ask
(agents feed post "<ask>" --blocked) — the filed record, not prose, is the receipt.
Otherwise the state must change before you stop again — re-explaining it will
not clear this check.

GUIDANCE
}
# --- end repeated-check guidance ---------------------------------------------

# Loop protection: a blocked Stop is retried with stop_hook_active=true. Every
# check below fires at most once per stop, so the retry passes unconditionally.
# The checks read facts, not wording, so there is nothing a retry could restate
# that would change a verdict.
if [ "$stop_active" = "true" ]; then
  exit 0
fi

# --- shared transcript facts -------------------------------------------------
# Computed lazily (at most once per stop) and only when a check needs them.
#
# Both facts read only the current goal's transcript suffix (from
# STATE_GOAL_OFFSET, the byte offset verify-work-state.py recorded at the
# owner's latest message): a watcher armed for an earlier ask does not cover
# the current one. With no recorded boundary the offset is 0 (whole transcript).
#
# BG_LIVE — in an INTERACTIVE session, the Stop payload lists in-flight
# background_tasks; the harness re-invokes the agent when they finish (see
# load_transcript_facts). Like a --blocked receipt it covers waiting, never a PR
# with conflicts or red checks. Headless runs are excluded (RUSH-2394).
#
# LIVE_WATCHER — a durable watcher was ARMED for this goal: a native
# ScheduleWakeup / Monitor tool_use (the harness owns the re-invoke) or an
# `agents monitors add` at a command position (the daemon owns the schedule),
# each counted only when its paired tool_result came back WITHOUT error —
# invoked is not armed. A background `gh pr checks --watch` is NOT durable: it
# is a child of the agent process tree and dies with a headless agent
# (RUSH-2394), so it never counts.
#
# LAST_STRUCT_TOOL — the name of the last tool_use in the transcript, so a stop
# that hands control to the user through AskUserQuestion / ExitPlanMode is
# recognized structurally rather than by a question mark in the prose.
transcript_facts() {
  python3 - "$TRANSCRIPT_PATH" "${STATE_GOAL_OFFSET:-0}" <<'PY' 2>/dev/null || echo "no -"
import json, re, sys
CMD_POS = r'(?:^|[\n;&]\s*|\$\(\s*)'
MONITORS_ADD = re.compile(CMD_POS + r'agents monitors add\b')
wake_ids = set()
ok_ids = set()
last_tool = ''
try:
    with open(sys.argv[1], 'rb') as f:
        f.seek(max(0, int(sys.argv[2] or 0)))
        for raw in f:
            raw = raw.decode('utf-8', 'replace')
            if 'tool_use' not in raw and 'tool_result' not in raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            m = rec.get('message') if isinstance(rec.get('message'), dict) else rec
            content = m.get('content') if isinstance(m, dict) else None
            if not isinstance(content, list):
                continue
            for b in content:
                if not isinstance(b, dict):
                    continue
                btype = b.get('type')
                if btype == 'tool_use':
                    name = b.get('name') or ''
                    last_tool = name
                    if name in ('ScheduleWakeup', 'Monitor'):
                        wake_ids.add(b.get('id') or '')
                    elif MONITORS_ADD.search(str((b.get('input') or {}).get('command', ''))):
                        wake_ids.add(b.get('id') or '')
                elif btype == 'tool_result' and not b.get('is_error'):
                    ok_ids.add(b.get('tool_use_id') or '')
    found = any(i for i in wake_ids if i in ok_ids)
    print('yes' if found else 'no', re.sub(r'\s+', '', last_tool) or '-')
except Exception:
    print('no -')
PY
}
LIVE_WATCHER=""
BG_LIVE="no"
LAST_STRUCT_TOOL=""
load_transcript_facts() {
  [ -n "$LIVE_WATCHER" ] && return 0
  local facts
  facts=$(transcript_facts)
  LIVE_WATCHER=${facts%% *}
  LAST_STRUCT_TOOL=${facts##* }
  [ "$LIVE_WATCHER" = "yes" ] || LIVE_WATCHER="no"
  # In an INTERACTIVE session the harness itself re-invokes the agent when a
  # background task finishes, so a non-empty `background_tasks` in the Stop payload
  # is a durable watcher there. Headless runs stay excluded: their background
  # children die with the agent process (RUSH-2394).
  BG_LIVE="no"
  if [ "${CLAUDE_CODE_ENTRYPOINT:-}" = "cli" ]; then
    if printf '%s' "$INPUT_JSON" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("background_tasks") else 1)' 2>/dev/null; then
      BG_LIVE="yes"
    fi
  fi
}

# A --blocked feed record filed by THIS session (`agents feed post --blocked`
# writes ~/.agents/.history/feed/block-<session_id>.json) is a verifiable
# receipt that a genuinely owner-only gate reached the owner. Checked on disk;
# prose never stands in for it.
block_receipt="no"
[ -n "${SESSION_ID:-}" ] && [ -f "$HOME/.agents/.history/feed/block-${SESSION_ID}.json" ] && block_receipt="yes"
# --- end shared transcript facts ---------------------------------------------

# --- Open-PR abandonment check ------------------------------------------------
# A session that CREATED *or actively WORKED* a pull request may not stop while
# any is still open. "PR open, waiting for reviewer" is not a stop state. The
# observed failure modes: (1) agents stopping WITHOUT claiming done ("waiting
# for CI/review") with stranded PRs they created, and (2) a session that
# INHERITED an open PR a prior session created, drove it (merge/review), then
# stopped with it unmerged.
#
# An open PR is covered — the stop passes — only by a fact:
#   - a durable watcher armed for the current goal (LIVE_WATCHER), which owns
#     the merge after this agent exits, or
#   - a --blocked feed receipt on disk for this session (block_receipt): the
#     owner-only gate was filed where the owner sees it. A receipt never covers
#     a PR whose mergeable state is CONFLICTING or whose checks are red — those
#     are the agent's own work — or
#   - the Stop payload's permission_mode is "plan" (the agent physically cannot
#     push or merge).
# What the final message says about handoffs, blockers, or plan mode is not read.
#
# A PR is attributed to THIS session two ways:
#   - CREATED: its URL appears in the tool_result of a tool_use whose command
#     ran `pr create` — paired by tool_use_id (the original precision guard).
#   - WORKED: a tool_use command OPERATED on the PR via
#     `gh pr merge|ready|rebase|close|reopen|edit <PR>`.
# A bare `gh pr view` is deliberately NOT a "worked" signal — reading someone
# else's PR is incidental; `view` only attributes a PR when the SAME PR is
# viewed 2+ times (active babysitting). So one incidental read of an unrelated
# PR never triggers the check. Fail-open: no gh, network down, parse errors —
# allow the stop.
responsible_prs=""
# Reads one `gh pr view --json state,mergeable,statusCheckRollup` document and
# prints "<STATE>[ conflicting][ red-checks]". A check is red when a CheckRun
# concluded FAILURE/ERROR/TIMED_OUT/CANCELLED or a StatusContext reads
# FAILURE/ERROR.
PR_FACTS_PY='
import json, sys
d = json.load(sys.stdin)
out = [str(d.get("state") or "")]
if str(d.get("mergeable") or "").upper() == "CONFLICTING":
    out.append("conflicting")
RED = {"FAILURE", "ERROR", "TIMED_OUT", "CANCELLED"}
for c in d.get("statusCheckRollup") or []:
    if not isinstance(c, dict):
        continue
    if str(c.get("conclusion") or "").upper() in RED or str(c.get("state") or "").upper() in {"FAILURE", "ERROR"}:
        out.append("red-checks")
        break
print(" ".join(out))
'
if command -v gh >/dev/null 2>&1; then
  responsible_prs=$(python3 -c "
import json, re, sys

PR_URL = re.compile(r'https://github\.com/[\w.-]+/[\w.-]+/pull/\d+')
# gh pr subcommands that DRIVE a PR toward merge = this session owns it, even if
# a PRIOR session created it. Observer verbs (checks/review/comment) and 'view'
# are deliberately excluded: a reviewer or CI-watcher who correctly stops with the
# ball in the author's court is not abandoning the PR. 'view' is handled below as a
# weak, repetition-checked signal.
WORK = re.compile(r'\bgh\s+pr\s+(?:merge|ready|rebase|close|reopen|edit)\b')
VIEW = re.compile(r'\bgh\s+pr\s+view\b')

def extract_ref(cmd):
    # The ref gh accepts for a state check: prefer a self-contained URL, else a
    # repo-qualified URL synthesized from --repo/-R + a number, else a bare
    # '#N' / positional number (never a --flag's value like --interval 30).
    m = PR_URL.search(cmd)
    if m:
        return m.group(0)
    tokens = cmd.split()
    repo = None
    number = None
    prev = None
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t.startswith('--repo='):
            repo = t.split('=', 1)[1]
            i += 1
            continue
        if t in ('--repo', '-R'):
            if i + 1 < len(tokens):
                repo = tokens[i + 1]
            i += 2
            continue
        if t.startswith('-R') and len(t) > 2:
            repo = t[2:]
            i += 1
            continue
        if t.startswith('#') and t[1:].isdigit():
            number = t[1:]
        elif t.isdigit() and (prev is None or not prev.startswith('-')):
            number = t
        prev = t
        i += 1
    if repo and number:
        return 'https://github.com/{}/pull/{}'.format(repo, number)
    return number

create_ids = set()
created = []
worked = []
views = {}
try:
    with open(sys.argv[1], 'rb') as f:
        f.seek(max(0, int(sys.argv[3])))
        for raw in f:
            raw = raw.decode('utf-8', 'replace')
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            msg = rec.get('message') if isinstance(rec.get('message'), dict) else rec
            content = msg.get('content')
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get('type') == 'tool_use':
                    cmd = str((block.get('input') or {}).get('command', ''))
                    if 'pr create' in cmd:
                        create_ids.add(block.get('id'))
                    if WORK.search(cmd):
                        r = extract_ref(cmd)
                        if r and r not in worked:
                            worked.append(r)
                    elif VIEW.search(cmd):
                        r = extract_ref(cmd)
                        if r:
                            views[r] = views.get(r, 0) + 1
                elif block.get('type') == 'tool_result' and block.get('tool_use_id') in create_ids:
                    for m in PR_URL.finditer(json.dumps(block.get('content', ''))):
                        u = m.group(0)
                        if u in created:
                            created.remove(u)
                        created.append(u)
    # A PR viewed 2+ times is active babysitting, not an incidental glance.
    for r, n in views.items():
        if n >= 2 and r not in worked:
            worked.append(r)
    # Session-owned PRs survive a follow-up prompt; transcript-derived evidence
    # is restricted to the current goal boundary.
    refs = [r for r in sys.argv[2].splitlines() if r]
    for r in created[-3:] + worked:
        if r not in refs:
            refs.append(r)
    print('\n'.join(refs[-5:]))
except Exception:
    pass
" "$TRANSCRIPT_PATH" "${STATE_OWNED_PRS:-}" "${STATE_GOAL_OFFSET:-0}" 2>/dev/null || true)

  if [ -z "$responsible_prs" ]; then
    record_check_ok open-pr skipped no-owned-pr
  fi
  if [ -n "$responsible_prs" ]; then
    # One probe per PR reads its live state plus the two agent-fixable facts a
    # receipt may never cover: merge conflicts and red checks. Fail-open as
    # before: a probe error reads as not-OPEN.
    open_prs=""
    unfit_prs=""
    while IFS= read -r pr_url; do
      [ -z "$pr_url" ] && continue
      pr_facts=$(_to 5 gh pr view "$pr_url" --json state,mergeable,statusCheckRollup 2>/dev/null | python3 -c "$PR_FACTS_PY" 2>/dev/null || echo "")
      state=${pr_facts%% *}
      if [ "$state" = "OPEN" ]; then
        open_prs="${open_prs}${pr_url}"$'\n'
        case "$pr_facts" in
          *" conflicting"*|*" red-checks"*) unfit_prs="${unfit_prs}${pr_url} (${pr_facts#OPEN })"$'\n' ;;
        esac
      fi
    done <<< "$responsible_prs"

    if [ -z "$open_prs" ]; then
      record_check_ok open-pr passed no-pr-left-open
    fi
    if [ -n "$open_prs" ]; then
      load_transcript_facts

      # Dispatch-is-not-a-handoff (2026-08-21): an orchestrator that dispatched
      # agents (`agents run … --no-follow`) and then stopped owns what it spawned.
      # This does not change the verdict — only a durable watcher, a receipt, or
      # plan mode clears an open PR — but it adds the recipe for watching children.
      # Detection requires a dispatch-shaped flag (--no-follow / --device / --name)
      # so a synchronous foreground probe run does not trip it, and uses the
      # command-position anchor so grepping FOR these markers does not either.
      self_dispatch=$(python3 -c "
import json, re, sys
CMD_POS = r'(?:^|[\n;&]\s*|\\\$\(\s*)'
DISPATCH = re.compile(CMD_POS + r'agents run\b[^\n]*--(?:no-follow|device|name)\b')
TEAMS = re.compile(CMD_POS + r'agents teams (?:start|create)\b')
found = False
try:
    with open(sys.argv[1]) as f:
        for raw in f:
            if 'tool_use' not in raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            m = rec.get('message') if isinstance(rec.get('message'), dict) else rec
            content = m.get('content') if isinstance(m, dict) else None
            if not isinstance(content, list):
                continue
            for b in content:
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    cmd = str((b.get('input') or {}).get('command', ''))
                    if DISPATCH.search(cmd) or TEAMS.search(cmd):
                        found = True
    print('yes' if found else 'no')
except Exception:
    print('no')
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "no")

      if [ "$LIVE_WATCHER" = "yes" ]; then
        record_check_ok open-pr passed durable-watcher-armed
      elif { [ "$block_receipt" = "yes" ] || [ "$BG_LIVE" = "yes" ]; } && [ -n "$unfit_prs" ]; then
        # A receipt says the owner was asked and a background task says the agent
        # will be re-invoked; neither hands off conflicts or red checks, which are
        # the agent's own work.
        cat >&2 <<UNFITMSG
STOP — you are waiting (a --blocked receipt or a running background task), but
these open PRs have merge conflicts or failing checks:

$unfit_prs
Conflicts and red CI are your own work, never the owner's: rebase onto the base
branch and re-push, or fix forward until checks are green. The receipt covers
only what no agent action can satisfy.
UNFITMSG
        record_block open-pr receipt-but-conflicts-or-red-ci
        exit 2
      elif [ "$block_receipt" = "yes" ]; then
        record_check_ok open-pr passed blocked-receipt-filed
      elif [ "$BG_LIVE" = "yes" ]; then
        record_check_ok open-pr passed background-task-running
      elif [ "${PERMISSION_MODE:-}" = "plan" ]; then
        record_check_ok open-pr passed plan-mode
      else
        _op_fires=$(prior_fires 'pull request(s) that are still OPEN')
        # Identical-state cap: two blocks already fired and the state hash has
        # not moved — a third identical block is pressure, not information
        # (measured: 630/1711 consecutive stops re-fired on an unchanged
        # hash). Record the outcome so telemetry keeps its denominator.
        if [ "${STATE_EVIDENCE_REPEAT:-no}" = "yes" ] && [ "${_op_fires:-0}" -ge 2 ]; then
          record_check_ok open-pr passed identical-state-capped
        else
        repeat_guidance "an open pull request (${open_prs%%$'\n'*})" "$_op_fires"
        cat >&2 <<PRMSG
STOP — this session created or worked pull request(s) that are still OPEN:

$open_prs
This PR is YOURS until it merges. Keep driving it:
  - conflicts / diverged base -> rebase your worktree branch and re-push
  - red CI / failing tests -> fix forward now; a broken check is your bug
  - docs/CHANGELOG the diff owes -> write them in this delivery
  - review -> the repo's automated reviewer, or spawn a non-author subagent
    review (subagents/code-reviewer); merge on green. Non-code PRs (docs,
    config, rules) merge immediately — no review, no CI wait. Reviews are
    never the owner's job.
Only facts clear this check, never wording: the PR merges or closes; a durable
watcher you armed owns the merge (\`agents monitors add\`, ScheduleWakeup,
Monitor); or, only when NO agent action can satisfy the requirement (a
credential, a repo policy), a filed ask: agents feed post "<ask>" --blocked.
PRMSG
        if [ "$self_dispatch" = "yes" ]; then
          cat >&2 <<'DISPATCHMSG'
You dispatched agents this session — dispatching is not a handoff.
You own what you spawn, until its PR merges. Either keep driving: re-check each
child on a bounded cadence (sleep ~300, then `agents sessions preview <id>` /
`gh pr view <pr>`) until it lands, or arm a durable watcher first
(`agents monitors add` on each child PR, or ScheduleWakeup) and park quoting
the armed watcher.
DISPATCHMSG
        fi
        record_block open-pr owned-pr-open
        exit 2
        fi
      fi
    fi
  fi
fi
# --- end open-PR abandonment check ---------------------------------------------

# --- live-team tick check -------------------------------------------------------
# An orchestrator whose team still has RUNNING teammates may not stop with
# nothing armed to re-invoke it (RUSH-3022): the orchestrator armed sleep-ticks
# and `teams start --watch` loops, but on later wakes it emitted status recaps
# and finally declared it would surface on the next real event (a merge) —
# deferring to watch loops that settle only when the WHOLE team settles, never
# on a single merge, so no real event could ever re-invoke it. Green MERGEABLE
# PRs sat unmerged until the user asked. The stop contract while teammates are
# RUNNING: EITHER a live tick — a background command armed THIS turn (after the
# last wake) whose completion notification has not fired yet — OR durable-
# watcher evidence (ScheduleWakeup / Monitor / agents monitors add, non-error
# result). Team detection uses command-position regexes; teammate liveness
# reads only the paired tool_result of an actual agents-teams-status
# invocation, so a session that merely greps FOR these markers cannot trip it.
# A stale tick from an earlier turn does NOT count: the dead --watch loops above
# would satisfy a pending-only check forever, which is exactly the observed
# failure. stop_hook_active (above) caps this at one fire per stop. Fail-open.
live_team_info=$(python3 -c "
import json, re, sys
CMD_POS = r'(?:^|[\n;&]\s*|\\\$\(\s*)'
TEAMS_RE = re.compile(CMD_POS + r'agents teams (?:start|create)\b')
TEAMS_ADD_RE = re.compile(CMD_POS + r'agents teams add\b')
STATUS_RE = re.compile(CMD_POS + r'agents teams status\b')
MONITORS_ADD = re.compile(CMD_POS + r'agents monitors add\b')
BG_START = re.compile(r'Command running in background with ID: (\S+)')
NOTIF_ID = re.compile(r'<task-id>([^<]+)</task-id>')
# A RUNNING teammate line, or a nonzero working count in the status header.
# (No double quotes or backticks in this code: it sits inside a double-quoted
# python3 -c string, where either would break or execute.)
LIVE_STATE = re.compile(r'\bRUNNING\b|\([1-9]\d* working')
team_used = False
status_ids = set()
watch_ids = set()
last_status_live = False
durable = False
completed = set()
bg_gen = {}
boundary_gen = 0
try:
    with open(sys.argv[1]) as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            rectype = rec.get('type') or ''
            msg = rec.get('message') if isinstance(rec.get('message'), dict) else rec
            role = rec.get('role') or (msg.get('role') if isinstance(msg, dict) else '')
            # Wake boundaries: a task-notification (any non-assistant entry —
            # they arrive as user, queue-operation, or attachment records) or a
            # genuine user turn (string content, or a text block). A
            # tool_result-only user entry is NOT a boundary.
            if rectype != 'assistant' and '<task-notification>' in raw:
                boundary_gen += 1
                for m in NOTIF_ID.finditer(raw):
                    completed.add(m.group(1))
            content = msg.get('content') if isinstance(msg, dict) else None
            if role == 'user':
                if isinstance(content, str):
                    boundary_gen += 1
                elif isinstance(content, list) and any(
                        isinstance(b, dict) and b.get('type') == 'text' for b in content):
                    boundary_gen += 1
            if not isinstance(content, list):
                continue
            for b in content:
                if not isinstance(b, dict):
                    continue
                btype = b.get('type')
                if btype == 'tool_use':
                    name = b.get('name') or ''
                    cmd = str((b.get('input') or {}).get('command', ''))
                    if TEAMS_RE.search(cmd) or (TEAMS_ADD_RE.search(cmd) and '--mode edit' in cmd):
                        team_used = True
                    if STATUS_RE.search(cmd):
                        status_ids.add(b.get('id') or '')
                    if name in ('ScheduleWakeup', 'Monitor') or MONITORS_ADD.search(cmd):
                        watch_ids.add(b.get('id') or '')
                elif btype == 'tool_result':
                    rid = b.get('tool_use_id') or ''
                    text = b.get('content')
                    if isinstance(text, list):
                        text = ' '.join(str(x.get('text', '')) for x in text if isinstance(x, dict))
                    text = str(text or '')
                    if rid in status_ids:
                        last_status_live = bool(LIVE_STATE.search(text))
                    if rid in watch_ids and not b.get('is_error'):
                        durable = True
                    for m in BG_START.finditer(text):
                        bg_gen[m.group(1)] = boundary_gen
    live_tick = any(g == boundary_gen and t not in completed for t, g in bg_gen.items())
    live = team_used and last_status_live
    print(('yes' if live else 'no'), ('yes' if live_tick else 'no'), ('yes' if durable else 'no'))
except Exception:
    print('no no no')
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "no no no")
lt_live=$(echo "$live_team_info" | awk '{print $1}')
lt_tick=$(echo "$live_team_info" | awk '{print $2}')
lt_watch=$(echo "$live_team_info" | awk '{print $3}')

if [ "$lt_live" = "yes" ]; then
  if [ "$lt_tick" = "yes" ] || [ "$lt_watch" = "yes" ]; then
    record_check_ok live-team passed tick-or-watcher-armed
  else
    repeat_guidance "a live team with nothing armed to re-invoke you" "$(prior_fires 'team still has RUNNING teammates')"
    cat >&2 <<'LIVETEAMMSG'
STOP — your team still has RUNNING teammates and this stop arms nothing that
re-invokes you. On every wake while a team runs, drive then re-arm:
  1. One concrete drive action — merge a PR that is green and mergeable, steer
     or resume a stalled teammate, re-dispatch a dead track.
  2. Re-arm the next bounded tick BEFORE stopping — a background command
     (run_in_background: true) shaped like
       sleep 300; agents teams status <team>; echo TICK done
     — or arm a durable watcher (`agents monitors add`, ScheduleWakeup) and
     park quoting it.
A status recap with no re-arm is abandonment. `teams start --watch` settles
only when the WHOLE team settles — a single PR merge never re-invokes you
through it, so "surface on the next real event" parks forever.
LIVETEAMMSG
    record_block live-team running-teammates-no-tick
    exit 2
  fi
fi
# --- end live-team tick check ---------------------------------------------------

# --- task-list keep-moving check ----------------------------------------------
# The strongest "stopped too early" signal is the session's OWN checklist: if it
# still holds pending / in_progress items, the agent is stopping before its work
# is done (RUSH-2113).
#
# Fires when the folded checklist has >=1 remaining item, unless a fact covers
# the stop:
#   - a durable watcher was armed for the current goal (LIVE_WATCHER), or
#   - a --blocked feed receipt is on disk for this session (block_receipt), or
#   - the last tool_use this goal was ExitPlanMode or AskUserQuestion (control
#     is with the user, structurally), or
#   - the Stop payload's permission_mode is "plan".
# Wording in the final message is not read. The checklist state is folded by
# todo-progress.py (snapshot TodoWrite/TodoList/todo_write/update_plan + Claude
# TaskCreate/TaskUpdate). Fail-open on any error.
todo_json=$(python3 "$HERE/todo-progress.py" "$TRANSCRIPT_PATH" 2>/dev/null || echo '{}')

# Cheap bash pre-check: only read transcript facts when the folded checklist
# actually has a remaining item. A no-checklist / all-done stop (the common
# case) adds no python call here.
task_verdict="allow"
task_reason="checklist-clear"
if echo "$todo_json" | grep -q '"remaining": [1-9]'; then
  load_transcript_facts
  if [ "$LIVE_WATCHER" = "yes" ]; then
    task_reason="durable-watcher-armed"
  elif [ "$BG_LIVE" = "yes" ]; then
    task_reason="background-task-running"
  elif [ "$block_receipt" = "yes" ]; then
    task_reason="blocked-receipt-filed"
  elif [ "$LAST_STRUCT_TOOL" = "ExitPlanMode" ] || [ "$LAST_STRUCT_TOOL" = "AskUserQuestion" ]; then
    task_reason="control-with-user-via-tool"
  elif [ "${PERMISSION_MODE:-}" = "plan" ]; then
    task_reason="plan-mode"
  else
    task_verdict="block"
  fi
fi

if [ "$task_verdict" != "block" ]; then
  record_check_ok keep-moving passed "$task_reason"
fi
if [ "$task_verdict" = "block" ]; then
  task_next=$(echo "$todo_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('next', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
  task_remaining=$(echo "$todo_json" | python3 -c "
import json, sys
try:
    print(int(json.load(sys.stdin).get('remaining', 0)))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
  repeat_guidance "unfinished checklist items" "$(prior_fires 'our task list still has')"
  cat >&2 <<TASKMSG
STOP — your task list still has ${task_remaining} unfinished item(s); next:
"${task_next}". Advance it now (TaskUpdate), or mark items that are no longer
needed status=deleted. If it genuinely needs the owner, file the ask:
agents feed post "<ask>" --blocked
TASKMSG
  record_block keep-moving unfinished-checklist
  exit 2
fi
# --- end task-list keep-moving check -------------------------------------------

# --- done-claim detector (delivery-chain trigger only) -------------------------
# A done-claim alone blocks nothing. It only decides whether the delivery-chain
# check below runs, and only on a session with real delivery evidence. Phrases
# match on word boundaries, and a bare "done." / "done!" is not a claim: it ends
# list items ("...; done.") far more often than it ends a delivery.
claims_done() {
  INPUT_JSON="$INPUT_JSON" python3 - <<'PY' 2>/dev/null || echo "no"
import json, os, re
try:
    msg = (json.loads(os.environ.get('INPUT_JSON') or '{}').get('last_assistant_message', '') or '').lower()
except Exception:
    msg = ''
done_signals = [
    'implementation is complete',
    'feature is complete',
    'all done',
    'that completes',
    'i have finished',
    'everything is working',
    'changes are complete',
    'the feature is ready',
    'successfully implemented',
    'implementation is done',
    'all changes have been made',
    'feature is done',
    'work is complete',
    'that should do it',
    'ready for use',
    'ready for review',
    "here's what was built",
    "here's what changed",
    'here is what changed',
    'here is what was built',
    'all tests pass',
    # Spelled out: word-boundary matching no longer finds it inside the
    # substring 'all tests pass', which the old substring match relied on.
    'all tests passed',
    'all passing',
    'that covers everything',
    'everything looks good',
    'should be working now',
    'fix is in place',
    'changes are live',
    'deployed successfully',
]
claimed = any(re.search(r'(?<!\w)' + re.escape(s) + r'(?!\w)', msg) for s in done_signals)
print('yes' if claimed else 'no')
PY
}
is_claiming_done=$(claims_done)

# Did this session run a delivery command even if the final message avoids the
# generic done phrases? Keep this anchored to command positions so grepping or
# editing this hook does not count as running a merge/create.
delivery_activity=$(python3 -c "
import json, re, sys

CMD_POS = r'(?:^|[\n;&]\s*|\\\$\(\s*)'
ACTIVITY = re.compile(CMD_POS + r'(?:gh\s+pr\s+(?:create|merge)\b|git\s+(?:-C\s+\S+\s+)?merge\b)')
seen = False
try:
    with open(sys.argv[1]) as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            msg = rec.get('message') if isinstance(rec.get('message'), dict) else rec
            content = msg.get('content') if isinstance(msg, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'tool_use':
                    cmd = str((block.get('input') or {}).get('command', ''))
                    if ACTIVITY.search(cmd):
                        seen = True
                        raise SystemExit
except SystemExit:
    pass
except Exception:
    seen = False
print('yes' if seen else 'no')
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "no")

# Decide whether this stop is the end of a delivery. Completion wording and a
# Git cwd are not evidence: the delivery chain runs only when this session
# positively mutated a repo, authored/operated a PR, or started a deployment.
# If state evaluation itself fails, preserve the prior done-claim enforcement;
# state can improve precision but can never weaken an existing safety check.
# Created/worked PR evidence remains as an independent precision backstop.
delivery_trigger="no"
if [ "$is_claiming_done" = "yes" ] && { [ "${STATE_DELIVERY_EVIDENCE:-no}" = "yes" ] || [ "${STATE_EVAL_FAILED:-yes}" = "yes" ]; }; then
  delivery_trigger="yes"
elif [ -n "$responsible_prs" ] || [ "$delivery_activity" = "yes" ]; then
  has_merge_phrase=$(echo "$INPUT_JSON" | python3 -c "
import json, re, sys
msg = json.load(sys.stdin).get('last_assistant_message', '').lower()
pats = [
    r'\bmerged\b', r'\bdone\b', r'\bshipped\b', r'\breleased\b',
    r'\bpublished\b', r'\bcomplete\b', r'\blanded\b',
]
print('yes' if any(re.search(p, msg) for p in pats) else 'no')
" 2>/dev/null || echo "no")
  if [ "$has_merge_phrase" = "yes" ]; then
    delivery_trigger="yes"
  fi
fi

# Not a delivery stop -> nothing left to check.
if [ "$delivery_trigger" != "yes" ]; then
  record_check_ok delivery skipped no-delivery-trigger
  exit 0
fi

# --- Delivery-chain close-the-loop check ---------------------------------------
# A stop at the end of a delivery must close the loop on Linear, docs/CHANGELOG,
# and release. This check is evidence-based: it parses the actual branch name,
# PR title/body, and commit messages for Linear ticket ids, then checks whether
# they are still open and whether the delivery artifacts exist. It fails open:
# any probe error allows the stop.
delivery_msg=$(python3 - "$INPUT_JSON" "$responsible_prs" "${STATE_GOAL_OFFSET:-0}" <<'PY' | python3 "$HERE/verify-delivery-chain.py" 2>/dev/null
import json, sys
data = json.loads(sys.argv[1])
refs = [r.strip() for r in sys.argv[2].splitlines() if r.strip()]
data["responsible_prs"] = refs
data["delivery_activity"] = True
data["goal_offset"] = int(sys.argv[3])
print(json.dumps(data))
PY
)

if [ -n "$delivery_msg" ]; then
  echo "$delivery_msg" >&2
  record_block delivery incomplete-delivery-chain
  exit 2
fi
record_check_ok delivery passed delivery-chain-closed
# --- end delivery-chain close-the-loop check -----------------------------------
exit 0
