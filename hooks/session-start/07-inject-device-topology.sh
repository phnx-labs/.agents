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
#   2. Live resource headroom (load / memory / disk / a headroom badge, plus a
#      fleet capacity summary) and each box's one-line description (what it is
#      FOR) — so the agent can pick a fitting idle box when offloading work
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
# Rendered table — carries the live load/mem/disk/headroom columns and the fleet
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
# Each data row looks like:  "[▸ ]<name> <platform> [<spec cell>] <load>% <mem>% [<disk>%] <badge> <word>[ ← this machine][ role][ description]"
# where the <spec cell> ("12c 64G 1T") carries no % and the <disk>% column only
# exists on newer CLIs — so pcts[0]/pcts[1] stay load/mem on every version and a
# third percentage, when present, is disk used.
# Offline/no-stats rows have no percentages and are simply skipped (the row still
# renders from JSON reachability, just without a stats suffix).
stats = {}          # name -> "<load>% load / <mem>% mem [/ <disk>% disk] / <headroom>"
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
    # Scan ONLY the numeric region — everything before the headroom badge. The
    # row continues past it with a role and a free-text description, and a
    # description is operator-supplied ("spot instance, 20% cheaper"). Scanning
    # the whole row let that 20% become pcts[2] whenever the disk probe itself
    # failed and rendered as a dash, fabricating disk telemetry from prose and
    # injecting it fleet-wide. The badge glyph is the column boundary.
    parts = re.split(r"[\u25cf\u25cb]", rest, 1)
    if len(parts) < 2:
        # No headroom badge means the renderer had no live stats to show — an
        # offline row, or a probe that produced nothing. Skip BEFORE scanning:
        # without a badge there is no column boundary, so the scan would fall
        # back to the whole row and read percentages out of the description,
        # inventing load/mem for a box that is not even reachable.
        continue
    numeric, after_badge = parts[0], parts[1]
    pcts = re.findall(r"(\d+)%", numeric)
    if len(pcts) < 2:
        continue  # badge present but the numbers did not parse
    # The headroom word is the FIRST token after the badge. Anchor it there
    # rather than searching the row: the row continues with a role and a
    # free-text description, and searching found "idle" inside a description
    # like "mostly idle overnight" — reporting a box at 95% load as idle, which
    # is worse than no reading because it routes work ONTO a saturated machine.
    hr = next((w for w in HEADROOM_WORDS if re.match(r"\s*" + w + r"\b", after_badge)), None)
    detail = f"{pcts[0]}% load / {pcts[1]}% mem"
    if len(pcts) >= 3:
        detail += f" / {pcts[2]}% disk"
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
        lines.append("Machines you can reach (from `agents devices`), with live load / memory / disk / headroom:")
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
        # One-line operator description (newer CLIs: top-level `description` in
        # `devices list --json`; absent on older ones) — what the box is FOR.
        desc = d.get("description")
        if isinstance(desc, str) and desc:
            row += f" — {desc}"
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
            f"`agents browser navigate --device {interactive} --url file:///tmp/<file>`. "
            f"Re-run that to refresh the SAME tab in place; a raw `open` spawns a new "
            f"duplicate tab every call. Use `--device`, NOT "
            f"`agents ssh {interactive} '"'"'agents browser ...'"'"'` — the ssh form skips the "
            f"fleet dispatch path, so the target never sees the remote-control consent "
            f"marker. That box also holds the logged-in browser profile for this fleet: "
            f"`agents browser profiles logins --device {interactive}` shows which "
            f"services it is signed in to, so you can act as the user rather than "
            f"launching a logged-out browser here. "
            f"Fall back to `agents ssh {interactive} '"'"'open /tmp/<file>'"'"'` only if "
            f"that host has no drivable browser profile. "
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
        "the machine knows. To drive another box, add `--device <host>` (still no "
        "--profile: the target picks its own)."
    )

print("\n".join(lines))
' <<< "$DEVICES_JSON"

exit 0
