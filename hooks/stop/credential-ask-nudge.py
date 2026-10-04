#!/usr/bin/env python3
"""Stop hook: catch an agent asking the human for a credential it already has.

When the agent's final message asks the human for a password, token, API key
or login, and the credentials catalog (secrets bundles + signed-in browser
profiles, see lib/credential_catalog.py) names the service it is asking about,
block the stop once and point at the match. The agent tries it first; the human
is not paged for something the machine already holds.

It stays quiet, so a genuine ask still reaches the human:
- No catalog match, no nudge. One-time codes (2FA, OTP) never match: no bundle
  can hold them.
- Once per session per topic. The cool-off is keyed on the matched service, not
  the wording, so asking about Stripe a second time passes however it is
  phrased.
- If the agent already consulted secrets or browser logins this session, its
  ask is informed and passes.
- `stop_hook_active` (the agent is already continuing from a Stop block) passes.

Blocks with exit 2 + stderr, the Claude-compatible Stop protocol. Fails open:
any error exits 0.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import credential_catalog  # noqa: E402

STATE_DIR = os.path.expanduser("~/.agents/.cache/state/hooks/credential-ask-nudge")
TAIL_CHARS = 800

CREDENTIAL = re.compile(
    r"\b(passwords?|passphrase|api[ _-]?keys?|keys?|tokens?|credentials?|secrets?|"
    r"log ?in|sign ?in|username)\b"
    # An env var naming the credential: `STRIPE_SECRET_KEY`, `GH_TOKEN`.
    r"|\b[A-Z][A-Z0-9_]*_(?:KEY|TOKEN|SECRET|PASSWORD|PASS)\b",
    re.I,
)
REQUEST = re.compile(
    r"\b(can you|could you|would you|please (?:provide|share|send|paste|give|enter|add)|"
    r"(?:i|we)(?: need| require|'d need| would need)|do you have|what(?:'s| is) (?:the|your)|"
    r"share (?:the|your)|provide (?:the|your)|paste (?:the|your)|send (?:me )?(?:the|your)|"
    r"let me know (?:the|your))\b",
    re.I,
)
ONE_TIME = re.compile(
    r"\b(2fa|two[- ]factor|otp|one[- ]time|verification code|authenticator|sms code|mfa)\b", re.I
)
# A service word counts only this close to a credential word, so "the Stripe
# dashboard looked fine ... can you share the VPN password" does not match Stripe.
NEAR = 6
CREDENTIAL_WORDS = {
    "password", "passwords", "passphrase", "key", "keys", "token", "tokens",
    "credential", "credentials", "secret", "secrets", "login", "log", "sign",
    "username", "pass",
}
STATE_TTL_SECONDS = 7 * 24 * 3600
CONSULTED = re.compile(r"\bsecrets (?:list|ls|exec|view|show|status)\b|\bprofiles logins\b")


def last_assistant_text(payload: dict) -> str:
    msg = payload.get("last_assistant_message")
    if isinstance(msg, str) and msg.strip():
        return msg
    last = ""
    for rec in read_transcript(payload.get("transcript_path")):
        if rec.get("type") != "assistant":
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, list):
            text = " ".join(
                b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"
            )
            if text.strip():
                last = text
    return last


def read_transcript(path):
    if not path or not os.path.isfile(path):
        return []
    records = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                records.append(json.loads(line))
            except ValueError:
                continue
    return records


def tool_call_inputs(records: list[dict]):
    """The serialized input of every tool call, Claude and Codex shapes."""
    for rec in records:
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    yield json.dumps(b.get("input") or {})
        payload = rec.get("payload") if isinstance(rec.get("payload"), dict) else rec
        if payload.get("type") in ("function_call", "custom_tool_call", "local_shell_call"):
            yield json.dumps(payload.get("arguments") or payload.get("input") or payload.get("action") or "")


def is_credential_ask(text: str) -> bool:
    tail = text[-TAIL_CHARS:]
    if ONE_TIME.search(tail):
        return False
    return bool(CREDENTIAL.search(tail) and REQUEST.search(tail))


def matches(text: str, catalog: dict) -> tuple[list[dict], list[dict]]:
    words = re.findall(r"[a-z0-9]+", text[-TAIL_CHARS:].lower())
    anchors = [i for i, w in enumerate(words) if w in CREDENTIAL_WORDS]
    near = {w for i, w in enumerate(words) if any(abs(i - a) <= NEAR for a in anchors)}
    bundles = [b for b in catalog["bundles"] if credential_catalog.aliases(b["name"]) & near]
    logins = [r for r in catalog["logins"] if credential_catalog.aliases(r["service"]) & near]
    return bundles, logins


def nudge(bundles: list[dict], logins: list[dict]) -> str:
    lines = ["You're about to ask the human for a credential this machine already has:"]
    for b in bundles:
        lines.append(f"  secrets exec {b['name']} -- <cmd>    ({b['keys']} key{'s' if b['keys'] != 1 else ''})")
    for r in logins:
        who = f" as {r['account']}" if r["account"] else ""
        lines.append(f"  browser start --profile {r['profile']}    (signed in to {r['service']}{who})")
    lines.append(
        "Try it first. If it is the wrong account or it fails, ask again and say what you tried; "
        "this check will not stop you a second time."
    )
    return "\n".join(lines)


def claim_topic(session: str, topic: str) -> bool:
    """True the first time this session asks about this topic; records it."""
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    cutoff = time.time() - STATE_TTL_SECONDS
    for entry in os.scandir(STATE_DIR):
        if entry.stat().st_mtime < cutoff:
            os.unlink(entry.path)
    key = hashlib.sha256(f"{session}\0{topic}".encode()).hexdigest()[:32]
    try:
        fd = os.open(os.path.join(STATE_DIR, key), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return False
    os.close(fd)
    return True


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0
    session = payload.get("session_id")
    # No session id means no per-session cool-off; one shared key would let a
    # single nudge silence every later session on the machine.
    if payload.get("stop_hook_active") or not session:
        return 0
    text = last_assistant_text(payload)
    if not text or not is_credential_ask(text):
        return 0
    if any(CONSULTED.search(i) for i in tool_call_inputs(read_transcript(payload.get("transcript_path")))):
        return 0
    bundles, logins = matches(text, credential_catalog.build())
    if not bundles and not logins:
        return 0
    topic = ",".join(sorted({b["name"] for b in bundles} | {r["service"] for r in logins}))
    if not claim_topic(str(session), topic):
        return 0
    print(nudge(bundles, logins), file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # noqa: BLE001 — a Stop hook must never wedge a session
        sys.exit(0)
