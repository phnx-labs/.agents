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

Session, agent, host, runtime, and process identity resolve automatically from
the launch and activity indexes. Do not stop or ask the user because
`AGENT_SESSION_ID` is empty. If automatic resolution still fails, retry with the
documented escape hatch:

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
`--blocked` with `--level`; keep working on every unblocked part after filing it.
