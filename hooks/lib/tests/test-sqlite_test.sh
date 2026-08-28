#!/usr/bin/env bash
# Pins that test-sqlite.sh matches sqlite3-CLI output using stdlib sqlite3.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../test-sqlite.sh
. "$DIR/../test-sqlite.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
DB="$SANDBOX/t.db"

sqlite3 "$DB" "create table t(n int); insert into t values (1); insert into t values (2);"
got=$(sqlite3 "$DB" "select count(*) from t;")
if [ "$got" != "2" ]; then
  printf 'FAIL - count: expected [2], got [%s]\n' "$got"
  exit 1
fi
got=$(sqlite3 "$DB" "select n from t order by n;")
if [ "$got" != $'1\n2' ]; then
  printf 'FAIL - rows: expected [1\\n2], got [%s]\n' "$got"
  exit 1
fi
printf 'ok   - test-sqlite stdlib fallback matches CLI row shape\n'
