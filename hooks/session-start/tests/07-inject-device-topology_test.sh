#!/usr/bin/env bash
# Tests for 07-inject-device-topology.sh — the SessionStart host/fleet injection.
# `agents` is stubbed via a PATH shim; no tailnet, no real registry. Covers both
# table shapes the parser must survive: the current one (spec cell + disk% column,
# description trailing) and the pre-spec one (load%/mem% only), since fleet boxes
# run mixed CLI versions.

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../07-inject-device-topology.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fail=0
check_contains() { if printf '%s' "$2" | grep -qF "$3"; then echo "ok   - $1"; else echo "FAIL - $1: output missing [$3]"; fail=1; fi; }
check_absent()   { if printf '%s' "$2" | grep -qF "$3"; then echo "FAIL - $1: output contains [$3]"; fail=1; else echo "ok   - $1"; fi; }

mkdir -p "$SANDBOX/bin"

# --- fixture: current shape (spec cell, disk column, description in JSON) ----
write_agents_stub_new() {
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "devices list --json")
    cat <<'JSON'
[{"name":"testhost","platform":"linux","tailscale":{"online":true,"direct":true},"interactive":false,"description":"long-running teams"},
 {"name":"zion","platform":"macos","tailscale":{"online":true,"direct":true},"interactive":true},
 {"name":"pinnacles","platform":"macos","tailscale":{"online":false}},
 {"name":"gpu-box","platform":"linux","tailscale":{"online":true,"direct":true},"interactive":false,"description":"spot instance, 20% cheaper"}]
JSON
    ;;
  "devices list")
    cat <<'TBL'
Devices (3)
  device          platform spec         load   mem disk  headroom
  pinnacles       macos    offline
▸ testhost        linux    20c 122G 3.7T  25%   48%  36%  ● busy  ← this machine  worker  long-running teams
  zion            macos    18c 127G 3.6T  31%   39%  54%  ● light  ★ interactive  personal
  gpu-box         linux    36c 96G 2T     15%   47%    —  ● busy  worker  spot instance, 20% cheaper
  Fleet capacity: 38 cores · 300G free / 249G RAM (65% free) · 4T disk free across 2 reachable devices
TBL
    ;;
esac
STUB
chmod +x "$SANDBOX/bin/agents"
}

# --- fixture: legacy shape (no spec cell, no disk column, no description) ----
write_agents_stub_old() {
cat > "$SANDBOX/bin/agents" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "devices list --json")
    printf '[{"name":"testhost","platform":"linux","tailscale":{"online":true,"direct":true},"interactive":false},{"name":"zion","platform":"macos","tailscale":{"online":true,"direct":true},"interactive":true}]\n'
    ;;
  "devices list")
    cat <<'TBL'
Devices (2)
  device          platform  load   mem  headroom
▸ testhost        linux    25%   48%  ● busy  ← this machine
  zion            macos    31%   39%  ● light
  Fleet capacity: 38 cores · 300G free / 249G RAM (65% free) across 2 reachable devices
TBL
    ;;
esac
STUB
chmod +x "$SANDBOX/bin/agents"
}

# hostname stub pins the self name so the fixtures are machine-independent.
cat > "$SANDBOX/bin/hostname" <<'STUB'
#!/usr/bin/env bash
echo testhost
STUB
chmod +x "$SANDBOX/bin/hostname"

run_hook() { PATH="$SANDBOX/bin:$PATH" bash "$HOOK" 2>/dev/null; }

# --- current shape -----------------------------------------------------------
write_agents_stub_new
OUT="$(run_hook)"
check_contains "new shape: load parses" "$OUT" "25% load / 48% mem"
check_contains "new shape: disk column parses as disk, not mem" "$OUT" "36% disk"
check_contains "new shape: headroom word survives" "$OUT" "busy"
check_contains "new shape: description from JSON rides the row" "$OUT" "long-running teams"
check_contains "new shape: fleet summary carried with disk free" "$OUT" "4T disk free"
check_absent  "new shape: offline row gets no phantom stats" "$(printf '%s' "$OUT" | grep '^\- pinnacles')" "%"
check_absent  "new shape: spec cell numbers never become percentages" "$OUT" "20c load"
# A failed disk probe renders as a dash, and the description is operator free
# text. Scanning the whole row let a description's percentage become pcts[2] and
# be injected as live disk telemetry — fabricated data, fleet-wide.
check_contains "new shape: failed disk probe still reports load/mem" "$OUT" "15% load / 47% mem"
check_absent  "new shape: a description percentage never becomes disk" "$OUT" "20% disk"

# --- legacy shape ------------------------------------------------------------
write_agents_stub_old
OUT="$(run_hook)"
check_contains "old shape: load/mem still parse" "$OUT" "25% load / 48% mem"
check_absent  "old shape: no disk suffix invented" "$OUT" "% disk"
check_contains "old shape: fleet summary carried" "$OUT" "Fleet capacity: 38 cores"

exit $fail
