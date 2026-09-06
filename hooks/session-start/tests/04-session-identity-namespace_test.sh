#!/usr/bin/env bash
# Run the actual hook in a fresh PID namespace, with colliding host PID files.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 - "$HERE/../04-session-identity.sh" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile

hook = str(pathlib.Path(sys.argv[1]).resolve())
if sys.platform != "linux":
    print("SKIP: Linux PID namespace isolation (native hook suite covers this platform)")
    sys.exit(0)
if not shutil.which("unshare"):
    if os.environ.get("AGENTS_REQUIRE_PID_NAMESPACE_TEST") == "1":
        raise SystemExit("unshare is required for this verification run")
    print("SKIP: unshare unavailable; run namespace coverage on a Linux worker")
    sys.exit(0)
probe = subprocess.run(["unshare", "--user", "--map-root-user", "--pid", "--fork", "--mount-proc", "true"], capture_output=True, text=True)
if probe.returncode:
    if os.environ.get("AGENTS_REQUIRE_PID_NAMESPACE_TEST") == "1":
        raise SystemExit(probe.stderr)
    print("SKIP: kernel refuses PID namespaces: " + probe.stderr.strip())
    sys.exit(0)

def invoke(home, nested=False):
    env = dict(os.environ, HOME=str(home), CLAUDECODE="1")
    for key in ("GROK_SESSION_ID", "GEMINI_SESSION_ID", "CLAUDE_SESSION_ID"):
        env.pop(key, None)
    # Python is PID1 in the nested namespace; its direct hook child sees PPID1.
    runner = "import subprocess,sys; p=subprocess.run(['bash',sys.argv[1]],input='{" + '\"session_id\":\"nested-session\"' + "}',text=True,capture_output=True); print(p.stdout,end=''); sys.exit(p.returncode)"
    args = [sys.executable, "-c", runner, hook]
    if nested:
        args = ["unshare", "--user", "--map-root-user", "--pid", "--fork", "--mount-proc"] + args
    p = subprocess.run(args, env=env, text=True, capture_output=True, check=True)
    assert "nested-session" in p.stdout, p

with tempfile.TemporaryDirectory(prefix="hook-view-") as tmp:
    home = pathlib.Path(tmp)
    cache = home / ".agents/.cache"
    reg = cache / "terminals/by-pid"
    meta = cache / "state/sessions"
    reg.mkdir(parents=True)
    meta.mkdir(parents=True)
    marker = reg.parent / "process-view.json"
    boot = pathlib.Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    init_start_ticks = pathlib.Path("/proc/1/stat").read_text().rsplit(")", 1)[1].split()[19]
    host_view = {"bootId": boot, "pidNamespace": os.readlink("/proc/self/ns/pid"), "initStartTicks": init_start_ticks}
    # Both the PPID metadata and the fallback registry PID collide at 1.
    original = '{"pid":1,"sessionId":"host-session","session_id":"host-session","terminalId":"host-tab","launchId":"host-launch"}'
    for parent in (reg, meta):
        (parent / "1.json").write_text(original)
    def unchanged():
        assert (reg / "1.json").read_text() == original
        assert (meta / "1.json").read_text() == original
        assert list(reg.iterdir()) == [reg / "1.json"]
        assert list(meta.iterdir()) == [meta / "1.json"]
    marker.write_text(json.dumps(host_view))
    invoke(home, nested=True)
    unchanged()
    print("PASS: real nested hook cannot overwrite either host PID registry; context still injects")
    for invalid in ("not-json", json.dumps(dict(host_view, bootId="old-boot"))):
        marker.write_text(invalid)
        invoke(home, nested=True)
        unchanged()
        assert marker.read_text() == invalid
    print("PASS: malformed and old-boot claims are never repaired by a hook")
    marker.unlink()
    invoke(home, nested=True)
    unchanged()
    assert not marker.exists()
    print("PASS: legacy host metadata without marker is protected from nested hook")
    # Metadata-only homes must not be mistaken for unclaimed empty registries.
    (reg / "1.json").unlink()
    invoke(home, nested=True)
    assert (meta / "1.json").read_text() == original and not list(reg.iterdir())
    assert not marker.exists()
    print("PASS: metadata-only legacy home cannot be claimed by nested hook")
    (meta / "1.json").unlink()
    daemon = cache / "helpers/daemon"
    daemon.mkdir(parents=True)
    for name in ("daemon.pid", "daemon.lifetime", "daemon.heartbeat", "daemon.lock"):
        residue = daemon / name
        residue.write_text("1")
        invoke(home, nested=True)
        assert not marker.exists() and not list(reg.iterdir()) and not list(meta.iterdir())
        assert residue.read_text() == "1"
        residue.unlink()
    print("PASS: legacy daemon singleton state alone prevents a nested fresh-home claim")
    invoke(home, nested=True)
    assert json.loads((meta / "1.json").read_text())["session_id"] == "nested-session"
    claim = json.loads(marker.read_text())
    assert claim["pidNamespace"] != host_view["pidNamespace"]
    assert claim["ownerPid"] == 1 and claim["ownerStartTicks"]
    before = {str(p): p.read_bytes() for p in (reg / "1.json", meta / "1.json", marker)}
    invoke(home, nested=True)
    assert before == {p: pathlib.Path(p).read_bytes() for p in before}
    print("PASS: fresh private hook claim is atomic; a successor namespace cannot reuse that HOME")
    # Exercise the claim lock with simultaneously live distinct namespaces.
    runner = "import subprocess,sys; sys.exit(subprocess.run(['bash',sys.argv[1]],input=sys.argv[2],text=True,stdout=subprocess.DEVNULL).returncode)"
    payload = '{"session_id":"race-session"}'
    for attempt in range(12):
        race_home = home / ("race-%d" % attempt)
        race_home.mkdir()
        env = dict(os.environ, HOME=str(race_home))
        native = subprocess.Popen(["bash", hook], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True)
        nested = subprocess.Popen(["unshare", "--user", "--map-root-user", "--pid", "--fork", "--mount-proc", sys.executable, "-c", runner, hook, payload], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, text=True)
        native.communicate(payload, timeout=5)
        nested.communicate(timeout=5)
        assert native.returncode == nested.returncode == 0
        race_cache = race_home / ".agents/.cache"
        claim = json.loads((race_cache / "terminals/process-view.json").read_text())
        expected = str(os.getpid()) if claim["pidNamespace"] == host_view["pidNamespace"] else "1"
        assert [p.name for p in (race_cache / "state/sessions").glob("*.json")] == [expected + ".json"]
        assert [p.name for p in (race_cache / "terminals/by-pid").glob("*.json")] == [expected + ".json"]
    print("PASS: 12 real simultaneous namespace races write PID files only for the enrolled namespace")
print("ALL PASS")
PY
