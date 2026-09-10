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
#      off this machine instead of guessing. Both come from the SAME `--json`
#      call: it embeds the live `health` fields as well as the registry, so
#      there is no second command and no table to parse. That call SSHes each
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
import json, os, sys, subprocess
from concurrent.futures import ThreadPoolExecutor

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

    interactive = next((d.get("name") for d in devices if d.get("interactive")), None)
    if interactive:
        lines.append(f"The user sits at **{interactive}** (interactive host). Deliver visual artifacts there. "
                     "Use `agents browser show <url|file>` on that host to open the configured viewer; "
                     "viewer tabs remain available to the user after the agent task ends.")
    else:
        lines.append("To show the user a visual artifact, first identify their interactive host, "
                     "then use `agents browser show <url|file>` there.")

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

# Read the CLI resolver rather than duplicating config precedence in the hook.
def read_json(args):
    try:
        result = subprocess.run(["agents", *args], capture_output=True, text=True, timeout=2)
        return json.loads(result.stdout) if result.returncode == 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None

def config(rows):
    if not isinstance(rows, list):
        return None
    return {r["key"]: r.get("value") for r in rows if isinstance(r, dict) and "key" in r}

with ThreadPoolExecutor(max_workers=2) as pool:
    cfg_future = pool.submit(read_json, ["config", "list", "--json"])
    profiles_future = pool.submit(read_json, ["browser", "profiles", "list", "--json"])
    cfg = config(cfg_future.result())
    profiles = profiles_future.result()

if cfg is not None:
    interactive = cfg.get("interactive.host") or next((d.get("name") for d in devices if d.get("interactive")), None)
    drive_host = cfg.get("browser.device") or self_host
    hosts = {h for h in (drive_host, interactive) if h and h != self_host}
    configs = {self_host: cfg}
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = {h: pool.submit(read_json, ["config", "list", "--device", h, "--json"]) for h in hosts}
        configs.update({h: config(f.result()) for h, f in futures.items()})
    drive_cfg = configs.get(drive_host)
    lines.append("")
    lines.append("Browser configuration (resolved at session start):")
    if drive_cfg is not None:
        profile = drive_cfg.get("browser.profile")
        lines.append(f"Automation: `agents browser start` routes to {drive_host}; " +
                     (f"configured profile: {profile}." if profile else "no default profile is configured."))
    else:
        lines.append(f"Automation routes to {drive_host}; its profile configuration could not be read.")
    if interactive:
        viewer_cfg = configs.get(interactive)
        if viewer_cfg is not None:
            viewer = viewer_cfg.get("browser.viewer") or viewer_cfg.get("browser.profile")
            lines.append(f"Show the user: `agents browser show <url|file>` on {interactive}; " +
                         ("viewer: OS default browser." if viewer == "os" else
                          f"configured viewer profile: {viewer}." if viewer else "no viewer profile is configured; uses the OS default browser."))
        else:
            lines.append(f"Show the user: run `agents browser show <url|file>` on {interactive}; viewer configuration unavailable here.")
    if isinstance(profiles, list):
        local = [p.get("name") for p in profiles if isinstance(p, dict) and self_host in p.get("devices", []) and p.get("name")]
        if local:
            lines.append("Profiles available on this machine: " + ", ".join(local) + ".")
    lines.append("Use the configured default for automation. To select another host, use `agents browser start --device <host>` "
                 "and let that host resolve its own profile. Use `agents browser profiles list` and "
                 "`agents config list --json` to recheck after configuration changes. "
                 "Use `agents browser show --json` to verify the actual viewer; unsupported profiles may fall back to the OS browser. Do not assume a particular browser, profile, or fleet hub.")

print("\n".join(lines))
' <<< "$DEVICES_JSON"

exit 0
