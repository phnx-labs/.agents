# Dispatching Agents to Remote Fleet (SSH) Devices

How to spin up an agent on another fleet box. These are the mistakes that cost real
recoveries — a remote agent hung on stdin, a sandbox that can't run, a log tail that
bills the whole transcript back to you.

## Use the native `--device` path — never hand-roll ssh

```bash
agents run <agent> "<prompt>" --device <box> --remote-cwd <ABS repo path> --mode <mode> --name <handle>
```

- `--device` is the flag for fleet routing and works on both `agents run` and `agents teams`.
- `--device auto` lets the CLI pick from your registered, online, dispatchable fleet by 14-day affinity + live headroom. Use this as the default for "send to the fleet"; use a named `--device <box>` only when the task must land on a specific machine.
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

## Probe the box with the OPERATION YOU WILL ACTUALLY PERFORM

A trivial prompt confirms the harness is installed and logged in:

```bash
agents run <h> "Reply with exactly PINGOK" --device <box> --remote-cwd <repo> --mode plan
```

**That is ALL it confirms. A passing ping does not mean the box can do your job.**
Capability on these boxes is gated per operation class, so a probe that skips the
operation under test certifies nothing:

| Probe | What it actually exercises | What it says about writes |
|---|---|---|
| `--mode plan` ping | no sandbox at all | nothing |
| `--mode edit` running `uname -a` | no **write** sandbox (read-only cmd) | nothing |
| `--mode edit` running `git fetch` + `git worktree add` | the real write path | this is the answer |

Measured: `--mode plan` and `--mode edit`+`uname -a` both returned OK on boxes that
then failed every real write (`bwrap: setting up uid map: Permission denied`).
**If the work writes, probe with a write.** If it opens a PR, probe a commit. If it
needs a credential, probe an authenticated request.

**Known trap — codex cannot write anywhere on this fleet.** Its sandbox fails on
Linux (`bwrap` uid map) and on macOS (`cannot open '.git/FETCH_HEAD': Operation not
permitted`), and the dispatch still **exits 0** — the job looks successful and
produced nothing. For write-heavy work (worktree, edits, PR) dispatch **claude** to
a box where it is signed in, confirmed by a real write probe. Codex remains fine
for read-only/analysis dispatch.

Do **not** silently escalate to `--mode skip` / `--dangerously-bypass-approvals-and-sandbox`
to dodge a sandbox failure — that's the same security escalation as any sandbox-off flag.
Move to a harness/box that genuinely works, and say in your report that the box changed
(measurements taken before and after a box change are not comparable).

## A detached (`--no-follow`) run's status is only true through `agents devices ps`

`agents run --device … --no-follow` returns immediately and leaves the agent running on
the remote box — the right primitive when you want to start work and do something else
(see `unattended-verification` for why hand-rolled `nohup … &` does not work from inside
an agent's tool call).

Because nobody is tailing it, the on-disk dispatch record at
`~/.agents/.cache/hosts/<id>.json` **stays `"status": "running"` after the agent has
exited**, until `agents devices ps` reconciles it by reading the run's **remote
`.exit` file** and writing the real outcome back.

**But reconciliation only works if the remote `.exit` was written.** A run whose
process was killed, or whose box rebooted, never writes one — then *no command
rescues it*: the record reports `running` forever (verified: four dead PIDs on
yosemite-s1 that `agents devices ps` still lists as `running`).

So:

- Poll `agents devices ps --json` (match the `name` you passed to `--name`), never the raw
  cache file — the file is stale until `ps` reconciles it.
- Harvest with `agents logs <id>` once status leaves `running`.
- **Always bound the wait — `ps` is not a liveness check.** Pick a concrete ceiling from
  the job's own expected runtime (2x it, or a stated cap) and treat anything past it as
  dead, not slow: `agents devices stop <id>`, then proceed. Without a ceiling, one
  abnormally-killed run leaves a permanent `running` record that blocks every future
  dispatch guarded on it. If you need certainty rather than a timeout, probe the pid
  directly (`ssh <host> 'ps -p <pid>'`).

**Dispatch records are local to the box that dispatched.** `~/.agents/.cache/hosts/`
holds only the runs *this* machine launched, so a record for a run started from another
box is not missing — it lives in that box's cache. Check there before concluding a
dispatch never happened.

## Monitor at the service level — never tail full logs

Reading a dispatched agent's full output bills its OUTPUT tokens back to you as INPUT
tokens, for no benefit. Use:

- `agents sessions preview <id>` — the fleet-resolved brief (fresh status, PR link, last response, files/tests/skills/plugins/errors).
- `agents sessions --active` — the status column across all live agents.

Pull the raw remote log (`agents logs <name>`) ONLY to `grep` the single error
line when the brief shows `failed`. Never `cat`/tail the whole transcript.
