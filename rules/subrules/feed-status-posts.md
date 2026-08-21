# Record Progress and Deliver Only Deliberate Updates

Use the feed to record milestones without turning every progress update into a
phone notification:

```bash
agents feed post --title "<short subject>" "<one human line — what happened>"
```

A plain post is **record-only**. The owner's configured `minLevel: important`
keeps ordinary milestones in the activity stream without delivering them to the
phone. When a successful update is genuinely phone-worthy, mark that same post
important:

```bash
agents feed post --title "Deploy verified" "PR #149 is live" --level important
```

This preserves one event in one stream: `--level important` records the update
and makes it eligible for owner delivery. Use it sparingly for completed work or
another successful boundary the owner needs to see while away. Do not use it for
routine edits, test runs, or synchronous work the user is watching.

## Teams

Teams are the easiest way to flood the phone, so the boundaries are strict. Only
two milestones matter for owner delivery:

1. **Team spawned** — one plain post on `agents teams start` ("spawned team
   `<name>` — N teammates on `<tickets>`"). Record-only; do not `--level important`.
2. **A teammate/agent finished & delivered** — its PR merged, or the composed
   cross-track work runs end-to-end. This is genuinely phone-worthy: mark it
   `--level important` (or `agents notify` the owner). A **blocked** teammate is the
   other delivery-worthy event — use `--blocked`.

Everything between those — each edit, each test run, each PR opened — is
record-vs-deliver: a plain `agents feed post` at most, never a phone notification.
Both the `/teams` playbook and [`parallel-teams.md`](parallel-teams.md) instruct
every teammate brief to follow this split, so N teammates don't become N×steps of
phone spam.

Session, agent, host, runtime, and process identity resolve automatically from
the launch and activity indexes. Do not stop or ask the user because
`AGENT_SESSION_ID` is empty. If automatic resolution still fails (orchestrator
shells outside `agents run`), retry with the documented escape hatch —
`--title` and the body are both required:

```bash
agents feed post --title "<short subject>" "<update>" --session <session-id>
```

`--blocked` is not a louder success level. Use it only after exhausting
self-serve options when work genuinely needs a human decision, credential, or
physical action:

```bash
agents feed post --title "Signing blocked" "Production needs your biometric" --blocked
```

Blocked posts open a needs-you record and deliver fail-loud. Never combine
`--blocked` with `--level`; keep working on every unblocked part after filing
it. `--option` records answers the user can pick; `--default` names a safe
fallback so work can resume without an answer. Front-load the ask — a phone
notification truncates after about two lines, so lead with the decision, not
the backstory.
