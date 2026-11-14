#!/usr/bin/env bash
# rules-check_test.sh — runs rules-check.sh against throwaway ~/.agents trees.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/rules-check.sh"
pass=0 fail=0
check() {  # check <name> <condition...>
  local name=$1; shift
  if "$@"; then pass=$((pass + 1)); echo "ok    $name"; else fail=$((fail + 1)); echo "FAIL  $name"; sed 's/^/      /' "$T/out"; fi
}
same() { [ "$(cat "$1")" = "$2" ]; }

setup() {  # a system layer with presets default=[core] and custom=[alt], one claude version
  T=$(mktemp -d); export HOME=$T GIT_CEILING_DIRECTORIES=$T
  A=$T/.agents; S=$A/.system/rules
  mkdir -p "$S/subrules" "$A/rules" "$A/.history/versions/claude/1.0.0/home/.claude"
  printf 'presets:\n  default:\n    subrules:\n      - core\n  custom:\n    subrules: [alt]\n' > "$S/rules.yaml"
  printf 'CORE\n\n' > "$S/subrules/core.md"
  printf 'ALT\n' > "$S/subrules/alt.md"
  V=$A/.history/versions/claude/1.0.0/home/.claude
  printf 'OLD\n' > "$V/CLAUDE.md"
}
run() { bash "$SCRIPT" "$@" > "$T/out" 2>&1; }

setup; run --apply
check "a stale file is rewritten" same "$V/CLAUDE.md" "CORE"
rm "$V/CLAUDE.md"; run --apply
check "an absent file is created" same "$V/CLAUDE.md" "CORE"

setup; printf 'presets:\n  default:\n    subrules: [alt, core]\n' > "$S/rules.yaml"; run --apply
check "a flow-style subrules list composes" same "$V/CLAUDE.md" "$(printf 'ALT\n\nCORE')"

setup; printf '{"claude":{"1.0.0":{"rulesPreset":"custom"}}}' > "$A/.history/version-resources.json"; run --apply
check "the version's rulesPreset in version-resources.json is composed" same "$V/CLAUDE.md" "ALT"

setup; printf '{"claude":{"1.0.0":{"rulesPreset":"missing"}}}' > "$A/.history/version-resources.json"; run --apply
check "a preset no layer defines leaves the file as is" same "$V/CLAUDE.md" "OLD"
check "  and is reported" grep -q NOPRESET "$T/out"

setup; rm "$S/rules.yaml"; run --apply
check "no rules.yaml leaves the file as is (never empties it)" same "$V/CLAUDE.md" "OLD"

setup; printf 'extraRepos:\n  team: {url: x, enabled: true}\n' > "$A/agents.yaml"; run --apply; rc=$?
check "an enabled extra repo makes --apply change nothing" same "$V/CLAUDE.md" "OLD"
check "  and exits non-zero" [ "$rc" = 1 ]

setup; mkdir "$T/outside"; printf 'KEEP\n' > "$T/outside/CLAUDE.md"
rm -r "$V"; ln -s "$T/outside" "$V"; run --apply; rc=$?
check "a symlinked config dir is not written through" same "$T/outside/CLAUDE.md" "KEEP"
check "  and the failure exits non-zero" [ "$rc" = 1 ]

setup; printf 'KEEP\n' > "$T/sentinel"; ln -s "$T/sentinel" "$V/CLAUDE.md.rules-check.tmp"; run --apply
check "a planted temp-file symlink is not written through" same "$T/sentinel" "KEEP"
check "  and the file is still fixed" same "$V/CLAUDE.md" "CORE"

setup; mkdir -p "$T/ext" "$A/rules/subrules"; printf 'EXT\n' > "$T/ext/rule.md"
ln -s "$T/ext" "$A/rules/subrules/linked"; printf 'MINE\n' > "$A/rules/subrules/mine.md"; run --apply
check "a symlinked user subrule dir is skipped, a user file unions in" same "$V/CLAUDE.md" "$(printf 'CORE\n\nMINE')"

setup; mkdir -p "$A/.history/accounts/cursor/a1/.cursor"; printf 'X\n' > "$A/.history/accounts/cursor/a1/.cursor/.cursorrules"; run
check "a frozen account copy outside .claude is reported" grep -q 'frozen .history/accounts/cursor/a1/.cursor/.cursorrules' "$T/out"

echo "---"; echo "rules-check: $pass passed, $fail failed"
[ "$fail" = 0 ]
