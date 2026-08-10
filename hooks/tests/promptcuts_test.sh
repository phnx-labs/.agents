#!/usr/bin/env bash
# hooks/tests/promptcuts_test.sh
# Cheap guard: promptcuts.yaml parses and every documented shortcut key exists,
# so a swallowed/mis-indented key fails loudly instead of silently disabling a cut.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

python3 - "$ROOT/hooks/promptcuts.yaml" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path) as f:
    data = yaml.safe_load(f)
shortcuts = data.get("shortcuts", {})
expected = [
    "#behonest",
    "#checkit",
    "#debugit",
    "#designit",
    "#godeep",
    "#gofast",
    "#nolazy",
    "#noslop",
    "#rethink",
    "#simplifyit",
    "#userecap",
    "#yousure",
]
missing = [k for k in expected if k not in shortcuts]
extra = [k for k in shortcuts if k not in expected]
if missing:
    print(f"FAIL: missing shortcut keys: {missing}", file=sys.stderr)
if extra:
    print(f"FAIL: unexpected shortcut keys: {extra}", file=sys.stderr)
if missing or extra:
    sys.exit(1)
# Also verify #debugit is not swallowed into #rethink's block scalar.
rethink = shortcuts.get("#rethink", "")
if "#debugit" in rethink:
    print("FAIL: #debugit is still inside #rethink's block scalar", file=sys.stderr)
    sys.exit(1)
print(f"OK: {len(shortcuts)} promptcut keys match expected set")
PY
