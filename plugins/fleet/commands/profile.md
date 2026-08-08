---
description: Profile a sluggish machine, attribute the load to agents-cli surfaces (daemon, menu-bar helper, doctor/sessions pollers), read the logs to root-cause it, and file a GitHub issue on the public agents-cli repo with the evidence.
---

The user's machine is sluggish and suspects agents-cli. Profile it end to end, find the root cause, and file a public GitHub issue. Optional focus — a surface name (`menubar`, `daemon`, `doctor`, `sessions`) narrows the investigation to that surface; empty means sweep everything: $ARGUMENTS

You OWN this through to a filed issue — do not stop at "here's what I found." Profile → attribute → read logs → root-cause with evidence → file the issue.

## 1. Profile the machine (read-only)

The tell is CPU **oversubscription**: load average vs core count. Load average is a QUEUE DEPTH, not a percentage.

- Load vs cores: `uptime` + `sysctl -n hw.ncpu` (macOS) / `nproc` (Linux). Load ≈ cores is healthy; load ≫ cores (e.g. 300 on 18 cores ≈ 17× oversubscribed) means every process — including the WindowServer that draws your keystrokes — is starved, which is why typing lags.
- Top consumers: `ps -Aceo pid,ppid,%cpu,%mem,rss,command -r | head -25` (CPU) and `-m` (memory).
- Memory + swap: `vm_stat`, `sysctl vm.swapusage` (macOS). Heavy swapping compounds the thrash but is usually a symptom, not the cause.
- Agent process counts: count `node`, `agents`, `claude`, `bun`, `codex`. **A high count alone is not the bug.** Compare against a healthy fleet box (`agents devices` → ssh → same counts): if a worker at load ~2 runs MORE agent processes than this box at load 300, the problem isn't "too many agents" — it's a small HOT SET burning CPU.

## 2. Attribute the hot set to an agents-cli surface

Group the hot processes by what they actually run:

- `ps -Awwxo pid,ppid,etime,command | grep -Ei 'agents .*(doctor|sessions|watchdog|__daemon-run)|MenubarHelper' | grep -v grep | sort`
- **Pile-up signature:** many concurrent instances of the SAME command (dozens of `doctor --json`), each burning CPU, most **orphaned (PPID 1)**, with evenly-spaced `etime`s — a new one every N seconds that never drains. That is a poller with no cross-process singleflight, or a caller crash-looping.
- **Crash-loop signature:** `launchctl print gui/$(id -u)/<label>` (e.g. `com.phnx-labs.agents-menubar`, `com.phnx-labs.agents-daemon`) showing a high `forks` count against a low `ThrottleInterval` — a `KeepAlive` LaunchAgent relaunching a process that keeps dying. Sum the hot processes' %CPU to quantify cores burned.

## 3. Read the logs and probe the surfaces — do NOT guess

- Menu-bar helper: `~/.agents/.cache/helpers/menubar/menubar.log`.
- Daemon: `~/.agents/.cache/helpers/daemon/logs.jsonl` (grep the error line; never cat the whole file).
- LaunchAgents: `~/Library/LaunchAgents/com.phnx-labs.*.plist` (ProgramArguments, KeepAlive, ThrottleInterval, StartInterval).
- **"… is damaged and can't be opened"** dialogs → a quarantined / ad-hoc-signed / un-notarized `.app`. For each agents-cli bundle under `~/Library/Application Support/agents-cli/*.app` AND its installed npm copy: `codesign -dv --verbose=4`, `codesign --verify --deep --strict`, `spctl -a -vvv`, `xcrun stapler validate`. An un-notarized helper is rejected by Gatekeeper and crash-loops under its KeepAlive agent. Also check the non-atomic-install race: an `.app` (re)installed on the hot path of every `agents` invocation can be transiently corrupted by concurrent writers.
- Quarantine events (who flagged what): `sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 "select datetime(LSQuarantineTimeStamp+978307200,'unixepoch','localtime'), LSQuarantineAgentName, LSQuarantineDataURLString from LSQuarantineEvent order by 1 desc limit 20;"`.
- Keep `log show` windows tight (`--last 30m`, a narrow predicate) — it is expensive on an already-loaded box.

## 4. Root-cause with evidence, in the source

If a checkout of `phnx-labs/agents-cli` is present, read the actual code path (the `agents doctor` command, the menu-bar poll timer, the install path) and quote `file:line`. A root cause is a mechanism you can point at, not a symptom — and cross-check against a healthy fleet box to separate cause from consequence. Spawn parallel subagents when the data path spans several files.

## 5. File a GitHub issue on the PUBLIC repo

`phnx-labs/agents-cli` is public. Search first — `gh issue list --repo phnx-labs/agents-cli --search "<keywords>"` — and comment on an existing issue rather than filing a duplicate. Otherwise `gh issue create --repo phnx-labs/agents-cli`:

- **Title:** the mechanism, not the symptom ("menu-bar helper crash-loop spawns orphaned `doctor --json`, pinning CPU to load 300", not "computer slow").
- **Body:** the profiling numbers (load/cores, the pile-up count + summed %CPU), the process signature, the log excerpts, and the root-cause `file:line`, plus a short repro and the fix direction if you found one.
- **PUBLIC-REPO REDACTION (mandatory):** never paste a session transcript, any secret/token, or private paths that leak sensitive info; never anything under `agents secrets`. Reference the local transcript by `<host>:<path>`, don't inline it. Scrub usernames/tokens from log excerpts. **Two traps this command itself collects:** (1) never paste raw `ps` argv verbatim — a hot process may be `agents run <agent> "<literal prompt>"` carrying private task text, hostnames, or ssh targets; redact anything past the binary name unless it is clearly agents-cli-internal (a subcommand + flags). (2) Strip the query string from every URL before pasting, including `LSQuarantineDataURLString` — a download URL can itself be a bearer credential (`X-Amz-Signature`, access tokens in the query).

## 6. Report + offer a scoped mitigation (never kill silently)

Report the filed issue link. If the machine is actively degraded, describe a **scoped, reversible** mitigation — `launchctl bootout` the crash-looping helper agent, reap only the orphaned (PPID 1) pollers — and offer to run it. Killing processes or booting out services is destructive (F5): propose and get the user's OK first; never do it silently.
