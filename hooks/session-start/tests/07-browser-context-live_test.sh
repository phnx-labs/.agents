#!/usr/bin/env bash
# The SessionStart hook states one fixed browser rule and reads no browser
# config: the `browser` CLI resolves the configured browser itself. `agents` is
# stubbed so any config or browser call is recorded and fails.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/agents" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$SANDBOX/calls"
case "\$*" in
  "devices list --json") echo '[{"name":"zion","platform":"macos","tailscale":{"online":true,"direct":true},"interactive":true}]' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$SANDBOX/bin/agents"

output="$(PATH="$SANDBOX/bin:$PATH" bash "$HERE/../07-inject-device-topology.sh")"
fail=0
for want in 'Browser: run a bare `browser start --url <url>` with no --profile and no --device.' \
            '`browser use` prints which one' 'browser <command> --help' 'browser show <url|file>'; do
  printf '%s' "$output" | grep -qF "$want" || { echo "FAIL - output missing [$want]"; fail=1; }
done
for banned in 'Do not assume a particular browser' 'could not be read' 'Browser configuration'; do
  printf '%s' "$output" | grep -qF "$banned" && { echo "FAIL - output contains [$banned]"; fail=1; }
done
if grep -vqx 'devices list --json' "$SANDBOX/calls"; then
  echo "FAIL - hook called agents beyond the device list: $(grep -vx 'devices list --json' "$SANDBOX/calls" | tr '\n' ';')"
  fail=1
fi
[ "$fail" = 0 ] && echo "PASS: one fixed browser rule, no config reads"
exit "$fail"
