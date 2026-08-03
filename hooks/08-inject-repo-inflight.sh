#!/usr/bin/env bash
# SessionStart hook: inject the repo's in-flight state — open PRs and other
# active agent sessions in this checkout — so an agent sees what is already
# owned before it spawns teammates, adopts work, or opens a PR.
#
# AX-by-injection: the doctrine checkpoint "check before you take work" is
# delivered as state at session start instead of an instruction the agent
# has to remember to follow. Prevents the observed failure modes:
#   - two agents opening duplicate PRs for the same scope
#   - taking over a surface another live session is mid-flight on
#
# Fail-open everywhere: no git repo, no gh, no agents CLI, network down,
# timeouts — all exit 0 silently. stdout becomes injected session context.
set -euo pipefail

# Portable timeout: macOS ships neither `timeout` nor `gtimeout` by default.
# Fall back to running the command bare — the manifest-level hook timeout is
# the real backstop; this helper only tightens individual network calls.
_to() {
  if command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  else shift; "$@"
  fi
}

input="$(cat)"

eval "$(printf '%s' "$input" | python3 -c 'import json,shlex,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print("cwd=%s" % shlex.quote(d.get("cwd","") or ""))
print("self_sid=%s" % shlex.quote(d.get("session_id","") or ""))' 2>/dev/null || echo 'cwd=""; self_sid=""')"
[ -z "${cwd:-}" ] && exit 0
[ -d "$cwd" ] || exit 0

command -v git >/dev/null 2>&1 || exit 0
repo="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo" ] && exit 0

prs=""
if command -v gh >/dev/null 2>&1; then
  prs="$(cd "$repo" 2>/dev/null && _to 4 gh pr list --state open --limit 10 \
    --json number,title,headRefName,isDraft \
    --template '{{range .}}- #{{.number}} {{if .isDraft}}[draft] {{end}}{{.title}} ({{.headRefName}}){{"\n"}}{{end}}' \
    2>/dev/null || true)"
fi

# Other active agent sessions working in this checkout (incl. its worktrees),
# on THIS machine only (--local). --json gives structured rows, so filtering
# is on the real cwd field with a path boundary — repo "…/agents" does not
# swallow "…/agents-cli" — instead of scraping the human-formatted tree. The
# session this hook is starting for (session_id in the hook input) is dropped.
# Budget: measured at 4923ms against the old `_to 5` — a 77ms margin, so any extra
# load silently dropped this whole section (the `|| true` makes a timeout
# indistinguishable from "nothing is running"). Raised to 8s, still inside the
# manifest-level `timeout: 10` backstop. The real fix is making
# `agents sessions --active --local` faster; this stops the silent data loss meanwhile.
sessions=""
if command -v agents >/dev/null 2>&1; then
  sessions="$(_to 8 agents sessions --active --json --local 2>/dev/null | python3 -c '
import json, sys
repo, self_sid = sys.argv[1], sys.argv[2]
try:
    rows = json.load(sys.stdin)
except Exception:
    rows = []
out = []
for r in rows if isinstance(rows, list) else []:
    if not isinstance(r, dict):
        continue
    cwd = r.get("cwd") or ""
    sid = r.get("sessionId") or ""
    if cwd != repo and not cwd.startswith(repo + "/"):
        continue
    if self_sid and sid == self_sid:
        continue
    status = r.get("activity") or r.get("status") or ""
    topic = " ".join((r.get("topic") or "").split())[:70]
    out.append("- %s %s [%s] %s" % (sid[:8], r.get("kind") or "?", status, topic))
for line in out[:12]:
    print(line)
' "$repo" "${self_sid:-}" 2>/dev/null || true)"
fi

[ -z "$prs" ] && [ -z "$sessions" ] && exit 0

echo "## In-flight in this repo (auto-injected)"
echo
echo "Work that already exists here. Before opening a PR, spawning agents, or"
echo "adopting a task: don't duplicate an open PR's scope, and don't take over"
echo "a live session's surface without checking what it is doing."
if [ -n "$prs" ]; then
  echo
  echo "Open PRs:"
  printf '%s\n' "$prs"
fi
if [ -n "$sessions" ]; then
  echo
  echo "Active sessions in this checkout:"
  printf '%s\n' "$sessions"
fi

exit 0
