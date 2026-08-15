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

# A project is usually several repos. `agents projects` binds them, so survey all
# of them rather than only the one this session happens to sit in: a session in
# `agents-cli` was blind to open PRs on `agents-cli-web` and `.agents-system`,
# which is exactly the duplicate-work this hook exists to prevent. The git repo
# stays the fallback anchor when no def claims the cwd.
LIB="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")")/lib/project-context.sh"
scope_label="this repo"
roots="$repo"
if [ -f "$LIB" ]; then
  # shellcheck source=/dev/null
  . "$LIB"
  resolve_project_context "$cwd"
  if [ -n "${PROJECT_ROOTS:-}" ]; then
    # Keep only roots that exist HERE — a def is fleet-wide, this box may not
    # have every checkout, and a missing path would just waste a probe.
    present=""
    while IFS= read -r r; do
      [ -n "$r" ] && [ -d "$r" ] && present="${present}${r}"$'\n'
    done <<< "$PROJECT_ROOTS"
    if [ -n "$present" ]; then
      roots="$(printf '%s' "$present")"
      scope_label="${PROJECT_NAME:-$PROJECT_DEF_NAME}"
    fi
  fi
fi

# Probes run in PARALLEL, each into its own temp file. They were sequential, so
# the worst case was 4s (gh) + 8s (sessions) = 12s against a `timeout: 10` — the
# manifest comment already said "speed comes from parallelising its two probes
# inside the script", and this is that. Worst case is now the slowest single
# probe, not their sum.
tmp="$(mktemp -d 2>/dev/null || true)"
[ -z "$tmp" ] && exit 0
trap 'rm -rf "$tmp"' EXIT

# Label each line with its repo only when the project spans more than one — on a
# single-repo project the prefix is pure noise. `gh pr list --json` has no
# `repository` field, so the label comes from the path we are already iterating.
multi_repo=0
[ "$(printf '%s\n' "$roots" | grep -c .)" -gt 1 ] && multi_repo=1

# One probe per repo, run with the repo as cwd so `gh` resolves its own origin.
# `-R <path>` does NOT work: that flag takes an owner/repo slug.
probe_prs() {
  local state="$1" limit="$2" template="$3" fields="$4" r label
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    label="$(basename "$r")"
    out="$( (cd "$r" 2>/dev/null && _to 4 gh pr list --state "$state" --limit "$limit" \
      --json "$fields" --template "$template" 2>/dev/null) || true )"
    [ -n "$out" ] || continue
    if [ "$multi_repo" = "1" ]; then
      printf '%s\n' "$out" | sed "s#^- #- [${label}] #"
    else
      printf '%s\n' "$out"
    fi
  done <<< "$roots"
}

if command -v gh >/dev/null 2>&1; then
  probe_prs open 10 \
    '{{range .}}- #{{.number}} {{if .isDraft}}[draft] {{end}}{{.title}} ({{.headRefName}}){{"\n"}}{{end}}' \
    number,title,headRefName,isDraft > "$tmp/prs" 2>/dev/null &
  # What just LANDED. An agent that cannot see the last few merges re-proposes
  # work already on main, or "fixes" something a newer commit deliberately
  # superseded — the regression this fleet hits most. Capped tight: this is
  # orientation, not a changelog.
  probe_prs merged 5 \
    '{{range .}}- #{{.number}} {{.title}}{{"\n"}}{{end}}' \
    number,title,mergedAt > "$tmp/merged" 2>/dev/null &
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
if command -v agents >/dev/null 2>&1; then
  (_to 8 agents sessions --active --json --local 2>/dev/null | ROOTS="$roots" python3 -c '
import json, os, sys
self_sid, cap = sys.argv[1], int(sys.argv[2])
# Every root the project binds, not just the one repo the caller sits in.
roots = [r for r in (os.environ.get("ROOTS") or "").split("\n") if r]
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
    # Path-boundary match against ANY bound root, so "…/agents" still does not
    # swallow "…/agents-cli".
    if not any(cwd == root or cwd.startswith(root + "/") for root in roots):
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
' "${self_sid:-}" "$CAP" 2>/dev/null || true) > "$tmp/sessions" 2>/dev/null &
fi

# Every probe was backgrounded above; collect them. `wait` with no argument
# returns once all of them are done, so the section costs the slowest probe
# rather than their sum.
wait 2>/dev/null || true
prs="$(cat "$tmp/prs" 2>/dev/null || true)"
merged="$(cat "$tmp/merged" 2>/dev/null || true)"
sessions="$(cat "$tmp/sessions" 2>/dev/null || true)"

[ -z "$prs" ] && [ -z "$merged" ] && [ -z "$sessions" ] && exit 0

# Widening from one repo to a whole project multiplies every list by the repo
# count, so each section carries a total cap with a "+N more" tail — the same
# shape the sessions section already uses. Without it a three-repo project turns
# a ~11-line block into ~30 lines of injected context on every session.
render_capped() {
  local body="$1" cap="$2" noun="$3" total shown
  total="$(printf '%s\n' "$body" | grep -c .)"
  printf '%s\n' "$body" | grep . | head -n "$cap"
  shown=$(( total > cap ? cap : total ))
  [ "$total" -gt "$shown" ] && echo "+ $(( total - shown )) more ${noun}"
  return 0
}

echo "## In-flight in ${scope_label} (auto-injected)"
echo
echo "Work that already exists here. Before opening a PR, spawning agents, or"
echo "adopting a task: don't duplicate an open PR's scope, don't take over"
echo "a live session's surface without checking what it is doing, and don't"
echo "re-propose something the recent merges already landed."
if [ -n "$prs" ]; then
  echo
  echo "Open PRs:"
  render_capped "$prs" 12 "open (gh pr list)"
fi
if [ -n "$merged" ]; then
  echo
  echo "Recently merged (check before re-proposing):"
  render_capped "$merged" 8 "recently merged (gh pr list --state merged)"
fi
if [ -n "$sessions" ]; then
  echo
  echo "Agents working on this project (most active first):"
  printf '%s\n' "$sessions"
fi

exit 0
