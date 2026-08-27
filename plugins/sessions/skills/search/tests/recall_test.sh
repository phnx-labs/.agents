#!/usr/bin/env bash
# Real-path test for recall.py — no mocks. Runs against the actual local
# sessions.db and actual transcript files on this machine (the plugin's own
# README already states this whole plugin requires agents-cli + a populated
# local session index; this test is environment-dependent the same way).
#
# Covers:
#   1. A term drawn live from the real DB returns >=1 hit with a real snippet,
#      and the digest stays far smaller than the transcript it was pulled from
#      (proof it extracted capped snippets, not full transcripts).
#   2. Assistant-recovery proof: a phrase that exists ONLY in an assistant
#      turn of a real recent Claude session is invisible to the standard
#      `agents sessions "<phrase>"` search (assistant text is not indexed),
#      but recall.py recovers it via transcript grep once the session is a
#      candidate through an indexed neighboring term.
#   3. Cross-harness: a real Codex session with a real indexed term gets a
#      genuine recovered snippet (not a stub), and a real Kimi session
#      (transcript format recall.py does not parse yet) stays in the digest
#      as an honest index-only stub rather than silently disappearing.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
RECALL="$DIR/../recall.py"
DB="$HOME/.agents/.history/sessions/sessions.db"
pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

if [ ! -f "$DB" ]; then
  echo "SKIP - no local sessions.db at $DB (fresh machine, nothing indexed yet)"
  exit 0
fi

command -v python3 >/dev/null 2>&1 || { echo "SKIP - python3 not on PATH"; exit 0; }

# --- fixture: pick a real, currently-indexed term straight out of the DB ---
TERM=$(python3 - "$DB" <<'PY'
import re, sqlite3, sys
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
cur = db.cursor()
cur.execute(
    "SELECT t.content FROM session_text t JOIN sessions s ON s.id = t.session_id "
    "WHERE length(t.content) > 200 ORDER BY s.timestamp DESC LIMIT 50"
)
stop = {"should", "before", "because", "however", "already", "current", "instructions"}
for (content,) in cur:
    words = re.findall(r"[A-Za-z]{6,}", content)
    for w in words:
        if w.lower() not in stop:
            print(w)
            sys.exit(0)
PY
)

if [ -z "$TERM" ]; then
  echo "SKIP - could not draw a fixture term from session_text (empty index)"
  exit 0
fi

echo "--- test 1: known term '$TERM' returns a ranked, snippet-level hit ---"
OUT=$(python3 "$RECALL" "$TERM" --limit 3 --snippets 2 --json 2>&1)
RC=$?
if [ "$RC" -ne 0 ] && [ "$RC" -ne 3 ]; then
  bad "recall.py exited $RC (expected 0=hits or 3=no hits): $OUT"
else
  HITS=$(printf '%s' "$OUT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['hits']))" 2>/dev/null || echo 0)
  if [ "${HITS:-0}" -ge 1 ]; then
    ok "recall.py found >=1 session for '$TERM' ($HITS hit(s))"
  else
    bad "recall.py found 0 sessions for a term drawn live from its own index: $OUT"
  fi

  SNIPPET_OK=$(printf '%s' "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('1' if d['hits'] and d['hits'][0]['snippets'] and d['hits'][0]['snippets'][0]['text'].strip() else '0')
" 2>/dev/null || echo 0)
  [ "$SNIPPET_OK" = "1" ] && ok "first hit carries a non-empty snippet (not a whole-session ref)" \
    || bad "first hit has no snippet text"

  # "loads 0 full transcripts": the digest must stay far smaller than the
  # SUM of the transcripts recall.py actually opened for this exact query
  # (same --limit 3), not an unrelated single file — otherwise this
  # assertion compares apples to oranges and can flip on corpus shape alone.
  TX_TOTAL=$(python3 - "$DIR/.." "$TERM" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import recall
conn = recall.open_db()
try:
    candidates = recall.find_candidates(conn, [sys.argv[2]], None, None, 3)
finally:
    conn.close()
total = 0
for c in candidates:
    fp = recall.resolve_transcript_path(c["filePath"])
    if os.path.exists(fp):
        total += os.path.getsize(fp)
print(total)
PY
)
  OUT_BYTES=${#OUT}
  if [ "${TX_TOTAL:-0}" -gt 0 ] && [ "$OUT_BYTES" -lt "$TX_TOTAL" ]; then
    ok "digest ($OUT_BYTES bytes) is smaller than the ${TX_TOTAL} bytes of transcripts it was drawn from — capped, not dumped"
  else
    bad "digest size ($OUT_BYTES) not smaller than the $TX_TOTAL bytes actually opened — snippet cap may not be working"
  fi
fi

echo
echo "--- test 2: assistant-only recovery — agents CLI blind, recall.py sees it ---"
# session_text (what the bare `agents sessions "<q>"` query reads) only ever
# holds user turns + title/topic/project — never assistant text or tool I/O.
# So a token an assistant TYPED that also shows up in that same session's
# TOOL activity (tool_call_text, a separate index) is: (a) discoverable by
# recall.py via the tool-activity table, (b) invisible to the bare CLI query,
# which never consults tool_call_text, and (c) never a user-authored word by
# construction, since it's drawn straight out of assistant prose. Find one
# for real, in a real recent session.
FIXTURE=$(python3 - "$DB" <<'PY'
import json, os, re, shutil, sqlite3, subprocess, sys

db_path = sys.argv[1]
db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
cur = db.cursor()
cur.execute("SELECT id, short_id, file_path FROM sessions WHERE agent='claude' ORDER BY timestamp DESC LIMIT 60")
rows = cur.fetchall()

AGENTS_BIN = shutil.which("agents")

def cli_hit_count(token):
    if not AGENTS_BIN:
        return None
    try:
        out = subprocess.run(
            [AGENTS_BIN, "sessions", token, "--all", "--local", "--json"],
            capture_output=True, text=True, timeout=20,
        )
        data = json.loads(out.stdout)
        return len(data) if isinstance(data, list) else None
    except Exception:
        return None

# Bias toward rare, code-shaped tokens: dotted/hyphenated/colon-joined
# identifiers, long enough that plain-English collision across the whole
# corpus is unlikely (e.g. "session_text.content", "resources.ts:64-65"),
# not short common compounds like "pre-commit".
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:[.:/-][A-Za-z0-9_]+){1,4}")

def blocks(obj, role_filter):
    t = obj.get("type")
    if t != role_filter:
        return
    msg = obj.get("message") or {}
    content = msg.get("content")
    if not isinstance(content, list):
        return
    for c in content:
        if not isinstance(c, dict):
            continue
        if role_filter == "assistant" and c.get("type") == "text":
            yield c.get("text", "")
        elif role_filter == "assistant" and c.get("type") == "tool_use":
            yield json.dumps(c.get("input", {}))
        elif role_filter == "user" and c.get("type") == "tool_result":
            out = c.get("content")
            if isinstance(out, list):
                out = "\n".join(x.get("text", "") for x in out if isinstance(x, dict))
            yield str(out or "")

for sid, short_id, fp in rows:
    fp = fp.replace("[HOME]", os.path.expanduser("~"))
    if not os.path.exists(fp):
        continue
    assistant_text, tool_blob = [], []
    with open(fp, errors="ignore") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("type") == "assistant":
                msg = obj.get("message") or {}
                for c in msg.get("content") or []:
                    if not isinstance(c, dict):
                        continue
                    if c.get("type") == "text":
                        assistant_text.append(c.get("text", ""))
                    elif c.get("type") == "tool_use":
                        tool_blob.append(json.dumps(c.get("input", {})))
            elif obj.get("type") == "user":
                msg = obj.get("message") or {}
                content = msg.get("content")
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "tool_result":
                            out = c.get("content")
                            if isinstance(out, list):
                                out = "\n".join(x.get("text", "") for x in out if isinstance(x, dict))
                            tool_blob.append(str(out or ""))

    tool_text = "\n".join(tool_blob)
    if not tool_text:
        continue
    for para in assistant_text:
        for m in IDENT.finditer(para):
            token = m.group(0)
            if len(token) < 14 or token not in tool_text:
                continue
            c2 = db.cursor()
            c2.execute("SELECT session_id FROM session_text WHERE session_text MATCH ?", ('"' + token.replace('"', '""') + '"',))
            if c2.fetchall():
                continue  # also user-authored somewhere; not a clean fixture
            hits = cli_hit_count(token)
            if hits is not None and hits != 0:
                continue  # loose CLI token-OR matching still finds something; try another
            # the sentence this token sits in, for display + snippet-match
            start = para.rfind(".", 0, m.start()) + 1
            end = para.find(".", m.end())
            end = end + 1 if end != -1 else len(para)
            sentence = para[start:end].strip()
            if not sentence:
                sentence = token
            print(short_id)
            print(token)
            print(sentence[:160])
            sys.exit(0)
sys.exit(1)
PY
)
FIXTURE_RC=$?

if [ "$FIXTURE_RC" -ne 0 ] || [ -z "$FIXTURE" ]; then
  echo "SKIP - could not draw a tool-anchored assistant fixture token from recent sessions"
else
  FIXTURE_ID=$(printf '%s\n' "$FIXTURE" | sed -n '1p')
  FIXTURE_TOKEN=$(printf '%s\n' "$FIXTURE" | sed -n '2p')
  FIXTURE_SENTENCE=$(printf '%s\n' "$FIXTURE" | sed -n '3p')
  echo "fixture session: $FIXTURE_ID"
  echo "fixture token (assistant-typed, tool-anchored): $FIXTURE_TOKEN"
  echo "fixture sentence: $FIXTURE_SENTENCE"

  if command -v agents >/dev/null 2>&1; then
    CLI_OUT=$(agents sessions "$FIXTURE_TOKEN" --all --local --json 2>/dev/null)
    CLI_HITS=$(printf '%s' "$CLI_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "?")
    if [ "$CLI_HITS" = "0" ]; then
      ok "agents sessions '<assistant-typed token>' returns 0 hits (session_text has no assistant/tool text)"
    else
      bad "agents sessions unexpectedly returned $CLI_HITS hit(s) for an assistant-only token"
    fi
  else
    echo "SKIP - agents CLI not on PATH, skipping the CLI side of the before/after"
  fi

  RECOVER_OUT=$(python3 "$RECALL" "$FIXTURE_TOKEN" --limit 5 --snippets 5 --context 2 2>&1)
  if printf '%s' "$RECOVER_OUT" | grep -qF "$FIXTURE_TOKEN"; then
    ok "recall.py recovered the assistant-typed token via tool-activity candidate discovery"
  else
    bad "recall.py did not recover the assistant-typed token: $RECOVER_OUT"
  fi
fi

echo
echo "--- test 3: cross-harness — Codex gets a real snippet, an unparseable harness never vanishes ---"
# Regression coverage for the exact bug this fixup fixed: the transcript
# parser used to only understand Claude Code's envelope, so a Codex/Kimi
# session the FIND phase matched via the index would silently return 0
# hits from recall.py. Checked directly against recall.py's own
# find_candidates/build_digest (bypassing --limit ranking cutoffs, which are
# a candidate-ranking concern, not a recovery concern) for real local data:
#   (a) a Codex session with a real indexed term gets a genuine RECOVERED
#       snippet (not an index-only stub) — the parser actually reads it.
#   (b) a Kimi session (transcript format recall.py does not parse yet)
#       with a real indexed term still shows up in the digest as an
#       index-only stub with a `note` — it never just disappears.
CROSS_HARNESS=$(python3 - "$DIR/.." "$DB" <<'PY'
import re, sqlite3, sys
sys.path.insert(0, sys.argv[1])
import recall

db = sqlite3.connect(f"file:{sys.argv[2]}?mode=ro", uri=True)


def pick_fixture(agent):
    cur = db.cursor()
    cur.execute(
        "SELECT s.id, s.short_id, t.content FROM session_text t JOIN sessions s ON s.id = t.session_id "
        "WHERE s.agent = ? AND length(t.content) > 100 ORDER BY s.timestamp DESC LIMIT 30",
        (agent,),
    )
    for sid, short_id, content in cur.fetchall():
        for w in dict.fromkeys(re.findall(r"[A-Za-z]{7,}", content)):
            # confirm this term actually resolves this exact session as a
            # FIND candidate (not just present somewhere in its content —
            # bm25/tool-text tokenization can differ), independent of rank.
            conn = recall.open_db()
            try:
                candidates = recall.find_candidates(conn, [w], None, None, 200)
            finally:
                conn.close()
            match = next((c for c in candidates if c["id"] == sid), None)
            if match:
                return short_id, w, [match]
    return None


for agent, label in (("codex", "CODEX"), ("kimi", "KIMI")):
    fixture = pick_fixture(agent)
    if not fixture:
        print(f"{label}\tSKIP\tno local {agent} session with a term that resolves as a FIND candidate")
        continue
    short_id, term, candidates = fixture
    digest = recall.build_digest(candidates, [term], 3, 1)
    hit = next((d for d in digest if d["shortId"] == short_id), None)
    if hit is None:
        print(f"{label}\tMISSING\t{short_id}\t{term}")
    elif hit["snippets"]:
        print(f"{label}\tRECOVERED\t{short_id}\t{term}")
    else:
        print(f"{label}\tSTUB\t{short_id}\t{term}\t{hit.get('note')}")
PY
)

while IFS=$'\t' read -r LABEL STATUS A B C; do
  [ -z "$LABEL" ] && continue
  case "$LABEL:$STATUS" in
    CODEX:SKIP) echo "SKIP - $A" ;;
    CODEX:RECOVERED) ok "codex session $A ('$B') got a real recovered snippet, not a stub" ;;
    CODEX:MISSING) bad "codex session $A vanished from the digest for its own indexed term '$B' (candidate confirmed present)" ;;
    CODEX:STUB) bad "codex session $A only produced an index-only stub ($C) for its own indexed term '$B' — parser regression" ;;
    KIMI:SKIP) echo "SKIP - $A" ;;
    KIMI:STUB) ok "kimi session $A ('$B') stays in the digest as an honest index-only stub, not dropped" ;;
    KIMI:MISSING) bad "kimi session $A silently vanished from the digest for its own indexed term '$B' (candidate confirmed present) — the never-drop guarantee regressed" ;;
    KIMI:RECOVERED) echo "note: kimi session $A unexpectedly got a real recovered snippet (parser support improved) — not a failure" ;;
    *) bad "unrecognized test-3 result line: $LABEL $STATUS $A $B $C" ;;
  esac
done <<< "$CROSS_HARNESS"

echo
echo "--- test 4: snippet size is hard-capped, even when a term recurs densely ---"
# Deterministic (no live DB): a term recurring closer than the merge distance
# must NOT collapse into one runaway snippet. The digest-vs-transcript byte
# check in test 1 is too loose to catch this; assert the per-snippet line cap
# directly against grep_snippets.
CAP_OUT=$(python3 - "$DIR/.." <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import recall
context = 3
lines = [("user", "hit foo here" if i % 4 == 0 else "filler line %d" % i) for i in range(200)]
snips = recall.grep_snippets(lines, ["foo"], context, 5)
cap = 3 * context + 2            # the documented per-snippet span
worst = max((len(s["text"].splitlines()) for s in snips), default=0)
# +1 tolerance for the truncation marker line
print("OK" if snips and worst <= cap + 1 else f"FAIL worst={worst} cap={cap}")
PY
)
if [ "$CAP_OUT" = "OK" ]; then
  ok "no single snippet exceeds the ~$((3*3+2))-line cap under a dense-recurrence term"
else
  bad "snippet cap breached: $CAP_OUT"
fi

echo
echo "recall: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
