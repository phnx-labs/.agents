#!/usr/bin/env bash
# hooks/syntax_test.sh — proves every hook script actually parses.
#
# Why this exists: a Stop/PreToolUse hook that does not parse still RUNS. bash
# exits 2 on a syntax error, and exit 2 is the harness's "block" code — so a
# typo turns every hook into a permanent block that no session can get past.
# That shipped: 2615e49 ("task-aware keep-moving gate") landed a heredoc whose
# body carried a lone `'`, and bash 3.2 — /bin/bash on every macOS box — tracks
# quotes inside a heredoc that sits in a $(...). The script became unparseable,
# exited 2 on every Stop, and blocked sessions fleet-wide until it was found by
# hand. The hook's own _test.sh was red the whole time; nobody ran it.
#
# The bash-3.2 part is the trap worth naming: bash 5 (every Linux box here)
# parses that same file FINE. So `bash -n` under the developer's shell is not
# enough — this checks /bin/bash explicitly, which is 3.2 on macOS and is what
# `#!/usr/bin/env bash` actually resolves to there.
#
# Covers *.sh in hooks/, one-level group dirs, and each group dir's tests/
# subdir (hooks/<event>/tests/<name>_test.sh — see hooks/AGENTS.md); *.py is
# checked with `python3 -m py_compile` for the same reason.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

fail=0
ran=0

# The interpreters to check .sh against: whatever `env bash` resolves to (what
# the shebang really uses), plus /bin/bash when it is a different binary — on
# macOS that is 3.2 and catches the quote-in-heredoc class above.
env_bash="$(command -v bash || echo /bin/bash)"
shells="$env_bash"
if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo $BASH_VERSION')" != "$("$env_bash" -c 'echo $BASH_VERSION')" ]; then
  shells="$shells /bin/bash"
fi

check_sh() {
  local f="$1" sh
  for sh in $shells; do
    ran=$((ran + 1))
    if err="$("$sh" -n "$f" 2>&1)"; then
      echo "ok   - $(basename "$f") parses under bash $("$sh" -c 'echo $BASH_VERSION')"
    else
      echo "FAIL - $(basename "$f") does NOT parse under bash $("$sh" -c 'echo $BASH_VERSION')"
      echo "       $err"
      fail=1
    fi
  done
}

check_py() {
  local f="$1"
  ran=$((ran + 1))
  if err="$(python3 -m py_compile "$f" 2>&1)"; then
    echo "ok   - $(basename "$f") compiles under python3"
  else
    echo "FAIL - $(basename "$f") does NOT compile under python3"
    echo "       $err"
    fail=1
  fi
}

for f in "$HERE"/*.sh "$HERE"/*/*.sh "$HERE"/*/tests/*.sh; do
  [ -e "$f" ] || continue
  check_sh "$f"
done

for f in "$HERE"/*.py "$HERE"/*/*.py "$HERE"/*/tests/*.py; do
  [ -e "$f" ] || continue
  check_py "$f"
done

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL HOOK SCRIPTS PARSE ($ran checks)"
else
  echo "SOME HOOK SCRIPTS DO NOT PARSE ($ran checks run)"
fi
exit $fail
