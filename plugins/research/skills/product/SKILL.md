---
name: product
description: "Explore a PRODUCT hands-on and prove every claim visually — don't just read about it. Install or sign up, DRIVE the real product through each user journey, screenshot every meaningful step, record a short clip of the headline flows, then put landing-page CLAIMS next to what the product ACTUALLY did. Produces a highly-visual artifact: favicon/logo-tagged product cards, per-journey flow diagrams, screenshot strips, an embedded clip, and a claims-vs-reality table — never one idle screenshot and a wall of text. Composes research:research for the public intel, browser + secrets to drive the surface, and artifacts to render. Triggers on: /research:product, 'explore <product> hands-on', 'how does <product> actually work', 'test out <product> and show me', 'does <product> really do X', 'walk through <product>'s features', 'compare these products by actually using them', 'evaluate <product>'s user flows'."
argument-hint: "<product(s) + what to explore — e.g. 'how Devin supports background agents', 'evaluate Harvey's document-review flow', 'compare v0 vs bolt.new by using both'> [--compare a,b,c] [--depth quick|standard|deep] [--record on|off] [--signup ask|auto|creds-only]"
allowed-tools: Bash(agents *), Bash(git *), Bash(gh *), Bash(linear *), Bash(rg *), Bash(ls *), Bash(cat *), Bash(jq *), Bash(curl *), Bash(scp *), Read(*), Write(*), Edit(*), Task(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# research:product — use the product, then show it working

You were asked to research a **product**. The failure mode this skill exists to kill is the
report that *read about* the product — a page of accurate prose, one screenshot of an idle
landing page, and a feature list nobody watched run. That doc proves nothing. A product is
verified by **driving it**: you sign in, you click through the real journeys, you capture
each step, you record the headline flow, and you put what the marketing *said* next to what
the product *did*. Humans read visually — so the output leads with the product working, not
with paragraphs.

Product / question: `$ARGUMENTS`.

| This skill | Not this skill |
|---|---|
| **Drive** the product, capture the journey, prove claims visually | `research:research` — answer a text question across engines |
| Signs up, clicks through real user flows, screenshots every step, records a clip | `demo` — prove **your own** shipped thing, before/after |
| Output: journey diagrams + screenshot strips + a clip + a claims-vs-reality table | `browser` alone — one tab, by hand, no synthesis |

## The two bars you may never skip

1. **Every feature you report is SHOWN being used** — a screenshot of it mid-flow, or a clip.
   A feature you only read in the docs is a **claim**, labeled as such, never stated as
   observed. If you couldn't drive it (paywall, version gate), say so — don't launder a doc
   line into a demonstrated fact.
2. **The journey is captured, not summarized.** A step you took but didn't screenshot didn't
   happen, as far as the report is concerned. One idle-landing-page screenshot is the exact
   defect this skill replaces.

## 1. Frame — the product, the journeys, the visual identity

- **Name the target(s)** and the **specific question** (a product is explored *for* something:
  "how does Devin support background agents", not "look at Devin"). `--compare a,b,c` explores a
  set on the **same journeys** for a fair matrix; default is **one product, deep**.
- **List the real user journeys** you'll walk — the 3–6 flows a real user actually does
  (onboard → first result; the core loop; the differentiated feature; the pricing/limits wall).
  These become the report's spine and each gets its own diagram + strip.
- **Grab the visual identity up front.** Fetch each product's **favicon/logo** and embed it as a
  base64 `data:` URI so every product card and table row is tagged with its mark (self-contained —
  no CDN; see the `artifacts`/`design` no-external-asset rule):
  ```bash
  curl -sL "https://www.google.com/s2/favicons?domain=<domain>&sz=128" -o /tmp/<slug>.png   # or the site's /favicon.ico, or the logo from its press/brand page
  base64 -w0 /tmp/<slug>.png     # → data:image/png;base64,… inline in the artifact
  ```
- Pick `--depth`: `quick` (one product, top journey + claims), `standard` (default: all journeys,
  clip on the headline flow), `deep` (every journey clipped, pricing/limits probed, edge cases).

## 2. Get the public picture first — compose `research:research`

Before you drive anything, know what to verify. Run the multi-engine sweep (`research:research`)
to pull the **claimed** surface and the **sentiment**, in parallel:

- **Positioning + claimed features + pricing** — the landing page, docs, changelog (Codex/web).
- **What real users say** — X/Twitter, Reddit, HN: complaints, "it doesn't actually do X",
  launch reactions (**Grok** — its privileged X data is the point).
- **The wedge** — what it claims *only it* does. This is the list you'll try to break in §4.

Stage these as the **claim column** for §5. A claim with no source is dropped, not carried.

## 3. Get in — install or sign up (driven, signed in, real)

You are not limited to reading the landing page. Get **inside** the product:

- **Credential exists** in `agents secrets` → sign in and drive the real account.
- **No credential** → default to a **free/trial signup** only if the owner's run policy allows it
  (this creates a real third-party account — an outward-facing act; honor `--signup ask|auto|creds-only`,
  default **creds-only**: sign in if we have creds, else drive the public surface + docs and **flag the
  login wall** rather than silently creating accounts). Never fake being inside.
- **CLI/installable product** → install it for real on a fleet box and run it end-to-end
  (`agents run` / a worker), quoting actual output — the eve exploration did this part right.
- Drive with **`agents browser`** (web) or **`agents computer`** (native desktop, element mode),
  signed in. If a step needs a secret, inject it from `agents secrets` — don't stop.

## 4. Drive every journey — screenshot each step, record the headline flow

This is the step the weak report skipped. For **each journey** from §1:

- **Walk it end-to-end** as a real user would, and **screenshot every meaningful step** —
  the empty state, the input, the mid-action, the result. Not one capture: a **strip** that
  reads as a filmstrip of the flow. Zoom / crop to the decisive interaction so a reader sees
  *what happened*, not a full-window thumbnail.
- **Record a short screen clip** (`--record on` for the 1–2 headline journeys; compose the
  `create:edit` / `animator` skills to trim + caption). A 10–20s clip of the core loop is worth
  more than any paragraph. `--record off` to skip for a fast pass.
- **Feed real, representative input** — a real repo, a real document, a real prompt of the shape
  the product is *for*. Toy "hello world" input hides exactly the behavior you're evaluating.
- **Capture the limits** — hit the pricing/quota/error wall on purpose and screenshot it; that's
  where claims and reality diverge most.

Save every capture into the run's artifact dir; name them by journey + step so §6 can assemble
the strips deterministically.

## 5. Claims vs reality — the differentiated finding

Merge §2's claim column with §4's captures into the table that makes this report worth reading:

| Landing-page claim | What it actually did (with capture) | Verdict |
|---|---|---|
| "Runs background agents autonomously" | *screenshot: agent ran 3 steps then stalled awaiting input* | ⚠ Partial — needs a nudge |
| "One-click deploy" | *clip: deploy succeeded in 22s* | ✓ As claimed |
| "Works with any repo" | *screenshot: errored on a monorepo* | ✗ Overstated |

- **✓ As claimed** — you drove it and it did the thing (cite the capture).
- **⚠ Partial / caveated** — it does it, but with a limit the marketing omits.
- **✗ Overstated / couldn't verify** — it didn't, or was walled. Say which; never guess a ✓.

The gap between the landing page and the driven product **is** the research finding.

## 6. Synthesize — one highly-visual artifact

Author a `kind: report` artifact and render it with the `artifacts` skill. It **must** carry,
per product:

- A **favicon/logo-tagged product card** (identity at a glance — §1).
- A **per-journey flow diagram** — an inline-SVG of the steps/states you walked (distinct from
  any architecture diagram; this is the *user's path*). Use the `artifacts` diagram conventions.
- The **screenshot strip** for each journey, and the **embedded clip** for the headline flow.
- The **claims-vs-reality table** from §5.
- For `--compare`: one **comparison matrix** of the products across the same journeys, each row
  favicon-tagged, plus a "reach for which when" split.
- **Honest gaps** — what you couldn't drive and why (version gate, paywall), named, not buried.

A product exploration that ships as mostly prose with one screenshot is **incomplete** — send it
back through §4.

## 7. Deliver where the owner will see it

- **Inspect headlessly first** — render, screenshot the rendered page, view it; both themes,
  no overflow, images resolve. (See it before you call it done.)
- **Show it on the owner's interactive box** in one reused tab:
  ```bash
  ROOT_DATE=$(date +%F); scp "$ARTIFACT.html" <interactive-box>:/tmp/
  agents browser navigate --device <interactive-box> --url file:///tmp/<file>.html
  ```
- **Promote the durable output** to the project's artifacts home
  (`.agents/artifacts/<YYYY-MM-DD>/product-<slug>.{md,html}` by default) with the captures beside
  it; `share` it if it's meant to leave the machine.
- Close with an honest line: what you **drove and verified** vs. what you **only read**.

## Anti-patterns (each is the weak report this skill replaces)

- **One idle screenshot.** A landing page or "Ready" status is not the product working. Capture
  the flow, not the front door.
- **Describing instead of driving.** "It supports X" with no capture is a claim, not a finding.
  Open it, do X, screenshot X.
- **No clip, no journey diagram.** The headline flow gets a clip; every journey gets a flow
  diagram. Text-only is the failure mode.
- **Features claimed, never shown.** If you didn't drive it, it's in the claim column marked
  unverified — never asserted as observed.
- **Toy input.** Real, representative data or a same-shape sample; toy input hides the failures.
- **Silently skipping the login wall.** No creds and policy is `creds-only`? Flag it and do the
  public surface — don't fake being inside, don't silently create accounts.
- **Leaving it in `/tmp` or as prose in scrollback.** Durable, visual, on the owner's screen.

## Compose map

- Public intel (claims + sentiment) → `research:research` (`agents run codex|grok|antigravity`).
- Get in + drive the surface → the `browser` skill (web) / `computer` skill (native) + `secrets`.
- Real-surface discipline (signed in, real inputs, capture every step) → the `demo` skill.
- Clip the headline flow → `create:edit` / `animator` (trim, caption, speed).
- Render the visual artifact + diagrams → the `artifacts` skill; publish → `share`.
- A wall only the owner can clear (paid signup, an enterprise gate) → `agents feed post "<ask>" --blocked`.
