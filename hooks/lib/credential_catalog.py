"""Value-free catalog of the credentials an agent can reach on this machine.

Shared by the SessionStart injector (renders it) and the credential-ask Stop
nudge (matches an ask against it). Two sources, both read without decrypting a
value or raising a Touch ID sheet:

- `secrets list --json`: bundle metadata (name, key count, description,
  policy). Bundle metadata is stored without an ACL precisely so listing never
  prompts. Values never appear in this output.
- `browser profiles logins --json`: per profile, the login-gated services with
  a live session cookie and the account username signed in (identity, which is
  not secret). Cookie values are never read.

Bundles named `__<harness>__` hold harness worker tokens the CLI injects itself;
they are not something an agent should run under, so they are left out.
"""
from __future__ import annotations

import json
import re
import subprocess

# Words too generic to identify a service: TLDs, environment and role names, and
# credential vocabulary itself. A bundle named `prod`, `auth` or `share` must not
# turn every sentence containing that word into a match.
_STOP_LABELS = {
    "com", "ai", "io", "app", "dev", "net", "org", "co", "sh", "so", "cloud", "www",
    "api", "exe", "local", "the", "default", "auth", "share", "shared", "prod",
    "production", "staging", "stage", "test", "testing", "main", "live", "user",
    "users", "admin", "root", "personal", "work", "team", "account", "accounts",
    "env", "config", "key", "keys", "token", "tokens", "secret", "secrets",
    "password", "passwords", "login", "service", "server", "db", "database",
    "private", "public", "internal", "global", "common", "misc", "temp", "tmp",
    "backup", "new", "old", "my", "your", "our",
}


def _run_json(argv: list[str], timeout: float):
    try:
        out = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout, check=False
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except ValueError:
        return None


def secrets_bundles(timeout: float = 8.0) -> list[dict]:
    rows = _run_json(["secrets", "list", "--json"], timeout) or []
    bundles = []
    for b in rows:
        name = b.get("name") or ""
        if not name or name.startswith("__"):
            continue
        bundles.append(
            {
                "name": name,
                "keys": b.get("keys") or 0,
                "description": (b.get("description") or "").strip(),
                "policy": b.get("policy") or "",
            }
        )
    return sorted(bundles, key=lambda b: b["name"])


def browser_logins(timeout: float = 8.0) -> list[dict]:
    rows = _run_json(["browser", "profiles", "logins", "--json"], timeout) or []
    return [
        {
            "profile": r.get("profile") or "",
            "service": r.get("service") or "",
            "account": r.get("account") or "",
        }
        for r in rows
        if r.get("profile") and r.get("service")
    ]


def aliases(name: str) -> set[str]:
    """Words that identify a bundle or service in prose: `stripe.com` -> {stripe}."""
    parts = re.split(r"[^a-z0-9]+", name.lower())
    return {p for p in parts if len(p) >= 3 and p not in _STOP_LABELS}


def build() -> dict:
    return {"bundles": secrets_bundles(), "logins": browser_logins()}
