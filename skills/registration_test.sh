#!/bin/bash
# Every skill installs into ONE flat directory (~/.<agent>/skills/), so two SKILL.md
# files declaring the same `name:` contest a single slot. The installer picks a winner
# silently — no error, no warning — and the loser is reachable only via its namespaced
# plugin id. This test makes that visible before it ships.
#
# It also catches the two ways a skill goes invisible: missing frontmatter, and a skill
# on disk that no README row lists.
#
# Run: bash skills/registration_test.sh   (from the repo root or anywhere)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
FAIL=0

# Bare names that are legitimately declared twice. Each needs a reason, because every
# entry here is a slot whose winner is decided by install order rather than by design.
#
#   browser — the user layer MUST shadow the system copy: agents-cli resolves browser
#             domain-skills from a hardcoded ~/.agents/skills/browser/domain-skills
#             with no system-layer fallback, and resolveDomainSkill swallows a miss
#             silently. Documented in ~/.agents/CLAUDE.md (RUSH-2497). Remove this
#             entry when that resolver searches user -> system.
#   learn   — top-level `learn` (post-session reflection) vs code:learn (learn the
#             codebase). Different jobs; the bare name resolves to the top-level one.
#   run     — top-level `run` (one agent) vs swarm:run (fan out). Different jobs.
#   loop    — code:loop vs work:loop. KNOWN WRONG: the bare name resolves to the
#             narrower code:loop while work:loop describes itself as the general case.
ALLOWED_CONTESTED="browser learn run loop"

say() { printf '%s\n' "$*"; }
fail() { say "FAIL - $*"; FAIL=1; }
ok()   { say "ok   - $*"; }

# ---------------------------------------------------------------- name contention
say "== contested bare names =="
NAMES_FILE="$(mktemp)"
trap 'rm -f "$NAMES_FILE"' EXIT

# The flat install namespace merges BOTH layers, so a cross-layer collision (user-layer
# skill shadowing a system one) is the case most worth catching. Scan the user layer too
# when it exists, so the `browser` entry below is real coverage rather than an inert claim.
USER_LAYER="${AGENTS_USER_DIR:-$HOME/.agents}"
for f in "$REPO"/skills/*/SKILL.md "$REPO"/plugins/*/skills/*/SKILL.md \
         "$USER_LAYER"/skills/*/SKILL.md "$USER_LAYER"/plugins/*/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in "$REPO"/*) rel="${f#"$REPO"/}" ;; *) rel="~/${f#"$HOME"/}" ;; esac
  n=$(awk '/^name:/{sub(/^name:[[:space:]]*/,""); gsub(/["\x27]/,""); sub(/[[:space:]]+$/,""); print; exit}' "$f")
  [ -n "$n" ] && printf '%s|%s\n' "$n" "$rel" >> "$NAMES_FILE"
done

sort -o "$NAMES_FILE" "$NAMES_FILE"
contested=$(cut -d'|' -f1 "$NAMES_FILE" | uniq -d)

if [ -z "$contested" ]; then
  ok "no bare name is declared twice"
else
  for name in $contested; do
    homes=$(grep "^$name|" "$NAMES_FILE" | cut -d'|' -f2 | tr '\n' ' ')
    case " $ALLOWED_CONTESTED " in
      *" $name "*) ok "$name: contested but allowlisted ($homes)" ;;
      *)           fail "$name: NEW contested bare name - one of these silently wins the flat install slot: $homes" ;;
    esac
  done
fi

# ---------------------------------------------------------------- frontmatter
say ""
say "== frontmatter =="
missing=0
for f in "$REPO"/skills/*/SKILL.md "$REPO"/plugins/*/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  rel="${f#"$REPO"/}"
  grep -q '^name:' "$f"        || { fail "$rel: no 'name:' - the skill cannot be addressed"; missing=1; }
  grep -q '^description:' "$f" || { fail "$rel: no 'description:' - nothing to match on, so it never loads"; missing=1; }
done
[ "$missing" -eq 0 ] && ok "every SKILL.md declares name and description"

# ---------------------------------------------------------------- README coverage
say ""
say "== README coverage =="
README="$REPO/skills/README.md"
if [ ! -f "$README" ]; then
  fail "skills/README.md is missing"
else
  uncatalogued=0
  for d in "$REPO"/skills/*/; do
    n=$(basename "$d")
    [ -f "$d/SKILL.md" ] || continue
      # Match the catalog LINK, not the bare word. A word-boundary grep passes on prose:
    # deleting the real `run` row still passed because "run" appears in the secrets row.
    grep -q "$n/SKILL.md" "$README" || { fail "skills/$n is on disk but has no catalog row in skills/README.md - invisible to humans"; uncatalogued=1; }
  done
  [ "$uncatalogued" -eq 0 ] && ok "every top-level skill has a README row"
fi

say ""
if [ "$FAIL" -ne 0 ]; then
  say "SKILL REGISTRATION FAILED"
  exit 1
fi
say "ALL SKILL REGISTRATION CHECKS PASSED"
exit 0
