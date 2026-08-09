# hooks/ — maintenance contract

Humans start at [README.md](./README.md).

A hook runs on every agent, on every machine, on an event the user did not ask for. It is the
highest-blast-radius thing in this repo. A hook that throws, hangs, or writes to stdout at the
wrong moment corrupts the session it fires in.

## Layout

```
hooks/<event-name>/<hook-file>.{sh,py}
```

| Event dir | Harness event |
|---|---|
| `session-start/` | SessionStart |
| `pre-tool-use/` | PreToolUse |
| `user-prompt-submit/` | UserPromptSubmit |
| `stop/` | Stop |
| `notification/` | Notification (and multi-event hooks whose primary event is Notification) |

- **Install name** = file **basename** (agents-cli flattens into version homes).
- **`script:` in agents.yaml** = path relative to `hooks/` (e.g. `session-start/04-session-identity.sh`).
- **Do not nest deeper** than one event dir.
- **Fixture-only dirs** under `hooks/` (e.g. `tests/` with no top-level scripts) are
  directory *bundles*, not event groups — leave them alone.
- **`hooks/lib/`** holds shared helpers sourced by hooks (e.g. `git-facts.sh`). Not
  event scripts: no `agents.yaml` entry, skipped by `registration_test.sh`. Source
  them by path; do not register them as hooks.
- **`promptcuts.yaml`** stays at `hooks/promptcuts.yaml` (hardcoded consumer paths).

## The script alone does nothing

Registration is the `hooks:` entry in [`../agents.yaml`](../agents.yaml). A script with no
entry is dead code that looks alive. Adding a hook is always two edits:

1. `hooks/<event-name>/<NN>-<name>.{sh,py}`, executable (`chmod +x`).
2. A `hooks:` entry in `../agents.yaml` with `script: <event-name>/<file>`, `events`, `timeout`.

Then add a row to [`README.md`](./README.md) under that event, ship a `<name>_test.sh`
beside the script, and add a `CHANGELOG.md` entry.

### Subrule hooks stay with the rule

Rule-enforcing guards ship under `rules/subrules/<rule>/` with a local `hooks.yaml`
(relative `script:` → absolute path at register time via `collectSubruleHooks`). They
are **not** moved into `hooks/<event>/`. Moving them would double-fire and desync from
the rule text. When you change a subrule guard, edit that subrule dir only.

## Execution order is NOT guaranteed — never depend on it

The `NN-` prefix is **cosmetic**. Registration order is YAML declaration order in
`../agents.yaml`. Claude runs matching hooks **concurrently**. A hook must be
independent: no reading another same-event hook's side effects. Ordered steps belong
in **one** script.

## `cache:` — the only instrumentation there is

A hook with a `cache:` entry is wrapped in a generated shim (timing + optional SWR).
Without `cache:`, the profiler cannot see it.

**Do not put `cache:` on a deny-capable PreToolUse guard.** The shim stores stdout and
always exits 0 on hit, so the first allow within the TTL would soft-allow every later
call — including after a branch switch onto the default branch. For git-derived facts
that guards share (repo root, current branch, origin/HEAD default, on-default), use the
shared short-TTL helper in `hooks/lib/git-facts.sh` instead: it re-validates HEAD on
every lookup so a switch invalidates immediately, and each guard still runs its own
allow/deny logic.

## Hook-owned session state

Programmable hooks own their logical state; agents-cli does not expose a generic
state command or interpret hook schemas. Use this layout consistently:

- Durable state: `~/.agents/.history/hooks/<stable-hook-id>/state.db`.
- Disposable state: `~/.agents/.cache/state/hooks/<stable-hook-id>/`.
- Stable hook ids are logical resource identities, never installed/version-home paths.
- Key session rows by harness + native `session_id`; record `AGENT_LAUNCH_ID` as
  a provisional alias and reconcile it when the native id arrives.
- Each hook owns its SQLite schema and transactional migrations. Use WAL, private
  permissions, a short busy timeout, bounded retention, and fail without exposing
  raw database errors to the harness.
- Never persist raw prompts, transcripts, commands, tool output, or credentials.

Do not add one generic database per hook invocation or put non-derivable hook state
only in `sessions.db`; that database is a rebuildable session index. A hook may have
one namespaced database per device when it genuinely needs durable state.

## One script is present but never fires

`user-prompt-submit/02-expand-prompt-skill-refs.py` has no entry in `../agents.yaml`
and has never had one. Allowlisted in `registration_test.sh`. Register it or delete it.

`stop/verify-delivery-chain.py` has no entry but **does** run: `stop/00-agent-verify-work-complete.sh`
pipes into it. "No manifest entry" ≠ dead when a registered script invokes it.

## Fail closed, never fail open

A guard that cannot evaluate its input must **refuse**, not allow. Use the
`_json_field` helper pattern (`jq` → `node` → `python`) and exit non-zero when no
parser is available.

## Exit codes and streams

- `exit 0` — allow. Anything on stdout is injected into the model's context.
- `exit 2` — block, with the reason on stderr.
- Never write to stdout from a `PreToolUse` guard on the allow path.

## SessionStart specifics

- Never hang, never Touch ID, never `agents secrets`.
- Prefer short timeouts; long work detaches (`setsid` + background) or uses `cache:`.
- Empty stdout unless you intentionally inject context.

## Registration integrity

`registration_test.sh` walks `hooks/*/*.{sh,py}` (event groups) and the top level.
`run_tests.sh` runs every `*_test.sh` under `hooks/` and one-level event dirs.
Run both before a PR that touches `hooks/`, `rules/subrules/`, or `agents.yaml`.

`syntax_test.sh` is the parse gate: a hook that does not parse still runs, and bash
exits 2 on a syntax error — which is the harness's *block* code, so a typo becomes a
gate no session can pass. It checks `.sh` under **`/bin/bash` (3.2 on macOS)** as well
as the PATH bash, because 3.2 tracks quotes inside a heredoc nested in a `$(…)` and
bash 5 does not: a quote in such a heredoc parses fine on Linux and breaks every Mac.
Keep quote characters out of heredoc bodies inside `$(…)` — spell them `\x27` / `\x22`.
