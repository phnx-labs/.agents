# Hooks

Shell and Python scripts that run on agent lifecycle events. If agent behavior differs from
plain Claude or Codex, it usually starts here.

A script in this directory does nothing on its own. It runs only once it is **registered**
in the `hooks:` section of [`../agents.yaml`](../agents.yaml), which names the events it
fires on. Layered with `~/.agents/agents.yaml`: a same-named entry in your user layer wins.

**A hook must never pop Touch ID or hang a session.** Hooks use only documented
non-interactive surfaces: `--json`-style flags and the tool's own plaintext config
(e.g. `~/.linear-cli/config.json`). Never `agents secrets` from a hook, and never
internal env knobs. SessionStart hooks are the sharp edge — they fire on every
session, on every harness, and a biometric sheet behind one blocks the session
until a human touches the sensor.

## Multi-harness

Target harnesses: **claude, codex, kimi, grok, cursor, droid, antigravity**.

| Fact | Detail |
|---|---|
| `agents:` in `agents.yaml` | **Ignored** by agents-cli (`ManifestHook.agents` is deprecated). Every registered hook is written into every hooks-capable version home on sync. |
| Gemini CLI | Hard-deprecated (Google → Antigravity). Do not list as a target; use `antigravity`. |
| Stdin field names | Claude / Codex / Kimi / Cursor / Droid: snake_case (`tool_name`, `tool_input.command`, `session_id`). Grok: camelCase (`toolName`, `toolInput.command`, `sessionId`). Guards and inject scripts accept **both**. |
| Shell tool matcher | Manifest keeps `matcher: Bash`. Grok auto-aliases `Bash` → `run_terminal_command` (and keeps the original name). |
| SessionStart stdout | Claude / Codex / Kimi / Cursor inject stdout into context. **Grok ignores SessionStart stdout** (passive only) — Linear / topology / inflight text injects do not reach the Grok model. Side-effect SessionStart hooks (autosync, git-pull-forward, session-identity file writes) still run. |
| Antigravity events | agents-cli maps only `PreToolUse` → `before_tool_call`, `PostToolUse` → `after_model_call`, `Stop` → `on_loop_stop`. No SessionStart / UserPromptSubmit / Notification on agy today. |
| Block protocol | Exit `2` + reason on stderr for PreToolUse / Stop (Claude-compatible). Grok also accepts `{"decision":"deny"}` on stdout. |

When you add a PreToolUse guard that reads a shell command, always try
`tool_input.command` then `toolInput.command`. When you read tool or session ids,
accept snake_case and camelCase.

## Layout — `hooks/<event-name>/<hook-name>`

Scripts live under a **one-level event directory** (kebab-case of the harness event):

```
hooks/
  session-start/          SessionStart
    tests/                  its *_test.sh files
  pre-tool-use/           PreToolUse
    tests/                  its *_test.sh files
  user-prompt-submit/     UserPromptSubmit
    tests/                  its *_test.sh files
  stop/                   Stop
    tests/                  its *_test.sh files
  notification/           Notification (+ multi-event hooks that start there)
  lib/                    shared helpers sourced by hooks (not event scripts)
    tests/                  its *_test.sh files
  promptcuts.yaml         data for promptcuts (internal hook: expand-promptcuts)
  registration_test.sh    integrity gate (top-level)
  syntax_test.sh          parse gate — every hook script, incl. under bash 3.2
  run_tests.sh
```

agents-cli discovers scripts one level under group dirs; the install name is the
**file basename** so version homes stay flat. `agents.yaml` `script:` is relative
to `hooks/` (e.g. `session-start/04-session-identity.sh`).

**Tests live in a `tests/` subdir of their own event dir**, one level deeper than
the hook script they cover — `hooks/<event-name>/tests/<name>_test.sh`, not
beside the script. This keeps `ls hooks/<event-name>/` limited to the scripts
that actually run on the harness event. See [`AGENTS.md`](./AGENTS.md) for the
path-reference rule a moved test must follow.

Rule-bundled guards do **not** live here — they ship with the subrule under
`rules/subrules/<rule>/` via that dir's `hooks.yaml` (absolute script paths at
register time). See [§Subrule hooks](#subrule-hooks-rules-not-this-tree).

## What runs, and when

### `session-start/` — SessionStart

| Hook | What it does |
|---|---|
| [`04-session-identity.sh`](./session-start/04-session-identity.sh) | The single "who am I" hook — session id, transcript path, runtime. Enriches by-pid with `sessionId` while **preserving** launcher `terminalId` / `launchId` (Factory / `--active` join keys) |
| [`03-linear-inject-tasks-context.sh`](./session-start/03-linear-inject-tasks-context.sh) | Injects Team & Agents, **every project** (milestones + top open tickets; cwd-matched first), then the active cycle grouped by project. Credentials from `~/.linear-cli/config.json` only (never `agents secrets` / Touch ID); skips with a one-line fix when absent |
| [`07-inject-device-topology.sh`](./session-start/07-inject-device-topology.sh) | Host and fleet topology, live load/memory per machine |
| [`08-inject-repo-inflight.sh`](./session-start/08-inject-repo-inflight.sh) | In-flight PRs and agents working on this project |
| [`05-session-start-autosync.sh`](./session-start/05-session-start-autosync.sh) | Brings the machine current — config repos, secrets, sessions |
| [`09-git-pull-forward.sh`](./session-start/09-git-pull-forward.sh) | Fast-forwards the session cwd git repo when clean (ff-only) |

### `pre-tool-use/` — PreToolUse

| Hook | What it does |
|---|---|
| [`git-guard.sh`](./pre-tool-use/git-guard.sh) | Blocks destructive git: `reset --hard`, force-push, `checkout -- .`, `stash`, `clean`, history rewrites |
| [`rm-guard.sh`](./pre-tool-use/rm-guard.sh) | Blocks destructive `rm` patterns |
| [`large-file-add-guard.sh`](./pre-tool-use/large-file-add-guard.sh) | Blocks `git add` of a file over 5 MiB |
| [`01-git-require-clean-tree.sh`](./pre-tool-use/01-git-require-clean-tree.sh) | Blocks `git pull` / `rebase` / autostash while the tree is dirty |
| [`09-mailbox-inject.py`](./pre-tool-use/09-mailbox-inject.py) | Delivers queued messages into a running session |
| [`10-mq-read-nudge.py`](./pre-tool-use/10-mq-read-nudge.py) | On a large whole-file `Read`, suggests `mq` |

### `user-prompt-submit/` — UserPromptSubmit

| Hook | What it does |
|---|---|
| [`02-expand-prompt-user-shortcuts.sh`](./user-prompt-submit/02-expand-prompt-user-shortcuts.sh) | **promptcuts** — expands shortcut tokens from `promptcuts.yaml` |
| [`02-expand-prompt-bang-commands.sh`](./user-prompt-submit/02-expand-prompt-bang-commands.sh) | **bangcuts** — runs inline `` `!cmd` `` blocks concurrently and injects their output |
| [`03-vacation-recap.py`](./user-prompt-submit/03-vacation-recap.py) | On a long gap since the session's last prompt, reminds the agent to open with a back-from-vacation recap |
| [`04-verify-work-state.py`](./user-prompt-submit/04-verify-work-state.py) | Records a hashed goal boundary in `verify-work-complete`'s session-keyed hook database; never stores prompt text |

### `stop/` — Stop

| Hook | What it does |
|---|---|
| [`00-agent-verify-work-complete.sh`](./stop/00-agent-verify-work-complete.sh) | Blocks a stop that claims "done" without verification / open PR with no handoff |
| [`verify-work-state.py`](./stop/verify-work-state.py) | Hook-owned SQLite state and positive-evidence classifier used by `verify-work-complete` |
| [`verify-delivery-chain.py`](./stop/verify-delivery-chain.py) | Invoked by the Stop gate (not registered alone) |

### `notification/` — Notification

| Hook | What it does |
|---|---|
| [`06-attention-sentinel.sh`](./notification/06-attention-sentinel.sh) | Per-session attention state (also fires on Stop + UserPromptSubmit) |

## Subrule hooks (rules, not this tree)

Guards that enforce a **standing rule** ship next to that rule:

```
rules/subrules/<rule-name>/
  rule.md
  hooks.yaml          # bare map: name → { script, events, matcher?, timeout? }
  <script>.sh
  <script>_test.sh
```

`collectSubruleHooks` rewrites `script` to an **absolute** path under the subrule
dir and namespaces the manifest key as `<rule>__<hook>`. Do not copy these into
`hooks/<event>/` — they would double-register and drift from the rule.

| Subrule | Hook(s) | Events |
|---|---|---|
| `gh-merge-guard` | `merge-guard` | PreToolUse (Bash) |
| `no-pr-footer` | `footer-guard` | PreToolUse (Bash) |
| `plan-presentation` | `plan-html-reminder`, `plan-html-stop-reminder` | PreToolUse (ExitPlanMode), Stop (cross-harness backstop) |
| `truly-agentic-git-workflow` | `main-branch-guard`, `pr-description-reminder` | PreToolUse |

## Manifest schema (`hooks:` in `../agents.yaml`)

```yaml
hooks:
  my-hook:
    script: pre-tool-use/02-my-hook.sh   # path relative to hooks/
    events: [PreToolUse]
    timeout: 5
    matches:               # optional pre-filters; AND together
      prompt_contains: "#"
    enabled: true
```

- `script` — path relative to this directory (event dir + filename).
- `events` — lifecycle events to register on.
- `timeout` — seconds.
- `matches` — optional predicates.
- `enabled` — set `false` to disable a hook in a manifest. The user layer can
  disable any system-shipped hook.
- `agents` — **deprecated**; ignored.

## Enabling and disabling hooks

Hooks change **runtime** behavior (unlike commands/skills/plugins, which are
tools agents open on demand). Promptcuts and bangcuts are both enabled by
default.

**Turn one off** — same name in the user layer, then `agents sync` so version
homes pick up the change:

```yaml
# ~/.agents/agents.yaml
hooks:
  expand-bang-commands:   # bangcuts
    enabled: false
    override: true
  expand-promptcuts:      # promptcuts
    enabled: false
    override: true
```

`enabled: false` alone is enough to disable it — a disabled hook is deleted from
the merged map before the registrar ever sees it. `override: true` only silences
the `User-layer hook '<name>' disables system-shipped hook` warning that a
user-layer entry shadowing a system one prints otherwise; leave it off if you
want the reminder.

The public feature names are **promptcuts** and **bangcuts**; the manifest keys
they map to are `expand-promptcuts` and `expand-bang-commands`. Those keys are
what `enabled:` takes, and they stay stable — existing user-layer YAML keeps
working.

The same YAML disables any other system-shipped hook:

```yaml
# ~/.agents/agents.yaml
hooks:
  linear-tasks:
    enabled: false
  verify-work-complete:
    enabled: false
```

An `agents hooks enable|disable <feature>` CLI that takes the public names is
planned but **not shipped** — `agents hooks` currently has only
`list|add|remove|view|profile`, so the YAML overlay above is the supported path.
Do not document the CLI form here until it exists: bangcuts runs shell commands
on by default, and an off-switch that errors is worse than no off-switch.

Data-loss guards (`git-guard`, `rm-guard`, `large-file-add-guard`) should stay
on unless you know why you're disabling them.

## Layering

System (`~/.agents/.system/agents.yaml`), extra repos, and user (`~/.agents/agents.yaml`)
merge with **user wins on key collision**. Same-named entry in the user repo replaces
the system entry wholesale; set `override: true` to silence the shadowing warning.

## Promptcuts and bangcuts

Type `#checkit`, `` `#checkit` ``, `!!checkit`, or `` `!!checkit` `` in a prompt
and it expands into the full verification discipline. The `!!` form leaves `#`
available for hashtags; backticks make either marker visually explicit. Existing
bare `#name` promptcuts remain compatible.
`promptcuts.yaml` stays at **`hooks/promptcuts.yaml`** (not under an event dir) —
agents-cli and the expand-promptcuts hook resolve that fixed path.

- `~/.agents/.system/hooks/promptcuts.yaml` — system defaults
- `~/.agents/hooks/promptcuts.yaml` — your shortcuts; user keys win

Bangcuts execute backticked commands such as `` `! git status --short` `` in
the local shell, concurrently when a prompt contains more than one, and inject
their output in source order. Only use bangcuts with prompt text you trust.

Run `python3 hooks/tests/benchmark_prompt_expansion.py` (or `py -3 ...` on
Windows) to measure cold-process no-marker latency, promptcut expansion, and
concurrent bang-command execution.
