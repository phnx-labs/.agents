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
SCRIPT="$HERE/verify-delivery-chain.py"
fail=0
GC="-c user.email=t@example.com -c user.name=tester"

# run_gate <repo_path> <transcript_path> -> gate stdout
run_gate() {
  local injson
  injson="$(mktemp)"
  printf '{"transcript_path":"%s","responsible_prs":[],"last_assistant_message":"done","repo_path":"%s"}\n' "$2" "$1" > "$injson"
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

rm -rf "$d1" "$d2" "$d3" "$bare2" "$bare3" "$tr1" "$tr2" "$tr3" 2>/dev/null

if [ "$fail" -ne 0 ]; then
  echo "verify-delivery-chain_test: FAILED"; exit 1
fi
echo "verify-delivery-chain_test: all passed"
