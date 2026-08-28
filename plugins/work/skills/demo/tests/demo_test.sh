#!/usr/bin/env bash
# Contract test for the work:demo skill. A guidance skill has no compiled behavior to
# unit-test; its VALUE is entirely in the mandate it carries and the command wiring that
# reaches it. Both regress silently:
#
#   1. Wiring — plugins/AGENTS.md warns that a rename leaves dangling alias links that
#      "route to nothing" (how the last removal broke three skills). This asserts the
#      top-level /demo alias and the /work:demo command both exist and route to the
#      `work:demo` skill, so a rename that forgets one fails loud here instead of at
#      an agent's runtime.
#   2. Mandate — the whole point of /demo is: real environment (NOT the dev build),
#      real logged-in account, REAL representative inputs (NOT toy examples), before/
#      after with a measured delta, and honest gaps. An edit that softens any of these
#      guts the skill while still "reading fine." Each is asserted as a load-bearing
#      contract phrase; if a rewrite drops one, decide deliberately and update the test.
#
# Real files on disk, no mocks. Run: bash plugins/work/skills/demo/tests/demo_test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../../../.." && pwd)"
SKILL="$REPO/plugins/work/skills/demo/SKILL.md"
CMD="$REPO/plugins/work/commands/demo.md"
ALIAS="$REPO/commands/demo.md"
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# -- wiring -------------------------------------------------------------------
[ -f "$SKILL" ] && ok "skill exists: plugins/work/skills/demo/SKILL.md" \
  || bad "skill missing: plugins/work/skills/demo/SKILL.md"
grep -q '^name: demo$' "$SKILL" \
  && ok "skill declares name: demo" || bad "skill missing 'name: demo' frontmatter"

if [ -f "$CMD" ]; then
  grep -qi 'work:demo' "$CMD" \
    && ok "/work:demo command routes to the work:demo skill" \
    || bad "plugins/work/commands/demo.md does not reference the work:demo skill"
else
  bad "command missing: plugins/work/commands/demo.md"
fi

if [ -f "$ALIAS" ]; then
  grep -qi 'work:demo' "$ALIAS" \
    && ok "top-level /demo alias routes to the work:demo skill" \
    || bad "commands/demo.md (alias) does not reference the work:demo skill"
else
  bad "top-level alias missing: commands/demo.md"
fi

# -- mandate (load-bearing contract phrases) ----------------------------------
contract() { # $1 = grep -E pattern, $2 = human name of the invariant
  grep -Eqi "$1" "$SKILL" && ok "mandate kept: $2" \
    || bad "mandate LOST: $2 — the skill no longer enforces this; was that deliberate?"
}
contract 'never the dev build|not the dev build|dev build.*call it shipped|released artifact' \
  "demo the REAL/released environment, never the dev build"
contract 'real,? representative input|never toy example|not.*toy|toy example' \
  "REAL representative inputs, never toy examples"
contract 'sign(ed)? in|logged.?in|profiles logins' \
  "sign in as the owner (real logged-in account)"
contract 'before[ /]*(vs|and|/)?[ ]*after|side by side' \
  "before/after side by side"
contract 'measure|measured|quantif|delta' \
  "quantify the improvement (measured delta)"
contract 'gap|missing|partial' \
  "surface honest gaps"
contract 'agents browser|agents computer' \
  "reach for agents browser / agents computer"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "DEMO SKILL CONTRACT FAILED"; exit 1; }
echo "ALL DEMO SKILL CONTRACT CHECKS PASSED"
