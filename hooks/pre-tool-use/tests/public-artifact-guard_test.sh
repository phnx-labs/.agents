#!/usr/bin/env bash
# Tests for public-artifact-guard.sh — the PreToolUse guard against committing
# confidential business strategy into a repo's COMMITTED .agents/artifacts/ dir.
#
# Hermetic: fixtures live in a sandbox; every case builds its own JSON payload
# and feeds it to the guard over stdin.
#
# The cases that matter are the two failure directions, not the happy path:
#   - a real RUSH-3033 filename must be DENIED, and
#   - an ordinary engineering plan carrying `surface: internal` must be ALLOWED,
#     because that field names a product surface, not a confidentiality level.
#     A guard that denies the common case gets bypassed, which is worse than no
#     guard at all.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../public-artifact-guard.sh"
SH_BIN="$(command -v sh)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0; fail=0

json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# run_guard <command-string> [path-override] -> sets RC, ERR
run_guard() {
  local cmdstr="$1" path_override="${2:-}"
  local json esc_cmd errfile
  esc_cmd=$(json_escape "$cmdstr")
  json=$(printf '{"tool_input":{"command":"%s"}}' "$esc_cmd")
  errfile="$SANDBOX/err.$$.$RANDOM"
  if [ -n "$path_override" ]; then
    RC=0; printf '%s' "$json" | PATH="$path_override" AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$HOOK" 2>"$errfile" || RC=$?
  else
    RC=0; printf '%s' "$json" | AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$HOOK" 2>"$errfile" || RC=$?
  fi
  ERR="$(cat "$errfile" 2>/dev/null)"
  rm -f "$errfile"
}

check() {  # check <label> <expected-rc> <actual-rc>
  if [ "$2" = "$3" ]; then
    pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL %s (expected rc=%s, got rc=%s)\n     %s\n' "$1" "$2" "$3" "$ERR"
  fi
}

ART="$SANDBOX/repo/.agents/artifacts/2026-08-19"
mkdir -p "$ART"

# A real leaked-document name from the RUSH-3033 incident.
printf -- '---\ntitle: "Monetizing agents-cli"\nsurface: internal\n---\n' > "$ART/monetize-agents-cli.md"
# An ordinary engineering plan — same dir, same `surface: internal` frontmatter.
printf -- '---\ntitle: "CLI identity surface"\nsurface: internal\n---\n' > "$ART/plan-cli-identity-surface.md"
# Confidential by explicit declaration, with an innocuous filename.
printf -- '---\ntitle: "Board notes"\nconfidential: true\n---\n' > "$ART/notes.md"
# The same phrase in PROSE, not frontmatter — must not trip the guard.
printf -- '---\ntitle: "Guard design"\n---\n\nWe considered `confidential: true` as a signal.\n' > "$ART/plan-guard-design.md"
# Outside the artifacts dir entirely.
mkdir -p "$SANDBOX/repo/.agents/scratch"
printf 'gtm notes\n' > "$SANDBOX/repo/.agents/scratch/gtm-strategy.md"

echo "public-artifact-guard"

run_guard "git add $ART/monetize-agents-cli.md"
check "denies a strategy-shaped filename in .agents/artifacts/" 2 "$RC"

case "$ERR" in
  *blocked_op:*artifacts.confidential-publish*) pass=$((pass+1)); printf '  ok   emits a structured denial\n' ;;
  *) fail=$((fail+1)); printf '  FAIL structured denial missing: %s\n' "$ERR" ;;
esac
case "$ERR" in
  *RUSH-3033*) pass=$((pass+1)); printf '  ok   cites the incident so the block is understandable\n' ;;
  *) fail=$((fail+1)); printf '  FAIL denial does not cite RUSH-3033: %s\n' "$ERR" ;;
esac

run_guard "git add $ART/notes.md"
check "denies an explicit 'confidential: true' frontmatter" 2 "$RC"

# --- the false-positive direction: these MUST be allowed -------------------
run_guard "git add $ART/plan-cli-identity-surface.md"
check "ALLOWS an ordinary plan that carries surface: internal" 0 "$RC"

run_guard "git add $ART/plan-guard-design.md"
check "ALLOWS 'confidential: true' appearing in prose, not frontmatter" 0 "$RC"

run_guard "git add $SANDBOX/repo/.agents/scratch/gtm-strategy.md"
check "ALLOWS a strategy doc in gitignored .agents/scratch/" 0 "$RC"

run_guard "git status --short"
check "ignores commands that stage nothing" 0 "$RC"

run_guard "git commit $ART/monetize-agents-cli.md -m wip"
check "covers git commit <path>, not just git add" 2 "$RC"

# --- staging the DIRECTORY, which is how a whole day actually gets added ----
# The first version of this guard checked only the literal argument, so
# `git add <day-dir>/` sailed through while `git add <day-dir>/gtm.md` blocked —
# i.e. it caught the careful caller and missed the realistic one.
run_guard "git add $ART"
check "denies staging a DIRECTORY that contains a confidential file" 2 "$RC"

run_guard "git add $ART/"
check "denies the same directory with a trailing slash" 2 "$RC"

run_guard "git add $SANDBOX/repo/.agents/artifacts"
check "denies the artifacts root when a confidential file is anywhere under it" 2 "$RC"

CLEANDAY="$SANDBOX/repo/.agents/artifacts/2026-08-21"
mkdir -p "$CLEANDAY"
printf -- '---\ntitle: "Session tracker"\nsurface: internal\n---\n' > "$CLEANDAY/plan-session-tracker.md"
run_guard "git add $CLEANDAY"
check "ALLOWS a directory whose artifacts are all ordinary plans" 0 "$RC"

# A private-ruleset compile: no strategy words in the name, no frontmatter to
# declare itself, but it is the operator's private config in a public tree.
printf '# Foundations\n\nF1 — you own the whole task.\n' > "$CLEANDAY/compiled-ruleset.md"
run_guard "git add $CLEANDAY/compiled-ruleset.md"
check "denies a compiled private ruleset (no frontmatter, innocuous name)" 2 "$RC"
rm -f "$CLEANDAY/compiled-ruleset.md"

# Paths that do not exist must not blow up under `set -eu`.
run_guard "git add $ART/does-not-exist.md"
check "tolerates a nonexistent path without erroring" 0 "$RC"

# --- review blockers, each reproduced then pinned ---------------------------
# A non-author review found five. They shared one root cause: the first version
# walked every whitespace-separated word of the command with no shell grammar,
# so it mis-parsed quotes, ignored the subcommand, and resolved paths against
# the wrong directory.

# B1: `cd <dir> && git add <relative>` bypassed the guard entirely, because the
# existence gates resolved against the HOOK's cwd, not the cd target. The name
# test now runs on the path string alone, so no filesystem resolution is needed
# for it at all.
run_guard "cd $SANDBOX/repo && git add .agents/artifacts/2026-08-19/monetize-agents-cli.md"
check "B1: catches cd <dir> && git add <relative path>" 2 "$RC"

# B2: a quoted path containing a space was split into two useless fragments --
# one with the directory but an innocuous basename, one with the filename but no
# directory -- so a check needing both matched neither.
QD="$SANDBOX/repo/.agents/artifacts/my docs"
mkdir -p "$QD"
printf -- '---\ntitle: "G"\n---\n' > "$QD/gtm-strategy.md"
printf -- '---\ntitle: "B"\nconfidential: true\n---\n' > "$QD/board notes.md"
run_guard "git add \"$QD/gtm-strategy.md\""
check "B2: catches a double-quoted path with a space" 2 "$RC"
run_guard "git add '$QD/board notes.md'"
check "B2: catches a single-quoted path with a space" 2 "$RC"

# B3: read-only commands that merely NAME a strategy path were blocked, because
# nothing scoped the check to a staging subcommand.
run_guard "git log --oneline $ART/monetize-agents-cli.md"
check "B3: ALLOWS git log naming a strategy path" 0 "$RC"
run_guard "git diff $ART/monetize-agents-cli.md"
check "B3: ALLOWS git diff naming a strategy path" 0 "$RC"

# B4: the worst failure mode available to this hook. It runs on every git add
# fleet-wide, so blocking real work gets it switched off, and then it protects
# nothing. Loose substrings (*pricing-model*, *monetiz*, *fundrais*) blocked all
# of these; matching is now anchored on whole document names.
for eng in plan-pricing-model-api monetization-service-refactor \
           fundraising-page-redesign plan-revenue-model-migration \
           gtm-dashboard-component pricing-page-redesign; do
  printf -- '---\ntitle: "eng"\nsurface: internal\n---\n' > "$ART/$eng.md"
  run_guard "git add $ART/$eng.md"
  check "B4: ALLOWS engineering file $eng.md" 0 "$RC"
  rm -f "$ART/$eng.md"
done

# --- the sweeping forms -----------------------------------------------------
# `git add -A` is the MOST likely leak vector, not an edge case: the recap
# workflow tells agents to commit any uncommitted work they find, and this is
# how that gets done. The guard reads `git status --porcelain` to see exactly
# what git is about to stage. Both directions are asserted, because a guard that
# fires on every clean `git add -A` would be turned off fleet-wide within a day.
SWEEP="$SANDBOX/sweeprepo"
mkdir -p "$SWEEP/.agents/artifacts/2026-08-19"
git -C "$SWEEP" init -q 2>/dev/null
git -C "$SWEEP" config user.email t@t.t 2>/dev/null
git -C "$SWEEP" config user.name t 2>/dev/null

# Clean first: an ordinary plan pending, nothing confidential.
printf -- '---\ntitle: "A plan"\nsurface: internal\n---\n' > "$SWEEP/.agents/artifacts/2026-08-19/plan-thing.md"
RC=0
printf '{"tool_input":{"command":"git add -A"}}' \
  | (cd "$SWEEP" && AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$HOOK") 2>/dev/null || RC=$?
check "ALLOWS git add -A when nothing confidential is pending" 0 "$RC"

# Now drop a confidential file into the same pending set.
printf -- '---\ntitle: "GTM"\n---\n' > "$SWEEP/.agents/artifacts/2026-08-19/gtm-strategy.md"
RC=0
printf '{"tool_input":{"command":"git add -A"}}' \
  | (cd "$SWEEP" && AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$HOOK") 2>/dev/null || RC=$?
check "denies git add -A when a confidential file is pending" 2 "$RC"

RC=0
printf '{"tool_input":{"command":"git commit -a -m wip"}}' \
  | (cd "$SWEEP" && AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$HOOK") 2>/dev/null || RC=$?
check "denies git commit -a the same way" 2 "$RC"

# Outside a git repo the status probe must fail open, not error under set -eu.
RC=0
printf '{"tool_input":{"command":"git add -A"}}' \
  | (cd "$SANDBOX" && AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$HOOK") 2>/dev/null || RC=$?
check "tolerates git add -A outside a git repo" 0 "$RC"

# --- fail closed with no JSON parser --------------------------------------
NOPARSE="$SANDBOX/noparse-bin"
mkdir -p "$NOPARSE"
for t in cat sed awk head tr printf; do
  src="$(command -v "$t" 2>/dev/null)" && [ -n "$src" ] && ln -sf "$src" "$NOPARSE/$t"
done
run_guard "git add $ART/monetize-agents-cli.md" "$NOPARSE"
check "fails CLOSED when no jq/node/python is available" 2 "$RC"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
