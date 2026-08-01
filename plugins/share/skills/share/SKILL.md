---
name: share
description: "Publish an agent-generated HTML artifact (a plan, viz, or report) to a shareable link on the user's own Cloudflare R2 (zero egress, ~$0) via `agents share`. Public links get an auto Open Graph cover (a screenshot of the page's hero) so they unfurl into preview cards in Slack/iMessage/Twitter/Discord; private links are unlisted + auto-expiring with no card. Use when an agent has produced HTML worth handing to a human, or when a plan/viz should outlive /tmp. Triggers on: 'share this', 'publish the plan', 'make a link', 'shareable link', 'send me the plan', 'og image / preview card for this'."
argument-hint: "[file | empty for the session's most recent HTML] [--private]"
allowed-tools: Bash(agents share*), Bash(agents secrets*), Read(*), Bash(ls*), Bash(curl *)
user-invocable: true
---

# share

Turn any HTML an agent made — a rendered plan, a data viz, a report — into a link a
human can open, backed by the user's **own** Cloudflare R2 (zero egress, effectively
$0). The page is stored in R2, so the link outlives the agent that made it.

## When to reach for this

- An agent rendered an HTML plan/viz/report and the user wants to *see* it or *send*
  it — don't leave it in `/tmp` where only this machine can open it.
- A `plan-render` / dashboard / infographic step just produced a file.
- The user says "share it", "make me a link", "publish this".

## One-time setup (per machine / per fleet)

`agents share` needs an endpoint first. Check with `agents share status`:

- **Empty** → the user must run **`agents share setup`** once (provisions an R2 bucket
  + a tiny Worker on their Cloudflare, read from their `cloudflare.com` secrets bundle;
  maps `share.<domain>` if the token owns the zone, else a free `*.workers.dev` URL), or
  **`agents share join <baseUrl>`** to publish through an existing endpoint with a shared
  write token. **Do not provision silently** — tell the user and stop if it's unset.
- **Configured** → just publish.

## Publishing

```bash
agents share plan.html                 # public link + auto OG cover
agents share plan.html --slug my-name  # stable, exact slug instead of the default
agents share plan.html --no-cover      # skip the preview image
agents share report.html --expire 7d   # auto-expire (30d / 12h / 2026-08-01 also work)
```

- **Default slug** is `<project>-<feature>-<hash>` (e.g. `agents-cli-fleet-cockpit-3a6687`):
  the repo name scopes the link, a random tail keeps it unguessable and collision-free.
- **OG cover**: HTML pages are screenshotted (their hero, 1200×630) and the shot is
  attached as `og:image` + `twitter:card`, so the link unfurls into a card. Capture is
  client-side (headless Chromium); if none is available the link still publishes, just
  without a card.

## Public vs private

- **Public** (`/share:public`, the default): a preview-card link meant to be posted.
  Permanent unless `--expire`. Anyone with the URL can read it — that's the point.
- **Private** (`/share:private`): `--no-cover --expire 7d` — unlisted, auto-expiring, no
  card. **Be honest**: this is *unlisted, not authenticated*. R2 reads are public, so
  anyone with the exact URL can still read it. Never call it encrypted or access-gated.
  True view-gating (a viewer token) is a future Worker enhancement.

## Cost

R2 has **zero egress** and a 10 GB free tier (~200k page-views of a 40 KB plan fit
free, served free even if one goes viral). Worker free tier = 100k req/day. For any
realistic personal/team use this is **$0**.

## Report back

Always print the link (and the `cover` URL when one was made). For a public share,
tell the user it will unfurl into a preview card where they paste it.
