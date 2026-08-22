#!/usr/bin/env bash
set -euo pipefail

# General-purpose Stop hook: blocks Claude from stopping when it claims "done"
# without verifying all conversation goals end-to-end.
#
# Exit 0 = allow stop
# Exit 2 = block stop, stderr becomes feedback to Claude

HERE="$(cd "$(dirname "$0")" && pwd)"

# Portable timeout: macOS ships neither `timeout` nor `gtimeout` by default.
_to() {
  if command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  else shift; "$@"
  fi
}

INPUT_JSON=$(cat)

# Preserve loop protection for legacy checks, but let the visual-claim check below
# evaluate on the retry: that retry is where the agent can add image read-back.
stop_active=$(echo "$INPUT_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(str(data.get('stop_hook_active', False)).lower())
" 2>/dev/null || echo "false")

# Extract last message and transcript path
eval "$(echo "$INPUT_JSON" | python3 -c "
import json, sys, shlex
data = json.load(sys.stdin)
tp = data.get('transcript_path', '')
lm = data.get('last_assistant_message', '')
print(f'TRANSCRIPT_PATH={shlex.quote(tp)}')
print(f'LAST_MSG_LEN={len(lm)}')
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
print("STATE_CONTEXT_KIND=" + shlex.quote(str(data.get("context_kind") or "unknown")))
print("STATE_GOAL_OFFSET=" + shlex.quote(str(data.get("transcript_offset") or 0)))
print("STATE_OWNED_PRS=" + shlex.quote("\n".join(str(value) for value in data.get("owned_prs", []))))
failed = bool(data.get("state_error")) or not isinstance(data.get("delivery_evidence"), bool)
print("STATE_EVAL_FAILED=" + shlex.quote("yes" if failed else "no"))
' 2>/dev/null || printf '%s\n' 'STATE_DELIVERY_EVIDENCE=no' 'STATE_CONTEXT_KIND=unknown' 'STATE_GOAL_OFFSET=0' 'STATE_OWNED_PRS=' 'STATE_EVAL_FAILED=yes')"

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

# Loop protection moved below the repeated-check helpers: the retry path now
# needs prior_fires() to bound the argue-past ramp. Nothing between here and
# that check executes a check, so the early-exit semantics are unchanged.

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
(agents feed post "<ask>" --blocked) and end with HANDOFF: <owner> - <receipt>.
Otherwise the state must change before you stop again — re-explaining it will
not clear this check.

GUIDANCE
}
# --- end repeated-check guidance ---------------------------------------------

# Loop protection: a blocked Stop is retried with stop_hook_active=true; the
# remaining checks fire at most once so a retry cannot wedge the session.
#
# Argue-past ramp (measured 2026-08-15): three sessions cleared blocked stops by
# RESTATING a stand-down phrase on the retry — "Merged, not released — and
# that's the correct stopping point" (ea913c60), "Release correctly stops at
# merged" re-asserted after /next (fe1b0f93), "RUSH-2719 stays open by design
# and is not mine to close" restated across three fires (6805bf66). The
# unconditional retry pass was the ramp. A retried stop whose final message
# carries one of those phrases is now blocked up to two more times; after that
# it passes (a check must never wedge a session) but files a fail-loud
# `agents feed post --blocked` so the evasion is never silent. Keep PHRASES in
# sync with `standdown` in the done-claim check below.
if [ "$stop_active" = "true" ]; then
  evasion=$(echo "$INPUT_JSON" | python3 -c "
import json, re, sys
msg = json.load(sys.stdin).get('last_assistant_message', '').lower()
PHRASES = [
    r'\bnot mine to (?:drive|own|finish|land|take|push|ship|complete|close|merge|run)\b',
    r'\bstays open by design\b',
    r'\bsomeone else.{0,3}s in.?flight work\b',
    r'\bowned by (?:another|other|two|the) (?:live )?(?:sessions?|agents?)\b',
    r'\bcorrect stopping point\b',
    r'\bnothing needs you\b',
    r'\bships? on the next train\b',
    r'\bpermission classifier (?:bars|blocks|denies|denied|refused|refuses)\b',
    # 2026-08-21 (f045b577): an orchestrator parked behind its own dispatches
    # (the-dispatched-agents-will-post-to-the-feed, im-done-unless-a-blocker)
    # with no watcher armed. Dispatching is not a handoff; you own what you
    # spawn.
    r'\bi\'?m done unless\b',
    r'\bdispatched (?:agents?|sessions?) will (?:post|report|surface|finish|merge|land)\b',
]
# Evidence exception: the ramp demands a probe, so a retry that CARRIES one
# passes — a URL the user can open, or a quoted live-probe command
# (pgrep/ps/lease/monitors runs/updated_at). The measured evasions carried
# neither (bare '#2664' citations, no probes); an honest evidenced wrap-up
# ('nothing needs you' + merged-PR URL + health check output) carries both.
EVIDENCE = [
    r'https?://\S+',
    r'\bpgrep\b', r'\bps -p \d+', r'\blease (?:state|held|claimed)\b',
    r'\bmonitors runs\b', r'\bupdated_at\b',
    # Honest owner-gated receipts are evidence, not evasion: the published
    # HANDOFF exit, a filed --blocked feed record, an armed durable monitor.
    r'(?m)^\s*handoff:', r'feed post [^\n]*--blocked', r'\bagents monitors (?:add|view)\b',
]
evading = any(re.search(p, msg) for p in PHRASES) and not any(re.search(p, msg) for p in EVIDENCE)
print('yes' if evading else 'no')
" 2>/dev/null || echo no)
  if [ "$evasion" = "yes" ]; then
    n=$(prior_fires 'stand-down phrase')
    if [ "${n:-0}" -lt 2 ]; then
      record_block argue-past restated-standdown-on-retry
      cat >&2 <<'MSG'
STOP — this stop was already blocked, and the retry restates a stand-down phrase
without evidence. Finish the step and quote real output, or defer with a live
probe quoted (`pgrep`/lease/the PR updated minutes ago) — a claim alone blocks again.
MSG
      exit 2
    fi
    if [ "${n:-0}" -eq 2 ]; then
      sid=$(echo "$INPUT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
      _to 5 agents feed post --session "${sid:-unknown}" --title "Argued past 3 stop blocks" "Session restated a stand-down phrase after repeated delivery blocks and was allowed to stop. Transcript: $TRANSCRIPT_PATH" --blocked >/dev/null 2>&1 || true
    fi
  fi
  exit 0
fi

# --- Open-PR abandonment check ------------------------------------------------
# A session that CREATED *or actively WORKED* a pull request may not stop while
# any is still open, unless the final message explicitly hands the PR off. "PR
# open, waiting for reviewer" is not a stop state — merged-or-handed-off is
# done. This fires independently of the done-claim check below: the observed
# failure modes are (1) agents stopping WITHOUT claiming done ("waiting for
# CI/review") with stranded PRs they created, and (2) a session that INHERITED
# an open PR a prior session created, drove it (merge/checks/review), then
# stopped with it unmerged.
#
# A PR is attributed to THIS session two ways:
#   - CREATED: its URL appears in the tool_result of a tool_use whose command
#     ran `pr create` — paired by tool_use_id (the original precision guard).
#   - WORKED: a tool_use command OPERATED on the PR via
#     `gh pr merge|checks|review|ready|rebase|comment|close|reopen|edit <PR>`.
# A bare `gh pr view` is deliberately NOT a "worked" signal — reading someone
# else's PR is incidental; `view` only attributes a PR when the SAME PR is
# viewed 2+ times (active babysitting). So one incidental read of an unrelated
# PR never triggers the check. Fail-open: no gh, network down, parse errors —
# allow the stop.
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
    open_prs=""
    while IFS= read -r pr_url; do
      [ -z "$pr_url" ] && continue
      state=$(_to 5 gh pr view "$pr_url" --json state --jq .state 2>/dev/null || echo "")
      if [ "$state" = "OPEN" ]; then
        open_prs="${open_prs}${pr_url}"$'\n'
      fi
    done <<< "$responsible_prs"

    if [ -z "$open_prs" ]; then
      record_check_ok open-pr passed no-pr-left-open
    fi
    if [ -n "$open_prs" ]; then
      # Durable watcher evidence (RUSH-2394): a process that OUTLIVES this agent
      # may own the next step. Background `gh pr checks --watch` is NOT durable
      # — it is a child of the agent process tree and dies when a headless agent
      # exits, stranding the PR (observed on PR #2334 / #2352). Accept ONLY a
      # native ScheduleWakeup / Monitor tool_use (the harness owns the re-invoke,
      # so it outlives this agent), or a successful `agents monitors add` (the
      # daemon owns its schedule — this is the watcher parallel-teams prescribes,
      # and until 2026-08-21 the hook demanded a watcher the rules elsewhere ban
      # while not counting the one they teach). Never phrasing alone; never
      # in-process `gh pr checks --watch`.
      live_watcher=$(python3 -c "
import json, re, sys
# Legacy in-process watch — REJECT as a handoff (dies with the agent).
INPROC_WATCH = re.compile(r'gh\s+pr\s+checks\b.*--watch', re.S)
# Command-position anchor (same guard as the swarm check below): a command that
# merely greps or echoes 'agents monitors add' must not count as arming one.
CMD_POS = r'(?:^|[\n;&]\s*|\\\$\(\s*)'
MONITORS_ADD = re.compile(CMD_POS + r'agents monitors add\b')
# Invoked is not armed (measured 2026-08-15, ea913c60: a claimed watcher with no
# live process). A ScheduleWakeup/Monitor/monitors-add tool_use only counts when
# its paired tool_result came back WITHOUT error — an errored or cancelled arm is
# not a watcher. Deeper daemon-side liveness belongs to agents monitors; this
# is the strongest check the transcript alone supports. (No backticks in this
# comment: it sits inside a double-quoted python3 -c string, where a backtick
# is live command substitution.)
wake_ids = set()
ok_ids = set()
try:
    with open(sys.argv[1]) as f:
        for raw in f:
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
                    # Durable handoff evidence: a native re-invoke tool the
                    # harness owns (ScheduleWakeup / Monitor), or a daemon-owned
                    # agents monitors add — both outlive this agent. (No
                    # backticks here: double-quoted python3 -c string.)
                    if name in ('ScheduleWakeup', 'Monitor'):
                        wake_ids.add(b.get('id') or '')
                    elif MONITORS_ADD.search(str((b.get('input') or {}).get('command', ''))):
                        wake_ids.add(b.get('id') or '')
                elif btype == 'tool_result' and not b.get('is_error'):
                    ok_ids.add(b.get('tool_use_id') or '')
                # Explicitly do NOT accept run_in_background + gh pr checks --watch
                # (RUSH-2394). Leave INPROC_WATCH unused except as documentation of
                # the rejected pattern so a future edit does not re-enable it by
                # matching the old comment alone.
                _ = INPROC_WATCH
    found = any(i for i in wake_ids if i in ok_ids)
    print('yes' if found else 'no')
except Exception:
    print('no')
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "no")

      # Dispatch-is-not-a-handoff (2026-08-21, f045b577): an orchestrator that
      # dispatched two agents (`agents run … --no-follow`) then stopped cleared
      # this check by writing "completion contract = PR merged or named handoff"
      # — the word 'handoff' matched the phrase escape with no watcher armed and
      # both children unwatched. You own what you spawn: a session you dispatched
      # is not a valid named owner for your own stop. When the transcript shows a
      # real dispatch, the handoff phrase alone no longer clears — a durable
      # watcher must exist. Detection requires a dispatch-shaped flag
      # (--no-follow / --device / --name) so a synchronous foreground probe run
      # does not trip it, and uses the command-position anchor so grepping FOR
      # these markers does not either.
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

      # Handoff escape: the final message may legitimately stop with an open PR
      # if it explicitly hands it off (named owner/babysitter) — restating that
      # after this check fires once is enough to pass (stop_hook_active).
      #
      # Owner-gated receipt: a fail-loud needs-you record filed by THIS session
      # (`agents feed post --blocked` writes ~/.agents/.history/feed/block-<sid>.json)
      # is a verifiable handoff receipt for a genuinely owner-only gate. Prose
      # alone never passes; the receipt is checked on disk.
      gate_sid=$(echo "$INPUT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
      block_receipt="no"
      [ -n "$gate_sid" ] && [ -f "$HOME/.agents/.history/feed/block-${gate_sid}.json" ] && block_receipt="yes"
      has_handoff=$(echo "$INPUT_JSON" | LIVE_WATCHER="$live_watcher" SELF_DISPATCH="$self_dispatch" BLOCK_RECEIPT="$block_receipt" python3 -c "
import json, os, re, sys
msg = json.load(sys.stdin).get('last_assistant_message', '').lower()
live_watcher = os.environ.get('LIVE_WATCHER') == 'yes'
self_dispatch = os.environ.get('SELF_DISPATCH') == 'yes'
block_receipt = os.environ.get('BLOCK_RECEIPT') == 'yes'
pat = r'\b(handed off|hand-off|handoff|handing (this|it) off|will babysit|is babysitting|takes over from here|owns (this|the) pr)\b'
# Structured external-blocker stop — the check's own option 3. A genuine external
# blocker the agent CANNOT resolve (CI/GitHub outage, a signing step needing the
# user's biometric) loops the check forever. Let it pass ONLY when the message
# names the blocker ('blocked on ...') AND points to either (a) a LIVE autonomous
# process that will finish it, or (b) an action only the user's biometric can do.
# The token set is deliberately narrow: 'your review' / 'awaiting your' / 'waiting
# on you' / 'watching' are ordinary PR-abandonment prose — wanting a human review
# is NOT an external blocker (keep driving it, or hand off via the phrase above).
blocked = re.search(r'\bblocked on\b', msg)
# nextstep must name a DURABLE finish path (a native ScheduleWakeup re-invoke or
# the pr-merge-on-green monitor, or a biometric), never an in-process
# gh pr checks --watch (RUSH-2394). This escape is NOT evidence-checked, so the
# tokens stay specific: bare 'monitor' is ordinary prose ('I'll monitor CI') and
# must NOT clear the check here (the tool name 'schedulewakeup' is specific enough).
nextstep = re.search(r'\b(schedulewakeup|pr-merge-on-green|will merge on green)\b|\byour (touch ?id|biometric)\b', msg)
# Fix 2 (phrasing): trusted ONLY when a durable ScheduleWakeup/Monitor tool_use
# exists this session (live_watcher). An in-process background gh pr checks
# --watch is NOT enough — that child dies with a headless agent (RUSH-2394).
watcher_phrase = re.search(r'\b(schedulewakeup|monitor|pr-merge-on-green|poll(?:er|ing)?|re-?invoke|re-?invokes me|will merge on green|owns the (?:next|merge))\b', msg)
# Fix 3 (plan mode): plan mode mechanically forbids commit/push/merge, so the
# agent physically cannot drive the PR — demanding it is a loop. Require the
# 'plan mode' phrase together with a can't/forbid cue to avoid an incidental hit.
plan_mode = re.search(r'\bplan mode\b', msg) and re.search(r'\b(cannot|can not|forbid|forbids|blocks?|blocked|prevent|no (?:commit|push|merge))\b', msg)
# A silent/down/unconfigured automated reviewer is NOT a stop reason and NOT a
# user handoff: spawn a non-author subagent review and keep driving merge-on-green.
# Do not treat reviewer-down + needs-you-to-click-merge as a valid escape.
# Dispatch-is-not-a-handoff: when THIS session dispatched agents, the bare
# handoff phrase is the exact measured evasion (f045b577 handed its own
# children to themselves). Phrase + a durable watcher still passes; phrase
# alone does not.
#
# Ownership is absolute for agent-fixable states (owner directive,
# 2026-08-21): conflicts, a needed rebase, red CI, failing tests, and
# missing docs/CHANGELOG are the agent's own work — a stop that cites one
# of them as its blocker or handoff reason NEVER clears this gate, whatever
# else the message says. Fix it, then stop.
FIXABLE = re.compile(
    r'\b(merge conflicts?|conflicts? (?:with|on|in|against) (?:main|master|origin|the base)|'
    r'rebase (?:needed|required|pending)|needs? (?:a )?rebase|'
    r'ci (?:is )?(?:still |currently )?(?:red|failing|broken)|failing (?:tests?|checks?)|tests? (?:are )?(?:still )?failing|'
    r'docs? (?:are )?(?:missing|not (?:yet )?written|still owed)|changelog (?:entry )?(?:missing|not (?:yet )?written)|'
    r'still blocks?|still blocking|blocking the \w+)\b')
# Tense matters (review findings 1-3 on this PR): 'fixed the failing tests'
# is completed work, not a blocker — but clause- and sentence-level lookback
# both let an unrelated resolution verb launder a LIVE blocker joined by a
# comma ('Addressed feedback, conflicts remain') or a subordinating
# conjunction ('fixed one issue although conflicts remain'). The check is now
# PROXIMITY-scoped per fixable match: a completed-form verb exempts the match
# only from within its own comma/sentence-bounded segment immediately BEFORE
# it with no contrast conjunction in between, or immediately AFTER it
# (postfix 'conflicts resolved') with no live-state word in between.
# 'resolving'/'resolve' are demands, not resolutions.
RESOLVED = re.compile(r'\b(?:fixed|resolved|rebased|cleared|addressed|landed|no (?:more|remaining|longer))\b')
# The verb must govern the phrase DIRECTLY. Review rounds 2-5 proved any
# denylist of connectors (comma, and/but, although/because, also/moreover)
# is an open class that can never be complete. The structural inverse is
# closed: the verb-to-phrase gap may contain ONLY function words — articles,
# quantifiers, possessives (prefix side: 'resolved the remaining merge
# conflicts'), plus the phrase's own continuation prepositions and branch
# nouns on the postfix side ('merge conflicts with main resolved'). Any
# content word or connector in the gap breaks adjacency and the blocker
# counts as live. Over-blocking an oddly-phrased honest wrap-up costs one
# rephrase; under-blocking costs the ownership gate.
GAP_BEFORE = re.compile(r'^(?:\s*(?:the|a|an|all|any|both|each|every|its|his|her|our|their|these|those|some|remaining|last|final|earlier|prior|previous|open|aforementioned))*\s*$', re.I)
GAP_AFTER = re.compile(r'^(?:\s*(?:the|a|an|all|its|our|their|with|on|in|against|from|for|of|main|master|origin|base|branch|are|is|were|was|been|now|fully|completely))*\s*$', re.I)
# Either exemption is void when nearby text says the state is live. Scope is
# a punctuation-blind +-160-char window around the match (round 7: '...with
# main, they still block the release' put the live clause past the segment
# boundary; rounds 2-4 already proved punctuation is not an ideas boundary).
# STATED BOUND: this check is a guard, not a parser — a live-state reference
# further than 160 chars from its phrase is out of scope by design. The
# backstops beyond the window are structural, not textual: an owner-targeted
# stop still needs the on-disk --blocked receipt, and the non-author review
# loop reads the whole message.
# 'remaining/remain' is deliberately absent: it is also an allowlisted
# quantifier ('resolved all the remaining conflicts' is honest), and every
# measured launder shape carries an unambiguous live word alongside it.
LIVE_STATE = re.compile(r'\b(?:still|needs?|need|not|unresolved|pending|blocking|outstanding|exists?|unfixed|open)\b', re.I)
# The HANDOFF clause is excluded from the live scan by BLANKING its own span
# (sentinel to that sentence's end), never by truncating the scan at the
# sentinel (round 9: truncation made a live confession typed AFTER the
# HANDOFF line invisible). The ask's vocabulary ('needs to review …') stays
# out; everything else — before or after the clause — still counts.
# ONE clause-boundary definition for the segment splits (round 10's lesson:
# restated delimiter sets breed gaps). The LIVE window CAPS at the sentinel —
# rounds 8-11 proved the ask clause's own punctuation is irreducibly
# ambiguous, so no delimiter rule can separate ask text from confession text
# past the sentinel. Instead, post-sentinel confessions are caught where they
# belong: 'still blocking …' idioms are FIXABLE phrases in their own right
# (see the FIXABLE alternation), each needing its own adjacent resolution.
# Ask text can never poison; a confession anywhere is a blocker claim.
CLAUSE_END = r'[.\n;,]'
_h = re.search(r'(?i)\bhandoff:', msg)
agent_fixable = False
for m in FIXABLE.finditer(msg):
    seg_before = re.split(CLAUSE_END, msg[:m.start()])[-1][-80:]
    seg_after = re.split(CLAUSE_END, msg[m.end():m.end() + 60])[0]
    live_end = m.end() + 160
    if _h is not None and _h.start() >= m.end():
        live_end = min(live_end, _h.start())
    live_after = bool(LIVE_STATE.search(msg[max(0, m.start() - 160):live_end]))
    exempt = False
    last = None
    for r in RESOLVED.finditer(seg_before):
        last = r
    if last is not None and GAP_BEFORE.match(seg_before[last.end():]) and not live_after:
        exempt = True
    if not exempt:
        first = RESOLVED.search(seg_after)
        if first is not None and GAP_AFTER.match(seg_after[:first.start()]) and not live_after:
            exempt = True
    if not exempt:
        agent_fixable = True
        break
# The published exit for a GENUINELY owner-only gate (a credential, a repo
# policy only the owner can satisfy, a product decision):
#   HANDOFF: <owner> - <receipt>
# honored only with a verifiable receipt: the --blocked feed record on disk,
# or a live durable watcher.
sentinel = re.search(r'^\s*handoff:\s*\S[^\n]*\S', msg, re.M)
# A handoff whose TARGET is the user/owner is a hand-back, and a hand-back
# without a filed receipt is the exact behavior the owner banned (2026-08-21:
# agents take full responsibility, never hand things back to the owner).
# Delegation to another agent, session, or watcher keeps the legacy escapes.
owner_target = re.search(
    r'\bhandoff:\s*(?:you\b|muqsit\b|the owner\b)|'
    r'\b(?:handed|handing|hand)(?: \w+){0,2} (?:back )?(?:off )?to (?:you|muqsit|the owner)\b|'
    r'\byour (?:approval|review|decision|sign-?off|merge|click)\b|'
    r'\bneeds? (?:you|muqsit|the owner) to\b',
    msg)
legacy_ok = ((re.search(pat, msg) and (not self_dispatch or live_watcher))
      or (blocked and nextstep)
      or (live_watcher and watcher_phrase)
      or plan_mode)
ok = (not agent_fixable) and (
      (sentinel and (block_receipt or live_watcher))
      or (block_receipt and re.search(r'\b(owner-gated|owner-only|only (?:the owner|you) can)\b', msg))
      or (legacy_ok and not sentinel and not (owner_target and not block_receipt)))
print('yes' if ok else 'no')
" 2>/dev/null || echo "no")

      if [ "$has_handoff" = "yes" ]; then
        # The PR is still open, but a named owner or a durable watcher accepted it.
        # That is the check's third real outcome and the one most worth counting: it
        # is the difference between "handed off properly" and "abandoned".
        record_check_ok open-pr passed handoff-or-watcher-declared
      fi
      if [ "$has_handoff" != "yes" ]; then
        repeat_guidance "an open pull request (${open_prs%%$'\n'*})" "$(prior_fires 'pull request(s) that are still OPEN')"
        cat >&2 <<PRMSG
STOP — this session created or worked pull request(s) that are still OPEN:

$open_prs
This PR is YOURS until it merges. Keep driving it:
  - conflicts / diverged base -> rebase your worktree branch and re-push
  - red CI / failing tests -> fix forward now; a broken check is your bug
  - docs/CHANGELOG the diff owes -> write them in this delivery
  - review -> the repo's automated reviewer, or spawn a non-author subagent
    review (subagents/code-reviewer); merge on green. Reviews are never the
    owner's job.
Conflicts, red CI, missing docs, or "waiting on review" are never grounds to
stop or hand back. Rare exception, only when NO agent action can clear the
gate (a credential, a repo policy): agents feed post "<ask>" --blocked, then
end with HANDOFF: <owner> - <receipt>.
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
# --- end open-PR abandonment check ---------------------------------------------

# --- swarm integration check ---------------------------------------------------
# An orchestrator that fanned work across an edit-mode swarm (`agents teams`) may
# NOT stop on "all tracks merged". Each teammate's tests + reviewer only saw its
# own diff, so the seam BETWEEN tracks (track A calls what track B built) is the
# one thing no track verified — and it's where the composed feature breaks
# (imsg shells out to `agents mission-control digest`; the digest track shipped
# `mission-control-digest` → every PR green, feature dead, declared "landed
# end-to-end" untested). The normal checks miss this: the teammates' PRs aren't
# created by THIS transcript's `pr create` (so the open-PR check is blind), and
# wrap-up phrasing ("done and merged", "landed end-to-end") isn't in the
# done-signal list below. This check is narrow: it only fires when the session
# actually ran an edit-mode swarm AND the final message claims completion.
# Single pass over the transcript detects swarm use and counts assistant turns.
# stop_hook_active (checked at top) makes it fire at most once. Fail-open.
swarm_info=$(python3 -c "
import json, re, sys
used = False
turns = 0
# Match an ACTUAL invocation — the marker at a command position (start of the
# command, or after a shell separator ; && || | or a \$( / newline) — NOT the
# same string appearing inside a grep pattern, an echo, a heredoc body, or any
# quoted argument. Without this anchor a command that merely SEARCHES for
# 'agents teams start' (e.g. grep -E \"agents teams start|create\" over a
# transcript) tripped the check — a false positive on any session that greps for
# or prints these markers, including work on this very hook. Note the separator
# class deliberately omits '|': a bare pipe before 'agents teams start' is never
# a real invocation (you don't pipe INTO it), but it IS how a grep alternation
# ('agents teams start|agents teams create') reads — matching it reintroduced
# the exact false positive. '&&' is still covered by '&'.
CMD_POS = r'(?:^|[\n;&]\s*|\\\$\(\s*)'
TEAMS_RE = re.compile(CMD_POS + r'agents teams (?:start|create)\b')
TEAMS_ADD_RE = re.compile(CMD_POS + r'agents teams add\b')
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
            role = rec.get('role') or (msg.get('role') if isinstance(msg, dict) else '')
            if role == 'assistant':
                turns += 1
            content = msg.get('content') if isinstance(msg, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'tool_use':
                    cmd = str((block.get('input') or {}).get('command', ''))
                    if TEAMS_RE.search(cmd) or (TEAMS_ADD_RE.search(cmd) and '--mode edit' in cmd):
                        used = True
    print(('yes' if used else 'no'), turns)
except Exception:
    print('no 0')
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "no 0")
swarm_used=${swarm_info%% *}
swarm_turns=${swarm_info##* }

if [ "$swarm_used" = "yes" ] && [ "${swarm_turns:-0}" -gt 2 ]; then
  swarm_done=$(echo "$INPUT_JSON" | python3 -c "
import json, re, sys
msg = json.load(sys.stdin).get('last_assistant_message', '').lower()
# Orchestrator wrap-up phrasings — broader than the generic done list because
# the trigger (an edit-mode swarm ran) already narrows the population hard.
pats = [
    r'\bdone and merged\b', r'\bmerged and done\b', r'\bdone end.to.end\b',
    r'end.to.end status', r'\bland(ed)? end.to.end\b',
    r'\ball (three |two |four )?tracks? (landed|merged|are done|done)\b',
    r'\bfully landed\b', r'\blanded on main\b', r'\ball (the )?tracks? .*(merged|landed)\b',
    r'\bthe .*work.* is done\b', r'\bwork you asked for is done\b',
    r'\bfeature .* is (done|complete|landed|shipped)\b', r'\ball merged\b',
]
print('yes' if any(re.search(p, msg) for p in pats) else 'no')
" 2>/dev/null || echo "no")

  if [ "$swarm_done" = "yes" ]; then
    repeat_guidance "an edit-mode swarm's cross-track seam" "$(prior_fires 'edit-mode swarm')"
    cat >&2 <<SWARMMSG
STOP — you ran an edit-mode swarm and are claiming it is done, but per-track
green never verified the seams between tracks. Trigger the composed flow where
it actually runs, quote its real output, and name any seam you cannot exercise
as UNVERIFIED.
SWARMMSG
    record_block swarm composed-flow-unverified
    exit 2
  fi
fi
# --- end swarm integration check -----------------------------------------------

# --- command-handback check ----------------------------------------------------
# The observed failure (a real correction — "No, you release it.."): an agent
# prepares a runnable script the user did NOT ask it to hand over — it writes
# /tmp/release.sh and its final message tells the user to RUN it — instead of
# running it itself or escalating. This slips past every other check: writing to
# /tmp is unguarded, a DECLARATIVE handoff ("Run it when ready.") has no '?' so
# the permission-stop guards miss it, and it makes no done-claim so the audit
# check below never sees it. The agent has the SAME shell + ssh the user does, so
# handing over a command it could run is exactly the hand-back this repo bans.
#
# Fires only when BOTH hold, to stay high-precision (a bare /tmp script write is
# often legitimate — a background job, the agent's own scratch):
#   (1) this session WROTE a runnable script to a temp path — a Write/Edit tool
#       to /tmp|/var/folders ...(.sh/.bash/.zsh/.command), or a shell
#       redirect/heredoc/tee/cp that lands such a script there, AND
#   (2) the final message DIRECTS the user to run/paste/execute it, EXCLUDING two
#       shapes that are NOT running a command: pasting/typing text INTO a UI
#       form/field/composer (data entry, e.g. 'paste that blurb into the
#       application'), and sending a message/email/reply under the user's own
#       identity ('hit send'). A plain 'just run it when you're ready' after a
#       temp-script write still fires — that is the canonical handback.
# Exempts a genuine user-only check — a biometric / interactive login, or sending
# a message/email under the user's own identity — those are legitimate handoffs
# the agent cannot perform. stop_hook_active (top of file)
# makes it fire at most once; running the script (or naming the user-only check)
# clears it. Fail-open on any parse error.
wrote_temp_script=$(python3 -c "
import json, re, sys
# A runnable script materialized under a temp dir (a place the USER would be told
# to run from), by a file tool or a shell write.
TEMP_SCRIPT_PATH = re.compile(r'/(?:tmp|var/folders/[\w./+-]+)/[\w.+-]+\.(?:sh|bash|zsh|command)\b')
SHELL_WRITE = re.compile(r'(?:>>?|\btee\b|\bcat\s+>|\bcp\b\s+\S+\s+)\s*[\x22\x27]?/(?:tmp|var/folders/[\w./+-]+)/[\w.+-]+\.(?:sh|bash|zsh|command)')
found = False
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
            m = rec.get('message') if isinstance(rec.get('message'), dict) else rec
            content = m.get('content') if isinstance(m, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get('type') != 'tool_use':
                    continue
                inp = block.get('input') or {}
                if block.get('name') in ('Write', 'Edit', 'MultiEdit', 'NotebookEdit'):
                    if TEMP_SCRIPT_PATH.search(str(inp.get('file_path', ''))):
                        found = True
                if SHELL_WRITE.search(str(inp.get('command', ''))):
                    found = True
    print('yes' if found else 'no')
except Exception:
    print('no')
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "no")

if [ "$wrote_temp_script" = "yes" ]; then
  directs_user_to_run=$(echo "$INPUT_JSON" | python3 -c "
import json, re, sys
msg = json.load(sys.stdin).get('last_assistant_message', '').lower()
# The final message hands the runnable thing to the USER to execute.
RUN = re.compile(
    r'\b(?:run|paste|execute|copy[- ]?paste|kick off) (?:it|this|that|the (?:script|command|following|one-?shot|file|snippet))\b'
    r'|\byou(?:\x27ll| will)?\s+(?:need to|have to|can|should|just)?\s*(?:run|paste|execute)\b'
    r'|\b(?:go ahead and|then|just|please|now) (?:run|paste|execute)\b'
    r'|\brun (?:it|this) (?:when|once|after)\b'
    r'|\bpaste (?:it|this|the following|the command)\b')
# The false positives are specific SHAPES, not 'lacks a command cue'. Excluding
# them by pattern keeps recall: a genuine handback often names no cue word yet
# must still fire ('just run it when you're ready' after writing /tmp/release.sh
# is the canonical failure). Requiring a positive cue instead silently dropped
# that case, so exclude the two shapes that are NOT running-a-command:
#   FORM_PASTE — pasting/typing text INTO a UI field/form/composer is data entry,
#     not execution ('paste that blurb into the application', 'type it into the
#     field'). It needs a paste/type verb AND 'into <a form-ish target>'.
FORM_PASTE = re.compile(
    r'\b(?:paste|type|enter|drop|put)\b[^.]{0,40}?\binto\b[^.]{0,30}?'
    r'\b(?:application|form|field|composer|profile|box|reply|message|email|thread|'
    r'website|site|page|dashboard|settings|calendar|browser|inbox|compose)\b')
#   EXEMPT — genuine user-only ACTIONS the agent CANNOT perform: a biometric /
#     interactive login, AND sending a message/email/reply under the user's OWN
#     identity ('hit send', 'send the email/reply'), theirs to do like a
#     fingerprint. RUN is broad by design (pronoun objects), so these exclusions
#     do the discriminating.
EXEMPT = re.compile(
    r'\b(?:biometric|touch ?id|face ?id|interactive login|sign in|log in|your password|'
    r'2fa|one-?time code|authenticate in the browser|browser to authorize|approve on your (?:phone|device)|'
    r'(?:hit|press|click) send|send (?:the )?(?:email|reply|message|dm|note))\b')
print('yes' if (RUN.search(msg) and not EXEMPT.search(msg) and not FORM_PASTE.search(msg)) else 'no')
" 2>/dev/null || echo "no")

  if [ "$directs_user_to_run" = "yes" ]; then
    cat >&2 <<'HBMSG'
STOP — you wrote a runnable script and your final message tells the user to run
it. You have the same shell: run it yourself and report the real result, or
name the genuinely user-only step ("needs your Touch ID" / "interactive login").
HBMSG
    record_block handback runnable-not-executed
    exit 2
  fi
fi
# --- end command-handback check ------------------------------------------------

# --- task-list keep-moving check ----------------------------------------------
# The strongest "stopped too early" signal is the session's OWN checklist: if it
# still holds pending / in_progress items, the agent is stopping before its work
# is done. This check makes the hook task-aware (RUSH-2113 A + B): recognizing a
# background watcher is NOT blanket permission to stop — it should free the agent
# to advance the NEXT item, and only stop when nothing else is advanceable.
#
# Fires when the folded checklist has >=1 remaining item AND the final message is
# a plain declarative stop. It does NOT fire (a legitimate stop) when the message:
#   - asks the USER for input / a decision (a real clarifying question), OR
#   - is in plan mode (physically can't act), OR
#   - names a genuine external blocker + who/what will finish it, OR
#   - explicitly hands the remaining work to a named owner, OR
#   - points at a LIVE background watcher/monitor that owns the remaining step
#     (a real ScheduleWakeup/Monitor/`gh pr checks --watch` tool_use this session,
#     never phrasing alone — the same evidence bar the open-PR check uses).
# The checklist state is folded by todo-progress.py (snapshot TodoWrite/TodoList/
# todo_write/update_plan + Claude TaskCreate/TaskUpdate). Fail-open on any error;
# stop_hook_active (top of file) makes it fire at most once per stop.
todo_json=$(python3 "$HERE/todo-progress.py" "$TRANSCRIPT_PATH" 2>/dev/null || echo '{}')

# Cheap bash pre-check: only pay for the escape-detection python when the folded
# checklist actually has a remaining item. A no-checklist / all-done stop (the
# common case) skips it entirely, so this check adds one python call, not two.
task_verdict="allow"
if echo "$todo_json" | grep -q '"remaining": [1-9]'; then
task_verdict=$(INPUT_JSON="$INPUT_JSON" TODO_JSON="$todo_json" python3 - "$TRANSCRIPT_PATH" <<'PY' 2>/dev/null
import json, os, re, sys

try:
    todo = json.loads(os.environ.get('TODO_JSON') or '{}')
except Exception:
    todo = {}
if int(todo.get('remaining', 0) or 0) < 1:
    print('allow'); sys.exit(0)

try:
    msg = (json.loads(os.environ.get('INPUT_JSON') or '{}').get('last_assistant_message', '') or '').lower()
except Exception:
    print('allow'); sys.exit(0)

# Durable monitor tool_use this session (evidence, not phrasing). RUSH-2394:
# in-process `gh pr checks --watch` is NOT durable — only a native re-invoke
# tool the harness owns (ScheduleWakeup / Monitor) outlives the agent.
live_watcher = False
last_struct_tool = ''
# Invoked is not armed (2026-08-15): a ScheduleWakeup/Monitor tool_use counts
# only with a non-error paired tool_result. Keep in sync with the open-PR check's
# identical check above.
wake_ids = set()
ok_ids = set()
try:
    with open(sys.argv[1]) as f:
        for raw in f:
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
                    last_struct_tool = name
                    if name in ('ScheduleWakeup', 'Monitor'):
                        wake_ids.add(b.get('id') or '')
                elif btype == 'tool_result' and not b.get('is_error'):
                    ok_ids.add(b.get('tool_use_id') or '')
    live_watcher = any(i for i in wake_ids if i in ok_ids)
except Exception:
    pass

# Escape 1 — the agent is handing control to the USER for input it needs to
# proceed (a clarifying question / plan-mode decision), not abandoning work.
asking = bool(
    # \x27 / \x22 are ' and " — spelled as hex so this heredoc body carries no
    # quote character. bash 3.2 (/bin/bash on macOS) tracks quotes inside a
    # heredoc that sits in a $(...), so a literal ' here breaks the whole script.
    re.search(r'\?\s*[)\]\x27\x22]*\s*$', msg.strip())
    or re.search(r'\b(let me know|which (would|do) you|do you want|would you like|your call|which of these|should i (?:proceed|go ahead|continue|do that|do it|pick|choose))\b', msg)
    or last_struct_tool in ('ExitPlanMode', 'AskUserQuestion'))
# Escape 2 — plan mode forbids acting (same cue the open-PR check uses).
plan_mode = bool(re.search(r'\bplan mode\b', msg)
                 and re.search(r'\b(cannot|can not|forbid|forbids|blocks?|blocked|prevent|no (?:commit|push|merge))\b', msg))
# Escape 3 — a genuine external blocker + who/what finishes it. Not evidence-
# checked, so keep the tokens specific: bare 'monitor' is ordinary prose here.
blocked = re.search(r'\bblocked on\b', msg)
nextstep = re.search(r'\b(schedulewakeup|pr-merge-on-green|will merge on green)\b|\byour (touch ?id|biometric)\b', msg)
# Escape 4 — explicit handoff of the remaining work to a named owner.
handoff = re.search(r'\b(handed off|hand-off|handoff|handing (this|it) off|will babysit|is babysitting|takes over from here|owns (this|the) (pr|task|work))\b', msg)
# Escape 5 — a durable ScheduleWakeup/Monitor owns the remaining step (evidence-checked).
watcher_phrase = re.search(r'\b(schedulewakeup|monitor|pr-merge-on-green|poll(?:er|ing)?|re-?invoke|re-?invokes me|will merge on green|owns the (?:next|merge))\b', msg)

ok = bool(asking or plan_mode or (blocked and nextstep) or handoff or (live_watcher and watcher_phrase))
print('allow' if ok else 'block')
PY
)
  [ -z "$task_verdict" ] && task_verdict="allow"
fi

if [ "$task_verdict" != "block" ]; then
  record_check_ok keep-moving passed checklist-clear-or-escaped
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
"${task_next}". Advance it now (TaskUpdate), name its owner or a genuine
blocker, or delete items no longer needed (status=deleted).
TASKMSG
  record_block keep-moving unfinished-checklist
  exit 2
fi
# --- end task-list keep-moving check -------------------------------------------

# Check if Claude is claiming completion
is_claiming_done=$(echo "$INPUT_JSON" | python3 -c "
import json, re, sys

data = json.load(sys.stdin)
msg = data.get('last_assistant_message', '').lower()

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
    'here\'s what was built',
    'here\'s what changed',
    'here is what changed',
    'here is what was built',
    'all tests pass',
    'all passing',
    'that covers everything',
    'everything looks good',
    'should be working now',
    'fix is in place',
    'changes are live',
    'deployed successfully',
    'done.',
    'done!',
]

# Parking / 'offer instead of do' stop: the final message DEFERS the obvious
# next step back to the user instead of doing it ('want me to…', 'say the
# word', 'on your go', 'do it on your go'). The repo own rules ban exactly
# this — a status report is fine, but parking the next step behind the user go
# is a stop that must be challenged (the observed failure: merged-but-not-
# released, then 'I can build the .vsix on your go' and stop). Kept TIGHT
# to avoid nagging: the strong deferral idioms below fire on their own; the
# fuzzier 'want me to' / 'should I proceed' fire ONLY when the message is not a
# genuine either/or CHOICE question (which the agent legitimately can't decide).
strong_parking = [
    r'\bon your go\b',
    r'\bsay the word\b',
    r'\bjust say the word\b',
    r'\blet me know if you(?:\'d| would)?(?: like| want)\b',
    r'\bi can \w+\b.{0,40}?\bif you(?:\'d| would)? like\b',
    r'\bready to \w+\b.{0,30}?\bwhen you(?:\'re| are| want| give)\b',
]
soft_parking = [
    r'\bwant me to\b',
    r'\bshould i (?:go ahead|proceed|continue|start|kick off|do that|do it|run it|ship it|release it|merge it|build it)\b',
]
# Stand-down: the agent DELIBERATES about ownership and refuses to drive work it
# was asked to do (is-yours-not-mine-to-drive, handing-it-back-and-standing-clear)
# — often citing a sibling session as the excuse. F1 is explicit: a sibling
# session on the same surface is coordinate-and-continue, NEVER stand-down; the
# user asked YOU. These are unambiguous refusals to drive, so (like
# strong_parking) they fire on their own, regardless of is_choice.
# Handoff-by-naming-an-owner (handed-off-to-a-named-watcher) does NOT match these
# — that legitimate escape lives in the open-PR check above.
standdown = [
    r'\bnot mine to (?:drive|own|finish|land|take|push|ship|complete|close|merge|run)\b',
    # 2026-08-15 additions — each phrase below was used verbatim that day to
    # rationalize a mid-delivery stop (ea913c60, fe1b0f93, 6805bf66, SV Atlas).
    # Matching routes the stop into the delivery check, where evidence decides;
    # an honest finished session passes because its evidence is real.
    r'\bstays open by design\b',
    r'\bsomeone else.{0,3}s in.?flight work\b',
    r'\bowned by (?:another|other|two|the) (?:live )?(?:sessions?|agents?)\b',
    r'\bcorrect stopping point\b',
    r'\bnothing needs you\b',
    r'\bships? on the next train\b',
    r'\bpermission classifier (?:bars|blocks|denies|denied|refused|refuses)\b',
    r'\b(?:is|it\'?s) yours,? not mine\b',
    # 'handing it back' must be TO THE HUMAN — bare 'handing it back to the main
    # thread / caller / event loop' is legitimate async prose, not a stand-down.
    # The screenshot failure ('handing it back and standing clear') still fires
    # via the 'standing clear' pattern below, so no true positive is lost.
    r'\bhanding (?:it|this|the pr|#?\d+) back to (?:you|your team|the user|muqsit)\b',
    r'\bstanding (?:clear|down)\b',
    r'\bi\'?ll stand (?:clear|down)\b',
    r'\bthis (?:one )?is (?:your|the user\'?s) (?:responsibility|job) to (?:drive|finish|own)\b',
    # 2026-08-21 (f045b577): parked behind own dispatches with no watcher armed
    # — keep in sync with PHRASES in the argue-past ramp at the top of the file.
    r'\bi\'?m done unless\b',
    r'\bdispatched (?:agents?|sessions?) will (?:post|report|surface|finish|merge|land)\b',
]
# A genuine clarifying question offers alternatives — NOT next-step parking.
is_choice = bool(re.search(r'\bwhich\b', msg) or re.search(r'\b\w+ or \w+\b', msg)
                 or 'prefer' in msg or 'either' in msg)
parked = any(re.search(p, msg) for p in strong_parking + standdown)
if not parked and not is_choice:
    parked = any(re.search(p, msg) for p in soft_parking)

for signal in done_signals:
    if signal in msg:
        print('yes')
        sys.exit(0)
if parked:
    print('yes')
    sys.exit(0)
print('no')
" 2>/dev/null || echo "no")

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

# Neither a done claim nor a PR finish line needs any later completion check.
if [ "$delivery_trigger" != "yes" ] && [ "$is_claiming_done" != "yes" ]; then
  record_check_ok stop skipped no-delivery-or-done-claim
  exit 0
fi

# Count assistant turns to skip short Q&A sessions
turn_count=$(python3 -c "
import json, sys

turns = 0
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            msg = entry.get('message') if isinstance(entry.get('message'), dict) else {}
            if (entry.get('role') or msg.get('role')) == 'assistant':
                turns += 1
        except (json.JSONDecodeError, KeyError):
            continue
print(turns)
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

if [ "${turn_count:-0}" -le 2 ]; then
  record_check_ok self-audit skipped session-too-short
  exit 0
fi

# --- Delivery-chain close-the-loop check ---------------------------------------
# A stop at the end of a delivery must close the loop on Linear, docs/CHANGELOG,
# and release. This check is evidence-based: it parses the actual branch name,
# PR title/body, and commit messages for Linear ticket ids, then checks whether
# they are still open and whether the delivery artifacts exist. It fails open:
# any probe error allows the stop.
delivery_msg=""
if [ "$delivery_trigger" = "yes" ]; then
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
fi

if [ -n "$delivery_msg" ]; then
  echo "$delivery_msg" >&2
  record_block delivery incomplete-delivery-chain
  exit 2
fi
# --- end delivery-chain close-the-loop check -----------------------------------

# Not claiming done -> no further checks (PR finish-line deliveries pass here).
if [ "$is_claiming_done" != "yes" ]; then
  record_check_ok stop skipped not-claiming-done
  exit 0
fi

# A positively observed non-code outcome has its own completion evidence and
# must not be converted into a code delivery or generic goal audit merely
# because the final answer says "done". Unknown/no-action claims still reach the
# audit below, preserving the guard against an agent that did nothing and quit.
case "${STATE_CONTEXT_KIND:-unknown}" in
  browser-external|ticket-creation|review-only|research-diagnostic)
    record_check_ok stop skipped non-code-outcome
    exit 0
    ;;
esac

# Extract the first few GENUINE user messages from the transcript. "Genuine"
# excludes harness noise that also carries role=user: `!`-prefix shell runs and
# their output (<bash-input>/<bash-stdout>/<bash-stderr>), slash-command
# expansions (<command-name>/<command-message>/<command-args>), local-command
# output, injected caveats, and tool_result blocks. The old code took the FIRST
# user turn over 20 chars, so a session opened with `j <dir>` quoted
# "<bash-input>j agents-cli</bash-input>" as "the original request" — useless for
# re-anchoring intent. We skip the noise and keep the first 3 real prose turns so
# the self-audit sees the actual ask (and its early follow-ups), not the jump cmd.
# (agents sessions --include user --first N does NOT help here: it still counts
# each bash-input/stdout as a turn — the filtering has to happen on the text.)
first_user_msg=$(python3 -c "
import json, re, sys

# A user turn is harness noise if its text starts with one of these wrappers:
# '!'-prefix shell runs + output, slash-command expansions, local-command
# output, injected system-reminders, and the interrupt marker — none are asks.
# (Apostrophes here are deliberate: a backtick inside this python3 -c "..." string
# is re-parsed by bash as a nested command substitution and throws at runtime.)
NOISE = re.compile(r'^\s*<(/?)(bash-(input|stdout|stderr)|command-(name|message|args|contents)|local-command-(stdout|stderr)|system-reminder|task-notification)>')
CAVEAT = re.compile(r'^\s*Caveat: The messages below were generated by the user while running')
INTERRUPT = re.compile(r'^\s*\[Request interrupted')
# Slash-command / skill body injected as a user turn (not something the user typed).
SKILL = re.compile(r'^\s*Base directory for this skill:')
# Hook feedback ('Stop hook feedback:', 'PreToolUse hook feedback:') is injected.
HOOKFB = re.compile(r'^\s*[A-Za-z]+ hook feedback:')

picked = []
try:
    with open(sys.argv[1]) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = entry.get('message') if isinstance(entry.get('message'), dict) else {}
            if (entry.get('role') or msg.get('role')) != 'user':
                continue
            content = entry.get('content', '') or msg.get('content', '')
            if isinstance(content, list):
                # A list content that carries any tool_result block is a tool
                # return, never a real request — skip the whole message.
                if any(isinstance(c, dict) and c.get('type') == 'tool_result' for c in content):
                    continue
                content = ' '.join(c.get('text', '') for c in content
                                   if isinstance(c, dict) and c.get('type') == 'text')
            content = (content or '').strip()
            if len(content) <= 20:            # 'yes' / 'ok' / bare slash-commands
                continue
            if (NOISE.search(content) or CAVEAT.search(content)
                    or INTERRUPT.search(content) or SKILL.search(content)
                    or HOOKFB.search(content)):
                continue                       # <bash-input>j foo</bash-input> etc.
            picked.append(content)
            if len(picked) >= 3:
                break
except Exception:
    pass

# Join the first few real asks; cap total length for the check message.
out = '\n---\n'.join(picked)
if len(out) > 900:
    out = out[:900] + '...'
print(out)
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

# If we couldn't extract a genuine user message, allow stop
if [ -z "$first_user_msg" ]; then
  record_check_ok self-audit skipped no-user-goal-found
  exit 0
fi

# Block and inject self-audit prompt
repeat_guidance "a done-claim (full goal re-audit)" "$(prior_fires 'ou claimed this work is done')"
cat >&2 <<MSG
STOP — you claimed this work is done, but you must verify before stopping.
Re-check every ask this session (first: "$first_user_msg" — plus later
corrections) against tangible output, finish what falls short, then post one
update: agents feed post --title "<outcome>" "<delivered + next step>" --level important
MSG
record_block self-audit completion-unverified
exit 2
