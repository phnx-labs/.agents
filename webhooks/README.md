# Webhooks

Inbound webhook handlers. `agents webhook` runs a signed receiver on localhost that accepts
GitHub and Linear deliveries on `/hooks/<source>` and fires any matching
[routine](../routines/README.md).

**This directory is empty in the system layer.** Handlers are tied to your own repos,
trackers, and secrets, so they belong in your user layer at `~/.agents/webhooks/`. The slot
exists so the path resolves consistently across all four layers.

## Webhook, routine, or monitor?

| Fires on | Use |
|---|---|
| A clock — cron or a one-shot time | [routine](../routines/README.md) |
| A change you have to poll for | [monitor](../skills/monitors/SKILL.md) |
| A push from an external service | **webhook** |

Prefer a webhook over a polling monitor when the source can push. It is immediate and costs
nothing while idle.

## Running the receiver

```bash
agents webhook serve --secrets-bundle <name>
```

`--secrets-bundle` is required: it names the `agents secrets` bundle holding
`GITHUB_WEBHOOK_SECRET` and `LINEAR_WEBHOOK_SECRET`. Signing secrets go in the keychain,
never in a file here — this repo is designed to be safely version-controlled, so treat every
byte of it as public.
