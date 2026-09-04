#!/usr/bin/env bash
# Unit test for hooks/lib/owner-mode.sh::_resolve_owner_mode (PHNX-3950).
# owner-mode gates who may self-merge, so its allowlist logic is tested in
# isolation: env + user-layer file + shipped file merge, numeric-only matching,
# and the safe default (OFF, no network) when nothing is configured. `gh api
# user` is stubbed on PATH; HOME is pointed at a sandbox so the real
# ~/.agents/trusted-owner-ids never leaks into the assertions.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../../.." && pwd)
LIB="$ROOT/hooks/lib/owner-mode.sh"
pass=0
fail=0

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin" "$SANDBOX/home"

# Stub `gh`: `api user --jq .id` prints $STUB_GH_ID; anything else empty. When
# STUB_GH_ID is the sentinel __FAIL__ the stub exits non-zero (gh hiccup).
cat > "$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"api user"*) [ "${STUB_GH_ID:-}" = "__FAIL__" ] && exit 1; printf '%s' "${STUB_GH_ID:-}" ;;
  *) echo "" ;;
esac
STUB
chmod +x "$SANDBOX/bin/gh"

# shellcheck source=../owner-mode.sh
. "$LIB"

# run <want> <desc> <sysfile> <env-ids> <stub-id>
run() {
  want=$1; desc=$2; sysfile=$3; ids=$4; gid=$5
  got=$(HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" \
        AGENTS_MERGE_TRUSTED_OWNER_IDS="$ids" STUB_GH_ID="$gid" \
        _resolve_owner_mode "$sysfile")
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s (want %s, got %s)\n' "$desc" "$want" "$got"; fi
}

EMPTY="$SANDBOX/empty"           # nonexistent sys file path
TMPL="$SANDBOX/template"; printf '# just comments\n#   13007401 in a comment\n' > "$TMPL"
IDFILE="$SANDBOX/ids"; printf '# owner\n13007401\n\n' > "$IDFILE"

run 0 "no env, no file -> OFF (and no gh needed)" "$EMPTY" "" "__FAIL__"
run 1 "env id matches authed id -> ON" "$EMPTY" "13007401" "13007401"
run 0 "env id does not match authed id -> OFF" "$EMPTY" "13007401" "99999999"
run 1 "sys file id matches -> ON" "$IDFILE" "" "13007401"
run 0 "comment-only file -> OFF (comments stripped, no digits)" "$TMPL" "" "13007401"
run 1 "multiple env ids, one matches -> ON" "$EMPTY" "42 13007401 7" "13007401"
run 0 "ids configured but gh returns empty -> OFF" "$EMPTY" "13007401" ""
run 0 "ids configured but gh errors -> OFF (fail-safe strict)" "$EMPTY" "13007401" "__FAIL__"
run 0 "gh returns non-numeric -> OFF" "$EMPTY" "13007401" "not-a-number"

# User-layer file (~/.agents/trusted-owner-ids under the sandbox HOME) is read too.
mkdir -p "$SANDBOX/home/.agents"; printf '13007401\n' > "$SANDBOX/home/.agents/trusted-owner-ids"
run 1 "user-layer ~/.agents/trusted-owner-ids id matches -> ON" "$EMPTY" "" "13007401"

printf -- '---\nowner-mode: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
