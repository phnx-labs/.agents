#!/usr/bin/env bash
# Native Linux cold hook behavior before the daemon has started.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
python3 - "$HERE/../04-session-identity.sh" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile

required = os.environ.get("AGENTS_REQUIRE_INITIAL_PID_NAMESPACE_TEST") == "1"
if sys.platform != "linux" or os.readlink("/proc/self/ns/pid") != "pid:[4026531836]":
    if required:
        raise SystemExit("initial Linux PID namespace required for this verification")
    print("SKIP: native cold hook test requires the initial Linux PID namespace")
    sys.exit(0)
hook = str(pathlib.Path(sys.argv[1]).resolve())
boot = pathlib.Path("/proc/sys/kernel/random/boot_id").read_text().strip()
init_start_ticks = pathlib.Path("/proc/1/stat").read_text().rsplit(")", 1)[1].split()[19]
with tempfile.TemporaryDirectory(prefix="hook-native-") as tmp:
    home = pathlib.Path(tmp)
    cache = home / ".agents/.cache"
    registry = cache / "terminals/by-pid"
    metadata = cache / "state/sessions"
    registry.mkdir(parents=True)
    metadata.mkdir(parents=True)
    marker = registry.parent / "process-view.json"
    reg = registry / (str(os.getpid()) + ".json")
    meta = metadata / reg.name
    env = dict(os.environ, HOME=str(home), CLAUDECODE="1")
    for key in ("GROK_SESSION_ID", "GEMINI_SESSION_ID", "CLAUDE_SESSION_ID"):
        env.pop(key, None)
    for name, owner, allowed in (
        ("absent", None, True),
        ("old-boot", json.dumps({"bootId": "prior-kernel-boot", "pidNamespace": "prior-namespace"}), True),
        ("same-boot foreign", json.dumps({"bootId": boot, "pidNamespace": "pid:[999999]"}), False),
        ("recycled namespace inode", json.dumps({"bootId": boot, "pidNamespace": "pid:[4026531836]", "initStartTicks": init_start_ticks + "1"}), False),
        ("malformed", "not-json", False),
    ):
        if marker.exists():
            marker.unlink()
        if owner is not None:
            marker.write_text(owner)
        prior = json.dumps({"pid": os.getpid(), "sessionId": "launcher", "session_id": "launcher", "terminalId": "native-tab", "launchId": "native-launch"})
        reg.write_text(prior)
        meta.write_text(prior)
        result = subprocess.run(["bash", hook], input='{"session_id":"native-session"}', text=True, capture_output=True, env=env, check=True)
        assert "native-session" in result.stdout
        if allowed:
            assert json.loads(reg.read_text())["sessionId"] == "native-session"
            assert json.loads(meta.read_text())["session_id"] == "native-session"
            assert json.loads(reg.read_text())["terminalId"] == "native-tab"
            assert json.loads(reg.read_text())["launchId"] == "native-launch"
        else:
            assert reg.read_text() == prior and meta.read_text() == prior
        if allowed:
            claim = json.loads(marker.read_text())
            assert claim["bootId"] == boot and claim["pidNamespace"] == "pid:[4026531836]"
            assert claim["initStartTicks"] == init_start_ticks
            assert claim["ownerPid"] == os.getpid() and claim["ownerStartTicks"]
        else:
            assert (marker.read_text() if marker.exists() else None) == owner
        print("PASS: native cold %s marker, PID writes %s, claim %s" % (name, "allowed" if allowed else "refused", "enrolled" if allowed else "unchanged"))
    # Compete on an empty HOME. Whichever namespace enrolls first must be the
    # only one with PID files; native authority cannot bypass a foreign claim.
    flags = ["--user", "--map-root-user", "--pid", "--fork", "--mount-proc"]
    if shutil.which("unshare") and subprocess.run(["unshare"] + flags + ["true"], capture_output=True).returncode == 0:
        runner = "import subprocess,sys; sys.exit(subprocess.run(['bash',sys.argv[1]],input=sys.argv[2],text=True,stdout=subprocess.DEVNULL).returncode)"
        payload = '{"session_id":"race-session"}'
        for attempt in range(12):
            race_home = home / ("race-%d" % attempt)
            race_home.mkdir()
            race_env = dict(env, HOME=str(race_home))
            native = subprocess.Popen(["bash", hook], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=race_env, text=True)
            nested = subprocess.Popen(["unshare"] + flags + [sys.executable, "-c", runner, hook, payload], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=race_env, text=True)
            native.communicate(payload, timeout=5)
            nested.communicate(timeout=5)
            assert native.returncode == nested.returncode == 0
            race_cache = race_home / ".agents/.cache"
            claim = json.loads((race_cache / "terminals/process-view.json").read_text())
            expected = str(os.getpid()) if claim["pidNamespace"] == "pid:[4026531836]" else "1"
            assert [p.name for p in (race_cache / "state/sessions").glob("*.json")] == [expected + ".json"]
            assert [p.name for p in (race_cache / "terminals/by-pid").glob("*.json")] == [expected + ".json"]
        print("PASS: 12 real native/nested fresh-HOME races publish PID files only for the enrolled namespace")
    elif os.environ.get("AGENTS_REQUIRE_PID_NAMESPACE_TEST") == "1":
        raise SystemExit("real native/nested race requires working unshare")
    else:
        print("SKIP: native/nested race requires working unshare")
print("ALL PASS")
PY
