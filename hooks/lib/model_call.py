"""One `claude -p` model call from inside a hook.

Shared by stop/08-stop-judge.py and rules/subrules/gh-merge-guard/pr-verdict.py.
`ask()` runs one machine prompt: no tools, no session file, no user or local
settings (so no hooks re-enter), thinking off, CLAUDE_CODE_ENTRYPOINT=sdk-cli,
the prompt on stdin (never argv), and a hard timeout that kills the whole process
group. Auth is CLAUDE_CODE_OAUTH_TOKEN when the hook already has one, otherwise
one setup-token out of the file-backed `auth` secrets bundle, the session
account's first; an account at its usage limit (429) gets one retry on the next.

Installed layout: agents-cli copies hooks/lib/*.py beside the hook scripts in each
agent home, so callers put both their own directory and ../lib on sys.path.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import Callable

NO_AUTH_EXIT = 77
MIN_CALL_S = 2.0

# Runs under `secrets exec auth`: exports one setup-token as CLAUDE_CODE_OAUTH_TOKEN,
# drops the rest, execs the model call. The keys are tried in order, the session
# account's (MODEL_CALL_ACCOUNT_KEY, never in argv) first; MODEL_CALL_KEY_TRY picks the nth.
AUTH_SHIM = r"""
keys=$(env | sed -n 's/^\(CLAUDE_CODE_OAUTH_TOKEN_[A-Za-z0-9_]*\)=.*/\1/p' | sort)
k="${MODEL_CALL_ACCOUNT_KEY:-}"; n="${MODEL_CALL_KEY_TRY:-0}"; unset MODEL_CALL_ACCOUNT_KEY MODEL_CALL_KEY_TRY
if [ -z "$k" ] || [ -z "$(printenv "$k")" ]; then k=""; fi
k=$({ [ -z "$k" ] || printf '%s\n' "$k"; printf '%s\n' "$keys" | grep -vxF -e "$k"; } | sed -n "$((n + 1))p")
[ -n "$k" ] || exit 77
CLAUDE_CODE_OAUTH_TOKEN=$(printenv "$k"); export CLAUDE_CODE_OAUTH_TOKEN
for v in $keys; do unset "$v"; done
exec "$@"
"""


def _home() -> Path:
    return Path(os.path.expanduser("~"))


def list_bundles(timeout: float = 2.0) -> list[dict]:
    """`secrets list --json` rows (names and backends, never values); [] when it fails."""
    try:
        out = subprocess.run(["secrets", "list", "--json"], capture_output=True, text=True,
                             timeout=timeout, stdin=subprocess.DEVNULL, check=False)
        rows = json.loads(out.stdout) if out.returncode == 0 else []
    except (OSError, subprocess.SubprocessError, ValueError):
        return []
    return [r for r in rows if isinstance(r, dict)] if isinstance(rows, list) else []


def auth_backend(bundles: list[dict]) -> str:
    """The `auth` bundle's backend. Only "file" reads without a Touch ID or passphrase prompt."""
    return next((str(b.get("backend") or "") for b in bundles if b.get("name") == "auth"), "")


def account_key() -> str:
    """The setup-token key name for the session's account: CLAUDE_CODE_OAUTH_TOKEN_<SLUG>."""
    config = os.environ.get("CLAUDE_CONFIG_DIR")
    path = Path(config) / ".claude.json" if config else _home() / ".claude.json"
    try:
        email = (json.loads(path.read_text()).get("oauthAccount") or {}).get("emailAddress") or ""
    except (OSError, ValueError, AttributeError):
        return ""
    if not email:
        return ""
    slug = email.upper().replace("@", "_AT_").replace(".", "_DOT_")
    return "CLAUDE_CODE_OAUTH_TOKEN_" + re.sub(r"[^A-Z0-9_]", "_", slug)


def ancestor_claude(pid: int | None = None, depth: int = 8) -> str | None:
    """The claude executable that fired this hook: walk up parent processes until one's
    argv[0] is an executable named claude / claude.exe. Works for every install layout
    (version homes and per-account homes alike) because the hook always runs under it."""
    pid = pid or os.getppid()
    for _ in range(depth):
        try:
            out = subprocess.run(["ps", "-o", "ppid=,args=", "-p", str(pid)], capture_output=True,
                                 text=True, timeout=2, stdin=subprocess.DEVNULL).stdout.strip()
        except (OSError, subprocess.SubprocessError, ValueError):  # ValueError: non-UTF-8 argv
            return None
        if not out:
            return None
        ppid, _, args = out.partition(" ")
        exe = args.split(" ", 1)[0] if args else ""
        if os.path.basename(exe) in ("claude", "claude.exe") and os.path.isabs(exe) and os.access(exe, os.X_OK):
            return exe
        if not ppid.strip().isdigit() or int(ppid) <= 1:
            return None
        pid = int(ppid)
    return None


def claude_binary() -> str | None:
    """The claude binary for the call.

    Hook processes do not reliably inherit CLAUDE_CODE_EXECPATH and the version's claude is
    not on PATH. Order: CLAUDE_CODE_EXECPATH; the version-home layout
    <version>/node_modules/.bin/claude (this file sits beside the hooks in
    <version>/home/.claude/hooks/); PATH; last, the claude that fired this hook, found by
    walking parent processes (per-account homes).
    """
    env_path = os.environ.get("CLAUDE_CODE_EXECPATH")
    if env_path and os.access(env_path, os.X_OK):
        return env_path
    here = Path(os.path.abspath(__file__))
    if len(here.parents) > 3:
        installed = here.parents[3] / "node_modules" / ".bin" / "claude"
        if os.access(installed, os.X_OK):
            return str(installed)
    on_path = shutil.which("claude")
    if on_path:
        return on_path
    return ancestor_claude()


def ask(system: str, prompt: str, *, model: str, cwd: Path, auth: str,
        remaining: Callable[[], float], env: dict | None = None) -> dict:
    """One model call. `auth` is the `auth` bundle's backend; `remaining()` is the time
    left for this call (two key tries share it); `env` adds variables for the child,
    such as the caller's re-entry sentinel.

    Returns {outcome, detail, text, latency_ms, in_tok, out_tok}. outcome is "ok" (text
    is the model's reply), "no-auth", "timeout", or "error" with detail one of
    no-claude, spawn, exit-<n>, reply-shape, limit, is_error.
    """
    result = {"outcome": "error", "detail": "", "text": "", "latency_ms": None,
              "in_tok": None, "out_tok": None}
    claude = claude_binary()
    if not claude:
        result["detail"] = "no-claude"
        return result
    argv = [claude, "-p", "--setting-sources", "project", "--model", model, "--tools", "",
            "--no-session-persistence", "--system-prompt", system, "--output-format", "json"]
    child_env = dict(os.environ, MAX_THINKING_TOKENS="0", CLAUDE_CODE_ENTRYPOINT="sdk-cli",
                     **(env or {}))
    if not child_env.get("CLAUDE_CODE_OAUTH_TOKEN"):
        if auth != "file" or not shutil.which("secrets"):
            result["outcome"] = "no-auth"
            return result
        child_env["MODEL_CALL_ACCOUNT_KEY"] = account_key()
        argv = ["secrets", "exec", "auth", "--", "sh", "-c", AUTH_SHIM, "sh"] + argv
    via_bundle = argv[0] == "secrets"
    reply = None
    for key_try in (0, 1) if via_bundle else (0,):
        budget = remaining()
        if budget < MIN_CALL_S:
            result["outcome"] = "timeout"
            break
        if via_bundle:
            child_env["MODEL_CALL_KEY_TRY"] = str(key_try)
        attempt = _run(argv, child_env, prompt, cwd, budget, result)
        if attempt is None and reply is not None:
            result["outcome"] = "error"  # no second account: the limit is the answer
            break
        reply = attempt
        if not (isinstance(reply, dict) and reply.get("is_error") and reply.get("api_error_status") == 429):
            break
    if not isinstance(reply, dict):
        return result
    usage = reply.get("usage") or {}
    result["in_tok"] = sum(int(usage.get(k) or 0) for k in
                           ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    result["out_tok"] = int(usage.get("output_tokens") or 0)
    if reply.get("is_error"):
        result["detail"] = "limit" if reply.get("api_error_status") == 429 else "is_error"
        return result
    result["outcome"] = "ok"
    result["text"] = str(reply.get("result") or "")
    return result


def _run(argv: list[str], env: dict, prompt: str, cwd: Path, timeout: float, result: dict):
    """One `claude -p` run: its JSON reply, or None with result's outcome or detail set."""
    started = time.monotonic()
    try:
        proc = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, start_new_session=True)
    except OSError:
        result["detail"] = "spawn"
        return None
    try:
        stdout, _ = proc.communicate(input=prompt, timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            pass  # a descendant that left the group holds the pipe; do not wait on it
        result["outcome"] = "timeout"
        result["latency_ms"] = int((time.monotonic() - started) * 1000)
        return None
    result["latency_ms"] = int((time.monotonic() - started) * 1000)
    if proc.returncode == NO_AUTH_EXIT:
        result["outcome"] = "no-auth"
        return None
    try:
        reply = json.loads(stdout)
    except ValueError:
        result["detail"] = f"exit-{proc.returncode}"
        return None
    if not isinstance(reply, dict):
        result["detail"] = "reply-shape"
        return None
    return reply


def first_json_object(text: str):
    """The first JSON object in a model reply, or None."""
    start = text.find("{")
    if start < 0:
        return None
    try:
        obj, _ = json.JSONDecoder().raw_decode(text[start:])
    except ValueError:
        return None
    return obj if isinstance(obj, dict) else None
