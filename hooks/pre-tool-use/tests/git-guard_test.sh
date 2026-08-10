#!/usr/bin/env bash
# Tests for git-guard.sh — the PreToolUse guard against destructive git ops.
#
# Hermetic: every case builds its own JSON payload and feeds it to the guard
# over stdin; the "fail closed" case runs the guard with a sandboxed PATH that
# has no jq/node/python on it (only `cat`, which the guard needs just to read
# stdin) to reproduce the footer-guard fail-open regression class.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../git-guard.sh"
# Resolve the interpreter to an ABSOLUTE path once, up front — the "no parser"
# case below runs it with PATH overridden to a sandbox dir, and a bare `sh`
# command name would then fail to resolve at all (command not found) rather
# than exercising the guard's own fail-closed behavior.
SH_BIN="$(command -v sh)"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0; fail=0

# JSON-escape a raw string for embedding as a JSON string value: backslash,
# then double-quote, then real newlines -> \n (slurp-mode sed, GNU + BSD safe).
json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# run_guard <command-string> [cwd] [path-override]
# Sets RC, OUT, ERR.
run_guard() {
  local cmdstr="$1" cwd="${2:-}" path_override="${3:-}"
  local json esc_cmd esc_cwd errfile
  esc_cmd=$(json_escape "$cmdstr")
  if [ -n "$cwd" ]; then
    esc_cwd=$(json_escape "$cwd")
    json=$(printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$esc_cmd" "$esc_cwd")
  else
    json=$(printf '{"tool_input":{"command":"%s"}}' "$esc_cmd")
  fi
  errfile="$SANDBOX/err.$$.$RANDOM"
  if [ -n "$path_override" ]; then
    OUT=$(printf '%s' "$json" | PATH="$path_override" "$SH_BIN" "$HOOK" 2>"$errfile")
  else
    OUT=$(printf '%s' "$json" | "$SH_BIN" "$HOOK" 2>"$errfile")
  fi
  RC=$?
  ERR=$(cat "$errfile")
  rm -f "$errfile"
}

check_deny() { # name, command-string, expected-stderr-substring
  run_guard "$2"
  if [ "$RC" -ne 2 ]; then
    echo "FAIL - $1: expected rc=2, got rc=$RC"; fail=$((fail+1)); return
  fi
  if [ -z "$ERR" ]; then
    echo "FAIL - $1: rc=2 but stderr is empty (no reason given)"; fail=$((fail+1)); return
  fi
  if [ -n "${3:-}" ] && [ "${ERR#*"$3"}" = "$ERR" ]; then
    echo "FAIL - $1: stderr missing [$3], got: $ERR"; fail=$((fail+1)); return
  fi
  echo "ok   - $1"; pass=$((pass+1))
}

check_allow() { # name, command-string
  run_guard "$2"
  if [ "$RC" -ne 0 ]; then
    echo "FAIL - $1: expected rc=0, got rc=$RC (stderr: $ERR)"; fail=$((fail+1)); return
  fi
  if [ -n "$OUT" ]; then
    echo "FAIL - $1: expected empty stdout (PreToolUse stdout pollutes the prompt), got: $OUT"; fail=$((fail+1)); return
  fi
  echo "ok   - $1"; pass=$((pass+1))
}

echo "git-guard"

# RUSH-2295: every deny must emit the structured next-step block so agents
# stop retrying the same blocked op. Substring checks only need one unique
# marker from each required line.
check_deny_structured() { # name, command-string, blocked_op_marker, next_marker
  run_guard "$2"
  if [ "$RC" -ne 2 ]; then
    echo "FAIL - $1: expected rc=2, got rc=$RC"; fail=$((fail+1)); return
  fi
  for needle in "blocked_op:" "reason:" "do_this_instead:" "$3" "$4"; do
    if [ "${ERR#*"$needle"}" = "$ERR" ]; then
      echo "FAIL - $1: stderr missing [$needle], got: $ERR"; fail=$((fail+1)); return
    fi
  done
  echo "ok   - $1"; pass=$((pass+1))
}

# --- 0. Structured denial shape (RUSH-2295) ---------------------------------
check_deny_structured "structured deny for git reset" "git reset --hard HEAD" "git.reset" "rebase origin"
check_deny_structured "structured deny for git push --force" "git push --force origin main" "git.push-force" "session prefix"
check_deny_structured "structured deny for git config write" "git config user.email x@y.z" "git.config-write" "config --get"

# --- 1. Blocks destructive ops, in various dressings -------------------------
check_deny  "plain git reset --hard"                          "git reset --hard HEAD" "reset is denied"
check_deny  "git push --force"                                "git push --force origin main" "push --force is denied"
check_deny  "git -C <path> reset --hard (the original bypass)" "git -C /tmp reset --hard HEAD" "reset is denied"
check_deny  "chained: benign && destructive"                  "ls -la && git reset --hard" "reset is denied"
check_deny  "env-var prefix before git"                       "FOO=bar git rebase origin/main" "rebase"
check_deny  "git branch -D (force-delete)"                    "git branch -D some-branch" "branch -D"
check_deny  "git push --delete (remote branch delete)"        "git push origin --delete some-branch" "deletes a remote branch"
check_deny  "git push -d (short remote delete)"               "git push origin -d some-branch" "deletes a remote branch"
check_deny  "git push :branch (colon-refspec delete)"         "git push origin :some-branch" "deletes a remote branch"
check_deny  "sh -c wrapper"                                   'sh -c "git reset --hard HEAD"' "reset is denied"
check_deny  "bash -c wrapper"                                  'bash -c "git clean -fd"' "clean is denied"
check_deny  "quoted first token"                                "'git' reset --hard HEAD" "reset is denied"
check_deny  "git config write"                                  "git config user.name newname" "config write is denied"
check_deny  "git merge --abort"                                 "git merge --abort" "merge --abort is denied"
check_deny  "real newline before destructive op"                 "$(printf 'cd /tmp\ngit reset --hard')" "reset is denied"

# worktree remove on a dirty tree -> denied, listing the dirty files.
WT_DIRTY="$SANDBOX/wt-dirty"
git init -q "$WT_DIRTY"
echo "uncommitted" > "$WT_DIRTY/scratch.txt"
check_deny "git worktree remove on dirty tree" "git worktree remove $WT_DIRTY" "uncommitted changes"

# --- 2. Allows the benign neighbour -------------------------------------------
check_allow "git status"                          "git status"
check_allow "git push --force-with-lease"         "git push --force-with-lease origin main"
check_allow "git push (plain)"                    "git push origin main"
check_allow "git push src:dst (normal refspec, not a delete)" "git push origin HEAD:refs/heads/main"
check_allow "git config --get (read)"             "git config --get user.name"
check_allow "non-git command"                     "ls -la /tmp"
check_allow "git branch (list, no destructive flag)" "git branch"
check_allow "git rebase --continue (finishing, not starting)" "git rebase --continue"

# worktree remove on a clean, fully-pushed tree -> allowed. Build a real
# origin so the worktree branch has an upstream with nothing ahead of it.
ORIGIN="$SANDBOX/origin.git"
git init -q --bare "$ORIGIN"
SRC="$SANDBOX/src"
git clone -q "$ORIGIN" "$SRC" 2>/dev/null
git -C "$SRC" -c user.email=t@t.com -c user.name=t commit -q --allow-empty -m init
git -C "$SRC" push -q origin HEAD:refs/heads/main -u
WT_CLEAN="$SANDBOX/wt-clean"
git -C "$SRC" worktree add -q -b feature "$WT_CLEAN" origin/main
git -C "$WT_CLEAN" branch -q --set-upstream-to=origin/main feature
check_allow "git worktree remove on clean+pushed tree" "git worktree remove $WT_CLEAN"

# --- 3. Fails CLOSED with no JSON parser on PATH ------------------------------
NOPARSER="$SANDBOX/noparser-bin"
mkdir -p "$NOPARSER"
ln -s "$(command -v cat)" "$NOPARSER/cat"
run_guard "git reset --hard HEAD" "" "$NOPARSER"
if [ "$RC" -eq 2 ]; then
  echo "ok   - no JSON parser on PATH -> fails closed (rc=2)"; pass=$((pass+1))
else
  echo "FAIL - no JSON parser on PATH -> expected rc=2, got rc=$RC"; fail=$((fail+1))
fi
if [ "${ERR#*"no JSON parser"}" != "$ERR" ]; then
  echo "ok   - fail-closed message names the missing parser"; pass=$((pass+1))
else
  echo "FAIL - fail-closed stderr missing 'no JSON parser', got: $ERR"; fail=$((fail+1))
fi
# Sanity: this same PATH still lets a benign command through the fast path
# (no "git" substring in the payload at all -> exits 0 before ever needing a
# parser), proving the deny above is really about the missing parser and not
# about the sandboxed PATH breaking the guard outright.
run_guard "ls -la /tmp" "" "$NOPARSER"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  echo "ok   - no-parser PATH still allows a non-git command (fast path, no parse needed)"; pass=$((pass+1))
else
  echo "FAIL - no-parser PATH broke the non-git fast path: rc=$RC out=[$OUT]"; fail=$((fail+1))
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
