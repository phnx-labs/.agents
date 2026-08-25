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
- **Do not nest deeper** than one event dir (the `tests/` subdir below is the one
  standing exception, and it never carries a `script:` entry of its own).
- **A hook's `*_test.sh` lives in a `tests/` subdir of its own event dir** —
  `hooks/<event-name>/tests/<name>_test.sh`, not beside the script. This keeps
  `ls hooks/<event-name>/` down to the scripts that actually run on the harness
  event, so the registered surface is visible at a glance instead of interleaved
  with its tests. `hooks/lib/` follows the same convention for its own helper
  tests (`hooks/lib/tests/git-facts_test.sh`).
  - **Path-reference rule:** a moved test resolves its own dir with
    `HERE="$(cd "$(dirname "$0")" && pwd)"` as before, but every reference to the
    script under test — and any sibling helper it also calls (e.g.
    `stop/00-agent-verify-work-complete_test.sh` reaching `stop/todo-progress.py`)
    — now needs one extra `../`: `HOOK="$HERE/../<script>.sh"`, not
    `HOOK="$HERE/<script>.sh"`. A reference to something outside `hooks/<event>/`
    (e.g. `../../../agents.yaml` from a `tests/` subdir, one level deeper than the
    `../../agents.yaml` an event-dir-level script would use) needs an extra `../`
    too. Fixtures/testdata that a test owns move into the same `tests/` dir.
  - `hooks/run_tests.sh` discovers tests in both the current `<event>/tests/`
    location and the legacy beside-the-script location, so nothing is silently
    skipped mid-migration. `hooks/syntax_test.sh` parses `.sh`/`.py` under
    `<event>/tests/` too. `hooks/registration_test.sh` needs no change: its
    group-dir scan is one level deep (`hooks/<event>/*.sh`), so it never
    descends into `hooks/<event>/tests/` at all — a moved `_test.sh` is simply
    outside its scan, the same net effect as the case-statement skip it used
    when tests sat beside the script.
- **Fixture-only dirs** under `hooks/` (e.g. the top-level `hooks/tests/` with
  benchmark/integration scripts that cover more than one event, and no
  top-level hook scripts of its own) are directory *bundles*, not event groups
  — leave them alone. This is a different thing from the per-event
  `hooks/<event-name>/tests/` above: the top-level one is cross-cutting infra,
  the per-event ones hold that event's own hook tests.
- **`hooks/lib/`** holds shared helpers sourced by hooks: `json-field.sh` (the JSON
  field extractor), `git-facts.sh` (HEAD-validated git-fact cache), and
  `git-parse.sh` (the git-command parser — `sh -c` unwrapping, chain splitting,
  env/quote stripping, global-flag peeling — shared by `git-guard`,
  `large-file-add-guard`, and `main-branch-guard`, which supply their own
  `git_on_command` policy callback). Not event scripts: no `agents.yaml` entry,
  skipped by `registration_test.sh`. Source them by path; do not register them as
  hooks.
- **`promptcuts.yaml`** stays at `hooks/promptcuts.yaml` (hardcoded consumer paths).

## The script alone does nothing

Registration is the `hooks:` entry in [`../agents.yaml`](../agents.yaml). A script with no
entry is dead code that looks alive. Adding a hook is always two edits:

1. `hooks/<event-name>/<NN>-<name>.{sh,py}`, executable (`chmod +x`).
2. A `hooks:` entry in `../agents.yaml` with `script: <event-name>/<file>`, `events`, `timeout`.

Then add a row to [`README.md`](./README.md) under that event, ship a
`<name>_test.sh` in that event dir's `tests/` subdir
(`hooks/<event-name>/tests/<name>_test.sh` — see the layout note above), and add
a `CHANGELOG.md` entry.

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
- Record a transcript byte offset with each goal boundary, then derive evidence
  only from that goal's suffix. Keep session-owned entities in a separate ledger
  so responsibility survives follow-up prompts without making old activity look
  like evidence for the new goal.
- Record check outcomes as compact structured events (check + outcome + reason),
  not copied hook messages. This makes effectiveness measurable without retaining
  conversation content.

Do not add one generic database per hook invocation or put non-derivable hook state
only in `sessions.db`; that database is a rebuildable session index. A hook may have
one namespaced database per device when it genuinely needs durable state.

## Scripts that are present but never fire

`user-prompt-submit/02-expand-prompt-skill-refs.py` has no entry in `../agents.yaml`
and has never had one. Allowlisted in `registration_test.sh`. Register it or delete it.

`stop/check-outcome-backfill.py` has no entry **by design** — it is offline analysis of
check telemetry that was already recorded, not an event handler, so putting it on a hook
path would make every Stop pay for a whole-corpus scan. Allowlisted in
`registration_test.sh`. Run it by hand. Do not register it.

`stop/verify-delivery-chain.py` has no entry but **does** run: `stop/00-agent-verify-work-complete.sh`
pipes into it. "No manifest entry" ≠ dead when a registered script invokes it.

## Fail closed, never fail open

A guard that cannot evaluate its input must **refuse**, not allow. Source the
shared `_json_field` extractor from `hooks/lib/json-field.sh` (`jq` → `node` →
`python`; returns 1 when no parser exists or the payload is malformed), then verify the function is
defined after the source and `exit 2` if it is not — a guard that cannot even
load its parser must fail closed, not run unchecked. Advisory (non-blocking)
hooks may fail open (`exit 0`) instead. Use `${0%/*}` (not `dirname`) to locate
the lib so the source works under a stripped PATH; fall back to the absolute
`${HOME}/.agents/.system/hooks/lib/json-field.sh`.

The same source-then-verify contract governs `hooks/lib/git-parse.sh`: a guard
that inspects a git command string sources it (verifying `git_scan_segment` is
defined) and `exit 2`s if the lib is unreachable — a guard that cannot parse a
git command must refuse, not wave it through. `git-parse-sourcing_test.sh` pins
this for all three consumers.

## Exit codes and streams

- `exit 0` — allow. Anything on stdout is injected into the model's context.
- `exit 2` — block, with the reason on stderr.
- Never write to stdout from a `PreToolUse` guard on the allow path.

## SessionStart specifics

- Never hang, never Touch ID, never `agents secrets`.
- Prefer short timeouts; long work detaches (`setsid` + background) or uses `cache:`.
- Empty stdout unless you intentionally inject context.

## Registration integrity

`registration_test.sh` walks `hooks/*/*.{sh,py}` (event groups) and the top level —
one level deep, so it never descends into an event dir's `tests/` subdir.
`run_tests.sh` runs every `*_test.sh` under `hooks/` root, one-level event dirs, and
each event dir's `tests/` subdir (`hooks/<event>/tests/*_test.sh`). Run both before a
PR that touches `hooks/`, `rules/subrules/`, or `agents.yaml`.

`syntax_test.sh` is the parse check: a hook that does not parse still runs, and bash
exits 2 on a syntax error — which is the harness's *block* code, so a typo becomes a
block no session can get past. It checks `.sh` under **`/bin/bash` (3.2 on macOS)** as well
as the PATH bash, because 3.2 tracks quotes inside a heredoc nested in a `$(…)` and
bash 5 does not: a quote in such a heredoc parses fine on Linux and breaks every Mac.
Keep quote characters out of heredoc bodies inside `$(…)` — spell them `\x27` / `\x22`.

The `plan-presentation` subrule's reminder is documented by the consolidated
`skills/artifacts/SKILL.md`. Keep its PreToolUse/ExitPlanMode and Stop registrations
unchanged when editing artifact authoring guidance; skill consolidation must not
change when the guard fires.
