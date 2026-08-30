#!/usr/bin/env python3
"""Advisory nudge AFTER a PR merges: reclaim the worktree it leaves behind.

The failure this targets (PHNX-3503): worktree law puts every tracked change in
<repo>/.agents/worktrees/<slug>/, and nothing ever removed one. `gh pr merge
--delete-branch` deletes the BRANCH and leaves the CHECKOUT — usually a few GB of
node_modules — so every merged PR leaked a working tree. Measured 2026-08-30
across the fleet: 581 worktrees / ~263 GB, which took the release home base to
1.6 GiB free and wedged publishing (PHNX-3478).

The daily `worktree-sweep` routine is the backstop, but it is a backstop: it runs
on a clock and only after the grace window. This hook closes the loop at the one
moment the agent is provably finished with the tree — the merge it just ran — so
the common case is reclaimed immediately by the agent that created it.

PostToolUse on the shell tool (matcher Bash): it sees the command and its output.

Firing rule — deliberately narrow, so it never fires on ordinary PR reads. The
trap is the same one 01-github-ratelimit-nudge documents: this file, its CHANGELOG
entry, and a `gh pr diff` of its own PR all contain the words "pr merge" as prose.

  1. The COMMAND must actually be a merge invocation: `gh pr merge`, or the REST
     equivalent (`gh api ... /pulls/N/merge -X PUT`). A `gh pr view`, `gh pr
     diff`, `gh pr list`, or any grep/cat of a file mentioning merges never
     qualifies.
  2. The merge must have SUCCEEDED — a non-zero exit or an error signal means
     nothing was merged and there is nothing to reclaim yet.

Advisory: prints `additionalContext` and exits 0. Never blocks a merge. Fails
open on any error. Fires once per session, because one reminder is a nudge and
three are noise. Handles snake_case (Claude/Codex) and camelCase (Grok) payloads.
"""
import hashlib
import json
import os
import re
import sys
import tempfile

# `gh pr merge ...` or a REST merge (`gh api repos/o/r/pulls/1/merge -X PUT`).
# Both require the `gh` binary as the leading command token, so no file read can
# match however its contents read.
_GH_PR_MERGE = re.compile(r"(?:^|[;&|]\s*)gh\s+pr\s+merge\b")
_GH_API_MERGE = re.compile(r"(?:^|[;&|]\s*)gh\s+api\b[^;&|]*/pulls/\d+/merge\b")

# A successful `gh pr merge` says so; the REST form returns "merged": true.
_SUCCESS = re.compile(r"merged|Merged pull request|Pull [Rr]equest successfully merged", re.I)
# Explicit failure wording, checked first so a failed merge never nudges.
_FAILURE = re.compile(
    r"not mergeable|merge conflict|is not mergeable|GraphQL: .*(?:denied|not authorized)"
    r"|Required status checks|review is required|API rate limit|HTTP 4\d\d|HTTP 5\d\d",
    re.I,
)


def _field(payload, *names):
    """Read the first present key, tolerating snake_case and camelCase harnesses."""
    for n in names:
        if n in payload and payload[n] is not None:
            return payload[n]
    return None


def _once_per_session(session_id: str) -> bool:
    """True the first time only. Keyed by session so a long run nudges once."""
    if not session_id:
        return True
    key = hashlib.sha256(f"worktree-reclaim-nudge:{session_id}".encode()).hexdigest()[:16]
    stamp = os.path.join(tempfile.gettempdir(), f"agents-wt-nudge-{key}")
    if os.path.exists(stamp):
        return False
    try:
        with open(stamp, "w") as fh:
            fh.write("1")
    except OSError:
        pass  # unwritable tmp: nudge rather than go silent
    return True


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # fail open: never block a merge on a parse error

    tool = _field(payload, "tool_name", "toolName") or ""
    if tool != "Bash":
        return 0

    tool_input = _field(payload, "tool_input", "toolInput") or {}
    command = (tool_input.get("command") or "") if isinstance(tool_input, dict) else ""
    if not (_GH_PR_MERGE.search(command) or _GH_API_MERGE.search(command)):
        return 0

    response = _field(payload, "tool_response", "toolResponse") or {}
    if not isinstance(response, dict):
        response = {}
    stdout = str(response.get("stdout") or "")
    stderr = str(response.get("stderr") or "")
    blob = f"{stdout}\n{stderr}"

    # A non-zero exit, an explicit error flag, or failure wording all mean the
    # merge did not happen — stay quiet rather than nudging about a tree the
    # agent still needs.
    exit_code = response.get("exit_code", response.get("exitCode"))
    if isinstance(exit_code, int) and exit_code != 0:
        return 0
    if response.get("is_error") or response.get("isError"):
        return 0
    if _FAILURE.search(blob):
        return 0
    if not _SUCCESS.search(blob):
        return 0

    if not _once_per_session(str(_field(payload, "session_id", "sessionId") or "")):
        return 0

    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": (
                        "PR merged — the worktree it was built in is still on disk. "
                        "`gh pr merge --delete-branch` removes the branch but never the checkout, "
                        "which is how this fleet accumulated 581 worktrees / ~263 GB and wedged a "
                        "release box at 1.6 GiB free (PHNX-3478).\n\n"
                        "Remove it now, from the repo root:\n"
                        "  git -C <repo> worktree remove <repo>/.agents/worktrees/<slug>\n\n"
                        "That is allowed without --force once the tree is clean and pushed, which "
                        "it is after a merge. It refuses on uncommitted changes or unpushed "
                        "commits, so it is safe to run immediately. Leave the local branch ref "
                        "alone — the nightly worktree-sweep routine reclaims stragglers and "
                        "branch refs on every device."
                    ),
                }
            }
        )
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)  # advisory hook: never take down the session
