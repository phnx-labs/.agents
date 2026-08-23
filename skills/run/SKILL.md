---
name: run
description: "Execute a single agent headlessly or interactively. Supports plan/edit/auto/skip modes, secrets bundle injection, version pinning, fallback chains, balanced rotation, profile dispatch (Kimi/DeepSeek/etc.), and workflow dispatch by name. Triggers on: 'run claude', 'run codex', 'agents run', 'dispatch an agent', 'headless agent', 'one-off agent task'."
argument-hint: "<agent|profile|workflow> [prompt]"
allowed-tools: Bash(agents run*)
user-invocable: true
---

# Run Skill

> Harness names in these examples are anchors, not prescriptions — substitute
> from the harnesses installed on this machine (`agents view`). Spreading runs
> across installed harnesses is the default; the `teams-roster-guard` enforces
> it for team rosters.


Dispatch a single agent for a one-off task. `agents run` is the fundamental command for interactive sessions and headless automation across Claude, Codex, Gemini, Cursor, OpenCode, and OpenClaw.

## Headless vs interactive

- **Prompt provided** → headless. Pipes stdout, no TTY, exits when the agent finishes.
- **Prompt omitted** → interactive. Launches the agent's TUI with full stdio inheritance.

```bash
# Interactive (TUI)
agents run claude

# Headless one-shot
agents run grok "summarize recent git commits"
```

## Modes

Permission mode controls what the agent can do.

| Mode | What it allows |
|------|----------------|
| `plan` (default) | Read-only where supported. Unsupported harnesses warn and degrade to their safest native mode (usually writable `edit`); headless Kimi rejects `plan`. |
| `edit` | Read + write files; prompts for shell / risky operations |
| `auto` | Harness-native automatic approval: Claude/Copilot use the smart classifier; Droid uses `--auto high`; Kimi uses `--auto` interactively, while headless `-p` already auto-approves and emits no mode flag. |
| `skip` | Last-resort bypass of every permission prompt. Direct exec uses the native unsafe flag; ACP selects a protocol permission option. `full` remains an alias. |

```bash
agents run kimi "fix lint errors in src/" --mode edit
agents run codex "/code:commit" --mode auto          # run a command unattended, safely
```

**Treat `skip` as a last resort.** In direct-exec runs (without `--acp`), agents-cli
forwards the harness's native bypass flag; it does not add another safety layer. Prefer
`auto` where it adds a safer automatic policy (smart classifier on Claude/Copilot,
native high-auto mode on Droid, or interactive Kimi), or `edit` everywhere else.
For headless Kimi, `edit`, `auto`, and `skip` all use the same already-auto-approved
`-p` behavior, so prefer `edit` rather than signaling a blanket bypass.

| Harness | Direct-exec `--mode skip` becomes |
|---|---|
| Claude Code | `--dangerously-skip-permissions` |
| Codex | `--dangerously-bypass-approvals-and-sandbox` (equivalent to `--yolo`) |
| Gemini | `--yolo` |
| Cursor | `-f` |
| OpenClaw | `--mode full` |
| GitHub Copilot | `--allow-all` (alias: `--yolo`) |
| Antigravity | `--dangerously-skip-permissions` |
| Grok | `--always-approve` |
| Kimi | `--yolo` interactively; no extra flag in headless `-p` runs, which already auto-approve |
| Droid | `--skip-permissions-unsafe` |

With `--acp`, these native flags are not used. agents-cli instead grants `skip`
permission requests at the ACP protocol layer: it selects `allow_always` when offered,
otherwise the first permission option offered by the server. The same last-resort
warning applies.

Codex has three managed permission profiles rather than a smart classifier. `edit`
and `auto` share one sandbox — workspace plus common build caches, network enabled —
and differ only in approvals: `edit` requests them on demand, while `auto` is
`approval_policy=never`, so it never prompts and a sandbox-denied command fails
instead of raising a dialog. Use `--mode auto` for anything unattended; a prompt
nobody answers is an agent that has stopped. When no configured run default exists,
omitting `--mode` for Codex uses `edit`. Explicit `--mode plan` remains
filesystem-read-only while retaining network access. `agents run codex --mode skip` instead bypasses approvals
**and** removes the sandbox. Harnesses without a native bypass flag reject
direct-exec `skip`.

**`plan` is not universally read-only.** Agents without a native read-only mode
(including Antigravity, Cursor, and Kiro) warn and degrade `plan` to their safest native
mode, which is usually writable `edit`. Headless Kimi has no read-only equivalent and
rejects `plan` instead of silently running writable.

## Reasoning effort and model

```bash
# Reasoning effort (claude and codex only)
agents run codex "..." --effort high

# Override the model directly
agents run claude "..." --model claude-opus-4-7
```

`--effort` accepts `low | medium | high | xhigh | max | auto`.

## Secrets injection

Inject keychain-backed bundles as env vars at run time. Repeatable.

```bash
agents run kimi "deploy the api" --secrets prod
agents run droid "..." --secrets prod --secrets stripe
```

Bundles resolve from macOS Keychain (no plaintext on disk). See the `secrets` skill for bundle management.

For workflows with a frontmatter `secrets:` field, declared bundles auto-inject. Pass `--no-auto-secrets` to skip.

## Pass env vars directly

```bash
agents run claude "..." --env DEBUG=1 --env API_KEY=xyz
```

## Run strategy

Controls which installed version/account gets the work.

| Strategy | Behavior |
|----------|----------|
| `pinned` (default) | Use the workspace/global pinned version |
| `available` | Use pinned if usage available; otherwise switch to another signed-in version |
| `balanced` | Distribute load across healthy accounts by remaining capacity |

```bash
agents run opencode "..." --strategy balanced
agents run codex "..." -b                  # shortcut for --strategy balanced

# Select any named provider or native account
agents run claude "..." --account work

# Attach the account used when --account is omitted
agents accounts attach work claude
```

Strategy is ignored when `@version` is pinned, a profile is used, or `--fallback` is set.

## Fallback chains

Retry on rate-limit by handing off to another agent via `/continue`.

```bash
agents run claude "..." --fallback codex,antigravity
agents run claude "..." --fallback codex@0.116.0,antigravity
```

Primary runs first; on rate-limit error, the next agent picks up.

## Profile dispatch

Run any OpenAI-compatible model (Kimi, DeepSeek, Qwen, etc.) through a host CLI by passing a profile name in the agent slot.

```bash
agents profiles add kimi --host claude --endpoint https://api.moonshot.ai/anthropic --model kimi-k2-thinking
agents run kimi "..."
```

The profile bundles host CLI + endpoint + model + auth. See `agents profiles --help`.

## Workflow dispatch

Pass a workflow name in the agent slot. agents-cli resolves the workflow directory (project > user > system), launches the host agent, and prepends `WORKFLOW.md` to the prompt as system instructions.

```bash
agents run code-review "review PR #42 on acme/api" --mode edit
```

See the `workflows` skill for authoring workflows.

## Pin version

```bash
agents run claude@2.1.143 "..."
```

## Resume a previous session (Claude only)

```bash
agents run claude --session-id <id>
```

## Output and observability

```bash
# Stream ndjson events for parsing
agents run kimi "..." --json --quiet | jq

# Verbose execution logs
agents run claude "..." --verbose
```

`--quiet` drops the rotation banner and "Running:" preamble.

## Bounded runs

Kill the agent after a duration. Useful in CI and scheduled jobs.

```bash
agents run droid "generate sales report" --timeout 30m
agents run opencode "..." --timeout 2h30m
```

## Grant access to extra directories (Claude only)

```bash
agents run claude "refactor shared utils" --add-dir ../shared --add-dir ../other-pkg
```

## Working directory

```bash
agents run codex "..." --cwd /path/to/repo
```

## ACP routing

Route through the Agent Client Protocol (Zed integration).

```bash
agents run grok "..." --acp           # ACP-capable harness (see acp/harnesses registry)
```

Emits a unified event stream; ndjson when combined with `--json`.

## Run in the cloud instead

`agents run` executes on this machine. To offload work to a remote backend — Rush Cloud (GitHub repo + branch, auto-opens a PR), Codex Cloud (pre-built env), or Factory pods — use `agents cloud run`:

```bash
agents cloud run "fix the flaky test" --provider rush --repo owner/repo
agents cloud run "add auth tests" --provider codex --env <env_id>
```

Scale past local capacity, dispatch async with `--no-follow`, and manage tasks with `agents cloud list|status|logs|cancel`. See the `cloud` skill.

## Run on another machine (SSH)

A different axis from cloud: `agents run --device <name>` runs the agent on one of your **own** registered machines over SSH (no daemon). It follows live by default; `--no-follow` detaches.

```bash
agents run claude "profile this build" --device gpu-box   # run there, follow live
agents run kimi "..." --device gpu-box --no-follow        # detach

agents devices ps              # list dispatched runs
agents logs --device gpu-box   # pick a run on that host and view its log
agents logs <id> -f          # re-attach to a running one and follow
```

`agents logs [id]` is the unified viewer over device-dispatch runs and local session transcripts; scope it to one machine with `--host <name>`. See the `devices` skill.

**`--remote-cwd <dir>` — the working directory on the host, used verbatim.** It is an `agents run` flag **only**: `agents teams add` rejects it with a hard error (a teammate's directory is `--worktree <role>` or `--cwd <dir>` instead — see the `teams` skill). Resolve the path **on the remote**: a bare `~`/`$HOME` expands on your local box (`/Users/you`) and silently targets a path that doesn't exist on the remote (`/home/you`), so pass a valid remote absolute path or single-quote so `$HOME` expands there. For codex, point it at a real git repo on the target box (it refuses to start outside a trusted git dir).

## Automatic fleet placement

`--device auto` lets the CLI choose a reachable machine from its
automatic-placement pool. For a named harness, placement prefers a device with
a healthy signed-in account, then the device with lower live load. An
interactive trailing-`@` picker launch also admits installed devices with a
selectable signed-out or revoked-account login target, while still ranking a
ready signed-in device first; a device whose picker would contain only
throttled accounts stays excluded. If no machine is eligible, the command fails
loud; it never silently degrades to the local machine.

```bash
agents run droid "fix the flaky test" --device auto
agents run claude "summarize logs" --device auto --no-follow
```

Use this as the default for "send this to the fleet" unless the task must land
on a specific box. Mark worker machines with `agents devices role <name> worker`;
once any worker is marked, automatic placement uses only marked workers. Mark
the user's machine `personal` to exclude it. `agents config set auto.pool all`
widens the pool past worker marks while still excluding personal devices.

## Quick reference

| Flag | Purpose |
|------|---------|
| `--mode plan\|edit\|auto\|skip` | Permission level (default `plan`; without a configured run default, omitted Codex mode uses safe writable `edit`; `full` = alias for `skip`) |
| `--effort low\|...\|max\|auto` | Reasoning effort |
| `--model <id>` | Override model |
| `--secrets <bundle>` | Inject keychain bundle (repeatable) |
| `--env KEY=val` | Pass env var (repeatable) |
| `--cwd <dir>` | Working directory |
| `--add-dir <dir>` | Extra dir access (Claude, repeatable) |
| `--json` | ndjson event stream |
| `--quiet` | Drop preamble |
| `--verbose` | Detailed logs |
| `--timeout 30m` | Kill after duration |
| `--session-id <id>` | Resume conversation (Claude) |
| `--fallback codex,antigravity` | Rate-limit fallback chain |
| `-b, --balanced` | Shortcut for `--strategy balanced` |
| `--strategy pinned\|available\|balanced` | Version selection |
| `--device <name>` | Run on a specific registered host/device |
| `--device auto` | Let the CLI pick a reachable fleet box |
| `--acp` | Route via Agent Client Protocol |

For everything else, run `agents run --help`.

`--account <name>` selects any named provider or native account and overrides
an `agents accounts attach` binding. Provider accounts are independent of
agent versions and may be used by multiple compatible harnesses; the execution
device resolves their secret locally and fails before spawn when it is absent.
Native accounts retain their declared version or device scope and validate the
harness-owned login before spawn without injecting a secret. Copy a provider bundle explicitly with
`agents accounts sync <name> <device>`. Harness-native signed-in identities may
be named with `agents accounts name <agent@version> <name>` and bound with
`agents accounts attach <name> <target>`; their auth material remains in the
harness home and is never copied.
Accounts do not apply to cloud or lease placement.
