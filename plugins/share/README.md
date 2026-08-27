# share plugin

Turn any agent-generated HTML — a plan, a viz, a report — into a shareable link in
one step through the managed Phoenix share endpoint, or your own Cloudflare R2
(zero egress, ~$0) when BYO is configured. Wraps the
`agents artifacts share` CLI.

## Commands

| Command | What it does |
| --- | --- |
| `/share <file>` | Publish a **public** link with an auto-generated OG cover, so it unfurls into a preview card in Slack / iMessage / Twitter/X / Discord. Managed shares use a deterministic server-rendered card; BYO keeps the local hero screenshot fallback. Default slug `<project>-<feature>-<hash>`. |
| `/share --private <file>` | Same command, private modifier: an **unlisted**, auto-expiring (`--expire 7d`) link with **no** preview card (`--no-cover`). Unguessable slug — but still public-read, not authenticated. |

Both resolve `<file>` from the argument, else the most recent HTML artifact of the
session, else they ask. Shared steps live in the `share` skill; the command file
only invokes it.

`/share:public` and `/share:private` are gone — use `/share` and `/share --private`.

## Example

`/share plan.html` publishes the page and auto-generates a branded cover,
so the link unfurls into a card like this:

![Example OG preview card — a shared agents-cli plan](https://share.agents-cli.sh/agi-cli-agents-share-666643.png)

The managed cover is a deterministic 1200×630 card rendered lazily by the share
Worker and cached in R2 — no design step, browser binding, or publisher-side Chromium.
Paste `https://share.agents-cli.sh/<slug>` into Slack / iMessage / Twitter/X / Discord
and it renders the card above.

## Requirements

- [`agents-cli`](https://github.com/phnx-labs/agents-cli) on `$PATH`.
- A Phoenix sign-in (`agents auth login`) for the managed endpoint; alternatively,
  a one-time `agents artifacts setup` provisions your own R2 bucket + Worker — or
  `agents artifacts share join <baseUrl>` to publish through an existing endpoint.
- BYO-only preview fallback: a local headless-capable Chromium-family browser.
  Managed shares render the cover on the server and need no local browser.

## Public vs private

`/share` is meant to be posted: it has a preview card. `/share --private` is for
discreet sharing: no card (`--no-cover` so the link does not unfurl into a preview
card), auto-expires after 7 days (the Worker returns `410` afterwards). Note that
R2 reads are public, so anyone with the exact URL can view a "private" link — it's
unlisted, not access-controlled. True view restriction (a viewer token) is a future Worker
enhancement.
