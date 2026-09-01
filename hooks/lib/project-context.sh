#!/usr/bin/env bash
# Shared SessionStart helper: resolve the working directory to a defined project.
#
# `agents projects` owns the cwd -> project mapping. A def under
# ~/.agents/projects/<name>.yaml binds a root, its repos[].path entries, and a
# `linear.projectId` / `linear.name`. Two hooks need that answer:
#
#   03-linear-inject-tasks-context.sh  — which Linear project to expand
#   08-inject-repo-inflight.sh         — which repos to survey for in-flight work
#
# so it lives here rather than being re-derived in each. Do NOT reimplement the
# resolution: `agents projects view <dir>` does longest-match over every bound
# root and monorepo subpath, which is what makes a worktree, a subdirectory, and
# two projects sharing one monorepo root all resolve correctly. A basename
# comparison cannot do any of those, and it breaks silently when a project is
# renamed on the board (the checkout stays `agents-cli` while Linear says
# "AGI") — the bug this replaced.
#
# Safe for a SessionStart hook: only the read-only `projects` subcommands are
# used, answered from local YAML. Nothing here touches `agents secrets`, the
# keychain, Touch ID, or the broker.
#
# Everything is bounded and fails open — no `agents` on PATH, no def for this
# cwd, a malformed answer, or a slow call leaves the outputs empty and the
# caller falls back to whatever it did before.

# Portable timeout, named `_to` because both hooks already call it that.
# macOS ships neither `timeout` nor `gtimeout`, so a fallback
# that runs the command bare bounds NOTHING on this fleet's Macs — and an
# unbounded call in a SessionStart hook takes the whole hook past its manifest
# timeout, which delivers zero bytes rather than a degraded brief.
#
# Emulation goes through python3, which every hook here already depends on, not
# bash job control. Two things the obvious bash version gets wrong: killing the
# child's pid leaves ITS children holding the pipe, so a `$(...)` still blocks
# for the full duration; and a backgrounded job silently loses stdin.
# `start_new_session` + `killpg` kills the subtree, and std streams are inherited.
_to() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  command -v python3 >/dev/null 2>&1 || { "$@"; return $?; }
  python3 -c '
import os, signal, subprocess, sys
secs = float(sys.argv[1])
try:
    p = subprocess.Popen(sys.argv[2:], start_new_session=True)
except (FileNotFoundError, PermissionError):
    sys.exit(127)
try:
    sys.exit(p.wait(timeout=secs))
except subprocess.TimeoutExpired:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(os.getpgid(p.pid), sig)
        except Exception:
            pass
        try:
            p.wait(timeout=1)
            break
        except Exception:
            continue
    sys.exit(124)
' "$secs" "$@"
}

# resolve_project_context [cwd]
#
# Sets, and exports, three variables (empty when unresolved):
#   PROJECT_DEF_NAME   the local def id            e.g. "agents-cli"
#   PROJECT_NAME       the board's display name    e.g. "AGI"
#   PROJECT_ROOTS      newline-separated absolute repo paths bound to the def
#
# The def id and the board name are deliberately distinct: several defs may
# point at one Linear project, so the def id identifies the local checkout set
# while the board name identifies the work.
#
# Measured cost: two CLI calls, 0.28-0.31s each on an idle box.
resolve_project_context() {
  local at="${1:-$PWD}"
  PROJECT_DEF_NAME=""
  PROJECT_NAME=""
  PROJECT_ROOTS=""
  export PROJECT_DEF_NAME PROJECT_NAME PROJECT_ROOTS

  command -v agents >/dev/null 2>&1 || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  # `view <dir> --json` returns {name, linear:{name,projectId}, root}; .name is
  # the local def id. (It does not carry every repos[].path, so PROJECT_ROOTS
  # still comes from the `list` call below — hence two calls, not one.)
  PROJECT_DEF_NAME=$(_to 3 agents projects view "$at" --json 2>/dev/null | python3 -c '
import json, sys
try:
    print((json.load(sys.stdin) or {}).get("name") or "")
except Exception:
    pass
' 2>/dev/null || true)
  [ -n "$PROJECT_DEF_NAME" ] || return 0

  # One `list` call carries every def, so the board name and the bound repo
  # paths come out of the same round trip.
  local answer
  answer=$(_to 3 agents projects list --json 2>/dev/null | PROJECT_DEF_NAME="$PROJECT_DEF_NAME" python3 -c '
import json, os, sys
want = os.environ.get("PROJECT_DEF_NAME") or ""
try:
    defs = json.load(sys.stdin)
except Exception:
    raise SystemExit
if not isinstance(defs, list):
    raise SystemExit
for d in defs:
    if not isinstance(d, dict) or d.get("name") != want:
        continue
    # Line 1 is always the board name, even when empty, so the caller can slice
    # roots from line 2 without counting.
    print(((d.get("linear") or {}).get("name")) or "")
    # Every directory the def binds: the root, the default cwd, and each
    # repos[].path (plus its monorepo subpath when pinned). De-duplicated,
    # order preserved, so a caller can survey the whole project rather than
    # the one repo the session happens to sit in.
    roots, seen = [], set()
    def add(p):
        if not isinstance(p, str) or not p or p in seen:
            return
        seen.add(p)
        roots.append(p)
    add(d.get("root"))
    add(d.get("defaultPath"))
    for r in d.get("repos") or []:
        if not isinstance(r, dict):
            continue
        add(r.get("path"))
        if isinstance(r.get("path"), str) and r.get("subpath"):
            add(r["path"].rstrip("/") + "/" + str(r["subpath"]).lstrip("/"))
    for p in roots:
        # A newline inside a path would desync the line-oriented contract.
        print(p.replace("\n", " "))
    break
' 2>/dev/null || true)

  [ -n "$answer" ] || return 0
  PROJECT_NAME=$(printf '%s\n' "$answer" | sed -n '1p')
  # Expand a leading ~ per line: definitions store paths home-relative so they
  # re-root on every machine, and a literal "~/src/..." matches no real path.
  PROJECT_ROOTS=$(printf '%s\n' "$answer" | sed -n '2,$p' | sed "s#^~#$HOME#")
  return 0
}
