#!/usr/bin/env bash
# Tests for 07-inject-device-topology.sh — the SessionStart host/fleet injection.
# `agents` is stubbed via a PATH shim; no tailnet, no real registry.
#
# The hook reads `agents devices list --json` and does NOT parse the rendered
# table. That is the point of most of what follows: the table row ends in an
# operator-supplied free-text description, and scraping it produced four separate
# fabrication bugs (a disk % read out of "spot instance, 20% cheaper"; a 95%-load
# box reported "idle" from "mostly idle overnight"; an offline box given stats
# from its own text; and a description carrying its own badge glyph defeating the
# guard added for the third). These tests feed a table that is actively hostile
# and assert the output comes from JSON regardless.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../07-inject-device-topology.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
check_contains() { if printf '%s' "$2" | grep -qF "$3"; then echo "ok   - $1"; else echo "FAIL - $1: output missing [$3]"; fail=1; fi; }
check_absent()   { if printf '%s' "$2" | grep -qF "$3"; then echo "FAIL - $1: output contains [$3]"; fail=1; else echo "ok   - $1"; fi; }

mkdir -p "$SANDBOX/bin"

# --- fixture: JSON carries the stats; the TABLE is deliberately hostile -------
# Every description below is one that broke the old text parser. If any of them
# reaches the output, the hook is scraping the table again.
write_agents_stub() {
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "devices list --json")
    cat <<'JSON'
[{"name":"testhost","platform":"linux","tailscale":{"online":true,"direct":true},"interactive":false,
  "description":"long-running teams",
  "health":{"reachable":true,"ncpu":20,"loadPercent":25,"memPercent":48,"diskUsedPercent":36,
            "memFreeBytes":100000000000,"memTotalBytes":131000000000,"diskFreeBytes":2000000000000,
            "headroom":"busy"}},
 {"name":"loaded-box","platform":"linux","tailscale":{"online":true,"direct":true},"interactive":false,
  "description":"mostly idle overnight",
  "health":{"reachable":true,"ncpu":36,"loadPercent":95,"memPercent":91,"diskUsedPercent":88,
            "memFreeBytes":9000000000,"memTotalBytes":103000000000,"diskFreeBytes":200000000000,
            "headroom":"busy"}},
 {"name":"spot-box","platform":"linux","tailscale":{"online":true,"direct":true},"interactive":false,
  "description":"spot instance, 20% cheaper",
  "health":{"reachable":true,"ncpu":36,"loadPercent":15,"memPercent":47,
            "memFreeBytes":54000000000,"memTotalBytes":103000000000,
            "headroom":"busy"}},
 {"name":"ghost-box","platform":"linux","tailscale":{"online":false},"interactive":false,
  "description":"load 12% steady, mem 8% steady, ● idle mostly, some 30% spikes",
  "health":{"reachable":false}},
 {"name":"unprobed","platform":"linux","tailscale":{"online":true,"direct":true},"interactive":false,
  "description":"runs at 20% load, 30% mem typically, ● idle mostly",
  "health":{"reachable":true,"headroom":"unknown"}},
 {"name":"zion","platform":"macos","tailscale":{"online":true,"direct":true},"interactive":true}]
JSON
    ;;
  "devices list")
    # Hostile table. The hook must ignore this entirely.
    cat <<'TBL'
Devices (5)
  testhost        linux    99c 999G 9T    77%   66%  55%  ● loaded  worker  TABLE-LEAKED
  ghost-box       linux    offline  worker  load 12% steady, mem 8% steady, ● idle mostly, some 30% spikes
  Fleet capacity: 999 cores · 1T free / 2T RAM (50% free) · 9T disk free across 9 reachable devices
TBL
    ;;
esac
STUB
chmod +x "$SANDBOX/bin/agents"
}

# --- fixture: an older CLI whose JSON has no disk fields ---------------------
write_agents_stub_old() {
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "devices list --json")
    cat <<'JSON'
[{"name":"oldbox","platform":"linux","tailscale":{"online":true,"direct":true},"interactive":false,
  "health":{"reachable":true,"ncpu":38,"loadPercent":25,"memPercent":48,
            "memFreeBytes":100000000000,"memTotalBytes":131000000000,"headroom":"busy"}}]
JSON
    ;;
  "devices list") echo "Devices (1)" ;;
esac
STUB
chmod +x "$SANDBOX/bin/agents"
}

run_hook() { PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX" bash "$HOOK" 2>/dev/null; }

# --- stats come from JSON ----------------------------------------------------
write_agents_stub
OUT="$(run_hook)"
check_contains "load/mem/disk read from JSON"            "$OUT" "25% load / 48% mem / 36% disk"
check_contains "headroom read from JSON"                 "$OUT" "36% disk / busy"
check_contains "a box with no disk field degrades"       "$OUT" "15% load / 47% mem / busy"
check_contains "fleet capacity computed from JSON"       "$OUT" "92 cores"
check_contains "fleet capacity carries disk free"        "$OUT" "disk free"
check_contains "description rides the row"               "$OUT" "long-running teams"

# --- the hostile table must not reach the output -----------------------------
check_absent  "table stats never leak"                   "$OUT" "TABLE-LEAKED"
check_absent  "table load never leaks"                   "$OUT" "77% load"
check_absent  "table fleet line never leaks"             "$OUT" "999 cores"

# --- the four historic fabrications, none reachable from JSON ----------------
check_absent  "a description % never becomes disk"       "$OUT" "20% disk"
check_contains "a 95%-load box reports busy, not idle"   "$OUT" "95% load / 91% mem / 88% disk / busy"
check_absent  "a description word never sets headroom"   "$OUT" "91% mem / 88% disk / idle"
check_absent  "an offline box gets no stats"             "$OUT" "12% load / 8% mem"
# Its description IS rendered — that is the point of descriptions, and an offline
# box's purpose is still worth knowing. What must not happen is the same text
# being read as telemetry, which the assertion above pins.
check_contains "an offline box still shows its description"  "$OUT" "load 12% steady"
check_absent  "offline box absent from the reachable count"  "$OUT" "5 reachable device"

# A THIRD row shape the old text parser never modelled: online in the registry
# but never probed this run, so headroom is "unknown" and the renderer prints a
# dash rather than a badge glyph. Under text parsing this fell through the
# badge-glyph guard exactly like the offline case; from JSON it simply has no
# loadPercent, so there is nothing to fall through to.
check_contains "unprobed box still shows its description"    "$OUT" "runs at 20% load"
check_absent  "unprobed box gets no fabricated stats"        "$OUT" "20% load / 30% mem"

# --- older CLI: fewer keys, no invented ones ---------------------------------
write_agents_stub_old
OUT="$(run_hook)"
check_contains "old JSON: load/mem still read"           "$OUT" "25% load / 48% mem"
check_absent  "old JSON: no disk suffix invented"        "$OUT" "% disk"
check_contains "old JSON: capacity still computed"       "$OUT" "38 cores"

exit $fail
