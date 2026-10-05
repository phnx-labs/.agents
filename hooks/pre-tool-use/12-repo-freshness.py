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
# Disposable hook state lives under ~/.agents/.cache/state/hooks/<hook-id>/ (hooks/AGENTS.md).
STATE = os.path.join(os.path.expanduser("~"), ".agents", ".cache", "state", "hooks", "repo-freshness")
ENV = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}


def primary_top(path: str) -> str | None:
    """Walk up to the repo root without a subprocess; None unless it is a primary checkout."""
    d = os.path.abspath(path)
    if not os.path.isdir(d):
        d = os.path.dirname(d)
    while True:
        git_dir = os.path.join(d, ".git")
        if os.path.isdir(git_dir):
            return d
        if os.path.isfile(git_dir):  # linked worktree or submodule: the agent's own tree
            return None
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def git(top: str, *args: str, timeout: float = 3) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", top, *args], capture_output=True, text=True,
                          timeout=timeout, stdin=subprocess.DEVNULL, env=ENV)


def claim(top: str) -> bool:
    """Atomically claim this repo's current window: exactly one caller wins per window.

    The claim is an O_EXCL create of a file named for the window bucket, so concurrent
    tool calls cannot all pass. Claims older than a day are pruned.
    """
    os.makedirs(STATE, exist_ok=True)
    key = hashlib.sha1(top.encode()).hexdigest()
    bucket = int(time.time() // max(WINDOW, 1)) if WINDOW > 0 else time.time_ns()
    try:
        os.close(os.open(os.path.join(STATE, f"{key}.{bucket}"), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    except FileExistsError:
        return False
    cutoff = time.time() - 86400
    for name in os.listdir(STATE):
        path = os.path.join(STATE, name)
        try:
            if os.path.getmtime(path) < cutoff:
                os.remove(path)
        except OSError:
            pass
    return True


def main() -> int:
    payload = json.load(sys.stdin)
    inputs = payload.get("tool_input") or payload.get("toolInput") or {}
    target = (inputs.get("file_path") or inputs.get("filePath") or inputs.get("notebook_path")
              or inputs.get("path") or payload.get("cwd") or os.getcwd())
    top = primary_top(str(target))
    if not top or not claim(top):
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
    # A fast-forward silently overwrites an IGNORED local file that upstream now tracks;
    # refuse that case instead of losing the file.
    incoming = set(git(top, "diff", "--name-only", f"HEAD..{upstream}").stdout.split("\n")) - {""}
    ignored = set(git(top, "ls-files", "-o", "-i", "--exclude-standard").stdout.split("\n")) - {""}
    clobber = sorted(incoming & ignored)

    if dirty:
        reason = "it has uncommitted changes"
    elif ahead:
        reason = f"it has {ahead} local commit(s)"
    elif clobber:
        reason = f"fast-forwarding would overwrite ignored local file(s): {', '.join(clobber[:5])}"
    else:
        merged = git(top, "merge", "--ff-only", "--quiet", upstream, timeout=FETCH_TIMEOUT)
        if merged.returncode == 0:
            note = f"[repo-freshness] Fast-forwarded {top} ({branch}) by {behind} commit(s) to {upstream}; you are reading current code."
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": note}}))
            return 0
        detail = " ".join((merged.stderr or merged.stdout).split())[:200] or f"git exited {merged.returncode}"
        reason = f"git refused the fast-forward ({detail})"
    note = (f"[repo-freshness] {top} ({branch}) is {behind} commit(s) behind {upstream} and was not "
            f"fast-forwarded because {reason}. Do not treat it as current: read with "
            f"`git -C {top} show {upstream}:<path>`, or work in a fresh worktree from {upstream}.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": note}}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        raise SystemExit(0)  # advisory: never wedge a tool call
