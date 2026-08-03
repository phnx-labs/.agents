---
name: plan-render
description: "Render an implementation plan as a self-contained, review-grade HTML doc — a fixed house structure (hero, chips, TOC, Dither Kit charts where data is charted, hand-authored inline-SVG diagrams, callouts, tagged tables, code) skinned in the target product's brand (dark + light editorial fallback with an in-page toggle), then opened in the user's default browser on the machine they sit at. The canonical LOOK for plan mode, /plan Step 9, and /swarm:plan. Triggers on: render a plan, present a plan, plan-as-HTML, open the plan in the browser, plan mode, show the plan visually."
allowed-tools: Bash(scp*), Bash(agents ssh*), Bash(agents browser*), Bash(open*), Bash(xdg-open*), Bash(find*), Bash(cp*), Bash(mkdir*), Bash(test*), Bash(git rev-parse*), Write
user-invocable: true
---

# plan-render — plans as browser-ready HTML

A plan buried in terminal scrollback is hard to review. Render every implementation
plan as **one self-contained `.html`** (inline CSS, no CDN/framework — opens offline
by double-click) and open it in the user's default browser on the machine they sit at.
This is the single source of the plan LOOK; `/plan` Step 9 and `/swarm:plan` reference it.

Start from **`template.html`** (in this skill dir); **`example.html`** is the gold
reference (the remote-run bookkeeping plan).

## Where to write it

The render produces **one durable artifact** — the HTML. Pick its home once, up front:

- **Project-scoped plan** — if the repo you're working in has an **`.agents/` directory**
  (`ROOT=$(git rev-parse --show-toplevel 2>/dev/null)`; `test -d "$ROOT/.agents"`), write to
  `"$ROOT/.agents/plans/plan-<slug>.html"` (`mkdir -p "$ROOT/.agents/plans"` first). This
  keeps the plan **next to the code it describes** — durable, greppable, and the source the
  future download portal indexes. `.agents/` is scratch/artifact space (gitignored in these
  repos), so the file never lands on a branch.
- **No project / no `.agents/` dir** — fall back to `/tmp/plan-<slug>.html`.

Set `HTML` to that path; every step below refers to `$HTML`. The HTML is self-contained
(inline CSS, no CDN) so it opens offline by double-click **and** converts cleanly to PDF.

## Structure — fixed house layout

Every plan has, in order:

- **Hero** — `.kicker` (mono, uppercased, a label not a slogan: `PRODUCT · SUBSYSTEM · plan`),
  an `<h1>` that states plainly what the plan does, with the `.accent` span on its key noun;
  a ~3-line `.sub` problem statement, `.chip` metadata (files touched, new helpers,
  `status: awaiting go`), a **`.meta.prov` provenance chip row** (harness · agent · host ·
  session · date — see "Provenance" below), and a `.toc` of numbered sections.
- **Numbered `<h2>` sections** (`<span class="n">01</span>…`) — context/problem first,
  then design, then a files table, then edge cases / verification.
- **≥1 visual figure** in a `.fig` — use **Dither Kit** for quantitative charts, and a
  hand-authored inline `<svg>` for a timeline, an architecture sketch, or a before/after
  `.grid2` comparison. **Never mermaid.** A plan with zero figures is not done. When the
  figure depicts something the audience already has a standard notation for, **use that
  notation** instead of ad-hoc boxes (sequence diagrams for message ordering, crow's-foot
  for data models, C4 levels for architecture, ISO shapes for control flow). Add a
  **legend** whenever color or line-style carries meaning. See `diagram-conventions.md` (this
  skill dir) for the per-domain rules.
- **`.callout`** (and `.callout.warn`) for the load-bearing takeaway/caveat.
- **Tagged tables** — `.tag.a/.b/.c` pills (new / edit / keep) in the leftmost cell.
- **`<pre>`** code with `.c/.k/.s/.r` spans for the 1–2 key snippets.
- **`.foot`** — one mono line: the same provenance (harness · agent · host · session · date)
  repeated so it survives a scroll-to-bottom / print, ending `next: go / reshape`.

## Provenance — every plan says who made it, where

A rendered plan is a durable artifact that outlives the session. Without attribution it is
an orphan: you can't tell which agent produced it, on what box, or which session to reopen
to continue the work. So **every plan carries a provenance chip row in the hero** (`.meta.prov`)
and repeats the same line in the `.foot`. Fill all five from the session, at render time:

| Chip | Value | Where to get it |
| --- | --- | --- |
| `harness` | the agent CLI you are (`claude` / `codex` / `grok` / `droid` / …) | your own identity; also the `versions/<harness>/` segment of the session transcript path |
| `agent` | the model / profile (`opus-4.8`, `sonnet-4.6`, `gpt-5-codex`) | your model id, shortened (drop the `claude-` prefix and any `[1m]` suffix) |
| `host` | the machine this session runs on (`yosemite-s0`, `zion`) | `hostname -s`, or the **Host & Fleet** block injected at session start ("You are running on **<host>**") |
| `session` | the short session id (first segment of the UUID) | the **session id** printed in the SessionStart context; `echo "$SESSION_ID" \| cut -c1-8` if exported |
| date | the plan's render date (`YYYY-MM-DD`) | `currentDate` in the system prompt / `date +%F` |

Add a `session-label` chip too when the session has a human label (`agents sessions` shows it).
These are **not** placeholders to leave as `claude` / `yosemite-s0` — the template ships them
filled with example values; replace each with **this** session's real values before you present.

## Voice — precise and reviewable, not marketing

A plan is read by someone checking it against the code, not by a customer being sold to.
Write like an engineer drafting a design doc for a colleague who will push back on every claim.

- **The kicker is a label, not a slogan.** Use `PRODUCT · SUBSYSTEM · plan`, e.g.
  `agents-cli · credential subsystem · plan`. Never a tagline. A line like
  `EVERY CLAIM CARRIES THE COMMAND THAT PROVES IT` carries no information and is banned.
- **The headline states what the plan does, plainly.** The `.accent` span marks the
  load-bearing noun, not a punchline. "Reconcile the local task record against the remote
  exit code" beats "Self-healing bookkeeping".
- **Name the concrete thing:** the file, function, flag, number, or error string, not a
  vague stand-in ("things", "surfaces", "stuff", "various", "several"). The one exception is
  when the vague-sounding word is the real technical term (an "attack surface", a "control plane").
- **No marketing register.** Drop "Critically:" / "Notably:" drama, flattery ("you asked the
  sharp question"), and filler adjectives ("seamless", "powerful", "robust", "leverage",
  "simply", "just"). State the fact and let it stand.
- **At most one em-dash per paragraph; never stack appositive dashes** (`X — Y — Z`). A comma,
  colon, period, or parentheses reads cleaner and avoids the machine-written cadence that
  stacked dashes signal.

## Theme — match the product, don't impose one

Before rendering, **probe the target repo for its brand** and skin the plan in it by
editing only the two `:root` blocks (`--bg --panel --ink --dim --line --accent …`).
Fall through in order; first hit wins:

1. **Design tokens** — `design-system.css`, `theme.ts/css`, `tokens.json`, a `brand/` dir.
2. **Framework config** — `tailwind.config.*` theme colors, global CSS custom properties.
3. **Brand assets** — logo / favicon / `site.webmanifest` `theme_color`; sample the dominant hues.
4. **Live UI** — screenshots or a running app; eyedrop the palette.
5. **House fallback** — the dark + light editorial palette shipped in `template.html`,
   used **only** when the product declares no brand. Keep diagrams as dark blueprint cards.

Match the product's accent, surface, and ink; keep the house *structure* regardless.

## Light + dark, with a toggle

The house fallback ships **both** palettes and an in-page `◐` toggle (top-right) that
defaults to the OS `prefers-color-scheme` — so a user in bright light on a light-mode
machine gets the readable light theme automatically, and can flip either way. Keep the
toggle even when re-skinning to a brand that defines both light and dark tokens. The
light accent is darkened for AA contrast on a light surface (`--accent:#4d7c0f` in the
fallback); pick a similarly contrast-safe accent when theming.

## Deliver it — land a viewable copy on the machine the user sits at

The core rule: **the user must be able to open the plan on the machine in front of them.**
An HTML in `/tmp` on a headless Linux node is not viewable — most control-room viewing
happens on a Mac or Windows laptop. So always land a **PDF** (portable, opens everywhere,
what the download portal will track) in the **user's `~/Downloads`** on the machine they sit
at, and open the interactive HTML in their browser. Do this **proactively, every time**, so
an away user finds it waiting.

1. **Resolve the viewing machine.** First check the configured **interactive host**: the
   **Host & Fleet** context injected at session start (`hooks/07-inject-device-topology.sh`)
   names it when set ("The user sits at **\<name\>**"), or read it live —
   `agents devices list --json` → the row with `interactive: true`. When set, that is the
   delivery target, full stop. Only when unset, fall back to finding the **online macOS
   device** where the user sits (prefer online+direct; ask once only if genuinely ambiguous).
   **Never hardcode a host name.**

2. **Make the PDF + drop it in Downloads + open the HTML.** Run this block **on the viewing
   machine** — directly if you're already on it (`hostname` matches), else copy the HTML there
   first and run the same block via `agents ssh <host>` with `HTML` pointed at the copy:

   ```bash
   scp "$HTML" <host>:/tmp/plan-$SLUG.html        # remote case only; then set HTML=/tmp/plan-$SLUG.html in the block
   ```

   PDF is generated with the browser stack (`agents browser`, which drives the machine's
   installed Chromium-family browser via CDP `Page.printToPDF`):

   ```bash
   SLUG=<kebab-slug>          # the plan topic, kebab-cased — same <slug> used for $HTML above
   HTML=<$HTML>               # local: the path from "Where to write it". remote: /tmp/plan-$SLUG.html
   agents browser start --task plan-$SLUG >/dev/null 2>&1
   agents browser navigate --task plan-$SLUG --url "file://$HTML" >/dev/null
   sleep 1                                            # let the page finish rendering
   # NOTE: the [output] positional is ignored in current builds — capture the auto-saved path.
   PDF=$(agents browser pdf --task plan-$SLUG 2>&1 | grep -oE '/[^ ]+\.pdf' | tail -1)
   agents browser done --task plan-$SLUG >/dev/null 2>&1
   if [ -d "$HOME/Downloads" ]; then                  # true on Mac + most Linux desktops
     cp "$HTML" "$HOME/Downloads/plan-$SLUG.html"     # interactive, offline — always if Downloads exists
     [ -n "$PDF" ] && cp "$PDF" "$HOME/Downloads/plan-$SLUG.pdf"   # portable; skipped if the browser step produced none
   fi
   open "$HTML" 2>/dev/null || xdg-open "$HTML" 2>/dev/null   # default browser
   ```

3. Tell the user it opened in their browser and the PDF is in **Downloads**, with a 2–3 line
   summary and the paths.

**Graceful degradation** (never block the plan on any of these):
- **No `~/Downloads`** (headless Linux / VM): skip the copy — that's fine, say so.
- **No reachable browser** on the viewer (no Chromium-family browser installed, or a
  headless-only fleet): skip the PDF and the open — still write the durable `$HTML` and tell
  the user where it is and how to open it.

## Checklist before you present

- [ ] Self-contained HTML written to `$HTML` — `<repo>/.agents/plans/` if the project has an
      `.agents/` dir, else `/tmp` — opens offline.
- [ ] Skinned in the product's brand, or the house fallback if none.
- [ ] Provenance chip row filled with **this** session's real harness · agent · host · session · date
      (hero `.meta.prov` + repeated in `.foot`) — no leftover template example values.
- [ ] ≥1 visual figure: Dither Kit for quantitative charts, hand-authored inline SVG for
      non-chart diagrams; no mermaid, no CDN.
- [ ] Figures use the domain's standard notation; a legend where color or line-style encodes meaning.
- [ ] Voice is precise, not marketing: kicker is a label (no slogan), headline is factual, prose
      names concrete files/functions/numbers, no filler adjectives, ≤1 em-dash per paragraph.
- [ ] Light/dark toggle present, defaults to `prefers-color-scheme`.
- [ ] PDF + HTML copied to the viewer's `~/Downloads` (or degradation noted).
- [ ] HTML opened on the resolved online Mac's default browser (or headless noted).
