# share plugin

Turn any agent-generated HTML — a plan, a viz, a report — into a shareable link in
one step, backed by **your own** Cloudflare R2 (zero egress, ~$0). Wraps the
`agents share` CLI.

## Commands

| Command | What it does |
| --- | --- |
| `/share:public <file>` | Publish a **public** link with an auto-generated OG cover (a screenshot of the page's hero), so it unfurls into a preview card in Slack / iMessage / Twitter/X / Discord. Default slug `<project>-<feature>-<hash>`; permanent unless `--expire` is passed. |
| `/share:private <file>` | Publish an **unlisted**, auto-expiring (`--expire 7d`) link with **no** preview card. Unguessable slug — but still public-read, not authenticated. |

Both resolve `<file>` from the argument, else the most recent HTML artifact of the
session, else they ask.

## Example

`/share:public plan.html` publishes the page and auto-generates a cover from its hero,
so the link unfurls into a card like this:

![Example OG preview card — a shared agents-cli plan](https://share.agents-cli.sh/agi-cli-agents-share-666643.png)

The cover is a 1200×630 screenshot of the page's own hero — no design step, no AI, ~$0.
Paste `https://share.agents-cli.sh/<slug>` into Slack / iMessage / Twitter/X / Discord
and it renders the card above.

## Requirements

- [`agents-cli`](https://github.com/phnx-labs/agents-cli) on `$PATH`.
- A one-time `agents share setup` (provisions an R2 bucket + a tiny Worker on your
  Cloudflare, read from your `cloudflare.com` secrets bundle) — or
  `agents share join <baseUrl>` to publish through an existing endpoint.
- For the public preview cover: a local headless-capable Chromium-family browser.
  Optional — without one, the link still publishes, just without a card.

## Public vs private

`public` is meant to be posted: it has a preview card and is permanent by default.
`private` is for discreet sharing: no card, auto-expires, unguessable slug. Note that
R2 reads are public, so anyone with the exact URL can view a "private" link — it's
unlisted, not access-controlled. True view-gating (a viewer token) is a future Worker
enhancement.
