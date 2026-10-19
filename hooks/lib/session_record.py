"""The per-agent-pid session record: ~/.agents/.cache/state/sessions/<pid>.json.

session-start/04-session-identity.sh creates it (session id, cwd, pid, ts);
stop/verify-work-state.py merges the Stop verdict into it. Both key it the same
way, on the agent process that spawned the hook.
"""
from __future__ import annotations

import json
import os


def unwrap_hook_shell(pid: int) -> int:
    """Claude runs a hook as `/bin/sh -c <command>`. bash (macOS /bin/sh) execs
    the lone command, so $PPID is the agent; dash (Debian/Ubuntu /bin/sh) forks
    it, so $PPID is a wrapper that exits with the hook. Keying state on that
    wrapper left a restarted `claude` unbound from its terminal. A shell the
    launcher registered is the agent itself and stays the key."""
    if os.path.exists(os.path.expanduser("~/.agents/.cache/terminals/by-pid/%d.json" % pid)):
        return pid
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            argv = f.read().split(b"\0")
        if (len(argv) > 2 and os.path.basename(argv[0]) in (b"sh", b"dash", b"bash", b"ash")
                and argv[1][:1] == b"-" and argv[1][-1:] == b"c" and argv[1][1:].isalpha()):
            with open("/proc/%d/stat" % pid) as f:
                parent = int(f.read().rsplit(")", 1)[1].split()[1])
            if parent > 1:
                return parent
    except Exception:
        pass
    return pid


def started_own_session(pid: int) -> bool:
    """True when the live process `pid` already reported its own SessionStart: its
    record names it and was written after it started (Linux /proc, like the walk
    that asks). Such a process is an agent, so a hook below it belongs to a
    session that agent started, never to the agent itself."""
    try:
        with open(record_path(pid)) as f:
            record = json.load(f)
        if not isinstance(record, dict) or record.get("pid") != pid or not record.get("session_id"):
            return False
        with open("/proc/%d/stat" % pid) as f:
            start_ticks = int(f.read().rsplit(")", 1)[1].split()[19])
        with open("/proc/stat") as f:
            boot = int(next(line.split()[1] for line in f if line.startswith("btime ")))
        return float(record.get("ts", 0)) >= int(boot + start_ticks / os.sysconf("SC_CLK_TCK"))
    except Exception:
        return False


def record_path(agent_pid: int) -> str:
    return os.path.join(os.path.expanduser("~"), ".agents", ".cache", "state", "sessions", "%d.json" % agent_pid)


def atomic_write_json(path: str, obj: object) -> None:
    """Best-effort atomic JSON write; a failure never breaks the session."""
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp.%d" % os.getpid()
        with open(tmp, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, path)
    except Exception:
        pass


def merge_fields(agent_pid: int, session_id: str, fields: dict) -> bool:
    """Merge `fields` into this session's existing record, keeping every other
    field. Never creates a record: session-start owns creation and its
    process-view check. A record naming another session (a reused pid, or a
    sandbox sharing HOME) is not ours and is left alone."""
    path = record_path(agent_pid)
    try:
        with open(path) as f:
            record = json.load(f)
    except Exception:
        return False
    if not isinstance(record, dict) or not session_id or record.get("session_id") != session_id:
        return False
    record.update(fields)
    atomic_write_json(path, record)
    return True
