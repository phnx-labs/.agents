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
if printf '%s' "$out2" | grep -q "User-facing change with no docs and CHANGELOG update"; then
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
if printf '%s' "$out4" | grep -q "Release/live verification incomplete"; then
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
if printf '%s' "$out6" | grep -q "Visual delivered without image read-back"; then
  echo "PASS: scratch visual delivery requires image read-back"
else
  echo "FAIL: scratch visual delivery passed without image read-back:"; echo "$out6"; fail=1
fi

# --- Test 7: merged but still under [Unreleased], in a repo that has tags -> gate FIRES --
# The old check set release_ran=True whenever `git describe --tags` answered at all, so any
# repo that had ever cut a release satisfied it forever. Measured 2026-08-15: agents-cli has
# 185 tags, PR #2705 merged with its entry stranded under `## [Unreleased]`, and the session
# stopped clean asking whether to release. A tag in history is not a shipped change.
d7="$(mktemp -d)"; bare7="$(mktemp -d)/o.git"
git init -q "$d7"; git init -q --bare "$bare7"
printf '{"name":"ext","version":"0.9.321"}\n' > "$d7/package.json"
printf '# Changelog\n\n## [Unreleased]\n\n- a user-facing feature merged and never published\n\n## [0.9.321] - 2026-08-14\n- shipped\n' > "$d7/CHANGELOG.md"
git -C "$d7" add package.json CHANGELOG.md; git -C "$d7" $GC commit -q -m "baseline"
git -C "$d7" tag v0.9.321
git -C "$d7" remote add origin "$bare7"; git -C "$d7" push -q origin HEAD:main
git -C "$d7" remote set-head origin main
# Commit ahead of origin/main rather than branching — the gate diffs origin/<default>..HEAD,
# so this produces the same changed-file set with no branch operation.
printf '# Changelog\n\n## [Unreleased]\n\n- a user-facing feature merged and never published\n- add the new publish flag\n\n## [0.9.321] - 2026-08-14\n- shipped\n' > "$d7/CHANGELOG.md"
git -C "$d7" $GC commit -q -am "feat: add the new publish flag"
tr7="$(mktemp)"
# The transcript carries BOTH release-command and live-verify evidence ("released
# v0.9.321", "npm view ... version"), so under the OLD code release_ran and
# verified_live were both True and the gate stayed silent — the reviewer reproduced
# exactly that (all 8 tests green against pre-fix code when this transcript lacked
# such evidence, because the gate then fired for the unrelated not-verified reason).
# Only the [Unreleased] override makes the gate fire here, so this test now fails
# against the old code and passes against the new.
printf '%s\n' '{"role":"user","content":"add a new publish flag and release it"}' > "$tr7"
printf '%s\n' '{"role":"assistant","content":"released v0.9.321 earlier; npm view ext version shows 0.9.321 — registry verified live"}' >> "$tr7"
out7="$(run_gate "$d7" "$tr7")"
if printf '%s' "$out7" | grep -q 'Unreleased'; then
  echo "PASS: gate fires on merged-but-unreleased even though the repo has a tag"
else
  echo "FAIL: a tag in history silently satisfied the release gate:"; echo "$out7"; fail=1
fi

# --- Test 8: an EMPTY [Unreleased] heading is the resting state -> must not trip it -----
d8="$(mktemp -d)"; bare8="$(mktemp -d)/o.git"
git init -q "$d8"; git init -q --bare "$bare8"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] - 2026-01-01\n- shipped\n' > "$d8/CHANGELOG.md"
printf 'hello\n' > "$d8/README.md"
git -C "$d8" add CHANGELOG.md README.md; git -C "$d8" $GC commit -q -m "baseline"
git -C "$d8" remote add origin "$bare8"; git -C "$d8" push -q origin HEAD:main
git -C "$d8" remote set-head origin main
# Same as above: commit ahead of origin/main, no branch operation.
printf 'hello there\n' > "$d8/README.md"
git -C "$d8" $GC commit -q -am "docs: tweak readme"
tr8="$(mktemp)"
printf '%s\n' '{"role":"user","content":"fix a typo in the readme"}' > "$tr8"
out8="$(run_gate "$d8" "$tr8")"
if printf '%s' "$out8" | grep -qi "unreleased"; then
  echo "FAIL: an empty [Unreleased] heading was treated as staged work:"; echo "$out8"; fail=1
else
  echo "PASS: an empty [Unreleased] heading does not trip the release gate"
fi

# --- Test 9: ticket demands are scoped to tickets this session WORKED; -----------
# --- merely-referenced tickets are FYI, never a demand (RUSH-3013). --------------
d9="$(mktemp -d)"
git init -q "$d9"
git -C "$d9" $GC commit -q --allow-empty -m init
git -C "$d9" checkout -q -b rush-9001-fix
echo x > "$d9/f.txt"; git -C "$d9" add f.txt; git -C "$d9" $GC commit -q -m "fix: f (RUSH-9001)"
stubdir="$(mktemp -d)"
cat > "$stubdir/linear" <<'STUB'
#!/usr/bin/env bash
printf '{"state":{"name":"Todo"},"title":"Fake"}\n'
STUB
chmod +x "$stubdir/linear"
tr9="$(mktemp)"
{
  printf '%s\n' '{"role":"user","content":"context: RUSH-9002 is someone else'"'"'s in-flight work; fix RUSH-9001"}'
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"l1","name":"Bash","input":{"command":"linear update RUSH-9001 --status Doing"}}]}}'
} > "$tr9"
out9="$(PATH="$stubdir:$PATH" run_gate "$d9" "$tr9")"
if printf '%s' "$out9" | grep -q "then finish:"; then
  echo "PASS: gate header says 'then finish', not 'stop again'"
else
  echo "FAIL: gate header wording wrong:"; echo "$out9"; fail=1
fi
if printf '%s' "$out9" | grep -q "this session worked: RUSH-9001"; then
  echo "PASS: worked ticket RUSH-9001 is demanded"
else
  echo "FAIL: worked ticket not demanded:"; echo "$out9"; fail=1
fi
if printf '%s' "$out9" | grep -q "not yours to close.*RUSH-9002"; then
  echo "PASS: referenced ticket RUSH-9002 is FYI only"
else
  echo "FAIL: referenced ticket not FYI:"; echo "$out9"; fail=1
fi
if printf '%s' "$out9" | grep -q "update state with proof.*RUSH-9002"; then
  echo "FAIL: referenced ticket RUSH-9002 was demanded:"; echo "$out9"; fail=1
else
  echo "PASS: referenced ticket is never a --done demand"
fi

rm -rf "$d1" "$d2" "$d3" "$d4" "$d7" "$d8" "$d9" "$stubdir" "$bare2" "$bare3" "$bare4" "$bare7" "$bare8" "$tr1" "$tr2" "$tr3" "$tr4" "$tr5" "$tr6" "$tr7" "$tr8" "$tr9" 2>/dev/null

if [ "$fail" -ne 0 ]; then
  echo "verify-delivery-chain_test: FAILED"; exit 1
fi
echo "verify-delivery-chain_test: all passed"
