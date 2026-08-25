#!/usr/bin/env python3
"""Advisory nudge AFTER a GitHub call comes back rate-limited; never blocks.

The failure this targets: an agent hits a GitHub rate limit and then sits idle
waiting for the reset, or parks the work on a background agent to retry "once the
limit resets" — instead of switching to a path that isn't limited right now. The
logged-in browser on the local device reads and posts as the user with no API
cost; the authenticated REST API (`gh api`) is 5000/hour when the wall was the
60/hour unauthenticated path.

PostToolUse on the shell tool (matcher Bash): it sees the command and its output.

Firing rule — deliberately airtight so it never distracts on ordinary repo reads
(the trap is that this hook's own source, the CHANGELOG entry describing it, and a
`gh pr diff` of its PR all *contain* the phrase "rate limit exceeded" as prose):

  1. The COMMAND must actually be a GitHub call — the `gh` CLI, or a raw HTTP
     client (curl/wget/...) aimed at a GitHub host. So `cat`/`grep`/`sed` of a
     file that merely mentions rate limits never qualifies, whatever its output.
  2. There must be an actual FAILURE signal, not prose: the rate-limit wording in
     STDERR (where gh writes its errors and exits non-zero), or a short structured
     GitHub error body in STDOUT (`{"message":"...rate limit..."}`, the curl case),
     or an explicit error/exit flag on the tool response paired with the wording.
     A *successful* `gh pr diff` puts its diff on stdout with clean stderr and exit
     0, so it never trips — even when that diff literally contains this file.

The wording itself requires an outcome (`... exceeded`, `secondary rate limit`,
`abuse detection`, `x-ratelimit-remaining: 0`), never the bare noun "rate limit".

Advisory: prints `additionalContext` and exits 0. Fails open on any error. Fires
once per session. Handles snake_case (Claude/Codex) and camelCase (Grok) payloads.
"""
import hashlib
import json
import os
import re
import sys
import tempfile

# An actual rate-limit OUTCOME (not the bare noun "rate limit", which appears in
# this hook's own docs and would misfire on repo reads).
HIT = re.compile(
    r"(?:"
    r"rate limit exceeded"              # primary REST: "API rate limit exceeded"
    r"|exceeded a secondary rate limit"  # secondary, GitHub's exact wording
    r"|secondary rate limit and have been"
    r"|abuse detection mechanism"
    r"|you have triggered an abuse"
    r"|was submitted too quickly"
    r"|x-ratelimit-remaining['\"]?\s*[:=]\s*['\"]?0\b"
    r")",
    re.I,
)
# A structured GitHub API error body (curl writes the 403 body to stdout and
# exits 0, so stderr won't carry it). A source file or diff is not JSON shaped
# like {"message": "...rate limit..."}, so this does not match ordinary reads.
STRUCT = re.compile(r'"message"\s*:\s*"[^"]*(?:rate limit|abuse detection)[^"]*"', re.I)
# Cheap first gate: only pay the parse cost when the payload even mentions a
# rate-limit-ish token. Broad on purpose; the real decision is the tight logic
# below (this only avoids parsing the ~all calls that never mention it).
GATE = re.compile(r"(?:rate.?limit|abuse detection|submitted too quickly)", re.I)

# The command is a GitHub call: the gh CLI, or a raw HTTP client to a GitHub host.
GH_CLI = re.compile(r"\bgh\b", re.I)
HTTP_CLIENT = re.compile(
    r"(?:\bcurl\b|\bwget\b|\bxh\b|\baria2c\b|\bhttpie\b|requests\.|urllib|urlopen|"
    r"\bfetch\s*\(|\baxios\b|Invoke-WebRequest|Invoke-RestMethod)",
    re.I,
)
GH_HOST = re.compile(r"(?:api\.github\.com|github\.com|githubusercontent)", re.I)


def command_is_github(cmd):
    if GH_CLI.search(cmd):
        return True
    return bool(HTTP_CLIENT.search(cmd) and GH_HOST.search(cmd))


def get(d, *names):
    for n in names:
        if isinstance(d, dict) and d.get(n) is not None:
            return d[n]
    return None


def main():
    raw = sys.stdin.read()
    if not GATE.search(raw):  # nothing rate-limit-ish in the whole payload -> done
        return
    try:
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            return
        inputs = payload.get("tool_input") or payload.get("toolInput") or {}
        command = str(get(inputs, "command", "cmd") or "")
        if not command or not command_is_github(command):
            return

        resp = payload.get("tool_response")
        if resp is None:
            resp = payload.get("toolResponse")

        stdout = stderr = ""
        errored = False
        if isinstance(resp, dict):
            stdout = str(get(resp, "stdout", "stdOut", "output", "content", "result") or "")
            stderr = str(get(resp, "stderr", "stdErr") or "")
            if any(resp.get(k) for k in ("is_error", "isError", "error", "interrupted")):
                errored = True
            for k in ("exit_code", "exitCode", "returncode", "code", "status"):
                v = resp.get(k)
                if isinstance(v, int) and v != 0:
                    errored = True
        elif isinstance(resp, str):
            stdout = resp

        combined = stdout + "\n" + stderr
        # An actual hit: in the error stream, or a short structured error body on
        # stdout (curl), or the wording paired with an explicit failure flag.
        hit_in_stderr = bool(HIT.search(stderr))
        struct_in_stdout = bool(STRUCT.search(stdout)) and len(stdout) <= 2000
        hit_and_errored = errored and bool(HIT.search(combined))
        if not (hit_in_stderr or struct_in_stdout or hit_and_errored):
            return

        session = str(payload.get("session_id") or payload.get("sessionId") or os.getppid())
    except Exception:
        return

    key = hashlib.sha1(f"github-ratelimit:{session}".encode()).hexdigest()
    directory = os.path.join(tempfile.gettempdir(), "agents-github-ratelimit-nudge")
    marker = os.path.join(directory, key)
    try:
        os.makedirs(directory, exist_ok=True)
        os.close(os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    except FileExistsError:
        return
    except OSError:
        pass

    note = (
        "[github rate-limited] Don't sit idle waiting for the reset or hand it to a background "
        "agent to retry later. Do it now another way: the logged-in browser on this device "
        "(`agents browser`), or the authenticated REST API (`gh api`)."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": note}}))


if __name__ == "__main__":
    main()
