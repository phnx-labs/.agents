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
#      (`--json` embeds the same health fields, which is why they are read from there). The probe SSHes each
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

SELF_HOST="$SELF_HOST" SELF_OS="$SELF_OS" python3 -c '
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

# Stats come from `--json`, NOT from the rendered table.
#
# This used to scrape the human table with regexes, and that approach produced
# four separate fabrication bugs — because the row ENDS in an operator-supplied
# free-text description, so every field found by searching the line could be fed
# by prose: a disk percentage read out of "spot instance, 20% cheaper"; a box at
# 95% load reported "idle" because its description said "mostly idle overnight";
# an explicitly-offline box given load/mem from its own text; and, after that was
# guarded by looking for a badge glyph, a description carrying its own glyph
# reviving the same bug. Each fix bounded one more scan; none of them removed the
# reason a scan could go wrong.
#
# `agents devices list --json` carries every field this needs — `health.loadPercent`,
# `health.memPercent`, `health.diskUsedPercent`, `health.headroom`, plus `ncpu` and
# the byte totals for the capacity line — and it is already fetched above. Reading
# typed values makes the whole class impossible: a missing field is absent, never a
# number scraped out of a sentence. Older CLIs simply carry fewer keys, so the
# output degrades to what that version actually knows.
def _fmt_bytes(n):
    if not isinstance(n, (int, float)) or n < 0:
        return None
    v, units = float(n), ["B", "K", "M", "G", "T", "P"]
    i = 0
    while v >= 1024 and i < len(units) - 1:
        v /= 1024.0
        i += 1
    return f"{round(v)}{units[i]}" if (v >= 100 or i <= 1) else f"{v:.1f}".rstrip("0").rstrip(".") + units[i]

stats = {}          # name -> "<load>% load / <mem>% mem [/ <disk>% disk] / <headroom>"
cores = mem_free = mem_total = disk_free = 0
reachable = 0
for d in devices:
    h = d.get("health") or {}
    if not h.get("reachable"):
        continue
    reachable += 1
    if isinstance(h.get("ncpu"), int):
        cores += h["ncpu"]
    for key, acc in (("memFreeBytes", "mem_free"), ("memTotalBytes", "mem_total"), ("diskFreeBytes", "disk_free")):
        v = h.get(key)
        if isinstance(v, (int, float)):
            if acc == "mem_free":
                mem_free += v
            elif acc == "mem_total":
                mem_total += v
            else:
                disk_free += v
    load, memp = h.get("loadPercent"), h.get("memPercent")
    if not isinstance(load, (int, float)) or not isinstance(memp, (int, float)):
        continue  # no live numbers for this box on this CLI version
    detail = f"{round(load)}% load / {round(memp)}% mem"
    diskp = h.get("diskUsedPercent")
    if isinstance(diskp, (int, float)):
        detail += f" / {round(diskp)}% disk"
    hr = h.get("headroom")
    if isinstance(hr, str) and hr:
        detail += f" / {hr}"
    stats[d.get("name")] = detail

fleet = ""
if reachable:
    bits = [f"{cores} cores"] if cores else []
    if mem_total:
        pct = round(mem_free / mem_total * 100)
        bits.append(f"{_fmt_bytes(mem_free)} free / {_fmt_bytes(mem_total)} RAM ({pct}% free)")
    if disk_free:
        bits.append(f"{_fmt_bytes(disk_free)} disk free")
    if bits:
        fleet = "Fleet capacity: " + " · ".join(bits) + f" across {reachable} reachable device" + ("" if reachable == 1 else "s")

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
