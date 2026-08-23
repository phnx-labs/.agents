#!/usr/bin/env bash
# Test for merge-guard.sh (PreToolUse Bash guard).
#
# Verifies the guard BLOCKS a real `gh pr merge ... --admin` invocation (exit 2)
# and ALLOWS everything else — including (a) commands whose body/message TEXT
# merely mentions the trigger (the false-positive that fired on PR #40) and NOT
# failing open on (b) real invocations hidden inside quotes / command
# substitutions (`sh -c '...'`, `$(...)`, shell-fed heredocs).
#
# Exercises the real script over real stdin JSON (no mocking). Trigger tokens in
# THIS file are assembled from fragments so the currently-installed (old) guard
# doesn't block the test runner itself.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
GUARD="$DIR/merge-guard.sh"

# gh/git stubs so the review-on-this-PR check never touches the network in
# tests. Defaults keep every legacy case's expectation: reviews empty, comments
# carry a fresh APPROVE verdict (so a plain merge stays allowed). Cases override
# with FAKE_MG_REVIEWS / FAKE_MG_COMMENTS; FAKE_MG_GH_FAIL=1 simulates an API
# error (guard must fail open).
STUBTMP=$(mktemp -d)
trap 'rm -rf "$STUBTMP"' EXIT
mkdir -p "$STUBTMP/bin"
cat > "$STUBTMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# NOTE: no inline-JSON ${VAR:-default} here — a default word containing `}`
# terminates the parameter expansion early and emits malformed JSON.
[ "${FAKE_MG_GH_FAIL:-}" = "1" ] && exit 1
case "$*" in
  *"/reviews"*)
    if [ -n "${FAKE_MG_REVIEWS+x}" ]; then printf '%s' "$FAKE_MG_REVIEWS"
    else printf '%s' '[]'; fi ;;
  *"/comments"*)
    if [ -n "${FAKE_MG_COMMENTS+x}" ]; then printf '%s' "$FAKE_MG_COMMENTS"
    else printf '%s' '[{"body":"Non-author review: APPROVE - verified the diff."}]'; fi ;;
  *) echo "" ;;
esac
STUB
chmod +x "$STUBTMP/bin/gh"
cat > "$STUBTMP/bin/git" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "git@github.com:acme/widgets.git" ;;
  *)                       echo "" ;;
esac
STUB
chmod +x "$STUBTMP/bin/git"
export PATH="$STUBTMP/bin:$PATH"
M="mer""ge"      # -> "merge"
A="--ad""min"    # -> "--admin"
pass=0
fail=0

# check <want_exit> <description> <command>
check() {
  want=$1
  desc=$2
  cmd=$3
  json=$(printf '%s' "$cmd" | jq -Rs '{tool_input:{command:.}}')
  printf '%s' "$json" | "$GUARD" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s (want exit %s, got %s)\n  cmd: %s\n' "$desc" "$want" "$got" "$cmd"
  fi
}

# checkc — same as check, but wraps the command in a Grok CLI camelCase payload
# (toolInput). The old snake_case-only extraction resolved empty under Grok and
# fail-OPEN'd, waving `gh pr merge --admin` through.
checkc() {
  want=$1
  desc=$2
  cmd=$3
  json=$(printf '%s' "$cmd" | jq -Rs '{toolInput:{command:.}}')
  printf '%s' "$json" | "$GUARD" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s (want exit %s, got %s)\n  cmd: %s\n' "$desc" "$want" "$got" "$cmd"
  fi
}

# --- Should BLOCK (exit 2): a genuine --admin bypass merge ---
check 2 "plain admin merge"          "gh pr $M 40 $A"
check 2 "admin + squash"             "gh pr $M 40 --squash $A"
check 2 "admin then delete-branch"   "gh pr $M 40 $A --delete-branch"
check 2 "create then admin-merge"    "gh pr create -t x -b y && gh pr $M 40 $A"

# --- Should BLOCK (exit 2): real invocation hidden in exec context (no fail-open) ---
check 2 "sh -c single-quoted bypass" "sh -c 'gh pr $M 40 $A'"
check 2 "sh -c double-quoted bypass" "sh -c \"gh pr $M 40 $A\""
check 2 "command subst in -m value"  "git commit -m \"\$(gh pr $M 40 $A)\""
check 2 "backtick command subst"     "echo \`gh pr $M 40 $A\`"
check 2 "shell-fed heredoc"          "$(printf 'sh <<EOF\ngh pr %s 40 %s\nEOF' "$M" "$A")"
check 2 "dot-source /dev/stdin heredoc" "$(printf '. /dev/stdin <<EOF\ngh pr %s 40 %s\nEOF' "$M" "$A")"
check 2 "source /dev/stdin heredoc"  "$(printf 'source /dev/stdin <<EOF\ngh pr %s 40 %s\nEOF' "$M" "$A")"
check 2 "command sh heredoc"         "$(printf 'command sh <<EOF\ngh pr %s 40 %s\nEOF' "$M" "$A")"
check 2 "env bash heredoc"           "$(printf 'env bash <<EOF\ngh pr %s 40 %s\nEOF' "$M" "$A")"
# heredoc routed onward into execution after the tag / via subst (round-3 attacks)
check 2 "cat heredoc piped to sh"    "$(printf 'cat <<EOF | sh\ngh pr %s 40 %s\nEOF' "$M" "$A")"
check 2 "cat heredoc no-space pipe bash" "$(printf 'cat<<EOF|bash\ngh pr %s 40 %s\nEOF' "$M" "$A")"
check 2 "cat heredoc redirect then run" "$(printf 'cat <<EOF >x.sh\ngh pr %s 40 %s\nEOF' "$M" "$A")"
check 2 "tee heredoc then run"       "$(printf 'tee x.sh <<EOF >/dev/null; sh x.sh\ngh pr %s 40 %s\nEOF' "$M" "$A")"
check 2 "process-subst sh <(cat)"    "$(printf 'sh <(cat <<EOF\ngh pr %s 40 %s\nEOF\n)' "$M" "$A")"
check 2 "eval command-subst cat"     "$(printf 'eval \$(cat <<EOF\ngh pr %s 40 %s\nEOF\n)' "$M" "$A")"
# --admin quote/backslash obfuscation on a visible merge (round-4 attacks)
check 2 "admin via empty dquotes"    "gh pr $M 40 --ad\"\"min"
check 2 "admin via empty squotes"    "gh pr $M 40 --ad''min"
check 2 "admin via backslash"        "gh pr $M 40 --ad\\min"
check 2 "admin via wrapped squotes"  "gh pr $M 40 --ad'min'"
check 2 "merge word split too"       "g\"\"h pr $M 40 --ad\"\"min"
# heredoc routed onward via backslash-newline line continuation (round-4)
check 2 "heredoc line-continuation pipe" "$(printf 'cat <<EOF \\\n| sh\ngh pr %s 40 %s\nEOF' "$M" "$A")"

# --- Should ALLOW (exit 0): legit merges and unrelated commands ---
check 0 "legit squash merge"         "gh pr $M 40 --squash --delete-branch"
check 0 "legit merge no flags"       "gh pr $M 40"
check 0 "unrelated command"          "ls -la && git status"

# --- Should ALLOW (exit 0): trigger tokens only as inert BODY/MESSAGE TEXT ---
check 0 "double-quoted body mentions it" \
  "gh pr create --body \"never run gh pr $M 40 $A, it bypasses protection\""
check 0 "single-quoted body mentions it" \
  "gh pr create --body 'do not gh pr $M --admin'"
check 0 "commit msg mentions it" \
  "git commit -m \"note: gh pr $M $A is blocked by the guard\""
check 0 "commit -am cluster mentions it" \
  "git commit -am 'fix: gh pr $M $A guard hardening'"
check 0 "commit -asm cluster mentions it" \
  "git commit -asm \"gh pr $M $A note\""
# but a real bypass inside an -am command substitution still blocks
check 2 "commit -am with subst bypass" \
  "git commit -am \"\$(gh pr $M 40 $A)\""

# cat-heredoc body feeding a doc flag (the exact shape that misfired on PR #40)
hd=$(printf 'gh pr create --title t --body "$(cat <<%sEOF%s\ndocs: never gh pr %s 40 %s here\nEOF\n)"' "'" "'" "$M" "$A")
check 0 "cat-heredoc doc body mentions it" "$hd"
# bare cat/gh heredoc whose body is only inert text
check 0 "bare cat heredoc mentions it"  "$(printf 'cat <<EOF\ndocs: gh pr %s 40 %s\nEOF' "$M" "$A")"
check 0 "gh body-file heredoc mentions it" \
  "$(printf 'gh pr create --body-file - <<EOF\ndocs: gh pr %s 40 %s\nEOF' "$M" "$A")"

# --- Harness portability: Grok CLI camelCase payloads (toolInput.command) ---
checkc 2 "camelCase plain admin merge"     "gh pr $M 40 $A"
checkc 2 "camelCase admin + squash"        "gh pr $M 40 --squash $A"
checkc 2 "camelCase sh -c quoted bypass"   "sh -c 'gh pr $M 40 $A'"
checkc 0 "camelCase legit squash merge"    "gh pr $M 40 --squash --delete-branch"
checkc 0 "camelCase body mentions it only" \
  "gh pr create --body \"never run gh pr $M 40 $A, it bypasses protection\""

# --- review-on-THIS-PR check (2026-08-15, the #2736 laundering pattern) -----
# Default stub carries a fresh APPROVE comment -> allowed (covered above by the
# legit-merge cases). Now the negative space:

# No verdict anywhere on the PR -> block.
FAKE_MG_COMMENTS='[{"body":"looks big, did not review"}]' \
  check 2 "merge with no APPROVE verdict on the PR blocks" "gh pr $M 42"

# The verdict is carried from ANOTHER PR -> laundering, block.
FAKE_MG_COMMENTS='[{"body":"Non-author APPROVE carried from #2731."}]' \
  check 2 "carried-from verdict does not satisfy the review" "gh pr $M 42"
FAKE_MG_COMMENTS='[{"body":"Non-author APPROVE on #2731 covers this."}]' \
  check 2 "APPROVE-on-#N citation does not satisfy the review" "gh pr $M 42"

# A real GitHub APPROVED review satisfies it even with no comments.
FAKE_MG_REVIEWS='[{"state":"APPROVED"}]' FAKE_MG_COMMENTS='[]' \
  check 0 "GitHub APPROVED review satisfies the check" "gh pr $M 42"

# A fresh APPROVE verdict comment satisfies it (the fleet convention).
FAKE_MG_COMMENTS='[{"body":"## Verdict: APPROVE\nRe-verified both findings."}]' \
  check 0 "fresh APPROVE verdict comment satisfies the check" "gh pr $M 42"

# API failure -> fail OPEN (a review guard must not block on a GitHub hiccup).
FAKE_MG_GH_FAIL=1 \
  check 0 "API error fails open" "gh pr $M 42"

# URL-form merge resolves repo+number from the URL.
FAKE_MG_COMMENTS='[{"body":"no verdict here"}]' \
  check 2 "URL-form merge without verdict blocks" "gh pr $M https://github.com/acme/widgets/pull/42"

# -R short flag resolves the repo the same as --repo (RUSH-3032: missing -R
# support probed the CWD repo's PR and blocked a legitimate merge).
FAKE_MG_COMMENTS='[{"body":"VERDICT: APPROVE"}]' \
  check 0 "-R short-flag repo with APPROVE verdict passes" "gh pr $M 42 -R acme/widgets"
FAKE_MG_COMMENTS='[{"body":"no verdict"}]' \
  check 2 "-R short-flag repo without verdict blocks" "gh pr $M 42 -R acme/widgets"

printf -- '---\nmerge-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
