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

setup; printf 'versions:\n  claude:\n    1.0.0: {rulesPreset: custom}\n' > "$A/.system/agents.yaml"; run --apply
check "a rulesPreset set only in the system agents.yaml is composed" same "$V/CLAUDE.md" "ALT"

setup; printf 'versions:\n  claude:\n    1.0.0: {rulesPreset: custom}\n' > "$A/agents.yaml"
printf '{}' > "$A/.history/version-resources.json"; run --apply
check "version-resources.json supersedes a legacy agents.yaml selection" same "$V/CLAUDE.md" "CORE"

setup; printf 'presets:\n  default:\n    subrules: [on]\n' > "$S/rules.yaml"; printf 'ON RULE\n' > "$S/subrules/on.md"; run --apply
check "a subrule named 'on' is a name, not a boolean" same "$V/CLAUDE.md" "ON RULE"

setup; mkdir -p "$T/team/rules/subrules"; printf 'TEAM\n' > "$T/team/rules/subrules/team.md"
printf 'extraRepos:\n  team: {url: x, enabled: true, path: %s}\n' "$T/team" > "$A/agents.yaml"; run --apply
check "an enabled extra repo's subrules union in" same "$V/CLAUDE.md" "$(printf 'CORE\n\nTEAM')"

setup; H=$A/.history/versions/claude/1.0.0/home
mkdir -p "$T/outside2/.claude"; printf 'KEEP\n' > "$T/outside2/.claude/CLAUDE.md"
mv "$H" "$T/moved-home"; ln -s "$T/outside2" "$H"; run --apply; rc=$?
check "a symlinked version home is not written through" same "$T/outside2/.claude/CLAUDE.md" "KEEP"
check "  and the failure exits non-zero" [ "$rc" = 1 ]

setup; mkdir "$T/outside"; printf 'KEEP\n' > "$T/outside/CLAUDE.md"
mv "$V" "$T/moved-claude"; ln -s "$T/outside" "$V"; run --apply; rc=$?
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

setup; mv "$A/.history/versions" "$T/versions-elsewhere"; ln -s "$T/versions-elsewhere" "$A/.history/versions"; run --apply; rc=$?
check "a symlinked versions dir is not written through" same "$T/versions-elsewhere/claude/1.0.0/home/.claude/CLAUDE.md" "OLD"
check "  and the failure exits non-zero" [ "$rc" = 1 ]

setup; printf 'versions:\n  claude:\n    default: 1.0.0\n' > "$A/.system/meta.yaml"; chmod 755 "$A"
# .agents/.cache is left out: importing agents-cli's modules opens its own empty secrets-serve log there.
snap() {  # files: mode, size, mtime; directories: mode only (macOS sizes a directory by its entries)
  (cd "$T" && { find . -type f -exec stat -c '%n %a %s %Y' {} + 2>/dev/null || find . -type f -exec stat -f '%N %Lp %z %m' {} +
                find . ! -type f -exec stat -c '%n %a' {} + 2>/dev/null || find . ! -type f -exec stat -f '%N %Lp' {} +; }) \
    | grep -v -e '^\./out ' -e '^\./\.agents/\.cache' | sort
}
before=$(snap); run; after=$(snap)
diff <(echo "$before") <(echo "$after") >> "$T/out"
check "a report changes nothing on disk (no metadata migration, no chmod)" [ "$before" = "$after" ]

setup; real=$(dirname "$(node -e 'console.log(require("fs").realpathSync(process.argv[1]))' "$(command -v agents)")")
real=${real%/bin}; P=$T/pkg; mkdir -p "$P/dist/bin" "$T/bin"
printf '{"name":"@phnx-labs/agents-cli"}' > "$P/package.json"; ln -s "$real/lib" "$P/dist/lib"
printf '#!/bin/sh\n' > "$P/dist/bin/agents"; chmod +x "$P/dist/bin/agents"; ln -s "$P/dist/bin/agents" "$T/bin/agents"
PATH="$T/bin:$PATH" run --apply
check "a native dist/bin/agents entrypoint finds the package's modules" same "$V/CLAUDE.md" "CORE"

echo "---"; echo "rules-check: $pass passed, $fail failed"
[ "$fail" = 0 ]
