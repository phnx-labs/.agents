---
name: share
description: "Publish an agent-generated HTML artifact (a plan, viz, or report) to a shareable link on the user's own Cloudflare R2 (zero egress, ~$0) via `agents artifacts share`. Public (the default) gets an auto Open Graph cover so the link unfurls into a preview card in Slack/iMessage/Twitter/Discord; pass --private for an unlisted auto-expiring link with no card. Use when an agent has produced HTML worth handing to a human, or when a plan/viz should outlive /tmp. Triggers on: 'share this', 'publish the plan', 'make a link', 'shareable link', 'send me the plan', 'og image / preview card for this', '/share --private'."
argument-hint: "[file | empty for the session's most recent HTML] [--private]"
allowed-tools: Bash(agents artifacts share*), Bash(agents secrets*), Read(*), Bash(ls*), Bash(curl *)
user-invocable: true
---

# share

Turn any HTML an agent made — a rendered plan, a data viz, a report — into a link a
human can open through the managed Phoenix share endpoint, or the user's own
Cloudflare R2 when BYO is configured. The page outlives the agent that made it.

`/share` is the one command. Public is the default; `--private` is a modifier.

## When to reach for this

- An agent rendered an HTML plan/viz/report and the user wants to *see* it or *send*
  it — don't leave it in `/tmp` where only this machine can open it.
- An `artifacts` / dashboard / infographic step just produced a file.
- The user says "share it", "make me a link", "publish this".

## Steps

1. **Resolve the file.** Strip `--private` from `$ARGUMENTS` if present (it is a
   mode flag, not a path). If a file remains, use it. If the args are empty, pick
   the most recent HTML artifact this session produced (a rendered plan, a viz —
   often under `/tmp` or `~/Downloads`). If you can't confidently identify one, ask
   which file.
2. **Check setup.** Run `agents artifacts share status`. If it prints no endpoint,
   tell the user to run `agents artifacts setup` once (provisions an R2 bucket +
   Worker on their own Cloudflare) — or `agents artifacts share join <baseUrl>` to
   use an existing endpoint — then stop. Do not try to provision silently.
3. **Publish.**
   - **Public** (default): `agents artifacts share <file>`
     HTML pages get an auto-generated Open Graph cover. The managed Worker lazily
     renders and caches a deterministic 1200×630 branded card; BYO endpoints keep
     the local hero-screenshot fallback. As an optional override, pass `--slug <project>-<feature>`
     to pin a stable name;
     otherwise the default `<project>-<feature>-<hash>` is used.
   - **Private** (`/share --private <file>`): `agents artifacts share <file> --no-cover --expire 7d`
     - `--no-cover` — no OG image, so the link does **not** unfurl into a preview
       card and won't be pulled into a rich embed.
     - `--expire 7d` — auto-expires after a week (offer a different window if the
       user wants; the Worker returns `410` and deletes the object past expiry).
     Do **not** pass the CLI's `--private` flag for this mode. On
     `agents artifacts share`, `--private` is an alias of `--unlisted` (hides the
     page from the public gallery and `agents artifacts share list`); it does not
     skip the cover or set 7-day expiry. Slash-command private mode is the two
     flags above.
4. **Report** the printed link. Public: also the `cover` URL, and tell the user it
   will unfurl into a preview card in Slack, iMessage, Twitter/X, and Discord.
   Private: say when it expires.

## One-time setup (per machine / per fleet)

`agents artifacts share` needs an endpoint first. Check with `agents artifacts share status`:

- **Empty** → the user must run **`agents artifacts setup`** once (provisions an R2 bucket
  + a tiny Worker on their Cloudflare, read from their `cloudflare.com` secrets bundle;
  maps `share.<domain>` if the token owns the zone, else a free `*.workers.dev` URL), or
  **`agents artifacts share join <baseUrl>`** to publish through an existing endpoint with a shared
  write token. **Do not provision silently** — tell the user and stop if it's unset.
- **Configured** → just publish.

## Publishing

```bash
agents artifacts share plan.html                 # public link + auto OG cover
agents artifacts share plan.html --slug my-name  # optional stable-name override
agents artifacts share plan.html --no-cover      # skip the preview image
agents artifacts share report.html --expire 7d   # auto-expire (30d / 12h / 2026-08-01 / never also work)
```

- **Default slug** is `<project>-<feature>-<hash>` (e.g. `agents-cli-fleet-cockpit-3a6687`):
  the repo name scopes the link, a random tail keeps it unguessable and collision-free.
- **OG cover**: managed HTML shares attach `og:image` + `twitter:card` to a lazy
  `<slug>.png` route. The Worker renders the title, description, handle, and
  visibility with bundled fonts, applies the page's visibility gate, then caches
  the PNG. No local browser is required. BYO endpoints retain client-side
  headless-Chromium capture because their Worker may predate the renderer.
- **Expiry**: the CLI default is `30d` (`--expire <spec>`). Pass `--expire never` for a
  permanent link. Private mode always passes `--expire 7d`.

## Public vs private

- **Public** (`/share`, the default): a preview-card link meant to be posted.
  Anyone with the URL can read it — that's the point.
- **Private** (`/share --private`): `--no-cover --expire 7d` — unlisted, auto-expiring,
  no card. **Be honest**: this is *unlisted, not authenticated*. R2 reads are public, so
  anyone with the exact URL can still read it. Never call it encrypted or access-restricted.
  True view restriction (a viewer token) is a future Worker enhancement.

## Cost

R2 has **zero egress** and a 10 GB free tier (~200k page-views of a 40 KB plan fit
free, served free even if one goes viral). Worker free tier = 100k req/day. For any
realistic personal/team use this is **$0**.
