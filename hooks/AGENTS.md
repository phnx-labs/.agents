# hooks/ — maintenance contract

Humans start at [README.md](./README.md).

A hook runs on every agent, on every machine, on an event the user did not ask for. It is the
highest-blast-radius thing in this repo. A hook that throws, hangs, or writes to stdout at the
wrong moment corrupts the session it fires in.

## The script alone does nothing

Registration is the `hooks:` entry in [`../agents.yaml`](../agents.yaml). A script with no
entry is dead code that looks alive. Adding a hook is always two edits:

1. `hooks/<NN>-<name>.{sh,py}`, executable (`chmod +x`).
2. A `hooks:` entry in `../agents.yaml` naming the script, its `events`, and a `timeout`.

Then add a row to [`README.md`](./README.md) under the right event group, ship a
`<name>_test.sh` beside the script, and add a `CHANGELOG.md` entry.

The `NN-` prefix orders execution within an event. Guards take a low number; context
injection takes a middle number; anything that reads the result of another hook takes a
higher one.

## One script is present but never fires

`02-expand-prompt-skill-refs.py` has no entry in `../agents.yaml` and has **never** had
one — `git log -S` over the manifest returns zero commits. It is an unfinished feature,
not a regression. Register it or delete it; do not copy its patterns assuming it is live.

### How the other four got here — the failure mode to watch for

Four scripts sat unregistered for months because two unrelated bulk edits dropped their
entries as collateral, and nothing failed loudly:

| Commit | Subject | Dropped |
|---|---|---|
| `606db6e` (May 13) | "fix(hooks): handle missing YAML frontmatter in pre-commit validator" | `-27` lines from `agents.yaml`: `expand-promptcuts`, `expand-bang-commands`, `linear-tasks`, `stop-completion-gate` |
| `8b006a6` (Jun 24) | "chore: remove legacy agents hook config" | `-34` lines: `rm-guard` **and** `large-file-add-guard` |

In both cases a sibling was later restored — `stop-completion-gate` came back as
`verify-work-complete`, `rm-guard` was re-registered — while the others were forgotten.
All four have now been restored and verified working.

**The lesson: a hook has no failing test for "is it registered."** The script keeps
passing its own `_test.sh` while never running. When a commit touches `agents.yaml`, check
the entry count before and after — a diff that removes registrations under an unrelated
subject is the exact shape of this bug.

**`verify-delivery-chain.py` is the exception, and the reason to check twice.** It has no
`hooks:` entry either, but it **does** run on every Stop: `00-agent-verify-work-complete.sh`
pipes into it directly. "No manifest entry" means *not registered as a hook*, not *dead* —
a script another hook invokes is live.

The inverse trap is just as easy: `02-expand-prompt-bang-commands.py` **is** referenced,
but only by `02-expand-prompt-skill-refs.py`, which is itself unregistered. Referenced is
not reachable — follow the chain to a registered entry point or it is dead either way.

```bash
# every mention, minus tests and docs — then check whether the caller is itself registered
grep -rl <script-name> ../agents.yaml . | grep -vE '_test\.sh|README|AGENTS'
```

## Fail closed, never fail open

A guard that cannot evaluate its input must **refuse**, not allow. The `footer-guard`
regression is the reference case: it extracted the command with a single `jq` call and
`|| cmd=""`, then `[ -n "$cmd" ] || exit 0`, so on any machine without `jq` it silently
permitted exactly what it existed to block. Use the `_json_field` helper pattern
(`jq` → `node` → `python`) and exit non-zero with an explanation when no parser is available.

## Exit codes and streams

- `exit 0` — allow. Anything on stdout is injected into the model's context.
- `exit 2` — block, with the reason on stderr. That text is what the agent reads, so write it
  as an instruction, not an error dump.
- Never write to stdout from a `PreToolUse` guard on the allow path. It lands in the prompt.
- Background work must detach both stdout and stdin (`>/dev/null 2>&1 </dev/null &` on the
  **subshell**, not the inner command) or the hook hangs the session. Two separate fixes have
  landed for exactly this.

## Keep it fast

`timeout` is real and it runs on every matching event. Anything that touches the network or
another machine needs `cache:` or a background detach. A session-start hook that blocks for
five seconds costs five seconds on every session on every box.

## Tests are required

`<name>_test.sh` sits beside the script and must pass before the PR. Test the real path — no
mocking. For a guard, include a fixture proving it blocks the bad input **and** one proving
it fails closed with no JSON parser on `PATH`. For a detector, include the transcript that
produced a past false positive; three of the gates here regressed on exactly that.
