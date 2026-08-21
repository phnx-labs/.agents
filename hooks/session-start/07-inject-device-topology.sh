#!/bin/bash
# SessionStart hook: inject host + fleet topology into the model context.
#
# Every agent should know where it is running and what other machines it can
# reach, so it can dispatch work to a peer (`agents ssh <name>`) or surface an
# artifact on the machine the user actually sits at. The device list comes from
# `agents devices` (tailscale-backed, populated by the autosync). This hook is
# always-on and NOT triggered by any keyword — it is pure context.
#
# We inject two things from `agents devices list`:
#   1. Reachability (from `--json`, always fast) — where each box is and whether
#      it is online / relayed / offline.
#   2. Live resource headroom (load / memory / a headroom badge, plus a fleet
#      capacity summary) — so the agent can pick an idle box when offloading work
#      off this machine instead of guessing. Stats come from the rendered table
#      (`--json` is registry-only and carries no live probe). The probe SSHes each
#      reachable box, bounded at ~2.5s/box in parallel, so worst case is a couple
#      of seconds; if it fails or is empty we fall back to reachability-only.
#
# Emitting to stdout is the injection mechanism: SessionStart stdout is folded
# into the model context on Claude/Codex (same convention the linear hook uses).
# Stay silent when there is nothing useful to say (no registry / no tailscale)
# so we never inject a bare, noisy block.

# Short hostname (first DNS label) + OS family of THIS machine.
SELF_HOST=$(hostname 2>/dev/null | cut -d. -f1)
case "$(uname -s 2>/dev/null)" in
  Darwin) SELF_OS=macos ;;
  Linux)  SELF_OS=linux ;;
  *)      SELF_OS=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]') ;;
esac

DEVICES_JSON=$(agents devices list --json 2>/dev/null)
# Rendered table — carries the live load/mem/headroom columns and the fleet
# capacity summary that `--json` omits. chalk auto-strips its color codes when
# stdout is not a TTY (as here), so the capture is plain text.
DEVICES_TABLE=$(agents devices list 2>/dev/null)

SELF_HOST="$SELF_HOST" SELF_OS="$SELF_OS" DEVICES_TABLE="$DEVICES_TABLE" python3 -c '
import json, os, re, sys

self_host = os.environ.get("SELF_HOST", "").strip()
self_os = os.environ.get("SELF_OS", "").strip()

raw = sys.stdin.read().strip()
devices = []
if raw:
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            devices = parsed
    except Exception:
        devices = []

# Parse the rendered table into a per-device stats map + the fleet summary line.
# Each data row looks like:  "[▸ ]<name> <platform> <load>% <mem>% <badge> <word>[ ← this machine]"
# Offline/no-stats rows have no percentages and are simply skipped (the row still
# renders from JSON reachability, just without a stats suffix).
stats = {}          # name -> "<load>% load / <mem>% mem / <headroom>"
fleet = ""
HEADROOM_WORDS = ("idle", "light", "busy", "loaded")
for rawline in os.environ.get("DEVICES_TABLE", "").splitlines():
    s = rawline.strip()
    if not s:
        continue
    if s.startswith("Fleet capacity:"):
        fleet = s
        continue
    # Drop the leading self marker ("▸ ") if present, then match name + platform.
    s = s.lstrip("▸ ").strip()
    m = re.match(r"^(\S+)\s+(macos|linux|windows)\b(.*)$", s)
    if not m:
        continue
    name, rest = m.group(1), m.group(3)
    pcts = re.findall(r"(\d+)%", rest)
    if len(pcts) < 2:
        continue  # no live stats for this box (offline / probe failed)
    hr = next((w for w in HEADROOM_WORDS if re.search(r"\b" + w + r"\b", rest)), None)
    detail = f"{pcts[0]}% load / {pcts[1]}% mem"
    if hr:
        detail += f" / {hr}"
    stats[name] = detail

# Header line always establishes "where am I".
where = f"**{self_host}**" if self_host else "an unregistered host"
lines = []
lines.append("## Host & Fleet")
lines.append("")
lines.append(f"You are running on {where}" + (f" ({self_os})" if self_os else "") + ".")

if devices:
    have_stats = any(d.get("name") in stats for d in devices)
    lines.append("")
    if have_stats:
        lines.append("Machines you can reach (from `agents devices`), with live load / memory / headroom:")
    else:
        lines.append("Machines you can reach (from `agents devices`):")
    lines.append("")
    for d in sorted(devices, key=lambda x: x.get("name", "")):
        name = d.get("name", "?")
        plat = d.get("platform", "unknown")
        ts = d.get("tailscale") or {}
        if name == self_host:
            reach = "this machine"
        elif ts.get("online"):
            reach = "online" + ("" if ts.get("direct") else " (relayed)")
        else:
            reach = "offline"
        row = f"- {name} — {plat} — {reach}"
        if name in stats:
            row += f" — {stats[name]}"
        lines.append(row)
    if fleet:
        lines.append("")
        lines.append(fleet + ".")
    lines.append("")
    guidance = (
        "Reach a peer with `agents ssh <name> [cmd]`. "
    )
    if have_stats:
        guidance += (
            "When offloading work off this machine, prefer an idle/light box over a "
            "busy/loaded one — the numbers above are a live snapshot, not the built-in "
            "scheduler'"'"'s teammate count. "
        )
    lines.append(guidance)

    # Interactive host: the one device that shows the USER artifacts (browser
    # opens, rendered plans, dashboards). Newer agents-cli marks it in
    # `devices list --json` (`interactive: true`); older CLIs omit the field and
    # we fall back to the generic guidance below.
    interactive = next((d.get("name") for d in devices if d.get("interactive")), None)
    if interactive and interactive != self_host:
        lines.append(
            f"The user sits at **{interactive}** (interactive host). To show them anything "
            f"visual (an HTML plan, a screenshot, a dashboard), deliver it THERE: "
            f"`scp <file> {interactive}:/tmp/` then show it in ONE reused browser tab — "
            f"`agents ssh {interactive} '"'"'agents browser navigate --url file:///tmp/<file>'"'"'`. "
            f"Re-run that to refresh the SAME tab in place; a raw `open` spawns a new "
            f"duplicate tab every call. Fall back to `agents ssh {interactive} "
            f"'"'"'open /tmp/<file>'"'"'` only if that host has no drivable browser profile. "
            f"Do not open it locally — the user is not watching this machine."
        )
    elif interactive:
        lines.append(
            "The user sits at THIS machine (interactive host) — show visual artifacts in "
            "ONE reused browser tab with `agents browser navigate --url file://<file>` "
            "(re-run to refresh in place, no tab pile-up), falling back to `open <file>` "
            "only if no drivable browser profile exists."
        )
    else:
        lines.append(
            "To show the user something visual (an HTML plan, a screenshot), display it on "
            "the online macOS device (where they sit) — SSH the file over, then "
            "`agents browser navigate --url file://<file>` on that host so it reuses one "
            "tab (fall back to `open <file>` only if it has no drivable browser profile)."
        )

    # Operator config for this machine (newer CLIs only): caps and notes set via
    # `agents devices config` (the retired `configure`/`note` verbs forward there).
    self_cfg = next((d.get("config") for d in devices if d.get("name") == self_host), None) or {}
    cfg_bits = []
    cap = self_cfg.get("maxAgents")
    if isinstance(cap, int):
        cfg_bits.append(f"max {cap} agents (operator cap)")
    if self_cfg.get("schedulerEnabled") is False:
        cfg_bits.append("scheduler off")
    if self_cfg.get("hooksEnabled") is False:
        cfg_bits.append("hooks off")
    notes = self_cfg.get("notes")
    if isinstance(notes, list) and notes:
        cfg_bits.append("notes: " + " · ".join(str(n) for n in notes))
    if cfg_bits:
        lines.append("This box: " + " · ".join(cfg_bits) + ".")

    lines.append(
        "Browser: a bare `agents browser start` on any machine uses THAT machine"
        "'"'"'s configured profile — never pass --profile and never name a browser binary; "
        "the machine knows."
    )

print("\n".join(lines))
' <<< "$DEVICES_JSON"

exit 0
