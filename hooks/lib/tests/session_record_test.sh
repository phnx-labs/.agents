#!/usr/bin/env bash
# Unit test for hooks/lib/session_record.py::merge_fields: it merges into this
# session's existing record only, keeps every other field, and never creates,
# rewrites, or crashes on a missing, corrupt, non-object, or foreign record.
# HOME is a sandbox so the real ~/.agents/.cache never leaks in.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
LIB="$DIR/.."
pass=0
fail=0
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
SESS="$SANDBOX/.agents/.cache/state/sessions"
mkdir -p "$SESS"

check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; pass=$((pass+1)); else echo "FAIL - $1: expected [$3] got [$2]"; fail=$((fail+1)); fi; }
merge() {   # $1 pid -> prints merge_fields' return
  HOME="$SANDBOX" python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import session_record as s; print(s.merge_fields(int(sys.argv[2]), "sid-1", {"verdict": {"state": "done"}}))' "$LIB" "$1"
}

printf '{"session_id":"sid-1","cwd":"/w","pid":11,"ts":1}' > "$SESS/11.json"
check "merges into this session's record" "$(merge 11)" "True"
check "keeps every other field" "$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["cwd"], r["ts"], r["verdict"]["state"])' "$SESS/11.json")" "/w 1 done"

check "missing record is refused" "$(merge 12)" "False"
check "missing record stays missing" "$([ -e "$SESS/12.json" ] && echo yes || echo no)" "no"

for case in 'corrupt:{not json' 'list:[1,2]' 'foreign:{"session_id":"sid-2","pid":13}'; do
  name=${case%%:*}; body=${case#*:}
  printf '%s' "$body" > "$SESS/13.json"
  check "$name record is refused" "$(merge 13)" "False"
  check "$name record is left untouched" "$(cat "$SESS/13.json")" "$body"
done

echo "session_record: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
