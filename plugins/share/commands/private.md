---
description: Publish an HTML file as an unlisted, auto-expiring link with no preview card (discreet sharing).
---

Publish `$ARGUMENTS` as a **private / unlisted** link with `agents share`.

## Steps

1. **Resolve the file** (same as `/share:public` — named file, else the most recent HTML artifact, else ask).
2. **Check setup.** Run `agents share status`. If unset, tell the user to run `agents share setup` (or `agents share join <baseUrl>`) first, then stop.
3. **Publish discreetly.** Run `agents share <file> --no-cover --expire 7d`.
   - `--no-cover` — no OG image, so the link does **not** unfurl into a preview card and won't be pulled into a rich embed.
   - `--expire 7d` — auto-expires after a week (offer a different window if the user wants; the Worker returns `410` and deletes the object past expiry).
4. **Report** the link and when it expires.

## Honesty (important — do not overstate privacy)

This is **unlisted**, not **authenticated**. The slug is unguessable and the link won't unfurl or get auto-indexed, but **anyone who has the exact URL can still read it** — R2 reads are public. Never describe it as encrypted or access-controlled. If the user needs true view-gating (a viewer token / password), say that's a future Worker enhancement, not something this command provides today.
