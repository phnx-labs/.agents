# Dispatching Agents to Remote Fleet (SSH) Devices

How to spin up an agent on another fleet box. These are the mistakes that cost real
recoveries — a remote agent hung on stdin, a sandbox that can't run, a log tail that
bills the whole transcript back to you.

## Use the native `--device` path — never hand-roll ssh

```bash
agents run <agent> "<prompt>" --device <box> --remote-cwd <ABS repo path> --mode <mode> --name <handle>
```

- `--device` and `--host` are the same flag (`--device` is an alias of `--host`) and work on both `agents run` and `agents teams`.
- `--device auto` / `--host auto` lets the CLI pick from your registered, online, dispatchable fleet by 14-day affinity + live headroom. Use this as the default for "send to the fleet"; use a named `--device <box>` only when the task must land on a specific machine.
- **NEVER** `ssh <box> 'agents run <agent> "<prompt>"'`. That leaks stdin: the remote agent (e.g. `codex exec`) blocks forever reading a stdin that never hits EOF, because the ssh channel stays open. The native `--device` path launches the remote process **detached** (`nohup bash -lc … >/dev/null 2>&1 &`), which is what prevents the hang — it survives a dropped connection and follows via an offset-tail of a remote log + `.exit` file.

## Fleet/SSH devices are NOT cloud devices — different venue

- **Fleet devices** = machines reachable over SSH/Tailscale, listed by `agents devices`. Dispatch with `agents run --device <box>` (or `agents teams --device`). This rule is about these.
- **Cloud devices** = `rush cloud` / codex-cloud pods — pre-built envs that open a PR, different commands and lifecycle. Do not conflate the two.

## Set `--remote-cwd` to a git repo that exists ON the remote

`--remote-cwd` is an `agents run` flag only — `agents teams add` **rejects it with a
hard error**, it is not a silent no-op. A teammate's directory is set with
`--worktree <role>` or `--cwd <dir>` instead (see the `teams` skill).

Some harnesses (codex) refuse to start outside a trusted git directory (`Not inside a
trusted directory and --skip-git-repo-check was not specified`). Point `--remote-cwd`
at an absolute repo path present on the target box. Resolve the remote HOME first
(`agents ssh <box> 'echo $HOME'`) — never pass a bare `~`/`$HOME`, which expands on the
local machine and silently targets a path that doesn't exist on the remote.

## Spread across harnesses — don't just spin up more of yourself

Dispatch whichever harness (codex / grok / droid / antigravity / claude) is confirmed
working on the target box, not a default clone of your own type. Spreading the load
across harnesses is the point of the fleet.

## Ping-test the harness on the box BEFORE the real dispatch

Fire a trivial headless prompt to confirm the harness is installed, logged in, and
functional there:

```bash
agents run <h> "Reply with exactly PINGOK" --device <box> --remote-cwd <repo> --mode plan
```

If it returns the token, it's ready. **Known trap:** codex `--mode auto` uses a
bubblewrap sandbox that fails on namespace-restricted fleet boxes
(`bwrap: setting up uid map: Permission denied`), so codex-auto can't run there at all
— the ping catches it. Fall back to another harness (or a box where it works). Do **not**
silently escalate to `--mode skip` / `--dangerously-bypass-approvals-and-sandbox` to
dodge the sandbox — that's the same security escalation as any sandbox-off flag.

## Monitor at the service level — never tail full logs

Reading a dispatched agent's full output bills its OUTPUT tokens back to you as INPUT
tokens, for no benefit. Use:

- `agents sessions <id>` — the brief/preview (status, PR link, last-response line, files/tests).
- `agents sessions --active` — the status column across all live agents.

Pull the raw remote log (`agents hosts logs <name>`) ONLY to `grep` the single error
line when the brief shows `failed`. Never `cat`/tail the whole transcript.
