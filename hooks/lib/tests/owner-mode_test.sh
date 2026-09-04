#!/usr/bin/env bash
# Unit test for hooks/lib/owner-mode.sh::_resolve_owner_login (PHNX-3950).
# owner-mode gates who may self-merge, so its allowlist logic is tested in
# isolation: env + user-layer file + shipped file merge, numeric-only matching,
# the safe default (empty, no network) when nothing is configured, and — the
# reviewer-requested regression — that a `gh api user` failure degrades to
# "no owner" instead of aborting a `set -e` caller. `gh api user` is stubbed on
# PATH; HOME is a sandbox so the real ~/.agents/trusted-owner-ids never leaks in.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../../.." && pwd)
LIB="$ROOT/hooks/lib/owner-mode.sh"
pass=0
fail=0

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/home"

# Stub `gh`: `api user` prints "$STUB_GH_ID $STUB_GH_LOGIN"; anything else empty.
# STUB_GH_ID=__FAIL__ makes the stub exit non-zero (a gh hiccup).
cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"api user"*) [ "${STUB_GH_ID:-}" = "__FAIL__" ] && exit 1; printf '%s %s' "${STUB_GH_ID:-}" "${STUB_GH_LOGIN:-}" ;;
  *) echo "" ;;
esac
STUB
chmod +x "$SANDBOX/bin/gh"

# shellcheck source=../owner-mode.sh
. "$LIB"

# run <want> <desc> <sysfile> <env-ids> <stub-id> <stub-login>
run() {
  want=$1; desc=$2; sysfile=$3; ids=$4; gid=$5; glogin=$6
  got=$(HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" \
        AGENTS_MERGE_TRUSTED_OWNER_IDS="$ids" STUB_GH_ID="$gid" STUB_GH_LOGIN="$glogin" \
        _resolve_owner_login "$sysfile")
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s (want [%s], got [%s])\n' "$desc" "$want" "$got"; fi
}

EMPTY="$SANDBOX/empty"           # nonexistent sys file path
TMPL="$SANDBOX/template"; printf '# just comments\n#   13007401 in a comment\n' > "$TMPL"
IDFILE="$SANDBOX/ids"; printf '# owner\n13007401\n\n' > "$IDFILE"

run ""            "no env, no file -> empty (and no gh needed)" "$EMPTY" ""          "__FAIL__" "muqsit"
run "muqsitnawaz" "env id matches authed id -> authed login"    "$EMPTY" "13007401"  "13007401" "muqsitnawaz"
run ""            "env id does not match authed id -> empty"    "$EMPTY" "13007401"  "99999999" "someoneelse"
run "muqsitnawaz" "sys file id matches -> authed login"         "$IDFILE" ""         "13007401" "muqsitnawaz"
run ""            "comment-only file -> empty (no digits)"      "$TMPL"  ""          "13007401" "muqsitnawaz"
run "muqsitnawaz" "multiple env ids, one matches -> login"      "$EMPTY" "42 13007401 7" "13007401" "muqsitnawaz"
run ""            "ids configured but gh returns empty -> empty" "$EMPTY" "13007401" ""        ""
run ""            "trusted id but empty login -> empty"          "$EMPTY" "13007401" "13007401" ""
run ""            "gh returns non-numeric id -> empty"           "$EMPTY" "13007401" "not-a-number" "x"
run ""            "login with a space is rejected -> empty"      "$EMPTY" "13007401" "13007401" "bad login"

# User-layer ~/.agents/trusted-owner-ids (under sandbox HOME) is read too.
mkdir -p "$SANDBOX/home/.agents"; printf '13007401\n' > "$SANDBOX/home/.agents/trusted-owner-ids"
run "muqsitnawaz" "user-layer ~/.agents/trusted-owner-ids id matches -> login" "$EMPTY" "" "13007401" "muqsitnawaz"

# Reviewer BLOCKER regression: under `set -e`, a `gh api user` failure with a
# trusted id configured must degrade to "" (owner-mode off), NOT abort the
# caller. If the `|| _om_user=""` guard regresses, the subshell dies before the
# echo and $out is empty.
out=$(HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" \
      AGENTS_MERGE_TRUSTED_OWNER_IDS="13007401" STUB_GH_ID="__FAIL__" \
      sh -eu -c ". \"$LIB\"; v=\$(_resolve_owner_login \"$EMPTY\"); printf 'SURVIVED[%s]' \"\$v\"")
if [ "$out" = "SURVIVED[]" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: gh failure under set -e must not abort caller (got [%s])\n' "$out"; fi

printf -- '---\nowner-mode: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
