# secrets-guard

A PreToolUse hook on the `Bash` tool that blocks the secret-materializing
one-liners before they reach the shell (RUSH-2774): the plaintext bundle
export, the bundle-key `get`, and the non-TTY `view --reveal --plaintext`
escape.

## Why this hook exists

An agent's Bash tool output lands in the model's context and is persisted
verbatim to the session transcript, which syncs across the fleet. So any
command that prints a secret to stdout exfiltrates it — and agents ran
`eval "$(agents secrets export <bundle> --plaintext)"` reflexively, copying it
from scripts and docs (measured: 263 local transcripts carried the pattern
before the fix; the screenshot that triggered RUSH-2774 showed an agent
exporting `hetzner.com` just to run `crabbox list`).

Current agents-cli removes/refuses these surfaces in the CLI itself (spec
SEC-9/SEC-9b/SEC-9c in `apps/cli/docs/specifications.md`). This guard is the
**skew-immune backstop**: it fires on the agent's own tool call before any CLI
executes, so it also protects sessions on fleet boxes still running an older
installed agents-cli where the printers still work.

## What it denies

| Pattern | blocked_op |
|---|---|
| `agents secrets export <b> --plaintext` with no destination flag (any dressing: `eval "$( … )"`, `sh -c`, pipes, env prefixes, `ag`, absolute paths) | `secrets.export-plaintext` |
| `agents secrets get <bundle> <KEY>` (two non-flag args) | `secrets.get-bundle-key` |
| `agents secrets view … --reveal --plaintext` | `secrets.view-reveal-plaintext` |

## What it allows

The transfer modes (`export --device/--to-1password/--to-file`), the injection
path (`secrets exec … -- …`, including `printenv` captures — deliberate
composition the value-free audit stream records), the raw-item `get <item>`
(the current CLI's own agent-context check owns that case), masked `view`, bare
`view --reveal` (the CLI's TTY check owns it), and prose/`echo`/`grep` that
merely mentions the commands — the check is token-precise per command segment,
not a substring match.

## Mechanics

Same harness as `rm-guard.sh`/`git-guard.sh`: fast substring pre-filter,
jq→node→python JSON extraction that **fails closed** when no parser exists,
chain-operator segmentation, `sh -c` unwrap, plus one level of `$(...)`
substitution unwrap (the eval-export idiom hides the real command inside a
substitution). Denials use the structured `blocked_op` / `reason` /
`do_this_instead` shape (RUSH-2295), steering to
`agents secrets exec <bundle> -- <cmd>`.

Limitations (same class as the sibling guards, out of scope): base64, `xargs`,
computed strings, deeper substitution nesting. The CLI-side refusals are the
layer that holds regardless of how the argv was assembled.

Tests: `tests/secrets-guard_test.sh` (20 cases, hermetic).
