#!/usr/bin/env python3
"""PostToolUse(Bash) hook: forward an agent's `agents feed post` status update to
the owner's phone — event-driven, NO polling routine (cheap: it only runs when a
status is actually posted).

The tiering the owner asked for falls out naturally: fine-grained progress
(checklist crossings) is auto-logged by 11-activity-log.py and stays feed-only;
a DELIBERATE `agents feed post` (a milestone / the completion recap) is the
important tier, and THIS hook forwards that one to the owner's iMessage.

Delivery: `rush message send` (owner-scoped iMessage via Rush's Sendblue number)
when it's available + authed on this box; otherwise falls back to OpenClaw
Telegram (works headless). Owner + channels come from ~/.agents/owner.md.

Safety: OPT-IN — does nothing unless owner.md sets `forward_status: true`. Deduped
per (session, text) with a short cooldown so a re-run can't double-send. Fires the
forward in the background so it never delays the tool. Fail-open on any error.
"""
import sys, os, re, json, shlex, hashlib, subprocess, time

_HOME = os.environ.get("HOME", os.path.expanduser("~"))
# Paths are overridable for tests; default to the real fleet locations.
SKILL = os.environ.get("ESCALATE_SKILL_DIR") or os.path.join(_HOME, ".agents", "skills", "escalate")
OWNER = os.environ.get("OWNER_PROFILE") or os.path.join(_HOME, ".agents", "owner.md")
STATE = os.environ.get("FEED_FORWARD_STATE") or os.path.join(_HOME, ".agents", ".cache", "state", "feed-forward")
COOLDOWN = 30  # seconds — dedup window for an identical (session,text)


def owner_json():
    try:
        out = subprocess.run(["python3", os.path.join(SKILL, "owner.py"), OWNER],
                             capture_output=True, text=True, timeout=5)
        return json.loads(out.stdout or "{}")
    except Exception:
        return {}


def extract_feed_post_text(command):
    """Return the text of an `agents feed post <text>` invocation, else None.
    Handles compound commands and flags; ignores a grep/echo that merely mentions
    the phrase (requires the tokens at a command position via shlex)."""
    if "feed" not in command or "post" not in command:
        return None
    try:
        tokens = shlex.split(command)
    except Exception:
        return None
    for i in range(len(tokens) - 2):
        if tokens[i] == "agents" and tokens[i + 1] == "feed" and tokens[i + 2] == "post":
            rest = [t for t in tokens[i + 3:] if not t.startswith("-")]
            text = " ".join(rest).strip()
            # stop at a shell separator if one slipped through as a token
            text = re.split(r"\s+(?:&&|\|\||;)\s+", text)[0].strip()
            return text or None
    return None


def already_sent(session, text):
    try:
        os.makedirs(STATE, exist_ok=True)
        key = hashlib.sha1(f"{session}\n{text}".encode()).hexdigest()[:16]
        mark = os.path.join(STATE, key)
        now = time.time()
        if os.path.exists(mark) and (now - os.path.getmtime(mark)) < COOLDOWN:
            return True
        with open(mark, "w") as f:
            f.write(str(now))
        return False
    except Exception:
        return False


def forward(text, agent):
    """Send the status to the owner: rush iMessage if available, else Telegram."""
    o = owner_json()
    host = o.get("host") or ""
    tg = o.get("telegram") or {}
    def on_host(shell):
        if not host or host == "local":
            return ["bash", "-lc", shell]
        return ["ssh", host, shell]
    # rush iMessage (owner-scoped) — preferred; only works where rush is authed.
    rush_cmd = ("command -v rush >/dev/null 2>&1 && rush whoami >/dev/null 2>&1 && "
                "rush message send --from-agent " + shlex.quote(agent or "claude") +
                " --text " + shlex.quote(text))
    try:
        if subprocess.run(on_host(rush_cmd), capture_output=True, timeout=25).returncode == 0:
            return
    except Exception:
        pass
    # Fallback: OpenClaw Telegram (works headless), if a target is configured.
    target = str(tg.get("target") or "")
    account = str(tg.get("account") or "default")
    if target:
        b64 = subprocess.run(["base64"], input=("[status] " + text).encode(),
                             capture_output=True).stdout.decode().replace("\n", "")
        tg_cmd = (f"openclaw message send --channel telegram --account {shlex.quote(account)} "
                  f"--target {shlex.quote(target)} --message \"$(printf %s {shlex.quote(b64)} | base64 -d)\"")
        try:
            subprocess.run(on_host(tg_cmd), capture_output=True, timeout=25)
        except Exception:
            pass


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        return
    if payload.get("agent_type"):                       # sub-agent gate
        return
    if payload.get("hook_event_name") != "PostToolUse":
        return
    if payload.get("tool_name") != "Bash":
        return
    command = str((payload.get("tool_input") or {}).get("command", ""))
    text = extract_feed_post_text(command)
    if not text:
        return
    # OPT-IN: only forward if the owner turned it on.
    if str(owner_json().get("forward_status", False)).lower() not in ("true", "1"):
        return
    session = payload.get("session_id", "") or "unknown"
    if already_sent(session, text):
        return
    agent = os.environ.get("AGENTS_AGENT_NAME") or "claude"
    # Forward in the background so the tool is never delayed.
    try:
        pid = os.fork()
    except Exception:
        forward(text, agent)                            # no fork -> inline, still fail-open
        return
    if pid == 0:
        try:
            os.setsid()
            forward(text, agent)
        finally:
            os._exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # fail open
