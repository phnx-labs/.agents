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

## What runs, and when

**At session start** — these live under [`session-starts/`](./session-starts/) and
build the context an agent wakes up with. agents-cli discovers one-level group
dirs (`hooks/<group>/<script>`); install names stay the file basename.

| Hook | What it does |
|---|---|
| [`session-starts/04-session-identity.sh`](./session-starts/04-session-identity.sh) | The single "who am I" hook — session id, transcript path, runtime |
| [`session-starts/03-linear-inject-tasks-context.sh`](./session-starts/03-linear-inject-tasks-context.sh) | Injects a Linear brief and the active-sprint board. Reads credentials from `~/.linear-cli/config.json` (env vars win); skips silently when absent |
| [`session-starts/07-inject-device-topology.sh`](./session-starts/07-inject-device-topology.sh) | Injects the host and fleet topology, with live load and memory per machine |
| [`session-starts/08-inject-repo-inflight.sh`](./session-starts/08-inject-repo-inflight.sh) | Injects the repo's in-flight state — open PRs and the other agents actively working on this project (activity-ranked, capped), resolving worktrees to their main repo |
| [`session-starts/05-session-start-autosync.sh`](./session-starts/05-session-start-autosync.sh) | Brings the machine current — config repos, secrets, sessions |
| [`session-starts/09-git-pull-forward.sh`](./session-starts/09-git-pull-forward.sh) | Fast-forwards the session cwd git repo when the tree is clean (ff-only; never force/rebase/autostash) |

**Before a tool call** — these block, nudge, or enrich.

| Hook | What it does |
|---|---|
| [`git-guard.sh`](./git-guard.sh) | Blocks the destructive git operations: `reset --hard`, force-push, `checkout -- .`, `stash`, `clean`, history rewrites |
| [`rm-guard.sh`](./rm-guard.sh) | Blocks destructive `rm` patterns |
| [`large-file-add-guard.sh`](./large-file-add-guard.sh) | Blocks `git add` of a file over 5 MiB — bypass with `LARGE_FILE_GUARD_MAX_KB=0` |
| [`02-expand-prompt-user-shortcuts.sh`](./02-expand-prompt-user-shortcuts.sh) | Expands `#shortcut` tokens from `promptcuts.yaml` into the prompt |
| [`02-expand-prompt-bang-commands.py`](./02-expand-prompt-bang-commands.py) | Runs inline `` `!cmd` `` and injects the output into the prompt |
| [`01-git-require-clean-tree.sh`](./01-git-require-clean-tree.sh) | Blocks `git pull` / `rebase` / autostash while the working tree is dirty |
| [`09-mailbox-inject.py`](./09-mailbox-inject.py) | Delivers queued messages into a running session |
| [`10-mq-read-nudge.py`](./10-mq-read-nudge.py) | On a large whole-file `Read`, suggests mapping it with `mq` and extracting one section |

**On stop or notification** — these decide whether the agent is really done.

| Hook | What it does |
|---|---|
| [`00-agent-verify-work-complete.sh`](./00-agent-verify-work-complete.sh) | Blocks a stop that claims "done" without verification, an open PR with no handoff, or a hand-back to the user |
| [`06-attention-sentinel.sh`](./06-attention-sentinel.sh) | Maintains a per-session attention state across notification, stop, and prompt |
| [`12-escalate-on-notification.sh`](./12-escalate-on-notification.sh) | On a "needs the user" notification, climbs the escalation ladder to reach the owner |
| [`13-feed-forward.py`](./13-feed-forward.py) | Forwards deliberate feed status posts to the owner's phone |

Guard hooks that belong to a rule ship with that rule, not here — see
[`rules/subrules/*/hooks.yaml`](../rules/subrules/) for `gh-merge-guard`, `no-pr-footer`,
`plan-presentation`, and `truly-agentic-git-workflow`.

## Manifest schema (the `hooks:` section of `../agents.yaml`)

```yaml
hooks:
  my-hook:
    script: 02-my-hook.sh
    events: [UserPromptSubmit]
    timeout: 5
    matches:               # optional pre-filters; AND together
      prompt_contains: "#"
    enabled: true          # default; set false to disable a system hook from the user side
```

- `script` — path relative to this directory.
- `events` — lifecycle events to register on.
- `timeout` — seconds.
- `matches` — `prompt_contains`, `prompt_matches`, `tool_name`, `tool_args_match`,
  `cwd_includes`, `project_has`, `git_dirty`. All AND together. Empty or missing means always.
- `enabled` — set `false` in the user layer (`~/.agents/agents.yaml`) to disable a
  system-shipped hook.
- `agents` — **deprecated**. The agent capability table decides which agents register a hook;
  the field is parsed for back-compat and ignored.

## Layering

System (`~/.agents/.system/agents.yaml`), extra repos, and user (`~/.agents/agents.yaml`)
merge with **user wins on key collision** — resolution order is user > extra > system. A
same-named entry in the user repo replaces the system entry wholesale; set `override: true`
there to silence the shadowing warning.

## Promptcuts

Type `#checkit` in a prompt and it expands into the full verification discipline;
`` `!date` `` runs the command and injects its output. `promptcuts.yaml` is the data,
layered the same way as everything else:

- `~/.agents/.system/hooks/promptcuts.yaml` — system-shipped defaults (`#checkit`, `#rethink`, …)
- `~/.agents/hooks/promptcuts.yaml` — your shortcuts; user keys win

## Look here when

- a `#shortcut` did not expand, or a `` `!cmd` `` bang command did not run
- an agent refuses to stop, or stops when it should not
- a git command was blocked and you want to know which guard did it
- agent behavior feels customized in a way that is not obvious

The scripts here are the implementations. The `hooks:` section of `../agents.yaml` shows what
is wired to which event. The installed agent config (`~/.claude/settings.json`) shows what is
active right now — `agents inspect hooks` reads it for you.

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
