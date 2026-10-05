#!/usr/bin/env python3
"""repo-freshness — PreToolUse: keep a primary checkout current before an agent reads it.

Replaces two hooks. `05-worktree-law-reminder` repeated the worktree rule on every
prompt, although main-branch-guard already enforces it at the first write (and creates
a fresh worktree from origin for the agent). `09-git-pull-forward` fast-forwarded only
the session's starting directory, only at SessionStart, so a repo touched later in the
session, or a long session, read stale code.

When a tool touches a PRIMARY checkout (not a linked worktree), at most once per repo
per WINDOW seconds:
  1. fetch the upstream (bounded by FETCH_TIMEOUT; on failure, use the refs on disk);
  2. clean tree, on a branch, only behind its upstream -> fast-forward (--ff-only);
  3. behind but dirty or with local commits -> tell the agent exactly how far behind,
     and where to read current code instead.
Never forces, rebases, stashes, or touches a dirty tree. Never blocks: exit 0 always.
Linked worktrees are the agent's own feature branches and are skipped.
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import time

WINDOW = int(os.environ.get("REPO_FRESHNESS_WINDOW_SEC", "600"))
FETCH_TIMEOUT = 4
STATE = os.path.join(os.path.expanduser("~"), ".agents", ".cache", "state", "repo-freshness")


def primary_top(path: str) -> str | None:
    """Walk up to the repo root without a subprocess; None unless it is a primary checkout."""
    d = os.path.abspath(path)
    if not os.path.isdir(d):
        d = os.path.dirname(d)
    while True:
        git = os.path.join(d, ".git")
        if os.path.isdir(git):
            return d
        if os.path.isfile(git):  # linked worktree or submodule: the agent's own tree
            return None
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def git(top: str, *args: str, timeout: float = 3) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", top, *args], capture_output=True, text=True, timeout=timeout)


def due(top: str) -> bool:
    """True at most once per WINDOW per repo; claims the window by touching a stamp."""
    os.makedirs(STATE, exist_ok=True)
    stamp = os.path.join(STATE, hashlib.sha1(top.encode()).hexdigest())
    try:
        if time.time() - os.path.getmtime(stamp) < WINDOW:
            return False
    except FileNotFoundError:
        pass
    with open(stamp, "w"):
        pass
    return True


def main() -> int:
    payload = json.load(sys.stdin)
    inputs = payload.get("tool_input") or {}
    target = inputs.get("file_path") or inputs.get("notebook_path") or inputs.get("path") or payload.get("cwd") or os.getcwd()
    top = primary_top(str(target))
    if not top or not due(top):
        return 0

    branch = git(top, "symbolic-ref", "--quiet", "--short", "HEAD").stdout.strip()
    upstream = git(top, "rev-parse", "--abbrev-ref", "@{u}").stdout.strip()
    if not branch or not upstream:
        return 0
    try:
        git(top, "fetch", "--quiet", "--no-tags", timeout=FETCH_TIMEOUT)
    except subprocess.TimeoutExpired:
        pass  # use the refs already on disk
    counts = git(top, "rev-list", "--left-right", "--count", f"HEAD...{upstream}").stdout.split()
    if len(counts) != 2:
        return 0
    ahead, behind = int(counts[0]), int(counts[1])
    if behind == 0:
        return 0

    dirty = bool(git(top, "status", "--porcelain", "--untracked-files=no").stdout.strip())
    if not dirty and ahead == 0 and git(top, "merge", "--ff-only", "--quiet", upstream).returncode == 0:
        note = f"[repo-freshness] Fast-forwarded {top} ({branch}) by {behind} commit(s) to {upstream}; you are reading current code."
    else:
        why = "it has uncommitted changes" if dirty else f"it has {ahead} local commit(s)"
        note = (f"[repo-freshness] {top} ({branch}) is {behind} commit(s) behind {upstream} and was not "
                f"fast-forwarded because {why}. Do not treat it as current: read with "
                f"`git -C {top} show {upstream}:<path>`, or work in a fresh worktree from {upstream}.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": note}}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        raise SystemExit(0)  # advisory: never wedge a tool call
