#!/usr/bin/env bash
# Exercise the installed CLI config resolver and the real session hook.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
command -v agents >/dev/null || { echo "SKIP: agents is not installed"; exit 0; }
BROWSER_CONFIG_JSON="$(agents config list --json)"
BROWSER_CONTEXT="$(bash "$HERE/../07-inject-device-topology.sh")"
export BROWSER_CONFIG_JSON BROWSER_CONTEXT
python3 - <<'CHECK'
import json, os
cfg = {r["key"]: r["value"] for r in json.loads(os.environ["BROWSER_CONFIG_JSON"])}
output = os.environ["BROWSER_CONTEXT"]
assert "Browser configuration (resolved at session start):" in output
assert "agents browser show" in output
assert "unsupported profiles may fall back" in output
hub = cfg.get("browser.device")
if hub:
    assert f"routes to {hub}" in output
else:
    profile = cfg.get("browser.profile")
    if profile:
        assert f"configured profile: {profile}." in output
assert "headless/Comet profile" not in output
assert "never pass --profile" not in output
print("PASS: session browser guidance matches the installed config resolver")
CHECK
