#!/usr/bin/env bash
# SessionStart hook: inject the repo's in-flight state — open PRs and the other
# agents actively WORKING on this same project — so an agent sees what is already
# owned before it spawns teammates, adopts work, or opens a PR.
#
# AX-by-injection: the doctrine checkpoint "check before you take work" is
# delivered as state at session start instead of an instruction the agent
# has to remember to follow. Prevents the observed failure modes:
#   - two agents opening duplicate PRs for the same scope
#   - taking over a surface another live session is mid-flight on
#
# Project-aware: the anchor is the project's MAIN repo root, resolved from
# `--git-common-dir` so a worktree (`…/.agents/worktrees/<slug>`) resolves to the
# same project as its main checkout. Only agents whose derived live activity is
# `working` are shown — idle, waiting-on-user, orphaned, abandoned, and closed
# sessions are dropped (the `activity`/`status` fields come straight from
# `agents sessions --active --json`, not guessed). Shown agents are ranked
# most-recently-active first and capped, with a "+N more" summary beyond the cap.
#
# Fail-open everywhere: no git repo, no gh, no agents CLI, network down,
# timeouts, malformed JSON — all exit 0 silently. stdout becomes injected
# session context.
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
# Project anchor = the MAIN repo root. `--git-common-dir` points at the shared
# `.git` for both the main checkout and every linked worktree, so its parent is
# the one project root that unifies them. Fall back to the plain toplevel on an
# older git that lacks `--path-format` (a worktree then only anchors on itself,
# which is still correct, just narrower).
common_dir="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$common_dir" ]; then
  repo="$(cd "$(dirname "$common_dir")" 2>/dev/null && pwd || true)"
fi
[ -z "${repo:-}" ] && repo="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo" ] && exit 0

prs=""
if command -v gh >/dev/null 2>&1; then
  prs="$(cd "$repo" 2>/dev/null && _to 4 gh pr list --state open --limit 10 \
    --json number,title,headRefName,isDraft \
    --template '{{range .}}- #{{.number}} {{if .isDraft}}[draft] {{end}}{{.title}} ({{.headRefName}}){{"\n"}}{{end}}' \
    2>/dev/null || true)"
fi

# Agents actively working on THIS project, on THIS machine only (--local).
# --json gives structured rows: filtering is on the real cwd field with a path
# boundary (repo "…/agents" does not swallow "…/agents-cli"), the activity gate
# is the CLI's own derived `activity` state, and ranking is on `lastActivityMs`.
# The session this hook is starting for (session_id in the hook input) is dropped.
# Budget: measured at 4923ms against the old `_to 5` — a 77ms margin, so any extra
# load silently dropped this whole section (the `|| true` makes a timeout
# indistinguishable from "nothing is running"). Raised to 8s, still inside the
# manifest-level `timeout: 10` backstop. The real fix is making
# `agents sessions --active --local` faster; this stops the silent data loss meanwhile.
CAP=5
sessions=""
if command -v agents >/dev/null 2>&1; then
  sessions="$(_to 8 agents sessions --active --json --local 2>/dev/null | python3 -c '
import json, sys
repo, self_sid, cap = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    rows = json.load(sys.stdin)
except Exception:
    rows = []
# Dead/parked statuses never count as "working" regardless of a stale activity field.
DEAD = {"orphaned", "abandoned", "closed"}
kept = []
for r in rows if isinstance(rows, list) else []:
    if not isinstance(r, dict):
        continue
    cwd = r.get("cwd") or ""
    if cwd != repo and not cwd.startswith(repo + "/"):
        continue
    sid = r.get("sessionId") or ""
    if self_sid and sid == self_sid:
        continue
    # Only agents currently DOING work: the derived live-activity state must be
    # "working" (not idle / waiting_input), the process must be alive, and the
    # session must not be parked/dead.
    if (r.get("activity") or "") != "working":
        continue
    if r.get("pidAlive") is False:
        continue
    if (r.get("status") or "") in DEAD:
        continue
    kept.append(r)

# Rank most-active first; lastActivityMs is the recency signal, startedAt breaks ties.
def recency(r):
    return (r.get("lastActivityMs") or r.get("startedAtMs") or 0)
kept.sort(key=recency, reverse=True)

def snippet(r):
    return " ".join((r.get("topic") or "").split())[:60]

def detail(r):
    bits = []
    pr = r.get("prLink") or ""
    if pr:
        num = pr.rstrip("/").rsplit("/", 1)[-1]
        bits.append("PR #%s" % num if num.isdigit() else "PR")
    tkt = (r.get("ticketId") or "").strip()
    if tkt:
        bits.append(tkt)
    return (" (" + ", ".join(bits) + ")") if bits else ""

def line(r):
    sid = (r.get("sessionId") or "")[:8]
    kind = r.get("kind") or "?"
    topic = snippet(r)
    head = "- %s %s" % (sid, kind)
    if topic:
        head += " — " + topic
    return head + detail(r)

for r in kept[:cap]:
    print(line(r))
extra = kept[cap:]
if extra:
    hint = snippet(extra[0]) or (extra[0].get("kind") or "?")
    print("+ %d more agent%s working on this project (next: %s)" % (
        len(extra), "" if len(extra) == 1 else "s", hint))
' "$repo" "${self_sid:-}" "$CAP" 2>/dev/null || true)"
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
  echo "Agents working on this project (most active first):"
  printf '%s\n' "$sessions"
fi

exit 0
