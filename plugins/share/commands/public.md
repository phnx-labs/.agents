---
description: Publish an HTML file (a plan, viz, or report) to a public shareable link with an unfurling preview card.
---

Publish `$ARGUMENTS` to a **public** link with `agents share`.

## Steps

1. **Resolve the file.** If `$ARGUMENTS` names a file, use it. If it's empty, pick the most recent HTML artifact this session produced (a rendered plan, a viz — often under `/tmp` or `~/Downloads`). If you can't confidently identify one, ask which file.
2. **Check setup.** Run `agents share status`. If it prints no endpoint, tell the user to run `agents share setup` once (provisions an R2 bucket + Worker on their own Cloudflare) — or `agents share join <baseUrl>` to use an existing endpoint — then stop. Do not try to provision silently.
3. **Publish.** Run `agents share <file>`. HTML pages get an auto-generated Open Graph cover (a 1200×630 screenshot of the page's hero). To pin a stable name pass `--slug <project>-<feature>`; otherwise the default `<project>-<feature>-<hash>` is used.
4. **Report** the printed link and its `cover` URL. Tell the user it will unfurl into a preview card in Slack, iMessage, Twitter/X, and Discord.

## Note

A public link is readable by anyone who has the URL (R2 reads are public — that's the point of a public share) and is permanent unless you pass `--expire`. For a discreet, auto-expiring, no-preview link, use `/share:private`.
