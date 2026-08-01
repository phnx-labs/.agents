#!/usr/bin/env bash
set -euo pipefail

# General-purpose Stop hook: blocks Claude from stopping when it claims "done"
# without verifying all conversation goals end-to-end.
#
# Exit 0 = allow stop
# Exit 2 = block stop, stderr becomes feedback to Claude

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
# A session that CREATED pull requests may not stop while any is still open,
# unless the final message explicitly hands the PR off. "PR open, waiting for
# reviewer" is not a stop state — merged-or-handed-off is done. This fires
# independently of the done-claim check below: the observed failure mode is
# agents stopping WITHOUT claiming done ("waiting for CI/review") and being
# marked completed with stranded PRs.
#
# Precision guard: a PR counts as session-created only when its URL appears
# in the tool_result of a tool_use whose command ran `pr create` — the two are
# paired by tool_use_id, so viewing/reviewing someone else's PR (even in a
# session that also created PRs) never triggers the gate. Fail-open: no gh,
# network down, parse errors — allow the stop.
if command -v gh >/dev/null 2>&1; then
  created_prs=$(python3 -c "
import json, re, sys

PR_RE = re.compile(r'https://github\.com/[\w.-]+/[\w.-]+/pull/\d+')

create_ids = set()
urls = []
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
                elif block.get('type') == 'tool_result' and block.get('tool_use_id') in create_ids:
                    for m in PR_RE.finditer(json.dumps(block.get('content', ''))):
                        u = m.group(0)
                        if u in urls:
                            urls.remove(u)
                        urls.append(u)
    print('\n'.join(urls[-3:]))
except Exception:
    pass
" "$TRANSCRIPT_PATH" 2>/dev/null || true)

  if [ -n "$created_prs" ]; then
    open_prs=""
    while IFS= read -r pr_url; do
      [ -z "$pr_url" ] && continue
      state=$(_to 5 gh pr view "$pr_url" --json state --jq .state 2>/dev/null || echo "")
      if [ "$state" = "OPEN" ]; then
        open_prs="${open_prs}${pr_url}"$'\n'
      fi
    done <<< "$created_prs"

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
STOP GATE: This session created pull request(s) that are still OPEN:

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
import json, sys
used = False
turns = 0
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
                    if ('agents teams start' in cmd or 'agents teams create' in cmd
                            or ('teams add' in cmd and '--mode edit' in cmd)):
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

# Check if Claude is claiming completion
is_claiming_done=$(echo "$INPUT_JSON" | python3 -c "
import json, sys

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
for signal in done_signals:
    if signal in msg:
        print('yes')
        sys.exit(0)
print('no')
" 2>/dev/null || echo "no")

# Not claiming done — allow stop (answering a question, asking user, etc.)
if [ "$is_claiming_done" != "yes" ]; then
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
# `!`-prefix shell runs + output, slash-command expansions, local-command
# output, injected system-reminders, and the interrupt marker — none are asks.
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
