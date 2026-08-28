#!/usr/bin/env bash
# Drop-in `sqlite3 <db> <sql>` for hook tests. Production hooks already speak
# Python's stdlib sqlite3; the sqlite3 CLI is not on every Linux PATH (this
# box: libsqlite3-0 present, no sqlite3 binary). Tests that shell out to the
# CLI were red as `sqlite3: command not found` while the code under test was
# fine. This helper prints the same `|`-separated, no-header rows the CLI
# prints so existing assertions keep their expected strings.
#
# Not a hook. Source from a *_test.sh; do not register.

sqlite3() {
  if [ "$#" -lt 2 ]; then
    printf 'test-sqlite: usage: sqlite3 <db> <sql>\n' >&2
    return 2
  fi
  _test_sql_db=$1
  shift
  TEST_SQL_STMT="$*" python3 -c '
import os, sqlite3, sys
db = sys.argv[1]
sql = os.environ["TEST_SQL_STMT"]
con = sqlite3.connect(db)
cur = con.cursor()
parts = [p.strip() for p in sql.split(";") if p.strip()]
for stmt in parts:
    result = cur.execute(stmt)
    if result.description:
        for row in result.fetchall():
            print("|".join("" if v is None else str(v) for v in row))
con.commit()
' "$_test_sql_db"
}
