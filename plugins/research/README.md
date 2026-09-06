# research plugin

Get the **real, evidenced** answer about the world — not one model's guess, and for a product,
not one screenshot of a landing page. Two skills, one principle: **diversity and hands-on beat
depth from one source.**

## Commands

| Command | Use when |
| --- | --- |
| `/research` (`/research:research`) | **A hard research question** answered across DISTINCT engines blind to each other — Codex (web search), Grok (X/Twitter community), Antigravity (Google), Perplexity (broad browser-driven **Deep Research** — the dedicated mode, never Computer/Control-browser), Claude (deep-read + reconcile). Cross-checks every claim (single-sourced = a lead, not a fact) and promotes the cited result to the project's durable-artifacts home (`.agents/artifacts/` by default). |
| `/research:product` | **Explore a PRODUCT hands-on and prove every claim visually.** Composes `research:research` for the public intel (claimed features + sentiment), then signs up / installs and **drives** the real product through each user journey with `agents browser`/`computer` + `secrets` — screenshotting every step, recording a short clip of the headline flow, and putting landing-page **claims** next to what the product **actually did**. Output is a favicon/logo-tagged, journey-diagrammed, screenshot-strip visual artifact — never one idle screenshot and a wall of text. `--compare a,b,c` explores a set on the same journeys. |

## Skills

| Skill | Role |
| --- | --- |
| `research:research` | Multi-modal research: frame the question into angles, fan out across engines that each see a different slice **blind to each other**, cross-check claims across sources (single-sourced = a lead to verify), and synthesize one cited artifact. Composes `run` + `teams` + `browser` + `artifacts`. |
| `research:product` | Hands-on product exploration: install/sign up, drive every user journey, capture each step + a clip, verify landing-page claims against real behavior, and render a highly-visual artifact (favicon/logo identity, per-journey flow diagrams, screenshot strips, claims-vs-reality table). Composes `research:research` (intel) + `browser`/`computer` + `secrets` + `demo` (real-surface discipline) + `artifacts` (render); the clip uses `agents browser`/`ffmpeg`, polished with `create:edit`/`animator` only when the extras `create` plugin is installed. |

## How the pieces fit

```
/research          → one question, many engines (blind), one cited answer          [text truth]
/research:product  → one product, driven end-to-end, claims proven visually          [shown truth]
```

- **`/research` vs `/research:product`** — `/research` answers *what is true* about a topic from
  many engines and cites it. `/research:product` answers *does this product actually do what it
  says* by **using it** and showing the flow. Product exploration **starts** by running `/research`
  for the claimed surface, then drives the product to verify it.

## Conventions

- **Diversity beats depth from one source.** Never just ask one model harder; spawn engines that
  each see a different slice (Grok sees X, Codex sees the web, Perplexity goes broad).
- **A claim is not a finding.** A single-sourced number is a lead to verify; a feature you only
  read in the docs is a claim, labeled as such — never asserted as observed.
- **Drive, don't describe.** For a product, every reported feature is **shown** being used
  (a captured step or a clip). One idle screenshot and a wall of prose is a defect.
- **Durable + visual.** The result lands in the project's artifacts home and goes on the owner's
  screen — humans read visually.

---

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
