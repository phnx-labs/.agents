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

## Layout — `hooks/<event-name>/<hook-name>`

Scripts live under a **one-level event directory** (kebab-case of the harness event):

```
hooks/
  session-start/          SessionStart
  pre-tool-use/           PreToolUse
  post-tool-use/          PostToolUse
  user-prompt-submit/     UserPromptSubmit
  stop/                   Stop
  notification/           Notification (+ multi-event hooks that start there)
  promptcuts.yaml         data for expand-promptcuts (stays at hooks/ root)
  registration_test.sh    integrity gate (top-level)
  run_tests.sh
```

agents-cli discovers scripts one level under group dirs; the install name is the
**file basename** so version homes stay flat. `agents.yaml` `script:` is relative
to `hooks/` (e.g. `session-start/04-session-identity.sh`).

Rule-bundled guards do **not** live here — they ship with the subrule under
`rules/subrules/<rule>/` via that dir's `hooks.yaml` (absolute script paths at
register time). See [§Subrule hooks](#subrule-hooks-rules-not-this-tree).

## What runs, and when

### `session-start/` — SessionStart

| Hook | What it does |
|---|---|
| [`04-session-identity.sh`](./session-start/04-session-identity.sh) | The single "who am I" hook — session id, transcript path, runtime |
| [`03-linear-inject-tasks-context.sh`](./session-start/03-linear-inject-tasks-context.sh) | Injects a Linear brief and the active-sprint board. Reads `~/.linear-cli/config.json`; skips silently when absent |
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
| [`02-expand-prompt-user-shortcuts.sh`](./user-prompt-submit/02-expand-prompt-user-shortcuts.sh) | Expands `#shortcut` tokens from `promptcuts.yaml` |
| [`02-expand-prompt-bang-commands.py`](./user-prompt-submit/02-expand-prompt-bang-commands.py) | Runs inline `` `!cmd` `` and injects output |

### `stop/` — Stop

| Hook | What it does |
|---|---|
| [`00-agent-verify-work-complete.sh`](./stop/00-agent-verify-work-complete.sh) | Blocks a stop that claims "done" without verification / open PR with no handoff |
| [`verify-delivery-chain.py`](./stop/verify-delivery-chain.py) | Invoked by the Stop gate (not registered alone) |

### `notification/` — Notification

| Hook | What it does |
|---|---|
| [`06-attention-sentinel.sh`](./notification/06-attention-sentinel.sh) | Per-session attention state (also fires on Stop + UserPromptSubmit) |
| [`12-escalate-on-notification.sh`](./notification/12-escalate-on-notification.sh) | Escalation ladder when the agent needs the user |

### `post-tool-use/` — PostToolUse

| Hook | What it does |
|---|---|
| [`13-feed-forward.py`](./post-tool-use/13-feed-forward.py) | Forwards deliberate feed status posts to the owner's channel |

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
| `plan-presentation` | `plan-html-reminder` | PreToolUse (ExitPlanMode) |
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
- `enabled` — set `false` in the user layer to disable a system-shipped hook.
- `agents` — **deprecated**; ignored.

## Layering

System (`~/.agents/.system/agents.yaml`), extra repos, and user (`~/.agents/agents.yaml`)
merge with **user wins on key collision**. Same-named entry in the user repo replaces
the system entry wholesale; set `override: true` to silence the shadowing warning.

## Promptcuts

Type `#checkit` in a prompt and it expands into the full verification discipline.
`promptcuts.yaml` stays at **`hooks/promptcuts.yaml`** (not under an event dir) —
agents-cli and the expand-promptcuts hook resolve that fixed path.

- `~/.agents/.system/hooks/promptcuts.yaml` — system defaults
- `~/.agents/hooks/promptcuts.yaml` — your shortcuts; user keys win
