#!/usr/bin/env bash
# Tests for verify-delivery-chain.py — the delivery close-the-loop gate.
#
# Invariant under test: the user-facing / shippable keyword heuristics describe a
# *conversation about* a feature, not a *delivery of* one. The gate must fire only
# when the session produced a real shippable change — a tracked file outside
# scratch/artifact/tmp paths, or a responsible PR. It must NOT fire when the only
# output is conversation, or writes confined to non-deliverable scratch paths.
#
# Real critical path: builds throwaway git repos + transcripts and runs the actual
# script. No mocking.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../verify-delivery-chain.py"
fail=0
GC="-c user.email=t@example.com -c user.name=tester"

# run_gate <repo_path> <transcript_path> [goal_offset] -> gate stdout
run_gate() {
  local injson
  injson="$(mktemp)"
  printf '{"transcript_path":"%s","responsible_prs":[],"last_assistant_message":"done","repo_path":"%s","goal_offset":%s}\n' "$2" "$1" "${3:-0}" > "$injson"
  python3 "$SCRIPT" < "$injson" 2>/dev/null
  rm -f "$injson"
}

# --- Test 1: conversation names a "command" but nothing changed -> NO gate --------
d1="$(mktemp -d)"
git init -q "$d1"
git -C "$d1" $GC commit -q --allow-empty -m init
tr1="$(mktemp)"
printf '%s\n' '{"role":"user","content":"which of these commands are used most often across sessions"}' > "$tr1"
out1="$(run_gate "$d1" "$tr1")"
if [ -z "$out1" ]; then
  echo "PASS: no gate when a user-facing keyword appears with zero changed files"
else
  echo "FAIL: gate fired on a no-delivery conversation:"; echo "$out1"; fail=1
fi

# --- Test 2: real user-facing delivery, missing docs/CHANGELOG -> gate FIRES ------
d2="$(mktemp -d)/r"; bare2="$(mktemp -d)/o.git"
mkdir -p "$d2"; git init -q "$d2"
git init -q --bare "$bare2"
git -C "$d2" $GC commit -q --allow-empty -m base
echo base > "$d2/base.txt"; git -C "$d2" add base.txt; git -C "$d2" $GC commit -q -m base-file
git -C "$d2" remote add origin "$bare2"
git -C "$d2" push -q origin HEAD:main
git -C "$d2" remote set-head origin main
git -C "$d2" checkout -q -b feature
mkdir -p "$d2/src"; printf 'print(1)\n' > "$d2/src/foo.py"
git -C "$d2" add src/foo.py; git -C "$d2" $GC commit -q -m "add new command foo"
tr2="$(mktemp)"
printf '%s\n' '{"role":"user","content":"please add a new command called foo to the cli tool"}' > "$tr2"
out2="$(run_gate "$d2" "$tr2")"
if printf '%s' "$out2" | grep -q "User-facing change detected"; then
  echo "PASS: gate still fires on a real user-facing delivery missing docs/CHANGELOG"
else
  echo "FAIL: gate did NOT fire on a real user-facing delivery:"; echo "$out2"; fail=1
fi

# --- Test 3: only a scratch/artifact file changed -> NO gate ----------------------
d3="$(mktemp -d)/r"; bare3="$(mktemp -d)/o.git"
mkdir -p "$d3"; git init -q "$d3"
git init -q --bare "$bare3"
echo base > "$d3/base.txt"; git -C "$d3" add base.txt; git -C "$d3" $GC commit -q -m base-file
git -C "$d3" remote add origin "$bare3"
git -C "$d3" push -q origin HEAD:main
git -C "$d3" remote set-head origin main
git -C "$d3" checkout -q -b feature
mkdir -p "$d3/.agents/artifacts"; printf 'report\n' > "$d3/.agents/artifacts/report.md"
git -C "$d3" add -f .agents/artifacts/report.md; git -C "$d3" $GC commit -q -m "add analysis report"
tr3="$(mktemp)"
printf '%s\n' '{"role":"user","content":"add a new command summary and save it as a report file"}' > "$tr3"
out3="$(run_gate "$d3" "$tr3")"
if [ -z "$out3" ]; then
  echo "PASS: no gate when the only changed file is a non-deliverable scratch/artifact path"
else
  echo "FAIL: gate fired on a scratch-only change:"; echo "$out3"; fail=1
fi

# --- Test 4: release from already-merged code (no diff, no PR) -> gate FIRES ------
# Regression guard: a release session ships without a local file diff or a PR, so
# is_real_delivery is False. That must NOT disable the shippable/release-verification
# gate — the release check keys off its own tag/publish/verify evidence.
d4="$(mktemp -d)"; bare4="$(mktemp -d)/o.git"
git init -q "$d4"
git init -q --bare "$bare4"
printf '{"name":"pkg","version":"1.0.0"}\n' > "$d4/package.json"
git -C "$d4" add package.json; git -C "$d4" $GC commit -q -m "baseline"
git -C "$d4" remote add origin "$bare4"
git -C "$d4" push -q origin HEAD:main
git -C "$d4" remote set-head origin main
tr4="$(mktemp)"
printf '%s\n' '{"role":"user","content":"please cut a release of version 1.0.1 to the registry"}' > "$tr4"
out4="$(run_gate "$d4" "$tr4")"
if printf '%s' "$out4" | grep -q "Independently-shippable change detected"; then
  echo "PASS: release-verification gate still fires on a zero-diff release session"
else
  echo "FAIL: release-verification gate was silently disabled for a zero-diff release:"; echo "$out4"; fail=1
fi

# --- Test 5: prior goal's feature/ticket evidence does not poison this goal ------
tr5="$(mktemp)"
printf '%s\n' '{"role":"user","content":"please add a new command for RUSH-9999"}' > "$tr5"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"linear update RUSH-9999 --comment done"}}]}}' >> "$tr5"
printf '%s\n' '{"role":"user","content":"please inspect whether the existing file contents are valid without changing them"}' >> "$tr5"
offset5=$(wc -c < "$tr5" | tr -d ' ')
printf '%s\n' '{"role":"assistant","content":"the configuration is valid"}' >> "$tr5"
out5="$(run_gate "$d2" "$tr5" "$offset5")"
if [ -z "$out5" ]; then
  echo "PASS: prior goal feature and ticket evidence is excluded"
else
  echo "FAIL: prior goal evidence poisoned the current diagnostic goal:"; echo "$out5"; fail=1
fi

# --- Test 6: a scratch visual shipped without read-back is a real delivery --------
tr6="$(mktemp)"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/mockup.html"}}]}}' > "$tr6"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"scp /tmp/mockup.html zion:/tmp/mockup.html"}}]}}' >> "$tr6"
out6="$(run_gate "$d1" "$tr6")"
if printf '%s' "$out6" | grep -q "Visual artifact delivery has no image read-back"; then
  echo "PASS: scratch visual delivery requires image read-back"
else
  echo "FAIL: scratch visual delivery passed without image read-back:"; echo "$out6"; fail=1
fi

rm -rf "$d1" "$d2" "$d3" "$d4" "$bare2" "$bare3" "$bare4" "$tr1" "$tr2" "$tr3" "$tr4" "$tr5" "$tr6" 2>/dev/null

if [ "$fail" -ne 0 ]; then
  echo "verify-delivery-chain_test: FAILED"; exit 1
fi
echo "verify-delivery-chain_test: all passed"
