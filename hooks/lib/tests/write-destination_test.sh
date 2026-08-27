#!/usr/bin/env bash
# Tests for git-parse.sh write-destination discovery. The library is deliberately
# policy-free, so this fixture supplies a tiny callback policy and proves the
# parser surfaces the historical escape destinations (including raw quoted SSH
# inners) without classifying fleet prompt dispatch as direct shell execution.
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
LIB="$DIR/../git-parse.sh"
pass=0
fail=0

# shellcheck source=../git-parse.sh
. "$LIB"

ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi; }

write_on_destination() {
  kind=$1 path=$2 host=${3:-}
  case "$kind:$path" in
    scp:*:*|rsync:*:*) host=${path%%:*}; path=${path#*:} ;;
  esac
  case "$path" in /*|'~/'*) ;; *) path=${WRITE_DEST_CWD:-.}/$path ;; esac
  case "$path" in
    */.agents/worktrees/*|.agents/worktrees/*|/tmp|/tmp/*|~/.agents|~/.agents/*)
      return 0 ;;
    */src/github.com/*/*)
      FOUND="${FOUND}${FOUND:+\n}$kind|$host|$path"
      return 1 ;;
  esac
  return 0
}

scan_command() {
  raw=$1
  if git_extract_sh_c_inner "$raw"; then scan_command "$_dash_c_inner"; return $?; fi
  if git_extract_remote_inner "$raw"; then
    saved=${WRITE_REMOTE_HOST:-}; WRITE_REMOTE_HOST=$_remote_host
    scan_command "$_remote_inner"; rc=$?; WRITE_REMOTE_HOST=$saved
    return "$rc"
  fi
  oldifs=${IFS-}; IFS=$'\n'
  for seg in $(git_split_chains "$raw"); do
    IFS=$oldifs
    if git_extract_remote_inner "$seg"; then
      saved=${WRITE_REMOTE_HOST:-}; WRITE_REMOTE_HOST=$_remote_host
      scan_command "$_remote_inner"; rc=$?; WRITE_REMOTE_HOST=$saved
      [ "$rc" -eq 0 ] || return "$rc"
    elif ! write_scan_segment "$seg"; then
      return 1
    fi
    IFS=$'\n'
  done
  IFS=$oldifs
  return 0
}

expect() { # expected rc, name, command
  IFS=$' \t\n'
  want=$1 name=$2 command=$3 FOUND='' WRITE_DEST_CWD='.' WRITE_REMOTE_HOST=''
  scan_command "$command"; got=$?
  if [ "$got" -eq "$want" ]; then ok "$name"; else bad "$name: expected $want, got $got ($FOUND)"; fi
}

# The three real escape classes.
expect 1 "Write-tool historical path represented as a direct destination" \
  "cp /tmp/source /home/muqsit/src/github.com/muqsitnawaz/agents/growth/content-source-materials-2026-08-10.md"
expect 1 "cross-machine scp into checkout" \
  "scp -q /tmp/refocus-brief.md zion:/Users/muqsit/src/github.com/muqsitnawaz/agents/.agents/artifacts/2026-08-14/refocus-brief.md && agents ssh zion 'cd ~/src/github.com/muqsitnawaz/agents/.agents/artifacts/2026-08-14 && artifacts render refocus-brief.md'"
expect 1 "shell redirect into checkout" \
  "cat > /Users/muqsit/src/github.com/muqsitnawaz/agents/growth/notes.md"
expect 1 "cd then relative redirect follows shell destination cwd" \
  "cd /Users/muqsit/src/github.com/muqsitnawaz/agents && cat > notes-relative.md"

# The three required allow classes.
expect 0 "documented scp /tmp readback" \
  "scp .agents/artifacts/2026-08-27/plan-x.html zion:/tmp/ && agents ssh zion 'open /tmp/plan-x.html'"
expect 0 "linked worktree destination wins" \
  "cat > /Users/muqsit/src/github.com/muqsitnawaz/agents/.agents/worktrees/fix-x/growth/notes.md"
expect 0 "agent home and tmp destinations" \
  "cp /tmp/a ~/.agents/cache/a && tee /tmp/b"
expect 0 "quoted greater-than prose is not a redirection" \
  "echo 'example: cat > /Users/muqsit/src/github.com/muqsitnawaz/agents/nope.md'"
expect 1 "quoted destination with spaces stays one token" \
  "cp /tmp/x '/Users/muqsit/src/github.com/muqsitnawaz/agents/dir with space/file.txt'"
expect 1 "tee checks every destination, not only the last" \
  "tee /Users/muqsit/src/github.com/muqsitnawaz/agents/first.txt /tmp/safe.txt"
expect 1 "target-directory option identifies the write destination" \
  "cp --target-directory /Users/muqsit/src/github.com/muqsitnawaz/agents /tmp/x"

# Regression for the POC gap: retain the complete quoted inner command before
# splitting its && chain, then qualify the discovered destination with the host.
FOUND=''
if scan_command "agents ssh zion 'cd /tmp && cat > /Users/muqsit/src/github.com/muqsitnawaz/agents/remote.md'"; then
  bad "agents ssh raw inner redirect must deny"
elif [ "$FOUND" = "redirect|zion|/Users/muqsit/src/github.com/muqsitnawaz/agents/remote.md" ]; then
  ok "agents ssh retains full inner and remote host"
else
  bad "agents ssh inner surfaced incorrectly: [$FOUND]"
fi
FOUND=''
if scan_command "ssh -q zion 'cat > /Users/muqsit/src/github.com/muqsitnawaz/agents/plain-ssh.md'"; then
  bad "plain ssh raw inner redirect must deny"
elif [ "$FOUND" = "redirect|zion|/Users/muqsit/src/github.com/muqsitnawaz/agents/plain-ssh.md" ]; then
  ok "plain ssh retains full inner and remote host"
else
  bad "plain ssh inner surfaced incorrectly: [$FOUND]"
fi

# These verbs transport prompts or isolated checkouts, not a direct write
# destination. Their remote agents/hooks (run, teams) or lease boundary
# (crabbox) own execution-time enforcement.
expect 0 "agents run --device is not direct remote shell" \
  "agents run claude 'write the report' --device zion"
expect 0 "agents teams remote is not direct remote shell" \
  "agents teams add x claude 'write the report' --device zion"
expect 0 "crabbox run writes only its leased checkout" \
  "crabbox run --id blue-lobster -- sh -c 'cat > /repo/report.md'"

split=$(git_split_chains 'echo "first
second"; git reset --hard')
eq "chain splitting retains quote state across newlines" $'echo "first\nsecond"\n git reset --hard' "$split"

printf '\nwrite-destination: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
