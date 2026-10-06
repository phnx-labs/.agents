#!/usr/bin/env bash
# Tests for 07-investigate-first-gate.py — run: bash 07-investigate-first-gate_test.sh
# Executes the real hook on transcripts built in the record shapes Claude Code
# writes (user string/list content, assistant text/tool_use blocks, tool_result,
# isMeta reminders, "Stop hook feedback:" records). No mocks.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../07-investigate-first-gate.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# _case <name> <expect block|allow> <entrypoint> <python that prints JSONL records>
_case() {
  local name="$1" expect="$2" ep="$3" gen="$4" t="$TMP/$1.jsonl" rc got
  python3 -c "$gen" > "$t"
  printf '{"session_id":"t","stop_hook_active":false,"transcript_path":"%s"}' "$t" \
    | CLAUDE_CODE_ENTRYPOINT="$ep" python3 "$HOOK" >/dev/null 2>"$TMP/err"; rc=$?
  got=allow; [ "$rc" -eq 2 ] && got=block
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then got="crash($rc)"; fi
  if [ "$got" = "$expect" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $name: expected $expect got $got :: $(head -c 300 "$TMP/err")"; fi
}

LIB='
import json
def u(text): print(json.dumps({"type":"user","message":{"role":"user","content":text}}))
def uimg(text): print(json.dumps({"type":"user","message":{"role":"user","content":[{"type":"text","text":text},{"type":"image","source":{}}]}}))
def meta(text): print(json.dumps({"type":"user","isMeta":True,"message":{"role":"user","content":text}}))
def a_text(t): print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":t}]}}))
def a_tool(i,name="Bash"): print(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":i,"name":name,"input":{}}]}}))
def res(i): print(json.dumps({"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":i,"content":"ok"}]}}))
def compact(t): print(json.dumps({"type":"user","isCompactSummary":True,"message":{"role":"user","content":t}}))
def fb(t): print(json.dumps({"type":"user","isMeta":True,"message":{"role":"user","content":"Stop hook feedback:\n[~/hooks/investigate-first-gate.py]: [investigate-first-gate] "+t}}))
'

# Observed failure: a status question answered from memory.
_case zero-tools block cli "$LIB
u('Wait, so what is the TLDR? What have we completed and what is still left???')
a_text('Nothing has landed on main yet: phases 1 and 2a are written, tested and approved.')"

# Earlier turns had tools; only the suffix after the latest owner message counts.
_case zero-tools-after-earlier-work block cli "$LIB
u('fix the flaky test'); a_tool('t1'); res('t1'); a_text('Fixed.')
u('are you sure it is merged?')
a_text('Yes. Both changes are merged and live on the fleet.')"

# Observed failure: conceded first, then called tools.
_case agree-first block cli "$LIB
u('use our artifact CLI, never the other artifacts')
a_text('You are right. Your instructions say to use the artifacts skill.')
a_tool('t1','Skill'); res('t1'); a_tool('t2'); res('t2')
a_text('Redoing the plan with the CLI now.')"

# A concession merely MENTIONED (quoted, or mid-sentence) is not an opener.
_case agree-first-quoted-mention allow cli "$LIB
u('OK')
a_text('Recap: the no-investigation block and the \"You are right\" opener check are live.')
a_tool('t1'); res('t1'); a_text('done')"

_case agree-first-mid-sentence allow cli "$LIB
u('why did it block?')
a_text('It flagged that I said you are right too early; checking the transcript.')
a_tool('t1','Read'); res('t1'); a_text('found it')"

# Real openers still block: lead-in words, list markers, curly apostrophe, no punctuation.
_case agree-first-unpunctuated block cli "$LIB
u('check it')
a_text(\"You're right\")
a_tool('t1'); res('t1'); a_text('done')"

_case agree-first-bullet block cli "$LIB
u('check it')
a_text(\"- You're right, I missed the second hook.\")
a_tool('t1'); res('t1'); a_text('done')"

_case agree-first-yes-lead-in block cli "$LIB
u('check it')
a_text(\"Yes, you're right. I used the wrong CLI.\")
a_tool('t1'); res('t1'); a_text('done')"

_case agree-first-ah-lead-in block cli "$LIB
u('check it')
a_text(\"Ah, good catch. Fixing it.\")
a_tool('t1'); res('t1'); a_text('done')"

_case agree-first-curly-apostrophe block cli "$LIB
u('check it')
a_text(\"You’re right. Checking now.\")
a_tool('t1'); res('t1'); a_text('done')"

_case agree-first-numbered block cli "$LIB
u('check it')
a_text(\"1) Good catch, the path was wrong.\")
a_tool('t1'); res('t1'); a_text('done')"

# Retry after an agree-first block: the opener is still on screen, cannot be deleted.
_case agree-first-retry-passes allow cli "$LIB
u('use our artifact CLI')
a_text('You are right, I used the wrong tool.')
a_tool('t1'); res('t1'); a_text('done')
fb('agree-first: you opened with ...')
a_tool('t2'); res('t2'); a_text('Checked: the CLI renders it; my opener was premature.')"

# Investigation first, then a conclusion that agrees: fine.
_case investigated-then-agrees allow cli "$LIB
u('is the stop hook inert?')
a_text('Checking the transcript records.')
a_tool('t1','Read'); res('t1')
a_text('You are right: it exits 0 and its text lands after the reply.')"

# Bookkeeping calls are not investigation.
_case bookkeeping-only block cli "$LIB
u('status?')
a_tool('t1','TodoWrite'); res('t1')
a_text('All tasks complete.')"

# Image paste with text is the owner speaking.
_case image-message block cli "$LIB
uimg('check out this session')
a_text('That agent should have merged it.')"

# Injected reminders and hook feedback are not owner messages.
_case meta-not-owner allow cli "$LIB
u('run the tests'); a_tool('t1'); res('t1')
meta('<system-reminder>x</system-reminder>')
a_text('Tests pass.')"

# Headless machine prompt (session-headline generator): out of scope.
_case headless allow sdk-cli "$LIB
u('Generate a concise session headline naming what this coding session is working on.')
a_text('Stop-hook redesign')"

# A compaction summary mid-turn is not an owner message: work before it still counts.
_case compaction-not-owner allow cli "$LIB
u('merge the PR'); a_tool('t1'); res('t1')
compact('This session is being continued from a previous conversation that ran out of context.')
a_text('Done, merged.')"

# Loop cap: after 3 blocks on one message the gate lets go instead of wedging.
_case loop-cap allow cli "$LIB
u('what changed?')
a_text('a'); fb('zero-tools: x'); a_text('b'); fb('zero-tools: x'); a_text('c'); fb('zero-tools: x'); a_text('d')"

echo "investigate-first-gate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
