---
name: run
description: "Execute a single agent headlessly or interactively. Supports plan/edit/auto/skip modes, secrets bundle injection, version pinning, fallback chains, balanced rotation, profile dispatch (Kimi/DeepSeek/etc.), and workflow dispatch by name. Triggers on: 'run claude', 'run codex', 'agents run', 'dispatch an agent', 'headless agent', 'one-off agent task'."
argument-hint: "<agent|profile|workflow> [prompt]"
allowed-tools: Bash(agents run*)
user-invocable: true
---

# Run Skill

Dispatch a single agent for a one-off task. `agents run` is the fundamental command for interactive sessions and headless automation across Claude, Codex, Gemini, Cursor, OpenCode, and OpenClaw.

## Headless vs interactive

- **Prompt provided** → headless. Pipes stdout, no TTY, exits when the agent finishes.
- **Prompt omitted** → interactive. Launches the agent's TUI with full stdio inheritance.

```bash
# Interactive (TUI)
agents run claude

# Headless one-shot
agents run claude "summarize recent git commits"
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
agents run claude "fix lint errors in src/" --mode edit
agents run claude "/code:commit" --mode auto          # run a command unattended, safely
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

Codex has no native smart-classifier mode, so `agents run codex --mode auto` resolves
to sandboxed `edit` and can still prompt. `agents run codex --mode skip` instead
bypasses approvals **and** removes the sandbox. Harnesses without a native bypass flag
reject direct-exec `skip`.

**`plan` is not universally read-only.** Agents without a native read-only mode
(including Antigravity, Cursor, and Kiro) warn and degrade `plan` to their safest native
mode, which is usually writable `edit`. Headless Kimi has no read-only equivalent and
rejects `plan` instead of silently running writable.

## Reasoning effort and model

```bash
# Reasoning effort (claude and codex only)
agents run claude "..." --effort high

# Override the model directly
agents run claude "..." --model claude-opus-4-7
```

`--effort` accepts `low | medium | high | xhigh | max | auto`.

## Secrets injection

Inject keychain-backed bundles as env vars at run time. Repeatable.

```bash
agents run claude "deploy the api" --secrets prod
agents run claude "..." --secrets prod --secrets stripe
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
agents run claude "..." --strategy balanced
agents run claude "..." -b                  # shortcut for --strategy balanced
```

Strategy is ignored when `@version` is pinned, a profile is used, or `--fallback` is set.

## Fallback chains

Retry on rate-limit by handing off to another agent via `/continue`.

```bash
agents run claude "..." --fallback codex,gemini
agents run claude "..." --fallback codex@0.116.0,gemini
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
agents run claude "..." --json --quiet | jq

# Verbose execution logs
agents run claude "..." --verbose
```

`--quiet` drops the rotation banner and "Running:" preamble.

## Bounded runs

Kill the agent after a duration. Useful in CI and scheduled jobs.

```bash
agents run claude "generate sales report" --timeout 30m
agents run claude "..." --timeout 2h30m
```

## Grant access to extra directories (Claude only)

```bash
agents run claude "refactor shared utils" --add-dir ../shared --add-dir ../other-pkg
```

## Working directory

```bash
agents run claude "..." --cwd /path/to/repo
```

## ACP routing

Route through the Agent Client Protocol (Zed integration).

```bash
agents run gemini "..." --acp
agents run claude "..." --acp           # via @zed-industries/claude-code-acp adapter
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

A different axis from cloud: `agents run --host <name>` runs the agent on one of your **own** registered machines over SSH (no daemon). It follows live by default; `--no-follow` detaches.

```bash
agents run claude "profile this build" --host gpu-box   # run there, follow live
agents run claude "..." --host gpu-box --no-follow        # detach

agents hosts ps              # list dispatched runs
agents logs --host gpu-box   # pick a run on that host and view its log
agents logs <id> -f          # re-attach to a running one and follow
```

`agents logs [id]` is the unified viewer over host-dispatch runs and local session transcripts; `agents hosts logs <id>` is the host-only equivalent. See the `devices` skill.

## Quick reference

| Flag | Purpose |
|------|---------|
| `--mode plan\|edit\|auto\|skip` | Permission level (default `plan`; `full` = alias for `skip`) |
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
| `--fallback codex,gemini` | Rate-limit fallback chain |
| `-b, --balanced` | Shortcut for `--strategy balanced` |
| `--strategy pinned\|available\|balanced` | Version selection |
| `--acp` | Route via Agent Client Protocol |

For everything else, run `agents run --help`.
