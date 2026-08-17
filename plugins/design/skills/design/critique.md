# design:critique — audit an existing surface, and make the findings reusable

Run the design-core rubric against something that already exists — a screenshot, a URL, a
local HTML file, several pages of one site, or a running native app — and return ranked,
concrete findings. Two things distinguish this from "have a look at it":

1. **Deterministic checks run as code, not vibes.** Contrast ratios and markup-level tells
   come from the scripts in `scripts/`, so no ratio is ever guessed and no tell is missed
   because the screenshot happened to crop it.
2. **Findings leave in a reusable form.** The output is a paste-ready fix brief for the
   next agent, and standing design laws for the project's own docs — so the user states a
   complaint once and never has to type it into a prompt again.

## Load design-core first

Read `design-core.md`. Its 11-item checklist (§9) is the rubric; the anti-tells catalog
(§6) and the accessibility rules (§3) are the two sections the scripts mechanize.

## When to use (vs neighbors)

- Judge, audit, or find inconsistencies in something that exists → **critique** (this).
- Then rebuild a screen from the findings → **`interface`** (redesign path).
- Auditing a *flow* for dead-ends rather than visuals → **`anticipate`**.

## The loop

1. **Capture the artifact — look before judging.** Never critique from a description.
   - URL or local HTML: `agents browser start --url <target>`, screenshot; if the page has
     a theme toggle or honors `prefers-color-scheme`, capture **both light and dark**.
     Scroll and capture every distinct region, not just the hero.
   - Screenshot input: read the image directly.
   - Native app: `agents computer` element mode (`describe`, then `screenshot`) — never
     `--raise` or coordinate clicks on a machine the user is using.
   - Multi-page audit: capture each page the user names (or the main nav's top pages).

2. **Run the deterministic pass** (both scripts live beside this file in `scripts/`):
   - `bun scripts/check-tells.ts <file.html>` — anti-tells (§6), external-CDN/offline
     violations (§1), and color-only status glyphs (§3), each with line numbers. For a
     URL, save the page first: `curl -s <url> -o /tmp/page.html`. The linter is a
     heuristic: every finding is a line to open and judge, not an automatic verdict.
   - `bun scripts/check-contrast.ts --json '[{"fg":"...","bg":"...","label":"body"}, ...]'`
     — feed it the real fg/bg pairs from the page's tokens or computed styles (hex, rgb,
     and oklch all parse; translucent fg is composited). Check at minimum: body text,
     muted text, the accent on its background, and text on any filled component — in each
     theme the page ships. **Never state a ratio you did not compute.**

3. **Run the visual pass on the screenshots.** Score the 11-item checklist (design-core
   §9): focal point, hierarchy, alignment/rhythm, type, color, contrast, copy, density,
   consistency, anti-tells, intent. Each item is a pass or a specific fix with the element
   named and a number attached ("h1 and body are both 400; set h1 to 700/32px").

4. **Check against the product's own system.** Probe for `BRAND.md`, `DESIGN.md`, design
   tokens, or a tailwind theme (the design-core §4 cascade). A page that disagrees with
   its own product's tokens — a stray font, an off-palette accent, a third spacing scale —
   is a finding even when it looks fine in isolation. On a multi-page audit, build a small
   census per page (families, palette, spacing steps, radii, status encodings) and **diff
   the pages against each other**; drift between pages is the inconsistency the user can
   feel but has to hunt for by hand.

5. **Report — ranked, quotable, concrete.** One table: severity (blocker / should / nice),
   where (page + selector or line), what is wrong, the concrete fix, and which rule it
   violates (design-core §N, or the product's own BRAND.md line). Deterministic findings
   quote script output; visual findings reference the screenshot they came from. Order:
   accessibility and intent first, then hierarchy/density, then polish.

6. **Route the findings so they stay fixed.** Deliver both, then offer the third:
   - **Fix brief** — a paste-ready block the user can hand to any building agent (or you
     dispatch yourself via `agents run` / the `interface` mode): one bullet per finding,
     imperative, with the file/selector and the target value. No context-hunting required
     by the receiving agent.
   - **Design laws** — findings that reflect a standing preference (density, status
     labeling, palette bans) become one-line laws appended to the project's `BRAND.md`
     (or its `AGENTS.md` design section) **with the user's OK**, so every future agent
     inherits them without being told. A complaint made twice should never need a third.
   - **Rebuild** — offer to run `interface` (redesign path) on the worst screen.

## Output & delivery

- The ranked findings table plus the fix brief, in-session; screenshots referenced by
  full path so they can be opened. Keyless, offline once the page is captured.
- For a standing audit the user will share, render the report with the `visualize`
  engine (self-contained HTML) — same delivery as every other mode (`SKILL.md`).

## Mode checklist

- [ ] You looked at real screenshots (every distinct region, both themes when present).
- [ ] `check-tells.ts` ran on the markup; its findings were opened and judged, not pasted blind.
- [ ] Every contrast claim came from `check-contrast.ts` — no guessed ratios.
- [ ] The page was checked against the product's own brand/tokens, and pages against each other.
- [ ] Every finding names the element and the concrete change.
- [ ] The fix brief is paste-ready; new standing laws were offered to the project's docs.
