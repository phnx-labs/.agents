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

# Check stop_hook_active first — prevent infinite loops
stop_active=$(echo "$INPUT_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(str(data.get('stop_hook_active', False)).lower())
" 2>/dev/null || echo "false")

if [ "$stop_active" = "true" ]; then
  exit 0
fi

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
    # '#N' / bare positional number (never a --flag's value like --interval 30).
    m = PR_URL.search(cmd)
    if m:
        return m.group(0)
    prev = None
    for t in cmd.split():
        if t.startswith('#') and t[1:].isdigit():
            return t[1:]
        if t.isdigit() and (prev is None or not prev.startswith('-')):
            return t
        prev = t
    return None

create_ids = set()
created = []
worked = []
views = {}
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
    # Union of created (most-recent 3) + worked, deduped, capped.
    refs = []
    for r in created[-3:] + worked:
        if r not in refs:
            refs.append(r)
    print('\n'.join(refs[-5:]))
except Exception:
    pass
" "$TRANSCRIPT_PATH" 2>/dev/null || true)

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
      # Handoff escape: the final message may legitimately stop with an open PR
      # if it explicitly hands it off (named owner/babysitter) — restating that
      # after this gate fires once is enough to pass (stop_hook_active).
      has_handoff=$(echo "$INPUT_JSON" | python3 -c "
import json, re, sys
msg = json.load(sys.stdin).get('last_assistant_message', '').lower()
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
nextstep = re.search(r'\b(watcher|background watch|gh pr checks --watch|will merge on green)\b|\byour (touch ?id|biometric)\b', msg)
ok = re.search(pat, msg) or (blocked and nextstep)
print('yes' if ok else 'no')
" 2>/dev/null || echo "no")

      if [ "$has_handoff" != "yes" ]; then
        cat >&2 <<PRGATE
STOP GATE: This session created OR worked pull request(s) that are still OPEN:

$open_prs
An open PR is not a finished task — merged-or-handed-off is done. Before
stopping you must do ONE of:
1. Keep driving it: watch CI (background gh pr checks --watch), get the
   non-author review, and merge on green.
2. Hand it off EXPLICITLY: name who or what now owns the PR (a person, a
   session, a watcher) in your final message.
3. If stopping is genuinely correct — a GENUINE external blocker you cannot
   resolve — name it ("blocked on <what>") AND point to either a LIVE process
   that will finish it (a background "gh pr checks --watch" / "watcher" that will
   "merge on green") or an action only your biometric can do ("your Touch ID").
   Wanting a human REVIEW is NOT this case: keep driving it (spawn a reviewer) or
   hand it off explicitly by naming the owner (option 2) — "awaiting your review"
   will NOT pass this gate.

Then finish your final message and stop again.
PRGATE
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
#   (2) the final message DIRECTS the user to run/paste/execute it.
# Exempts a genuine user-only gate (biometric / interactive login) — those are
# legitimate handoffs the agent cannot perform. stop_hook_active (top of file)
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
# Genuine user-only gate the agent CANNOT perform — a legitimate handoff, no nag.
EXEMPT = re.compile(
    r'\b(?:biometric|touch ?id|face ?id|interactive login|sign in|log in|your password|'
    r'2fa|one-?time code|authenticate in the browser|browser to authorize|approve on your (?:phone|device))\b')
print('yes' if (RUN.search(msg) and not EXEMPT.search(msg)) else 'no')
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
    exit 2
  fi
fi
# --- end command-handback gate ------------------------------------------------

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

# Decide whether this stop is the end of a delivery.
#   - Claiming done -> delivery gate.
#   - Created/worked a PR, or ran gh/git delivery activity, and the final
#     message treats merge/release as the finish line -> delivery gate (the
#     open-PR gate already handled OPEN PRs).
delivery_trigger="no"
if [ "$is_claiming_done" = "yes" ]; then
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

# Neither a done claim nor a PR finish line -> allow stop (answering a question, etc.)
if [ "$delivery_trigger" != "yes" ]; then
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
delivery_gate_msg=$(python3 - "$INPUT_JSON" "$responsible_prs" <<'PY' | python3 "$HERE/verify-delivery-chain.py" 2>/dev/null
import json, sys
data = json.loads(sys.argv[1])
refs = [r.strip() for r in sys.argv[2].splitlines() if r.strip()]
data["responsible_prs"] = refs
data["delivery_activity"] = True
print(json.dumps(data))
PY
)

if [ -n "$delivery_gate_msg" ]; then
  echo "$delivery_gate_msg" >&2
  exit 2
fi
# --- end delivery-chain close-the-loop gate -----------------------------------

# Not claiming done -> no further gates (PR finish-line deliveries pass here).
if [ "$is_claiming_done" != "yes" ]; then
  exit 0
fi

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

Only stop when every goal has tangible, verified results.
GATE
exit 2
