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
