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

# Preserve loop protection for legacy gates, but let the visual-claim gate below
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

record_gate() { # $1 gate, $2 reason code
  printf '%s' "$INPUT_JSON" | python3 "$HERE/verify-work-state.py" record-gate "$1" blocked "$2" >/dev/null 2>&1 || true
}

# --- visual claim read-back gate --------------------------------------------
# Gate the claim, not scp/open. A narrow visual assertion is blocked only when
# this goal authored a visual artifact and no paired image result read that render
# back afterward. Unsupported transcript shapes fail open.
visual_gate=$(VISUAL_STOP_INPUT="$INPUT_JSON" python3 - "$TRANSCRIPT_PATH" "${STATE_GOAL_OFFSET:-0}" "$HERE" <<'PY' 2>/dev/null || true
import json, os, sys
sys.path.insert(0, sys.argv[3])
from visual_readback import inspect_transcript, makes_visual_claim

payload = json.loads(os.environ.get("VISUAL_STOP_INPUT", "{}"))
message = str(payload.get("last_assistant_message") or payload.get("lastAssistantMessage") or "")
evidence = inspect_transcript(sys.argv[1], int(sys.argv[2] or 0))
if (evidence["parser_supported"] and evidence["visual_authored"]
        and makes_visual_claim(message) and not evidence["visual_read_back"]):
    print(evidence["latest_visual"] or "visual artifact")
PY
)
if [ -n "$visual_gate" ]; then
  cat >&2 <<GATE
STOP GATE (visual read-back): Your final message describes a rendered UI, but this
session has no paired image read-back after authoring `$visual_gate`.

Render it headlessly with `agents browser start --url file://…`, capture it with
`agents browser screenshot`, then read the resulting image and inspect what it
actually shows before describing or delivering it.
GATE
  record_gate visual-readback visual-claim-unverified
  exit 2
fi

# A blocked Stop is retried with stop_hook_active=true. The visual claim check
# above still runs meaningfully once; older gates retain their loop protection.
if [ "$stop_active" = "true" ]; then
  exit 0
fi

# --- repeated-gate guidance --------------------------------------------------
# Repeating the identical block text eventually stops adding information. On a
# 3rd+ matching fire, keep the proof standard unchanged but remind the agent to
# re-check live state and choose its own next tactic. Prior fires are read from
# the transcript and anchored to the injected 'Stop hook feedback:' prefix so a
# Read of this hook's source is never miscounted as a fire.
prior_fires() {   # $1 = a substring unique to the gate's injected message
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

# Add lightweight strategy guidance when this gate has already fired >=2 times
# this session on the same item (so this is the 3rd+). It supplements the normal
# block message and never weakens the gate.
repeat_guidance() {   # $1 = human name of the repeated item, $2 = prior count
  local n="${2:-0}"
  [ "$n" -lt 2 ] && return 0
  cat >&2 <<GUIDANCE
NOTE — this gate has now fired $((n + 1)) times this session on $1. Re-check the
live state and choose the most useful next move toward the user's goal. If the
same approach is not working, change tactics. Possibilities include retrying
differently, using your tools to unblock yourself, advancing another in-scope
item, coordinating ownership, or escalating a genuinely human-only step. Use
the actual context to decide; these are suggestions, not a fixed route.

GUIDANCE
}
# --- end repeated-gate guidance ---------------------------------------------

# --- Open-PR abandonment gate ------------------------------------------------
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
# PR never triggers the gate. Fail-open: no gh, network down, parse errors —
# allow the stop.
if command -v gh >/dev/null 2>&1; then
  responsible_prs=$(python3 -c "
import json, re, sys

PR_URL = re.compile(r'https://github\.com/[\w.-]+/[\w.-]+/pull/\d+')
# gh pr subcommands that DRIVE a PR toward merge = this session owns it, even if
# a PRIOR session created it. Observer verbs (checks/review/comment) and 'view'
# are deliberately excluded: a reviewer or CI-watcher who correctly stops with the
# ball in the author's court is not abandoning the PR. 'view' is handled below as a
# weak, repetition-gated signal.
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

  if [ -n "$responsible_prs" ]; then
    open_prs=""
    while IFS= read -r pr_url; do
      [ -z "$pr_url" ] && continue
      state=$(_to 5 gh pr view "$pr_url" --json state --jq .state 2>/dev/null || echo "")
      if [ "$state" = "OPEN" ]; then
        open_prs="${open_prs}${pr_url}"$'\n'
      fi
    done <<< "$responsible_prs"

    if [ -n "$open_prs" ]; then
      # Durable watcher evidence (RUSH-2394): a process that OUTLIVES this agent
      # may own the next step. Background `gh pr checks --watch` is NOT durable
      # — it is a child of the agent process tree and dies when a headless agent
      # exits, stranding the PR (observed on PR #2334 / #2352). Accept ONLY a
      # native ScheduleWakeup / Monitor tool_use: the harness owns the re-invoke,
      # so it outlives this agent (a headless run's daemon-owned monitor, or the
      # session re-invoke path). Never phrasing alone; never in-process
      # `gh pr checks --watch`.
      live_watcher=$(python3 -c "
import json, re, sys
# Legacy in-process watch — REJECT as a handoff (dies with the agent).
INPROC_WATCH = re.compile(r'gh\s+pr\s+checks\b.*--watch', re.S)
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
                if not isinstance(b, dict) or b.get('type') != 'tool_use':
                    continue
                name = b.get('name') or ''
                # The only durable handoff evidence is a native re-invoke tool the
                # harness owns (ScheduleWakeup / Monitor) — it outlives this agent.
                if name in ('ScheduleWakeup', 'Monitor'):
                    found = True
                # Explicitly do NOT accept run_in_background + gh pr checks --watch
                # (RUSH-2394). Leave INPROC_WATCH unused except as documentation of
                # the rejected pattern so a future edit does not re-enable it by
                # matching the old comment alone.
                _ = INPROC_WATCH
    print('yes' if found else 'no')
except Exception:
    print('no')
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "no")

      # Handoff escape: the final message may legitimately stop with an open PR
      # if it explicitly hands it off (named owner/babysitter) — restating that
      # after this gate fires once is enough to pass (stop_hook_active).
      has_handoff=$(echo "$INPUT_JSON" | LIVE_WATCHER="$live_watcher" python3 -c "
import json, os, re, sys
msg = json.load(sys.stdin).get('last_assistant_message', '').lower()
live_watcher = os.environ.get('LIVE_WATCHER') == 'yes'
pat = r'\b(handed off|hand-off|handoff|handing (this|it) off|will babysit|is babysitting|takes over from here|owns (this|the) pr)\b'
# Structured external-blocker stop — the gate's own option 3. A genuine external
# blocker the agent CANNOT resolve (CI/GitHub outage, a signing step needing the
# user's biometric) loops the gate forever. Let it pass ONLY when the message
# names the blocker ('blocked on ...') AND points to either (a) a LIVE autonomous
# process that will finish it, or (b) an action only the user's biometric can do.
# The token set is deliberately narrow: 'your review' / 'awaiting your' / 'waiting
# on you' / 'watching' are ordinary PR-abandonment prose — wanting a human review
# is NOT an external blocker (keep driving it, or hand off via the phrase above).
blocked = re.search(r'\bblocked on\b', msg)
# nextstep must name a DURABLE finish path (a native ScheduleWakeup re-invoke or
# the pr-merge-on-green monitor, or a biometric), never an in-process
# gh pr checks --watch (RUSH-2394). This escape is NOT evidence-gated, so the
# tokens stay specific: bare 'monitor' is ordinary prose ('I'll monitor CI') and
# must NOT clear the gate here (the tool name 'schedulewakeup' is specific enough).
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
ok = (re.search(pat, msg)
      or (blocked and nextstep)
      or (live_watcher and watcher_phrase)
      or plan_mode)
print('yes' if ok else 'no')
" 2>/dev/null || echo "no")

      if [ "$has_handoff" != "yes" ]; then
        repeat_guidance "an open pull request (${open_prs%%$'\n'*})" "$(prior_fires 'pull request(s) that are still OPEN')"
        cat >&2 <<PRGATE
STOP GATE: This session created OR worked pull request(s) that are still OPEN:

$open_prs
An open PR is not a finished task — merged-or-handed-off is done. Before
stopping you must do ONE of:
1. Keep driving it: set a native \`ScheduleWakeup\`/\`Monitor\` to re-invoke you
   when CI settles, or enable the built-in \`pr-merge-on-green\` monitor
   (\`agents monitors enable pr-merge-on-green\`) — the daemon owns it, so it
   outlives this agent. Get the non-author review and merge on green. Do NOT
   background \`gh pr checks --watch\` — that child dies when a headless agent
   exits and strands the PR (RUSH-2394). Do NOT open the PR link for the user
   or ask them to click merge.
2. Non-author review path: if the automated code reviewer is configured and
   posting (e.g. prix-cloud), wait for it. If it is missing, silent, down, or
   the repo has none — spawn a non-author subagent review NOW (code:review /
   Agent that is not the author). Do not wait, and do not hand the merge to
   the user because the bot is down.
3. Hand it off EXPLICITLY only when someone/something else truly owns it: name
   who or what now owns the PR (a person, a session, a durable monitor) in your
   final message. "Needs you to merge" / "open the PR" is NOT a handoff.
4. If stopping is genuinely correct — a GENUINE external blocker you cannot
   resolve — name it ("blocked on <what>") AND point to either a DURABLE process
   that will finish it (a native \`ScheduleWakeup\`/\`Monitor\` re-invoke, or the
   \`pr-merge-on-green\` monitor — "will merge on green") or an action only your
   biometric can do ("your Touch ID"). A background \`gh pr checks --watch\` is
   NOT durable. Wanting a human REVIEW is NOT this
   case: keep driving it (spawn a reviewer) or hand it off explicitly by naming
   the owner (option 3) — "awaiting your review" will NOT pass this gate.

Then finish your final message and stop again.
PRGATE
        record_gate open-pr owned-pr-open
        exit 2
      fi
    fi
  fi
fi
# --- end open-PR abandonment gate ---------------------------------------------

# --- swarm integration gate ---------------------------------------------------
# An orchestrator that fanned work across an edit-mode swarm (`agents teams`) may
# NOT stop on "all tracks merged". Each teammate's tests + reviewer only saw its
# own diff, so the seam BETWEEN tracks (track A calls what track B built) is the
# one thing no track verified — and it's where the composed feature breaks
# (imsg shells out to `agents mission-control digest`; the digest track shipped
# `mission-control-digest` → every PR green, feature dead, declared "landed
# end-to-end" untested). The normal gates miss this: the teammates' PRs aren't
# created by THIS transcript's `pr create` (so the open-PR gate is blind), and
# wrap-up phrasing ("done and merged", "landed end-to-end") isn't in the
# done-signal list below. This gate is narrow: it only fires when the session
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
# transcript) tripped the gate — a false positive on any session that greps for
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
    repeat_guidance "an edit-mode swarm's cross-track seam" "$(prior_fires 'STOP GATE (swarm)')"
    cat >&2 <<SWARMGATE
STOP GATE (swarm): You ran an edit-mode swarm and are claiming it is done.
Every track's PR merging green is NOT proof the composed feature works — each
teammate's tests and reviewer only ever saw that teammate's own diff. The seam
BETWEEN tracks (where one track calls what another built) is the one thing no
track verified, and it is exactly where the feature breaks.

Before you can stop, you MUST:
1. List every seam where one track calls/imports/hits what another track built.
2. For each seam, TRIGGER the composed cross-track flow against where the
   feature actually runs (the running daemon / installed binary / deployed
   service — merged to main is NOT deployed) and QUOTE the real output.
3. If a seam genuinely cannot be exercised, name that hop as UNVERIFIED — do
   not fold it into a "done end-to-end" claim.

"All PRs merged" / a table of green checkmarks is a report of merges, not proof
of a working feature. Go run the composed flow, then report with quoted output.
SWARMGATE
    record_gate swarm composed-flow-unverified
    exit 2
  fi
fi
# --- end swarm integration gate -----------------------------------------------

# --- command-handback gate ----------------------------------------------------
# The observed failure (a real correction — "No, you release it.."): an agent
# prepares a runnable script the user did NOT ask it to hand over — it writes
# /tmp/release.sh and its final message tells the user to RUN it — instead of
# running it itself or escalating. This slips past every other gate: writing to
# /tmp is unguarded, a DECLARATIVE handoff ("Run it when ready.") has no '?' so
# the permission-stop guards miss it, and it makes no done-claim so the audit
# gate below never sees it. The agent has the SAME shell + ssh the user does, so
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
# Exempts a genuine user-only gate — a biometric / interactive login, or sending
# a message/email under the user's own identity — those are legitimate handoffs
# the agent cannot perform. stop_hook_active (top of file)
# makes it fire at most once; running the script (or naming the user-only gate)
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
    cat >&2 <<'HBGATE'
STOP GATE (handback): You wrote a runnable script to a temp path and your final
message tells the user to run it. You have the SAME shell + ssh the user does —
handing them a command you could run yourself is the hand-back this repo exists
to prevent ("No, you release it..").

Before you can stop, do ONE of:
1. RUN IT YOURSELF (the default — you almost always can). Execute the script or
   command you just prepared, then report the real result.
2. If a step genuinely needs the USER (a biometric, an interactive login on their
   own machine), say so explicitly ("needs your Touch ID" / "interactive login")
   — that phrasing clears this gate.
3. If you are blocked and it is NOT a user-only gate, do NOT stop in this window:
   reach the user OUT-OF-BAND (message them) so you get their attention, keep
   working every other thread meanwhile, and escalate if they do not reply. A
   chat message in this window is a note in an empty room — the user is not
   watching it.

Then finish your final message and stop again.
HBGATE
    record_gate handback runnable-not-executed
    exit 2
  fi
fi
# --- end command-handback gate ------------------------------------------------

# --- task-list keep-moving gate ----------------------------------------------
# The strongest "stopped too early" signal is the session's OWN checklist: if it
# still holds pending / in_progress items, the agent is stopping before its work
# is done. This gate makes the hook task-aware (RUSH-2113 A + B): recognizing a
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
#     never phrasing alone — the same evidence bar the open-PR gate uses).
# The checklist state is folded by todo-progress.py (snapshot TodoWrite/TodoList/
# todo_write/update_plan + Claude TaskCreate/TaskUpdate). Fail-open on any error;
# stop_hook_active (top of file) makes it fire at most once per stop.
todo_json=$(python3 "$HERE/todo-progress.py" "$TRANSCRIPT_PATH" 2>/dev/null || echo '{}')

# Cheap bash pre-check: only pay for the escape-detection python when the folded
# checklist actually has a remaining item. A no-checklist / all-done stop (the
# common case) skips it entirely, so this gate adds one python call, not two.
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
                if not isinstance(b, dict) or b.get('type') != 'tool_use':
                    continue
                name = b.get('name') or ''
                last_struct_tool = name
                if name in ('ScheduleWakeup', 'Monitor'):
                    live_watcher = True
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
# Escape 2 — plan mode forbids acting (same cue the open-PR gate uses).
plan_mode = bool(re.search(r'\bplan mode\b', msg)
                 and re.search(r'\b(cannot|can not|forbid|forbids|blocks?|blocked|prevent|no (?:commit|push|merge))\b', msg))
# Escape 3 — a genuine external blocker + who/what finishes it. Not evidence-
# gated, so keep the tokens specific: bare 'monitor' is ordinary prose here.
blocked = re.search(r'\bblocked on\b', msg)
nextstep = re.search(r'\b(schedulewakeup|pr-merge-on-green|will merge on green)\b|\byour (touch ?id|biometric)\b', msg)
# Escape 4 — explicit handoff of the remaining work to a named owner.
handoff = re.search(r'\b(handed off|hand-off|handoff|handing (this|it) off|will babysit|is babysitting|takes over from here|owns (this|the) (pr|task|work))\b', msg)
# Escape 5 — a durable ScheduleWakeup/Monitor owns the remaining step (evidence-gated).
watcher_phrase = re.search(r'\b(schedulewakeup|monitor|pr-merge-on-green|poll(?:er|ing)?|re-?invoke|re-?invokes me|will merge on green|owns the (?:next|merge))\b', msg)

ok = bool(asking or plan_mode or (blocked and nextstep) or handoff or (live_watcher and watcher_phrase))
print('allow' if ok else 'block')
PY
)
  [ -z "$task_verdict" ] && task_verdict="allow"
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
  repeat_guidance "unfinished checklist items" "$(prior_fires 'STOP GATE (keep moving)')"
  cat >&2 <<TASKGATE
STOP GATE (keep moving): Your task list still has ${task_remaining} unfinished
item(s). The next one to advance is:

  "${task_next}"

A checklist is your acceptance rubric — you are done when every item is completed,
not before. Recognizing a background watcher on one item is not permission to stop
the rest. Before stopping, do ONE of:
1. Advance the next item now — do the work, then mark it completed (TaskUpdate
   status=completed). Then move to the following item; stop only when nothing is
   left to advance.
2. If the item is genuinely owned by someone/something else — a live background
   watcher, another session, or a person — name that owner explicitly in your
   final message (that hands it off).
3. If it is blocked on a genuine external step you cannot do (a biometric, an
   interactive login), name the blocker ("blocked on <what>") and what will
   finish it.
4. If the item is no longer needed, delete it (TaskUpdate status=deleted) so the
   list reflects reality.

Do not stop with unfinished items and no owner named.
TASKGATE
  record_gate keep-moving unfinished-checklist
  exit 2
fi
# --- end task-list keep-moving gate -------------------------------------------

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
# — that legitimate escape lives in the open-PR gate above.
standdown = [
    r'\bnot mine to (?:drive|own|finish|land|take|push|ship|complete|close|merge|run)\b',
    r'\b(?:is|it\'?s) yours,? not mine\b',
    # 'handing it back' must be TO THE HUMAN — bare 'handing it back to the main
    # thread / caller / event loop' is legitimate async prose, not a stand-down.
    # The screenshot failure ('handing it back and standing clear') still fires
    # via the 'standing clear' pattern below, so no true positive is lost.
    r'\bhanding (?:it|this|the pr|#?\d+) back to (?:you|your team|the user|muqsit)\b',
    r'\bstanding (?:clear|down)\b',
    r'\bi\'?ll stand (?:clear|down)\b',
    r'\bthis (?:one )?is (?:your|the user\'?s) (?:responsibility|job) to (?:drive|finish|own)\b',
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
# state can improve precision but can never weaken an existing safety gate.
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

# Neither a done claim nor a PR finish line needs any later completion gate.
if [ "$delivery_trigger" != "yes" ] && [ "$is_claiming_done" != "yes" ]; then
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
  exit 0
fi

# --- Delivery-chain close-the-loop gate ---------------------------------------
# A stop at the end of a delivery must close the loop on Linear, docs/CHANGELOG,
# and release. This gate is evidence-based: it parses the actual branch name,
# PR title/body, and commit messages for Linear ticket ids, then checks whether
# they are still open and whether the delivery artifacts exist. It fails open:
# any probe error allows the stop.
delivery_gate_msg=""
if [ "$delivery_trigger" = "yes" ]; then
delivery_gate_msg=$(python3 - "$INPUT_JSON" "$responsible_prs" "${STATE_GOAL_OFFSET:-0}" <<'PY' | python3 "$HERE/verify-delivery-chain.py" 2>/dev/null
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

if [ -n "$delivery_gate_msg" ]; then
  echo "$delivery_gate_msg" >&2
  record_gate delivery incomplete-delivery-chain
  exit 2
fi
# --- end delivery-chain close-the-loop gate -----------------------------------

# Not claiming done -> no further gates (PR finish-line deliveries pass here).
if [ "$is_claiming_done" != "yes" ]; then
  exit 0
fi

# A positively observed non-code outcome has its own completion evidence and
# must not be converted into a code delivery or generic goal audit merely
# because the final answer says "done". Unknown/no-action claims still reach the
# audit below, preserving the guard against an agent that did nothing and quit.
case "${STATE_CONTEXT_KIND:-unknown}" in
  browser-external|ticket-creation|review-only|research-diagnostic)
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

# Join the first few real asks; cap total length for the gate message.
out = '\n---\n'.join(picked)
if len(out) > 900:
    out = out[:900] + '...'
print(out)
" "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

# If we couldn't extract a genuine user message, allow stop
if [ -z "$first_user_msg" ]; then
  exit 0
fi

# Block and inject self-audit prompt
repeat_guidance "a done-claim (full goal re-audit)" "$(prior_fires 'You claimed this work is done')"
cat >&2 <<GATE
STOP GATE: You claimed this work is done, but you must verify before stopping.

The user's request(s) this session — re-read the FULL conversation for the rest,
including any later corrections:
"$first_user_msg"

Before you can stop, you MUST:
1. Re-read the full conversation from the beginning
2. List EVERY goal, requirement, and question the user raised
3. For each goal, state one of:
   - DONE and TESTED end-to-end (cite the tangible output — test result, screenshot, live behavior)
   - DONE but UNTESTED (state what verification is missing, then go do it)
   - NOT DONE (continue working on it now)
4. If ANY goal is UNTESTED or NOT DONE, keep working. Do not stop.
5. Once EVERY goal is DONE and verified, close out in this order:
   a. New follow-up ideas, improvements, or issues you noticed along the way that
      are out of scope for this session: FILE them as tickets via the project's
      tracker right now, with real context (what you found, why it's out of
      scope, any evidence) — not a one-line stub. Do not just mention an idea
      and wait ('say the word', 'let me know if you want this') — either do it,
      file it as tracked work, or drop it. A dangling optional idea is not a
      finished session.
   b. Clean up loose ends: commit and push any stray uncommitted work, remove
      worktrees and branches this session no longer needs, and confirm every
      ticket this session actually finished is closed with proof (not left
      Todo because it slipped your mind).
   c. Post ONE quick status update the way you would update a human manager — the
      headline outcome + the one link/next-step, not a transcript:
       agents feed post --title "<short outcome>" "<what you delivered + the one next step>" --level important
      This records the completion and marks this phone-worthy successful update
      for owner delivery.
   d. This session is now genuinely finished. If this is a headless, dispatched,
      or background run — not a live terminal a person might be actively
      watching right now — run /done as your very last action: its own Step 1
      builds the real handoff recap (the /recap discipline — facts, what's
      done, tests actually run, nothing left dangling) as your final message,
      THEN its Step 2 self-exits via the guarded SIGTERM (do not hand-roll a
      bare SIGTERM, and do not skip straight to Step 2 — a self-exit with no
      recap first is not a clean handoff). If you are unsure, or this looks
      like an interactive session someone is driving, run /recap instead (same
      handoff discipline, no self-exit) and then just stop.

Only stop when every goal has tangible, verified results, any real follow-ups are
filed with context (not dangled or stubbed), loose ends are cleaned up, and — if
applicable — the session has recapped and cleanly exited itself.
GATE
record_gate self-audit completion-unverified
exit 2
