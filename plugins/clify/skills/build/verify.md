# Stage 4 — Verify (the gate)

This is the stage that makes clify trustworthy. **No command ships until it has hit the real service
and returned a real, well-shaped response.** This is core-hard-lines #1 baked into the tool.

## The gate

For **every** generated command:

1. Run it against the **real** service through the installed/linked CLI, with credentials injected from
   the secrets bundle:
   ```bash
   agents secrets exec clify.<slug> -- clify-<slug> <resource> <command> <safe-args>
   ```
   Prefer read-only / idempotent commands and the smallest scope (`--limit 1`) for the probe. For
   mutating commands (POST/DELETE), verify against a sandbox/test resource when the API offers one; if
   it doesn't, mark the command **verified-signature-only** (args + auth + URL resolve, not executed)
   rather than firing a real mutation — and say so in the report.

2. Classify the result:
   - **Green** — a real response with the expected shape (status 2xx, body matches the inferred type).
     The command ships.
   - **Quarantined** — 401/403 (auth wrong), 404 (endpoint wrong — likely a bad rung-3/4 guess), 5xx,
     timeout, or a body that doesn't match the inferred schema. The command **does not ship**.

3. For quarantined commands, do one repair pass at the source: re-check the endpoint against its rung
   (fix the path/param/auth), regenerate, re-verify. If it still fails, drop it from the CLI.

## Output — the build report

Emit a report (and print a summary):

```
clify build <slug> — verification
  shipped:      12 commands  (rung1: 9, rung2: 2, rung3: 1)
  quarantined:   3 commands
    - reports.export    404 at rung3 — endpoint not seen in captured traffic; dropped
    - charges.refund    POST, no sandbox — verified-signature-only, hidden behind --unsafe
    - webhooks.list     401 — token lacks scope; needs a broader key
```

The shipped CLI contains only green commands. Quarantined ones are documented, never silently included.

## Done-gate for the whole build

Stage 5 isn't "the package builds." It is: **install the CLI globally, run one green command through
the installed binary, and quote the real output.** Until you've done that and pasted real output, the
build is not done (not "npm pack succeeded", not "tsc is clean").
