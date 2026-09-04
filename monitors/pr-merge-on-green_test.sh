#!/usr/bin/env bash
# Real-path tests for the pr-merge-on-green poll selector (RUSH-2848).
#
# Exercises the actual helper and the actual pr-verdict.py (no mocked
# verdict logic) against gh-pr-view-shaped JSON fixtures. Selects an
# approved+green PR and rejects an unapproved one.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
SEL="$DIR/pr-merge-on-green.sh"
DATA="$DIR/testdata"
pass=0
fail=0

check() {
  want=$1
  file=$2
  desc=$3
  got=$(sh "$SEL" --select < "$DATA/$file" | tr -d '\n')
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  want: %s\n  got:  %s\n' "$desc" "$want" "$got"
  fi
}

check "acme/widgets#7" approved-green.json \
  "formal APPROVED review + green CI is selected"
check "acme/widgets#8" approve-comment-green.json \
  "APPROVE verdict comment + green CI is selected (reviewDecision empty)"
check "" unapproved-green.json \
  "green CI without a verdict is rejected"
check "" approved-red.json \
  "APPROVED review with failing CI is rejected"
check "" carried-from-green.json \
  "carried-from APPROVE comment is rejected"
# PHNX-3236: this daemon lists PRs `--author @me`, so the PR author is always
# the same shared fleet identity. An APPROVE comment posted by that same
# identity on its own PR must not clear the guard, or the daemon would
# auto-merge on its own self-approval.
check "" self-authored-approve-green.json \
  "self-authored APPROVE comment (PHNX-3236) is rejected even with green CI"

# PHNX-3950 owner-mode: when the daemon's identity is a trusted owner, its own
# APPROVE clears the verdict so the auto-merger stops deadlocking every PR onto
# the human. Hermetic: stub `gh api user --jq .id` to a fixed id and opt that id
# in via AGENTS_MERGE_TRUSTED_OWNER_IDS. OWNER_MODE is recomputed per `--select`
# subprocess, so per-invocation env + PATH fully control it.
OWNER_STUB=$(mktemp -d)
trap 'rm -rf "$OWNER_STUB"' EXIT
mkdir -p "$OWNER_STUB/bin"
cat > "$OWNER_STUB/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in *"api user"*) printf '13007401' ;; *) echo "" ;; esac
STUB
chmod +x "$OWNER_STUB/bin/gh"

checko() {
  want=$1; file=$2; ids=$3; desc=$4
  got=$(PATH="$OWNER_STUB/bin:$PATH" AGENTS_MERGE_TRUSTED_OWNER_IDS="$ids" \
        sh "$SEL" --select < "$DATA/$file" | tr -d '\n')
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  want: %s\n  got:  %s\n' "$desc" "$want" "$got"; fi
}
checko "acme/widgets#12" self-authored-approve-green.json '13007401' \
  "owner-mode: self-authored APPROVE + green CI is selected for a trusted owner"
checko "" self-authored-approve-green.json '99999999' \
  "owner-mode: a non-trusted identity leaves the self-authored PR rejected"
checko "" unapproved-green.json '13007401' \
  "owner-mode: green CI without any verdict is still rejected"

# The YAML must not regress to a cwd-relative gh pr list / reviewDecision filter.
yml="$DIR/pr-merge-on-green.yml"
if grep -q 'pr-merge-on-green.sh' "$yml" \
  && ! grep -q 'reviewDecision == "APPROVED"' "$yml" \
  && ! grep -q 'gh pr list --author' "$yml"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL: YAML poll still uses cwd-relative gh pr list or reviewDecision filter\n'
fi

# merge-guard.sh must call pr-verdict.py rather than a second copy of the python.
guard="$DIR/../rules/subrules/gh-merge-guard/merge-guard.sh"
if grep -q 'pr-verdict.py' "$guard" && ! grep -q 'carried\\s+(?:over\\s+)?from' "$guard"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL: merge-guard.sh still inlines the verdict python instead of pr-verdict.py\n'
fi

printf -- '---\npr-merge-on-green: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
