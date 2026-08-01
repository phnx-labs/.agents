---
description: Fleet-wide token-burn + output report — runs `agents output` across every device, folds in relay-only machines, renders an HTML dashboard, drops a PDF in Downloads, and opens it in the browser
---

You are producing a **fleet-wide productivity + token-usage report**: $ARGUMENTS

Interpret `$ARGUMENTS` as the time window (e.g. `24h`, `7d`, `1mo`, or an ISO
date). Default to **24h** if none is given.

The engine is the built-in **`agents output`** command — a productivity rollup of
token burn vs shipped output (PRs, commits) across every agent (Claude, Codex,
Kimi, Rush, OpenClaw, …). Do NOT hand-roll transcript parsers; `agents output`
already scans the raw transcripts (not a stale index) on each machine.

## 1. Run the fleet rollup

```bash
agents output --since <WINDOW> --all-hosts --json > /tmp/out-fleet.json
```

`--all-hosts` folds in every online device from `agents devices` over SSH. Read
the JSON: `burn` (fleet totals), `breakdown.rows` (by agent), and `machines[]`
(per-machine, each with a possible `error`).

## 2. Double-check the machines that failed — the user WILL ask about these

`agents output --all-hosts` connects to each machine's **direct** address. LAN-only
boxes frequently time out (`ssh: connect to host 192.168.x.y ... timed out`) even
though `agents devices` lists them **online (relayed)**. Those are NOT zero — they
are *unmeasured*. Never report a total while any machine still shows an `error`.

For every machine with an `error`, re-query it over the relay and fold the result
in:

```bash
for h in <errored-hosts>; do
  ( agents ssh "$h" 'agents output --since <WINDOW> --json 2>/dev/null' > /tmp/out-$h.json ) &
done
wait
```

A relay result **supersedes** that machine's errored fleet entry. If a relayed box
is genuinely idle (0 sessions / 0 tokens), say so explicitly — that is a verified
zero, not a gap. Also sanity-check anomalies: a machine with commits but 0 sessions
(e.g. Windows) may store transcripts outside the scanned path — call it out.

## 3. Aggregate + report the numbers

Combine the fleet run (its non-errored machines + agent breakdown) with the relay
re-queries. Report, in plain language:

- **Total token count** (input + cache read/write + output — the cache-inflated
  number) AND **output tokens** (what was actually generated). Distinguish them —
  they differ by ~100x and conflating them is the #1 error here.
- **Estimated burn ($)** — priced for the costed agents only. Codex/Kimi tokens are
  counted but **uncosted** (no public price table); Rush/OpenClaw are dispatch
  layers with **no per-token accounting** (their real spend lands under the
  underlying Claude/Codex session). State these caveats — don't imply $0 = free.
- **By agent** and **by machine** breakdowns, largest first.
- **Sessions**, plus the shipped-output side `agents output` gives you (PRs opened/
  merged, commits) when relevant.

## 4. Render an HTML dashboard + PDF, then open it

The user wants to *see* this, not read a terminal dump. Follow the **`visualize`**
skill's house style: a self-contained HTML doc, brand-dark + light with an in-page
`◐` toggle defaulting to the OS scheme, stat cards for the headline numbers, a
by-machine bar chart, by-agent + all-machines tables, and a short **Method +
Caveats** footnote (how it was computed, which machines were relay-rechecked, the
uncosted/no-accounting agents).

Then:

```bash
cp report.html ~/Downloads/fleet-tokens-<WINDOW>.html
python3 -c "import weasyprint; weasyprint.HTML('report.html').write_pdf('$HOME/Downloads/fleet-tokens-<WINDOW>.pdf')"
open ~/Downloads/fleet-tokens-<WINDOW>.html   # macOS default browser (use the online mac in the fleet if remote)
```

`weasyprint` is the reliable local HTML→PDF path — Comet's headless
`--print-to-pdf` is disabled in the Perplexity fork, and the `agents browser` CDP
export needs a live debug-port browser that usually isn't running. If `weasyprint`
is absent, fall back to `pandoc` or a running Chromium's CDP `pdf`, but don't
rabbit-hole — the HTML is the primary artifact.

Report the on-disk paths (full paths, clickable) and confirm the browser opened.
