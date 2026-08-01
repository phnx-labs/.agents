# Changelog

## [0.1.78] - 2026-08-01

### Added
- **`plugins/swarm/skills/orchestrate/SKILL.md` — caveat: `agents teams doctor` `signedIn` is config-level, not a live auth check.** A stale-authed provider (droid observed) reports signed-in and then 401s at spawn ("Authentication failed. Please log in using /login or set a valid FACTORY_API_KEY") while its reviewer slot silently produces nothing. Guidance: smoke-test a load-bearing provider with `agents run <agent> --mode skip --timeout 1m "Reply with exactly OK"` before fanning out. Grounded in the gh-monitor mars migration session (2026-07-13), where doctor reported droid signed-in and both dispatched droid reviewers failed.
- **`skills/agents-cli/SKILL.md` — "Calling `agents` from automation" section.** `agents` resolves node via `/usr/bin/env node`; under a minimal PATH (launchd/systemd units, cron, git hooks) every call dies with `env: node: No such file or directory`, silently when stderr is redirected. Observed live: a launchd dashboard job's `agents ssh` pull no-oped until a node bin dir was added to PATH.

## [0.1.77] - 2026-08-01

### Changed
- **Dither Kit is now the default charting library for agent-authored dataviz.** `rules/subrules/tech-stack.md` and its compiled `rules/AGENTS.md` mirror add a Charts/dataviz row and a "Default Charting Library" section telling agents to reach for Dither Kit before ad-hoc inline SVG, one-off canvas code, Recharts, Chart.js, Plotly, or D3 whenever a rendered artifact carries a numeric chart (HTML plans, shareable visualizations, dashboards, QA/quality reports, blog visuals, and React/Next.js pages). A new `skills/dither-kit/SKILL.md` covers `npx @dither-kit/cli add <chart>` install, chart-type selection, and the keep-it-local (no CDN) rule. `commands/plan.md`, `rules/subrules/plan-presentation/rule.md`, the `plan-html-reminder.sh` gate, `skills/docs/SKILL.md`, `skills/docs/write-technical.md`, `skills/plan-render/SKILL.md`, `skills/visualize/SKILL.md`, and both `template.html` files now route quantitative charts to Dither Kit, while ASCII and Mermaid stay fine for text-only structural diagrams and hand-authored inline SVG for architecture and timeline figures.

## [0.1.76] - 2026-08-01

### Fixed
- **`rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh` no longer false-blocks writes to files outside the repo from Windows-native harnesses.** A Windows-style absolute path (`C:\tmp\out.html` or `C:/tmp/out.html`) did not match the POSIX-only `/*` absolute-path check, so it fell through to the relative branch and got concatenated onto `cwd`; `dirname` then walked that bogus path back up to `cwd` itself, misreporting an edit to a file completely outside the repo as "on the default branch." Fix: normalize backslashes to forward slashes for `cwd`, `file_path`, and the `git -C` path before any comparison, extend the absolute-path glob from `/*` to `/*|[A-Za-z]:/*`, and strip surrounding quotes from a quoted `-C` value. `main-branch-guard_test.sh` gains two ALLOW cases for drive-letter paths that run on Linux/macOS CI (not only under Windows `cygpath`), so the regression is caught everywhere (63 pass).

## [0.1.75] - 2026-08-01

### Changed
- **Core-hard-lines #7 changed from a Claude-model pick into a fleet delegation policy.** The old rule banned Haiku for subagents and defaulted load-bearing work to Opus. `rules/subrules/core-hard-lines.md` and its compiled `rules/AGENTS.md` mirror now make fleet spread the default: hand delegated work across harnesses (Kimi, Grok, DeepSeek, Codex, Gemini via `agents run <profile>` or a mixed `agents teams` roster) and across the several accounts of one harness (balanced rotation or per-account pinning), so no single account or harness carries the whole load and token spend stays low. Opus stays reserved for work where a cheaper harness would genuinely lose correctness, never the default. In-session `Agent` subagents still set `model` explicitly (default `"sonnet"`; omitting it can fall through to a pinned Haiku). Framed as a refinement of #2: equal correctness delivered cheaper and spread across the fleet wins.

## [0.1.74] - 2026-08-01

### Changed
- **A swarm is not done when its tracks merge — it's done when the composed cross-track flow runs.** An orchestrator fanned "dispatch the factory from iMessage" across three teammates, watched every PR go green + merge, and reported "done and merged / end-to-end" — but the halves didn't connect: the imsg track's daemon shelled out to `agents mission-control digest` while the digest track shipped a bin named `mission-control-digest`, so the feature was dead on `main`. Each PR passed its own tests and reviewer in isolation; nobody ran the seam. Four changes close this at the source. `core-hard-lines.md` #1 gains the proxy example "'every track's PR merged green' is not 'the composed feature runs across the seam where one track calls another'". `parallel-teams.md` gains an **Orchestrator completion contract**: the orchestrator's task is done only when the composed cross-track flow has been triggered end-to-end against where the feature actually executes (running daemon / installed binary — merged is not deployed) and its real output quoted, with any un-exercisable seam named unverified. The `swarm/orchestrate` skill records each seam + the command that proves it during pre-spawn discovery, and makes running that integration checklist the mandatory FIRST post-completion step. And the `verify-work-complete` Stop hook gains a **swarm integration gate**: for a session that ran an edit-mode swarm (`agents teams start/create`, or `teams add --mode edit`) and whose final message claims completion with wrap-up phrasing the generic done-list misses ("done and merged", "all three tracks landed", "end-to-end status"), it blocks the stop and demands the composed-flow output — the two normal gates were blind here because the teammates' PRs aren't created by the orchestrator's own `pr create`. Fires at most once (`stop_hook_active`), fail-open. Six new fixtures added to `00-agent-verify-work-complete_test.sh` (22 pass).
- **Handoffs land where the user is, not in a chat window they never see.** The user runs many agents and is rarely watching the window an agent stops in, so a "review + merge PR #119" note there is a note in an empty room. `workflow-proactive.md` gains **"When you DO hand back, land it where the user is"**: on a genuine handoff (a decision only the user can make, a PR only they can approve/merge, an artifact to eyeball), open the thing on the user's interactive device — resolve the online macOS box from Host & Fleet / `agents devices` and `agents ssh <device> 'open <url>'` so a PR lands on a tab where they click Merge/Approve directly — make the single required action obvious, and send the out-of-band phone notification when they may be away. The handoff analog of the plan-render "open it in the browser, every time" rule. `truly-agentic-git-workflow` cross-references it from the PR-merge section for the governance-change-you-can't-self-review case.
- **The done-claim gate now quotes the user's real request, not the jump command that opened the session.** The `verify-work-complete` Stop hook reconstructed "the user's original request" by taking the first user turn over 20 chars — so a session opened with `j agents-cli` quoted `"<bash-input>j agents-cli</bash-input>"` back as the goal to verify against, which is useless for re-anchoring intent. The extraction now skips harness-injected user turns (`<bash-input>`/`<bash-stdout>`/`<bash-stderr>`, `<command-*>`, `<local-command-*>`, `<system-reminder>`, `<task-notification>`, `[Request interrupted…]`, `Caveat:` prefaces, `Base directory for this skill:` bodies, and `… hook feedback:` injections) and keeps the first **three genuine prose asks** (joined, capped at 900 chars) so the self-audit sees the actual request and its early follow-ups. Verified against the real failed transcript: the gate now quotes the AGI-factory ask, the task-division note, and the "have you done any tests?" pushback instead of `j agents-cli`. (`agents sessions --include user --first N` doesn't solve this — it still counts each bash-input/stdout as a turn; the filtering has to happen on the text.) Two fixtures added (25 pass).

## [0.1.73] - 2026-07-31

### Changed
- **Agents now run a ticket lifecycle and put a picture on every user-visible PR.** Two always-on rules changed. `conventions.md` (and its compiled `rules/AGENTS.md` mirror) turns the one-line Tickets bullet into a three-step lifecycle: check for an open ticket before substantive work and claim it if found; open one scoped to the task when none exists and a tracker is configured (skip when no tracker is set up, or for a trivial fix or a plain question); and on delivery post a closing update with the PR link plus a screenshot or short screen recording, then move it to Done, closing only with proof. `truly-agentic-git-workflow` gains a pre-review gate in its evidence section: a user-visible change does not get review requested until the PR body carries a screenshot or short screen recording of the outcome, because the user reviews the PR in GitHub rather than the diff and a screenshot beats a description; a change with no visible surface attaches the closest concrete artifact (passing test output, the `curl`'d response). The `/tickets` command gains a "starting a task" section for the same check/open/close flow, and the `git-workflow` skill's Step 3 elevates its attach-evidence line to that gate with a screen-recording example.

## [0.1.72] - 2026-07-31

### Added
- **New default `design` plugin: one keyless, offline-first front door for design.** `/design` routes a design intent to a mode and renders it on the self-contained HTML/SVG substrate (the `plan-render`/`visualize` engine: inline CSS/SVG, no CDN, no paid keys), so a fresh install has real design capability with zero setup. Modes: `interface` (screens, pages, components, redesign), `prototype` (clickable multi-screen HTML flows), `system` (design systems, tokens, `DESIGN.md`, a live token preview), `diagram` (architecture/flow/sequence/ER via `plan-render/diagram-conventions.md` notation, legend-bearing SVG, never mermaid), `dataviz` (infographics and charts with Tufte discipline and colorblind-safe palettes), `deck` (HTML slide decks, PPTX optional), `asset` (OG cards, SVG logos, icon sets, and posters rendered offline; true raster degrades to a spec plus an editable placeholder plus enable-steps rather than hard-failing), `motion` (CSS/HTML animation honoring `prefers-reduced-motion`), and `critique` (run the design-core checklist on an existing screen). Every mode loads `design-core.md` first: visual hierarchy and rhythm, WCAG AA contrast, colorblind-safe palettes, the brand-probe cascade, precise non-marketing copy, and mandatory render/screenshot/critique verification. The design bet is that most jobs have a better answer in editable vector/HTML than in a generated raster, so the common design jobs work fully offline; brand plugins (rush, prix) layer on top by calling `/design`, and brand is optional. Registered in `plugins/design/.claude-plugin/plugin.json` and the marketplace seed (`.claude-plugin/marketplace.json`).

## [0.1.71] - 2026-07-31

### Added
- **`plan-render` / `visualize` now teach a precise, review-grade voice, plus a per-domain diagram-notation reference.** Generated plans and visuals had drifted into magazine-editorial copy: slogan kickers, "Critically:" drama, and stacked em-dashes (four in a single sub-paragraph) that make a plan hard to *review* rather than easy to check. `plan-render/SKILL.md` gains a `## Voice` section: the `.kicker` is a label (`PRODUCT · SUBSYSTEM · plan`), not a tagline; the `<h1>` states plainly what the plan does; prose names the concrete file/function/flag/number instead of a vague stand-in ("things"/"surfaces"/"stuff"); and em-dashes are capped at one per paragraph, never stacked. The gold `example.html` was rewritten to model it, dropping from ~30 em-dashes to 0, with the slogan and flattery removed and the headline changed from "Self-healing bookkeeping" to "Reconcile local bookkeeping"; both templates' kicker and headline placeholders now demonstrate the label form, and the `.legend`/`.sw` classes are promoted in. A new `plan-render/diagram-conventions.md` is a compact per-domain notation cheat-sheet (C4, UML class and sequence arrowheads, ER crow's-foot, DFD, ISO 5807 flowchart shapes, BPMN, network/cloud, plus non-software P&ID/ISA-5.1 and IEC/IEEE, Tufte chart rules, and colorblind-safe palettes) so figures use the notation a domain expert recognizes, with a legend whenever color or line-style encodes meaning. `visualize` gets the same rules, lighter: a shareable page may keep one accurate punchy headline while the body stays precise.

### Changed
- **New Tier-2 `code-quality` rule: write prose precisely; don't market.** Added to `rules/subrules/code-quality.md` (and mirrored into the compiled `rules/AGENTS.md`), it governs all agent prose (plans, PRs, commit messages, chat), not only the HTML skills: name the concrete file/function/flag/number/error rather than a vague stand-in unless that word is the real technical term; drop the marketing register (no slogans, no "Critically:"/"Notably:" drama, no filler adjectives like "seamless"/"powerful"/"robust"/"leverage"/"simply"); and cap em-dashes at one per paragraph, never stacking appositive dashes. The reader is reviewing the claim, not being sold it.

## [0.1.70] - 2026-07-21

### Added
- **New `/swarm:spec` command + skill in the `swarm` plugin (bumped to 0.4.0).** The durable-specification sibling to `/swarm:plan`: where `plan` drafts a change *delta* (`## ADDED / MODIFIED / REMOVED Requirements` + tasks to build it), `spec` reverse-engineers the **source-of-truth spec** of a capability from the **real code** — `## Purpose` + `## Requirements`, each a testable `### Requirement:` with an RFC 2119 keyword (SHALL/SHOULD/MAY) and `#### Scenario:` Given/When/Then blocks, in the [OpenSpec](https://openspec.dev/) `specs/` shape. The swarm value is two-fold: **blind independent specs** (agents on different providers spec the same capability from the code alone, and divergence exposes ambiguous/missing requirements) and a **spec-vs-code drift check** (every stated requirement confirmed against actual behavior at its cited file:line — a requirement the code doesn't satisfy is surfaced as drift, a bug or a wrong requirement, never quietly rewritten to match a buggy implementation). Anchors every requirement to file:line, web-searches external contracts it must conform to, and renders the spec via `plan-render`. Registered in `plugins/swarm/.claude-plugin/plugin.json`, the marketplace seed (`.claude-plugin/marketplace.json`, synced + bumped to 0.4.0 — its description had drifted, predating even `/swarm:run`), the plugin README command table, and the root README plugin row.

## [0.1.69] - 2026-07-17

### Fixed
- **`/hibernate` visible wake can no longer vanish silently.** The 0.1.68 context-aware wake set `opened=1` when a terminal launcher (`ghostty -e` / `osascript`) returned 0 — but those exit on *window-launch*, not on the *resume* actually starting, so a tab that opened but whose resume died would suppress the headless floor with no notification (a narrow silent-loss seam flagged in review, confined to `WAKE_VISIBLE=1`). The interactive inner script now **runs** the resume instead of `exec`-ing it, checks the exit code, and Telegram-pings on failure — so a dead visible wake is always observable. It pings on *any* non-zero exit (dismissing the tab with Ctrl-C exits 130, so a normal end can ping too); we don't whitelist clean-quit codes because a real death can also exit 130 — erring toward a stray ping over ever losing a wait.

## [0.1.68] - 2026-07-17

### Changed
- **`/hibernate` wakes are now context-aware, not always headless.** The wake transport is chosen from the wait length: a **short wait (< ~2h) from an interactive session** wakes into a **visible terminal tab** (Ghostty → iTerm → Terminal.app), while a **long/away wait** stays **headless + Telegram** as before. The wrapper always keeps a **headless floor** — if a visible tab is requested but no GUI terminal is installed, it resumes headless anyway and pings Muqsit, so the wait fires regardless of presentation (the terminal is never a hard dependency). Previously every wake resumed headless in the background, so a short interactive wait came back invisibly. Adds a tiny inner resume script (interactive `--raw -i` for the tab, `-p` for the floor) to keep terminal launchers quote-clean.

## [0.1.67] - 2026-07-17

### Fixed
- **`/fleet:sync` now propagates plugins to EVERY installed agent version, not just the default.** The refresh step (`agents repos refresh -y`) only materializes into the **default** version home per agent (the one `~/.claude` points at). On a box that runs **multiple versions of the same agent** — e.g. several Claude versions each signed into a different account — the non-default homes stayed stale, so a plugin newly added to the repo (this is exactly how `fleet` itself, and then `share`, went missing) **never appeared in whichever account the user was actually running**. The command now adds an `agents plugins sync` pass after refresh for any plugin not yet `everywhere` (detected from `agents plugins list`), on both the POSIX and Windows branches, and calls out that an already-running session needs a **restart** before a freshly-synced command appears. Without this, `/fleet:sync` could report a clean sync while the user still couldn't see the very commands it shipped.

## [0.1.66] - 2026-07-17

### Added
- **New `share` plugin — `/share:public` and `/share:private`.** One-step publishing of an agent-generated HTML artifact (a plan, viz, or report) to a shareable link on the user's own Cloudflare R2 (zero egress, ~$0), wrapping the `agents share` CLI (shipped in agents-cli 1.20.66). `/share:public` posts a public link with an auto-generated Open Graph cover (a 1200×630 screenshot of the page's hero) so it unfurls into a preview card in Slack/iMessage/Twitter/Discord; `/share:private` posts an unlisted, auto-expiring (`--expire 7d`) link with no preview card — unguessable but still public-read, and the command is explicit that it is *not* authenticated. Both check `agents share status` first and point at `agents share setup`/`join` if unconfigured. Ships a `share` skill (the deeper reference — setup, public vs private, naming, cost, OG covers) and a plugin README with an example preview card. Registered in `marketplace.json`; listed in the root README plugin table.

## [0.1.65] - 2026-07-17

### Fixed
- **Declared `fleet` in `.claude-plugin/marketplace.json` — it was the only plugin dir in the repo not listed in the marketplace seed.** 0.1.64 added the plugin manifest so `agents repos refresh` regenerates local marketplace membership and `fleet` registers; this completes the fix for the npm-shipped path, where `.claude-plugin/marketplace.json` is the seed a fresh install reads (before any local regenerate). Every sibling plugin (`cloud`, `code`, `git`, `social`, `swarm`) was already declared; `fleet` is now too, so a clean install of the system layer sees `/fleet:sync` and `/fleet:onboard` without needing a refresh first.

## [0.1.64] - 2026-07-17

### Fixed
- **`plugins/fleet/` now registers — added the missing `.claude-plugin/plugin.json` manifest.** The fleet plugin shipped in 0.1.60/0.1.61 with `/fleet:sync` and `/fleet:onboard` but **without a plugin manifest**, so it was never materialized into any agent home — the two commands silently failed to appear in the completion menu on every device (every other plugin — `code`, `git`, `cloud`, `swarm`, `social` — carries a `.claude-plugin/plugin.json`; `fleet` was the sole exception). Adding the manifest (name/version/description/author, matching the sibling plugins) makes `agents repos refresh` pick the plugin up so `/fleet:sync` and `/fleet:onboard` register. Ironically the command needed to propagate this fix fleet-wide (`/fleet:sync`) was itself the thing broken by its absence.

## [0.1.63] - 2026-07-17

### Added
- **`commands/output.md` — `/output [window]`: a fleet-wide token-burn + shipped-output report.** Wraps the built-in **`agents output --all-hosts`** (a productivity rollup that scans raw agent transcripts, not a stale index, across every online device) and productizes the two things that trip people up when they ask "how many tokens did I burn across all my machines and agents." **(1) It re-checks the machines the fleet pass couldn't reach.** `agents output --all-hosts` dials each box's *direct* address, so LAN-only nodes routinely time out (`ssh: connect ... timed out`) even though `agents devices` lists them **online (relayed)** — those are *unmeasured*, not zero. The command re-queries every errored host over the DERP relay (`agents ssh <host> 'agents output --json'`) and folds the result in, so no machine is silently dropped from the total. **(2) It keeps the two token numbers straight** — total **token count** (cache-inflated: input + cache read/write + output) vs **output tokens** (actually generated), which differ by ~100x — and states the pricing caveats: Codex/Kimi tokens are counted but **uncosted**, and Rush/OpenClaw are dispatch layers with **no per-token accounting** (their spend lands under the underlying Claude/Codex session). Then it renders the numbers as an HTML dashboard in the **`visualize`** house style (brand dark+light with a `◐` toggle, stat cards, by-machine bar chart, by-agent + all-machines tables, a Method+Caveats footnote), drops a **PDF in `~/Downloads`** via `weasyprint` (the reliable local HTML→PDF path — Comet's headless `--print-to-pdf` is disabled in the Perplexity fork and the `agents browser` CDP export needs a live debug-port browser), and opens the report in the browser. Filed under a new **Observability** group in the commands README.

## [0.1.62] - 2026-07-16

### Changed
- **`/fleet:sync` now refreshes ALL installed agent types, not just the default.** The refresh step is spelled `agents repos refresh -y` (no agent argument), which re-materializes the pulled skills/commands/plugins into **every** installed agent home on each box (claude, codex, gemini, grok, opencode, kimi, …). A bare `agents repos refresh claude` refreshes only claude and silently leaves the other agents stale — a real gap on any device running more than one agent (e.g. mac-mini has 4 agent homes; s0/s1/m0 have 2). The `-y` also keeps an unattended `bash -lc` run from blocking on a prompt. The Windows branch and the safety rules are updated to match. (The prose already used the no-arg form; this makes it explicit, adds `-y`, and calls out the "not just the default" contract so no one re-introduces `refresh claude`.)

## [0.1.61] - 2026-07-16

### Added
- **`plugins/fleet/commands/onboard.md` — `/fleet:onboard <device>`: bring a bare new machine up to fleet parity.** Takes a device with little/none of the setup (agents-cli not installed, repos not cloned, no fleet SSH key, agent auth missing) and brings it to the same state as a healthy node: install agents-cli + the agent CLIs, register/clone the DotAgent repos, install the shared fleet SSH key, fix the non-interactive PATH shim, register the device + sync the registry, and provision agent auth. It **productizes the manual enrollment this fleet did by hand** (the yosemite m-node setup). Deliberately **discovery-first, not over-refined**: the agents-cli command surface drifts, so the command instructs the agent to read `agents <area> --help` + **`agents doctor`** (the ground truth for what's present vs missing) at run time and prefer **`agents setup`** on a bare box — treating the doc as the goal + map, not exact keystrokes. Additive + idempotent (installs only what `doctor` shows missing; never tears down existing setup). Hard line on **credentials: never copied host-to-host** — agent auth and the fleet SSH key are provisioned only through sanctioned paths (`agents secrets`, `agents profiles login <provider>`, the agent's native login flow, `agents setup`) with explicit authorization, and any credential that can't be provisioned that way is handed to the user, not improvised. The runbook's verification step has the agent confirm **node-to-node reachability both ways** at run time (proves the fleet SSH key took — the exact thing broken before the mesh fix). **Not yet dogfooded end-to-end against a bare device** (the whole fleet is already onboarded) — this productizes the manual yosemite m-node enrollment done by hand this session, and gets its real bare-metal test the next time an actual new device joins. Moves `/fleet:onboard` from "Planned" to a shipped command in the plugin README.

## [0.1.60] - 2026-07-16

### Added
- **`plugins/fleet/` — a new plugin for fleet-wide operations, with its first command `/fleet:sync`.** `/fleet:sync` pulls **every registered DotAgent repo** (`system`, `user`, and any team/extra a device registered) to `origin` latest on **every online device**, then refreshes the installed agents — ending with a repo × device matrix. It's a curated recipe on top of `agents devices` / `agents repo`, encoding the exact sequence (and gotchas) rather than making anyone re-derive them live: (1) the **fast-forward workaround** — `agents repo pull <alias>` doesn't fast-forward, so it uses `git merge --ff-only origin/<default>` directly (upstream fix belongs in agents-cli); (2) a **retry** on the transient `kex_exchange_identification … Software caused connection abort` GitHub-SSH throttle; (3) **login-shell** invocation (`bash -lc`) so agents-cli is on the non-interactive PATH; (4) the **Windows PowerShell** branch (`Set-Location` + plain `git`, no `-C`, no nested quotes). Hard line: **never clobber local work** — `git merge --ff-only` only, never `reset`/`checkout`/`clean`/`stash`/`pull`/`--force`; `user` and team repos are user-authored and each machine carries different local drift, so a repo that can't fast-forward is *reported* (`blocked (local changes)`), not forced. Does not auto-commit/push local edits (a future explicit `--push`). `/fleet:onboard` (bootstrap a bare new device to fleet parity, credentials via sanctioned paths only) is scoped as the planned follow-up. Delivered to every install via `agents repo pull system` + `agents repo refresh claude` (or `/fleet:sync` once live).

## [0.1.59] - 2026-07-16

### Added
- **`skills/visualize/` — a new general-purpose skill: turn any concept, dataset, or codebase/session finding into ONE self-contained, shareable HTML visual (infographic · explainer · status-dashboard · data-story · comparison).** It is the sibling of `plan-render`, reusing that skill's engine verbatim — brand-probe theming, the light/dark `◐` toggle, the hand-authored-inline-SVG-never-mermaid rule, the self-contained/no-CDN constraint, and the open-on-the-user's-Mac transport — but drops the plan-specific framing (the `plan mode` kicker, "files touched" chips, "go / reshape" footer, and the context→design→files section taxonomy) so it applies to arbitrary context, not just implementation plans. This closes a real gap: nothing owned "context → interactive shareable HTML explainer" — `visual-styles`/`image` produce raster PNGs, `rush:slides` outputs PPTX, `rush:pdf` a print doc, and `plan-render` is plan-scoped. Ships `template.html` (the generalized house template) and `example.html` (a fully-themed neon "fleet status" dashboard as the gold reference). Bakes in three recipes learned the hard way building that page: (1) single-page full-bleed **poster PDF** export via Playwright's bundled `chrome-headless-shell`, sized to exact content height — because paginated Letter slices a screen-designed visual into broken bordered sheets; (2) guard count-up/entrance animations under `navigator.webdriver` so headless print doesn't snapshot zeros; (3) Chromium *forks* (Comet) can't `--headless`-print (the updater hijacks the launch) — use Playwright's Chromium. Auto-discovered like every skill (no registry entry). Delivered to every install via `agents repo pull system` + `agents repo refresh claude`.

## [0.1.58] - 2026-07-16

### Changed
- **`skills/plan-render/SKILL.md` — plans now land a viewable PDF in the user's `~/Downloads`, and durable HTML lives in the project.** The render previously wrote one self-contained HTML to `/tmp` and opened it in the browser — which strands the plan when the agent runs on a headless Linux node while the user views on a Mac/Windows laptop (an HTML in a remote `/tmp` is not viewable, and control-room viewing is mostly off-fleet). The skill now: (1) writes the durable HTML to **`<repo>/.agents/plans/plan-<slug>.html`** when the project has an `.agents/` dir (next to the code it describes, indexable by the future download portal), falling back to `/tmp` otherwise; (2) generates a **PDF** from that HTML via the browser stack (`agents browser` → CDP `Page.printToPDF`, which drives the machine's installed Chromium-family browser) and **copies both PDF and HTML into `~/Downloads` on the machine the user actually sits at** — directly if local, else `scp` + run the block via `agents ssh <host>`; (3) still opens the interactive HTML in the default browser. Degrades cleanly: no `~/Downloads` (headless/VM) skips the copy, no reachable browser skips the PDF+open — the durable HTML is always written. Verified end-to-end on zion: `example.html` → 7-page PDF + HTML both in `~/Downloads` (note: `agents browser pdf`'s `[output]` positional is ignored in current builds, so the recipe captures the auto-saved path). Delivered to every install via `agents repo pull system` + `agents repo refresh claude`.

## [0.1.57] - 2026-07-16

### Changed
- **`hooks/07-inject-device-topology.sh` now injects live fleet resources, not just reachability.** The SessionStart "Host & Fleet" block previously listed each machine's platform and online/relayed/offline state (from the fast `agents devices list --json`, which is registry-only). It now also captures the rendered `agents devices list` table — the only surface that carries the live probe — and appends each reachable box's **load / memory / headroom** (`idle`/`light`/`busy`/`loaded`) plus the **fleet capacity summary** (total cores · free/total RAM across reachable devices). The guidance line gains a "prefer an idle/light box when offloading work off this machine" nudge, since that offload decision is the agent's to make and the built-in scheduler isn't utilization-aware. The probe SSHes each reachable box, bounded at ~2.5s/box in parallel; if it fails or returns nothing the block degrades cleanly to the previous reachability-only output (verified), and a missing registry still stays silent. Shellcheck-clean (the pre-existing SC2016 info on the intentionally single-quoted Python block is unchanged).

## [0.1.56] - 2026-07-15

### Changed
- **`check-updates` now runs as a `command:` (shell) routine instead of an LLM agent.** The routine's work — compare installed vs. latest `agents-cli`, `npm install -g` when behind, fast-forward `~/.agents/.system`, and desktop-notify on change — is deterministic, so it no longer spins up a Claude agent. This removes the failure mode where the daemon's account rotation dispatched the update-check to a logged-out agent version and the run died on "Not logged in · /login" — a `command:` routine has no auth, token, or rate-limit surface. Uses a direct `git merge --ff-only` for the `.system` update (working around `agents repo pull system` not fast-forwarding). **Requires** agents-cli with command-mode routines (the release adding `JobConfig.command`); do not distribute before that ships, or older installs reject the routine.
### Added
- **`commands/hibernate.md` — adopt the `/hibernate` slash command into the system repo, with its permission footgun fixed.** `/hibernate` schedules a macOS launchd one-shot that resumes **the same** claude session at a future wall-clock time to re-check a slow external wait (an approval, a soaking deploy, a review you can't hurry) — no summary, no hand-back to the user. It was an **orphan**: it only ever existed as an untracked copy in per-version agent homes (`~/.agents/.history/versions/claude/*/home/.claude/commands/`), never tracked here, so the fleet never had it under version control. The wake wrapper previously resumed via `claude --print --dangerously-skip-permissions --resume "$SID"` — a persistent, auto-launched job carrying a **blanket permission bypass**. It now resumes via `agents run claude --resume "$SID" --mode auto`: the smart permission classifier (auto-approves safe ops, still prompts/blocks risky), **never** `--dangerously-skip-permissions`. Delivered to every install via `agents repo pull system` + `agents repo refresh claude`.

## [0.1.55] - 2026-07-15

### Added
- **Built-in `check-updates` routine (`routines/check-updates.yml`).** The first routine shipped in the system repo. It keeps `agents-cli` and the shared `.system` config repo current on every machine: checks the installed vs. latest npm version and upgrades when behind (skipping local `0.0.0-dev` builds), runs `agents repo pull system`, and fires a native desktop notification (`osascript`/`notify-send`, best-effort) when anything changed — otherwise stays quiet. Runs Mondays 09:00, self-updating **per box** (no SSH fan-out, no designated primary), so a one-laptop user and a large fleet are both covered. Delivered to every install via `agents repo pull system`; the daemon fires it once agents-cli supports system-layer routines (agents-cli ≥ the release that adds `getSystemRoutinesDir` unioning). Users override it with a same-named `~/.agents/routines/` file or disable it via `agents routines disable check-updates` — the shipped file is never mutated in place.

## [0.1.54] - 2026-07-14

### Changed
- **mq guidance now teaches the winning one-call pattern, not the map-then-extract dance (`hooks/10-mq-read-nudge.py`, `skills/mq/SKILL.md`, `rules/subrules/context-query-mq.md`).** A controlled A/B measured that the `.tree`→`.section` dance for a target you already named is **2.3× more expensive and ~2× slower** than just reading the file, while a **single** `mq <file> '.section("X") | .text'` call is **~18% cheaper AND faster** than a whole-file read (same answer) — the shipped hook was previously instructing the losing dance. All three surfaces now: lead with the one-call extract (`.section|.text` / `.search`), reserve `.tree` for genuine structure discovery or repeat access, and add an explicit when-NOT-to-use boundary (small files, one-shot whole-file reads → just `Read`). Grounded in the fleet audit (mq used 0× / 835 sessions) plus the follow-up A/B that showed misused mq is worse than reading.
- **`skills/run/SKILL.md` — document permission modes without encouraging the bypass.** Replaces the legacy `full` recommendation with primary `plan` / `edit` / `auto` / `skip` modes, marks `skip` as a last resort, maps direct-exec skip to every native harness flag (including Codex `--dangerously-bypass-approvals-and-sandbox`/`--yolo` and Claude Code `--dangerously-skip-permissions`), explains ACP permission-option selection, distinguishes Codex sandboxed `auto` from unsandboxed `skip`, distinguishes Kimi's interactive `--auto` from its already-auto-approved headless `-p` path, and discloses that unsupported `plan` modes degrade to writable `edit` while headless Kimi rejects `plan`.
## [0.1.53] - 2026-07-13

### Added
- **`cli/mq.yaml` — `mq` is now a system-default required host CLI.** Declared at the system-repo level so `agents doctor` reports it under Host CLIs and `agents cli install mq` provisions it on any machine. Installs from the project's own per-platform GitHub release tarballs (`github.com/muqsitnawaz/mq`, darwin/linux × arm64/x64) — no Go toolchain needed. Check is `mq --version`. The manifest warns (docs-level) about the unrelated Homebrew `mq` markdown processor, a different tool with the same binary name — the check can't disambiguate them (both exit 0), so the guidance is "don't `brew install mq`", not a runtime identity test.
- **`skills/mq/SKILL.md` — system copy with the honest capability description.** The prior (user-layer) skill advertised "Markdown, HTML, and PDF" only. `mq --help` actually supports **source code (Go/Python/TS/Rust/…), JSON/YAML/CSV, and Office (xlsx/docx/pptx)** as well. The skill now leads with that — the undersell was a measured cause of non-use: the agent believed mq was a docs tool and never reached for it on the `.ts`/`.py` files that are the majority of reads.
- **`rules/subrules/context-query-mq.md` — "query structure before reading whole files" discipline.** Probe with `mq <file> .tree`, extract the one section, never re-read the same file to hunt different parts. Grounded in a fleet audit: `mq` invoked 0 times across 835 sessions in 3 days while 62% of all tool calls were context reads (whole-file dumps; the same file re-read up to 34× per session).
- **`hooks/10-mq-read-nudge.py` — PreToolUse Read nudge (wired in `agents.yaml`).** When the agent is about to read a large (≥16 KiB) supported file whole, it injects a one-time (per session + per file) suggestion to map + extract with `mq` instead. Advisory only — never blocks; skips targeted reads (offset/limit set), small files, and unsupported/binary formats; dedups via an `O_EXCL` marker so a file is nudged at most once per session. Fail-open everywhere. Claude only (relies on PreToolUse `additionalContext`). Disable from the user side with `enabled: false` if it proves noisy.

### Fixed
- **`rules/rules.yaml` — register `context-query-mq` in the default preset.** The subrule file shipped but was absent from the explicit `subrules:` list, so it never compiled into the agents' memory file (verified live: the file synced but its content was missing from `CLAUDE.md`). Added it after `tech-stack`.

### Changed
- **`rules/subrules/tech-stack.md` — corrected the `mq` tool-map row.** Was "Query large docs (.md, .html, .pdf)"; now "Read a large file (200+ lines) or map an unfamiliar dir → `mq`" with the full format list (code/docs/data/Office) and a pointer to `context-query-mq`.

## [0.1.52] - 2026-07-13

### Added
- **`hooks/08-inject-repo-inflight.sh` — SessionStart injection of the repo's in-flight state.** Every session starting inside a git repo now sees the repo's open PRs (`gh pr list`, number/title/branch/draft) and the other agent sessions currently active in that checkout on this machine (`agents sessions --active --json --local`, filtered on the structured `cwd` field with a path boundary so `agents` does not swallow `agents-cli`; the starting session itself is dropped via `session_id`) before it takes work. AX-by-injection: "check what's already owned before opening a PR / spawning teammates / adopting a task" is delivered as state, not an instruction to remember — targeting the two observed failure modes of duplicate PRs for the same scope and taking over a surface another live session is mid-flight on. Fail-open everywhere (no repo, no gh, no agents CLI, timeouts → silent exit 0), portable `timeout` shim for stock macOS. Wired for claude+codex+gemini; covered by `08-inject-repo-inflight_test.sh` (11 cases incl. the path-prefix collision, worktree inclusion, and self-exclusion) and smoked against a live repo. A "see what's in flight" row is added to the tech-stack tool map. (Review round: an earlier text-scraping parser leaked sessions from `unknown` directory blocks and other machines — replaced with the `--json --local` structured filter.)
- **The `verify-work-complete` Stop gate is now wired — and blocks PR abandonment.** The script existed but was never registered in `agents.yaml`, so nothing fired; every issue-drain teammate stopped with stranded PRs. Now wired (claude, Stop event) and extended with an open-PR abandonment gate: a PR counts as session-created only when its URL appears in the `tool_result` paired (by `tool_use_id`) to a `tool_use` that ran `pr create` — so viewing or reviewing someone else's PR, even in a session that also created PRs, never triggers the gate. A created PR still OPEN blocks the stop unless the final message explicitly hands it off (word-boundary matched) to a named owner. "PR open, CI green, waiting for reviewer" is not a stop state — merged-or-handed-off is done. Fail-open on missing gh/network; `stop_hook_active` prevents loops. Covered by `00-agent-verify-work-complete_test.sh` (8 cases incl. mixed create+review and the handoff-substring escape) and smoked against a real session transcript with a live open PR (blocks citing the right PR; allows with an explicit handoff).

### Fixed
- **The done-claim half of `verify-work-complete` could never fire on real transcripts.** Its turn counter and first-user-message extraction read `role`/`content` at the top level of each JSONL line, but real Claude Code transcripts nest them under `message` — so the turn count was always 0 and the gate always allowed. Both now fall back to `message.role`/`message.content`.

### Changed
- **`rules/subrules/parallel-teams.md` — completion contract for edit-mode briefs.** Every edit-mode teammate brief must state that the task is complete only when the PR is merged or explicitly handed off to a named owner (an entire 11-teammate run once ended with every PR unmerged). The `verify-work-complete` Stop gate is the mechanical backstop; the brief line is what makes teammates drive to merge instead of arguing with the gate.

## [0.1.51] - 2026-07-13

### Added
- **`skills/routines/SKILL.md` — "Pattern: continuous ticket drain".** A recipe for turning an issue-tracker queue into a self-draining pipeline: one triage routine routes tickets to workers by label (single writer, no claim race; opt-out label is human-only), one drain routine per worker lands them end-to-end. Documents the tested design points: label-per-worker partitioning, pilot-label gating, `mode: skip` + `sandbox: false` + the `claude` secrets bundle for headless auth, a staleness-aware overlap lock (a leaked lock must not deadlock the queue), and a verbatim notify one-liner for escalation. Includes a drain-routine YAML template.

### Changed
- **`plugins/code/skills/loop/SKILL.md`** — two new sections proven in a live fleet drain: "Unattended mode" (no `AskUserQuestion` headless; park blocked tickets with a comment + notify command and continue; verify tracker label filters aren't silently dropped) and "Claim before you build, dedup before you claim" (search open PRs by item ID and `agents sessions --active` before claiming; claim = Todo → In Progress, a best-effort signal with a re-check before first commit; every PR carries its item ID in the title so other loops' dedup can find it; spawned workers never land on the user's interactive machine).
- **`plugins/code/skills/review/SKILL.md`** — the BLOCKED verdict no longer dead-ends on `AskUserQuestion` in unattended runs: the reviewer states the verdict and reasons in output for the orchestrator to park and notify.
- **`plugins/code/.claude-plugin/plugin.json`** — bumped to 0.7.1.

## [0.1.50] - 2026-07-12

### Fixed
- **The PreToolUse guard hooks are now harness-portable across Claude Code and Grok CLI.** Claude Code sends hook JSON in snake_case (`tool_name`, `tool_input.command`, `tool_input.file_path`); Grok CLI sends camelCase (`toolName`, `toolInput.command`) and names plan-exit `exit_plan_mode` (not `ExitPlanMode`). All four guards read only snake_case, so under Grok `main-branch-guard`, `merge-guard`, and `footer-guard` extracted empty strings and **silently failed OPEN** (the default-branch, admin-bypass, and PR-footer rails were dead on Grok), while `plan-html-reminder` **failed CLOSED**: its `[ -n "$tool" ] && [ "$tool" != "ExitPlanMode" ] && exit 0` defensive check fell *through* on an empty tool name, so it hit the plan-HTML freshness gate and exited 2, **blocking every tool call** in a Grok session whenever no `/tmp/plan-*.html` was fresher than 90 minutes (seen live in a Grok session 2026-07-12). The three fail-open guards now read `tool_name // toolName` and `tool_input.* // toolInput.*` across all three parser branches of their shared `_json_field` helper (jq → node → python), preserving the "no parser → fail CLOSED" behavior for `main-branch-guard`/`merge-guard` unchanged. `plan-html-reminder` now resolves the tool name across both harnesses, recognizes both `ExitPlanMode` and `exit_plan_mode`, and — as a REMINDER hook — **fails OPEN** (exit 0) whenever the tool name is empty or unrecognized, so it can never again block an unrelated tool call. Verified across jq/node-only/python-only parser conditions and with camelCase-payload regression cases added to each guard's `*_test.sh` (`main-branch-guard` 61/0, `merge-guard` 42/0, new `footer-guard_test.sh` 11/0, `plan-html-reminder` 8/0).

## [0.1.49] - 2026-07-08

### Fixed
- **Re-wired the destructive-op guards that had gone dead.** `git-guard` (blocks `reset`/`checkout`/`stash`/`clean`/rebase-outside-worktree, force-push, branch delete, config write), `rm-guard` (blocks `rm -r` on protected paths — `$HOME`, `~/.ssh`, `/`, …), and `git-require-clean-tree` (blocks `pull`/`rebase`/`--autostash` on a dirty tree) were **not registered on any agent**: their manifest entries had been defined under a stray `run:` key (never parsed by `parseHookManifest`) and were removed in `8b006a6` as "legacy" — so the destructive-op protections the docs describe were not actually firing. They are now correctly declared under `hooks:` (PreToolUse / matcher `Bash`, claude+codex+gemini) and register into settings.json. These cover data-loss ops (`git reset --hard`, `rm -rf $HOME`) that no other wired guard catches. Verified via `registerHooksToSettings` (all three → PreToolUse/Bash, zero errors) and the guards' own behavior tests.

## [0.1.48] - 2026-07-07

### Fixed
- **The destructive-op guards no longer fail OPEN on Windows.** Every guard extracted the command via `jq`, which is absent on Windows git-bash — the fallback `cmd=$(…jq…)||cmd=""; [ -z $cmd ]&&exit 0` then collapsed to `exit 0` (allow) without inspecting anything, so on Windows the guards silently didn't fire (proven by stripping `jq` from PATH: `git reset --hard`, `rm -rf $HOME`, edit/commit on `main`, `gh pr merge --admin`, and `pull`/`rebase` on a dirty tree all passed unguarded). `git-guard`, `rm-guard`, `main-branch-guard`, `merge-guard`, and `01-git-require-clean-tree` now share a portable `_json_field` helper — jq (fast, on mac/Linux) → node (always shipped with agents-cli) → python — and **fail CLOSED** (block with an actionable message) when no parser exists at all. `node`/`python` `JSON.parse` unescape `\n \t \" \\` exactly like `jq -r`, so multi-line/chained command splitting is preserved. No behavior change on macOS/Linux (the jq path is unchanged). Verified 29/29 across normal/no-jq/no-parser conditions plus a live run on a real Windows box (parser resolves to node; `git reset --hard` and `rm -rf <home>` block, `git status` allows). Convenience hooks that hardcode `python3` are a separate follow-up. (#70)

## [0.1.47] - 2026-07-07

### Changed
- **"Shipping" now explicitly means the change runs on the user's machine — not that it reached a registry.** `core-hard-lines.md` #1 gains a proxy example: "npm publish succeeded" / "the published tarball contains the code" is not "the feature runs on the user's machine". Run the *installed* artifact, confirm the *installed version* carries the change (`agents --version`), and watch for a second install shadowing it on `PATH`. Motivated by a session that called a feature "shipped/live" after `npm publish` + a `grep` of the tarball while the installed binary was still an old version (1.20.19 vs the published 1.20.38) — so the feature was not actually running for the user. Extends the 0.1.45 (#53) anti-hesitation work, which the running config happened to be 10 commits behind — itself an instance of the same published-≠-live gap.
- **The release banned-stop now names its declarative twin.** `workflow-proactive.md`'s "Should I release?" ban (#53) caught the *question* form; it now also names **"say the word and I'll release / deploy / publish"** as the identical stop in declarative clothing, and points *shipping* at the user-visible surface (run the installed binary — core-hard-lines #1) rather than stopping at "it's on npm".
- **A verification gap is a problem to solve, not to report.** `core-hard-lines.md` #1 previously read "quote the gap and call it unverified instead" as the response to a ⚠️/hung/skipped/untriggered hop, with "work around it" trailing as a secondary clause — which biased the agent toward *flagging* the gap. Reworded so the first move is to **drive it to done** (fix the failure, work around the blocker, or reach the outcome another way — #9), and "call it unverified" is the **last resort after genuinely exhausting** those. The honesty invariant is unchanged: never claim "confirmed" when evidence shows a gap.

## [0.1.46] - 2026-07-07

### Fixed
- **`main-branch-guard` no longer false-blocks writes to gitignored paths on the default branch.** The file-tool branch denied any Write/Edit under a repo on its default branch purely from "is this repo on `main`?", without ever consulting `.gitignore` — so it blocked the harness's own memory dir (`~/.claude/…/memory/`, a symlink into the gitignored `~/.agents/.history/`) as well as `.agents/scratch` / `.agents/artifacts`, even though a gitignored file can never be committed and thus can never land on the default branch. The guard now runs `git check-ignore -q` on the target and allows it when ignored; tracked paths — real source, or a would-be-new tracked file — still deny and must go through a worktree + PR (the exemption is gitignore-scoped, not a blanket bypass). Regression-tested with real throwaway repos in `main-branch-guard_test.sh` (gitignored `.history/`/`scratch` allow, tracked still deny). Source: `rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh`, `rule.md`. (#68)

## [0.1.45] - 2026-07-07

### Changed
- **The `release` skill no longer asks "should I release or hold off?"** §6.2 of `skills/release/SKILL.md` previously ran `AskUserQuestion` with a literal "Cancel" option before every publish — the direct source of the hesitation, and inconsistent with `code:review`, which is told never to offer a "stop"/"cancel" option (`plugins/code/commands/review.md`). Now an in-session release authorization ("release" / "ship" / "cut a new version" / "merge and release") carries through to the publish, the same way an in-session "open a PR" carries through to merge-on-green — after showing the dry-run as a report. It asks only on genuine forks it can't resolve (monorepo package selection, a major/breaking version bump, an un-inferable version), and offers forward actions only. Guardrail preserved: it **never publishes as a side-effect** — no in-session release request means it surfaces that a release is ready rather than running the publish. Motivated by a cross-machine audit of 3,783 typed prompts + 810 `AskUserQuestion` calls where release/merge/"what's next" hesitation dominated. (#53)
- **Docs + changelog are now part of the standing definition of "done."** The docs/changelog requirement lived only in the opt-in `/finish` command; the always-on "delivered end-to-end" line in `workflow-proactive.md` omitted it, so ordinary changes shipped without a changelog line or doc update until the user asked. It's now folded into the definition of done — scoped to user-visible surface changes, with `/finish`'s exemptions (pure bug fixes, internal refactors, test-only, self-evident renames), and explicitly reconciled with the "no unsolicited .md files" rule (update *existing* docs, don't invent READMEs/summaries). (#53)
- **The banned-stops list now names the exact stall-phrases the audit caught the agent using.** `workflow-proactive.md` quoted no agent-side phrases; it now bans ending a delivered task with "What's next?", asking "Should I merge/proceed/release/commit?" for an already-authorized step, and telling the user to "check now" for a log/URL the agent can tail or curl itself. The `AskUserQuestion` guidance is tightened and cross-references the `ask-user-question-guard` PreToolUse hook (defined in the user `.agents` repo, live at `~/.claude/hooks/`). (#53)

## [0.1.44] - 2026-07-05

### Changed
- **Agents now attach evidence when opening PRs, issues, and tickets.** Every "opening" flow (a PR, a GitHub issue, or a Linear/Jira ticket) is a handoff to a human reviewer, so the agent identifies the flow and attaches what the reviewer needs to judge it without re-running the session: **screenshots and relevant materials** of the user-visible outcome (uploaded to the PR/issue, not merely described; on-disk images referenced by full path), plus **the session transcript kept confidential — always**. The transcript can carry secrets/tokens/paths, so it never goes inline and never touches a public repo/tracker: a secret-gist link (`gh gist create --secret`) on private repos, a local-path reference on public ones. Landed in the always-on `truly-agentic-git-workflow` rule (+ its compiled `rules/AGENTS.md` mirror), the `git-workflow` skill's "Open the PR" step, and the `tickets` command. (#59)

## [0.1.43] - 2026-07-01

### Changed
- **Merged the three SessionStart "identity" hooks into one (`hooks/04-session-identity.sh`).** `04-capture-session-start-metadata.sh`, `07-inject-session-id.sh`, and `08-register-session-pid.sh` each independently re-read and re-parsed the *same* SessionStart stdin JSON (`session_id`/`cwd`/`transcript_path`) and spawned their own process on every session start. They are now one hook that reads stdin once and does all three jobs: writes the session metadata file (`~/.agents/.cache/state/sessions/<agent_pid>.json`), enriches the per-pid registry (`~/.agents/.cache/terminals/by-pid/<pid>.json`), and injects the live session id into the model context. Net: session start spawns one identity process instead of three, with no change to any consumer's on-disk contract.
  - **Deployed to the union of the former agent lists** (`claude`, `codex`, `gemini`, `kimi`, `grok`, `antigravity`). The two silent state writes now run for every agent — strictly additive (a metadata/registry file for an agent that previously lacked one is harmless and closes the former arbitrary gaps). The stdout injection self-gates to the Claude harness via `$CLAUDECODE` (set for Claude Code and the `kimi`/`deepseek` `ANTHROPIC_MODEL` presets the former `07` covered; unset under codex/gemini/standalone-grok), so non-Claude agents never receive Claude-shaped context JSON.
  - Fails safe exactly as before: runs on every session start, `no set -e`; empty/malformed/idless payloads exit 0 with no write and no stdout. `hooks/04-session-identity_test.sh` (14 cases) covers the metadata write, registry enrichment across every delivery shape (stdin/grok-env/idless/malformed), ancestor-pid resolution, launcher merge, and the Claude-gated injection (both the injected shape and the non-Claude no-injection). Run hermetically under a sandbox `HOME`.
  - Removed `hooks/07-inject-session-id.sh`, `hooks/08-register-session-pid.sh`, `hooks/08-register-session-pid_test.sh`, and the dormant `hooks/04-capture-session-start-metadata.sh` (the latter had no `agents.yaml` registration; its behaviour is preserved in the merged hook).

## [0.1.42] - 2026-07-01

### Added
- **`plan-render` skill + `plan-presentation` subrule — every agent now presents implementation plans as a browser-ready HTML doc, in the product's own brand, opened on the machine the user sits at.** Commit `05c10da` shipped the transport (`/plan` Step 9 render + `agents ssh <host> 'open'` via the device-topology hook); the LOOK was left as one thin line ("dark background, readable mono/sans") and the harness's *native* plan mode had no render step at all. This makes the rich format a codified default:
  - **`skills/plan-render/`** — the single source of the plan LOOK. `SKILL.md` defines the fixed house structure (hero with kicker/headline/chips/TOC, numbered sections, **≥1 hand-authored inline-SVG diagram** — never mermaid — callouts, tagged tables, code) and a **theme-resolution** order that skins the plan in the *target product's* brand (design tokens → tailwind/CSS vars → logo/manifest → live UI), falling back to a dark **+ light** editorial palette only when the product declares no brand. Ships `template.html` (dual-theme skeleton with an in-page `◐` toggle defaulting to `prefers-color-scheme`, so plans read in bright light and dim alike) and `example.html` (gold reference).
  - **`rules/subrules/plan-presentation/`** — an always-on subrule (added to the `default` preset) so *native plan mode*, `/plan`, and `/swarm:plan` all render + open the plan; bundles the **`plan-html-reminder`** hook (PreToolUse on `ExitPlanMode`): if no fresh plan HTML was rendered this session it blocks the presentation once with a render+open reminder, then passes on the re-call. Self-terminating; a headless fleet still renders the file (which clears the gate) even when it can't open a browser. Covered by `plan-html-reminder_test.sh` (5 cases: block-when-absent, allow on canonical/nested render, stale-render blocks, non-ExitPlanMode never gated).
  - **Wired the existing plan verbs to the new source:** `/plan` Step 9 and `/swarm:plan`'s review-artifact step now reference `plan-render` for the look (product theming, light/dark, ≥1 SVG) instead of restating a thin recipe. The open-on-Mac transport stays canonical in `/plan` Step 9. Host is always resolved from `agents devices` — never hardcoded.

## [0.1.41] - 2026-07-01

### Added
- **`register-session-pid` SessionStart hook (`hooks/08-register-session-pid.sh`) — records each agent process's live session id into the per-pid registry (`~/.agents/.cache/terminals/by-pid/<pid>.json`) so `ag sessions --active` maps a pid to its EXACT session instead of guessing the newest transcript in the cwd (which collapses co-located agents onto one row on hosts with no terminal extension).** Complements the agents-cli `ag run` launcher write: the launcher assigns Claude's id via `--session-id`; this hook fills in the id for agents that generate it internally (Codex/Kimi/Grok/Antigravity), by resolving the agent pid up the parent chain and enriching the launcher's entry. Registered for `claude`, `codex`, `kimi`, `grok`, `antigravity`.
  - Reads the session id from whichever channel the agent uses (verified against each vendor's hook docs): stdin SessionStart JSON `session_id` (Claude/Codex/Kimi/Antigravity), else `$GROK_SESSION_ID` / `$GEMINI_SESSION_ID` / `$CLAUDE_SESSION_ID`. The launcher's `agent`/`cwd`/`tmuxPane` win on merge — the hook only owns `sessionId`.
  - Fails safe: runs on every session start, `no set -e`; empty/malformed/idless payloads exit 0 with no write. `hooks/08-register-session-pid_test.sh` covers all delivery shapes, ancestor-pid resolution, launcher merge, and the idless no-ops (9 cases).
  - **Verified end-to-end for Claude:** a real session fired the hook, which recorded the true session id — matched against the on-disk transcript. Firing inside Codex/Kimi/Grok/Antigravity is doc-asserted (those agents are not installed/authed on the dev host); the script itself is tested against each of their documented payload shapes.

## [0.1.40] - 2026-07-01

### Changed
- **PR merges now default to `--rebase`, not `--squash`.** The workflow optimizes for one-concept-per-commit history — `/code:commit` splits aggressively into micro-commits precisely so each lands individually — but the merge step then squashed that history away. The two were contradictory. Rebase is now the single, consistent default across the rule sources (`truly-agentic-git-workflow`, `gh-merge-guard`, and the flat `rules/AGENTS.md` mirror), the `git-workflow` skill (`gh pr merge --rebase` + a "Rebase, not squash" rationale), and the code plugin (`code:review`). Squash is reserved for throwaway-WIP commit series ("wip", "fix typo"). Left untouched: `prune`'s squash-merged-branch *detection*, `/commit`'s `squash` *mode* argument, and the `--admin` guard test fixtures. (#49)
- **Parallel edit-mode teammates now get isolated worktrees.** Teammates sharing one checkout collide on the index and files (cross-writes, stale reads, merge chaos). The `parallel-teams` rule, the `teams` skill, and the `/teams` command now direct agents to give each teammate its own git worktree — one per teammate type / independent surface — via `teams create --enable-worktrees` + `teams add --worktree <role>`. (#48)
## [0.1.39] - 2026-07-01

### Added
- **`main-branch-guard` hook — enforces the worktree+PR workflow at the tool boundary, so agents can't commit straight to a protected branch.** A PreToolUse guard blocks direct commits/pushes to `main`/`master` (always protected, regardless of the repo's configured default) and, per #46, refuses a `git worktree add -b` whose base is stale or a local ref — the new branch must fork from a freshly-fetched `origin/<default>` so PRs never diverge from an old base. Consolidated the previously scattered git subrules into a single `truly-agentic-git-workflow` rule and recompiled `AGENTS.md` from the subrules (absorbing prior merge-guard/footer staleness). (#43, #46)
  - Follow-up hardening (#44): precise guard-scope wording, always-protect `main`/`master`, dropped a dangling reference, and added 5 edge-case tests to the guard's test suite.

### Fixed
- **`hooks/03-linear-inject-tasks-context.sh` now routes the "Your Tasks" bucket to the *running* agent instead of a hardcoded `agent:claude`.** On a codex (or any non-claude) session the agent's own `agent:<name>` tasks fell under generic "Team Tasks" while claude's were mislabelled as "yours" — the bucket was a guess, not an identity check. The hook now derives the harness from its own resolved path (`.../versions/<agent>/.../home/.<agent>/hooks/`): agents-cli installs one copy per agent and each harness invokes ITS copy, so the path names the agent on every launch path (interactive shim, headless runner, sandbox) with no dependency on harness-specific env vars. `AGENT_SELF=<name>` is an explicit override; `claude` is the last-resort default for manual runs. Verified across claude/codex/`AGENT_SELF` paths and with a synthetic two-issue payload that routes `agent:codex` vs `agent:claude` correctly under each identity. (#45)

## [0.1.38] - 2026-07-01

### Added
- **`inject-session-id` SessionStart hook (`hooks/07-inject-session-id.sh`) — injects the live session id (+ transcript path) into the agent's own context.** Registered on `SessionStart` for `claude` in `agents.yaml`, alongside `session-start-autosync` and `attention-sentinel`. This covers Claude Code and every Claude-harness profile (e.g. the `kimi` / `deepseek` `ANTHROPIC_MODEL` presets), so the model can reference its own session id without reading any file.
  - Deliberately the opposite of the two neighbouring SessionStart hooks (`04-capture-session-start-metadata.sh` writes a silent state file; `05-session-start-autosync.sh` runs a detached sync and stays silent): this hook writes to stdout on purpose. Claude appends SessionStart `hookSpecificOutput.additionalContext` to the model context verbatim — verified end-to-end (the model echoes back the injected UUID, and it matches the real `~/.claude/projects/.../<uuid>.jsonl` transcript on disk), with a negative control confirming no leakage.
  - **Blast radius is every Claude session start, so the hook fails safe.** No `set -e`; every branch (empty stdin, unparseable JSON, non-object payload, missing `session_id`) exits 0 with no output — a malformed payload yields no context, never a broken or aborted turn. The only thing ever written to stdout is well-formed `additionalContext` JSON, or nothing.
  - Codex/Gemini deferred to a follow-up: Codex injection is proven viable (a `session_start` hook's stdout lands in the rollout as a `developer` message) but needs the `codex_hooks` feature flag + a pre-trusted hash to be wired, so it is out of scope for this Claude-first change. Gemini has no SessionStart-to-context path.

## [0.1.37] - 2026-07-01

### Fixed
- **`merge-guard.sh` no longer false-blocks commands that merely *mention* an admin-bypass merge in body/message text.** The guard did a naive substring match over the entire command string, so a `gh pr create` / `git commit` whose `--body` or `-m` text documented the guard (as this repo's own rules do) was blocked as if it were a bypass merge — it fired on a `gh pr create` during PR #40. Deciding shell dataflow with a regex is a losing game, so the guard is now **block-by-default**: it blanks only regions it can PROVE are inert, then matches; anything else stays visible and blocks (via `perl`, with a safe raw-match fallback if `perl` is absent). Provably-inert = (a) a documentation-flag value (`--body`/`-b`/`--title`/`-t`/`-m`/`--message`/…) that is a plain quoted string with no command substitution, and (b) a heredoc body whose sink is `cat`/`gh`/`git` at top level and that is not routed onward into execution (no pipe/`;`/`&`/backtick/redirect after the tag, no process substitution or interpreter around the sink). So real bypasses are always caught, including the review evasions: `-m "$(gh pr merge --admin)"`, `sh -c '...'`, `cat <<EOF | sh`, `cat <<EOF >x.sh`, `tee ... <<EOF; sh ...`, `sh <(cat <<EOF)`, `eval $(cat <<EOF)`, `. /dev/stdin <<EOF`, and `source`/`command sh`/`env bash` heredocs. It also normalizes quote/backslash obfuscation of `--admin` (`--ad""min`, `--ad\min`, `--ad'min'`) and joins backslash-newline line continuations so `cat <<EOF \`⏎`| sh` is seen as piped. Over-blocks exotic constructs (safe direction).
  - **Scope, stated honestly in the script header:** this is a best-effort speed-bump against a cooperative agent's careless admin-bypass merge, **not** an adversarial boundary — a shell string can't be fully analysed with text rules, so variable indirection (`X=--admin; gh pr merge $X`) or splitting the literal word `merge` can still evade it. The real enforcement is **server-side GitHub branch protection with required reviews** (note: `main` on this repo is currently unprotected).
  - Combined single-dash flag clusters are handled, so `git commit -am/-asm "msg"` (the most common commit form) is treated like `-m "msg"` and does not false-block when the message documents the guard.
  - Added `rules/subrules/gh-merge-guard/merge-guard_test.sh` — 37 cases over the real script and real stdin JSON: genuine bypass merges block (plain, chained, `sh -c` both quote styles, command-subst in `-m`/`-am`, backtick; heredocs piped/redirected/process-substituted/line-continued into an interpreter; and `--admin` obfuscated via quotes/backslashes); legit merges and unrelated commands pass; and body / commit-message (`-m` and `-am`/`-asm`) / `cat`-heredoc / `gh --body-file` documentation text mentioning the tokens passes.

## [0.1.36] - 2026-07-01

### Changed
- **`gh-merge-guard` rule (`rules/subrules/gh-merge-guard/rule.md`) aligned with auto-merge-on-green.** The rule contradicted `git-workflow` and `workflow-proactive`: those say "merge autonomously on green review + CI," while `gh-merge-guard` said "never merge a PR the user didn't explicitly ask you to merge … opening a PR is the end of the task — then ask," and "an earlier 'open a PR' does not authorize a merge." Agents reading the composed ruleset behaved inconsistently at the merge step. Resolved in favor of **auto-merge on green**: authorization to do the work carries through to a squash-merge once a non-author review **and** CI are green; `AskUserQuestion` only on red (review finds problems, tests fail, or conflict). The real safety rails are unchanged — never `gh pr merge --admin`, never self-approve your own PR, never transfer credentials.

## [0.1.35] - 2026-06-30

### Removed
- **`reflect` skill (`skills/reflect/`) — folded into `learn` + inlined where it was actually used.** `reflect` and `learn` were two reflection commands with colliding triggers (`reflect` on the bare word "reflect"; `learn` on "reflect and improve"). The scope axis people reach for — *this session vs many* — is already `learn`'s argument (`/learn` = current session, `/learn <id|topic>` = across sessions), so a second command wasn't earning its place; its only distinct job was the no-write, mid-draft feedback recall, which is baseline behavior, not a capability.
  - Its one real consumer, the `#rethink` promptcut (`hooks/promptcuts.yaml`), no longer loads the skill — its "recall every constraint, correction, and piece of feedback" step is now inlined (with the cumulative-feedback note reflect carried), so the rethink gate is unchanged in behavior.
  - Dropped the `reflect` rows from `README.md` and `skills/README.md`, and the now-dangling "Distinct from `reflect`" clause in the `learn` inventory line. `learn` is now the single reflection skill.

## [0.1.34] - 2026-06-30

### Added
- **`/learn <target>` — target-audit mode on the `learn` skill (`skills/learn/`).** `/learn` gains a second mode alongside post-session reflection: pass the name of a skill, plugin, command, or workflow you use (`/learn rush:design`, `/learn code:loop`) and it audits *that one thing* across every past session that used it, then proposes fixes for where it keeps going wrong.
  - **`audit/find-sessions.sh`** enumerates the sessions that actually used the target and classifies each use as a real invocation (`Skill`/tool `tool_use`, or a `<command-name>`) vs. an incidental prose mention — so a passing reference to the word never outranks a real run. `--structured-only` keeps only real invocations (named targets); omit it to grep conversation text for a loose workflow phrase. `--all` widens past the current project; results stream newest-first with the JSONL line numbers of the moments to quote.
  - **`audit/report.ts`** renders the findings to a self-contained HTML triage report (same visual language as `/code:quality`): each problem framed **expectation → what happened → why**, anchored to the session that surfaced it (id + topic + line) with the real user/error quote so the user recalls the moment instantly, recurrence count across sessions, a **recency-weighted "maybe fixed"** flag for problems only seen in old sessions, and a proposed fix + target. The user ticks the fixes they approve and **Copy approved fixes → /learn apply**.
  - Approved fixes flow back through the existing engine — four gates, route-to-home, edit-without-downgrading, verify + ship via worktree + PR. The audit changes *what* gets fixed (problems mined from real sessions, not the current conversation); it does not relax *how*.
  - Frontmatter updated: target-audit triggers + argument hint, and `bun`/`open`/`mkdir`/`chmod` added to `allowed-tools` for the report pipeline. Refreshed the `skills/README.md` inventory row.

## [0.1.33] - 2026-06-29

### Changed
- **`/done` repurposed to recap + self-exit; the ship gate moved into `/finish`.** `/done` and `/finish` had overlapping "complete the work" jobs. Now they own opposite ends of the lifecycle:
  - **`/done` (`commands/done.md`)** no longer runs a checklist — it builds a `/recap`-style handoff summary, emits it as the assistant message, then **cleanly self-exits the session** by sending `SIGTERM` to the harness (the Bash tool shell's `$PPID`). This is the agent-side equivalent of the user typing `/exit`; there is no `/exit` tool exposed, so signalling the parent is the only self-exit path. A guard refuses to fire if the parent looks like infrastructure (bare shell, tmux, sshd, init/systemd) rather than an agent harness. Agent-agnostic — works under claude/codex/gemini/etc.
  - **`/finish` (`commands/finish.md`)** absorbed `/done`'s ship-gate steps: Step 5 now covers docs (AGENTS.md/README/CHANGELOG/help-text), commit + PR with a secret session-transcript gist, an optional package release (build → test → confirm → verify-in-registry), and follow-up ticket creation for proven-remaining work. It remains the anti-stopping driver on top of that. This **relocates the "Update Docs" step added to `/done` in 0.1.30** into `/finish`, since `/done` no longer ship-gates.
  - Rewrote the `/done` ↔ `/finish` cross-reference at the top of both files and updated `commands/README.md`. Removed the stale user-repo override that shadowed the system `/done`.

## [0.1.32] - 2026-06-27

### Added
- **`plugins/cloud/`** - new Rush Cloud dispatch plugin. Ships `/cloud:run` for the native `rush cloud run` path (Claude Code/Codex harness selection, repo dispatch, status/logs/transcript/message/cancel lifecycle, and proof required before claiming a run worked) plus `/cloud:accounts` for Rush login and connected Claude/Codex account setup (`rush cloud accounts add/list/remove`). Documents the verified Rush path: production `rush` CLI -> `api.prix.dev` `/api/v1/cloud-runs` -> Factory Floor / Yosemite agent-host pods, with Claude tokens or Codex auth forwarded per task. Calls out the important distinction between Rush Cloud subscription/access gates and vendor account capacity, so users do not confuse adding Claude/Codex credentials with granting Rush Cloud access.

## [0.1.31] - 2026-06-27

### Added
- **`skills/learn/` (`/learn`)** — a top-level reflection engine that converts a finished session into durable improvements without downgrading existing workflows or overfitting to one session. Recalls what was used → checks the used plugins for their own learn/develop skills and follows their domain routing → distills candidates through four gates (generalization, recurrence, root cause, durability) and shows its rejects → routes survivors to a skill / rule / memory / nothing → edits additively → verifies → ships via worktree+PR with human sign-off. Distinct from `reflect` (intra-session feedback recall, writes nothing).
- **`plugins/code/skills/learn/` + `commands/learn.md` (`/code:learn`)** — the code-plugin-specific layer on the `learn` engine: a routing map from a lesson to the right `code:*` skill, when a missing loop *verb* justifies a new skill, and a contract-safety rule for editing the composing `code:*` skills.
- **`plugins/code/skills/ship/` + `commands/ship.md` (`/code:ship`)** — the post-merge gate for distributables (VS Code extensions, npm/cargo CLIs, web apps): publish, confirm live on the public channel's API, activate where it runs, verify the real surface. Wired into `code:loop` ("merged is the middle, not the end" for distributables; added to its composed-tools list). Code plugin bumped 0.6.1 → 0.7.0.

### Changed
- **`skills/computer/SKILL.md`** — added an "Electron Editors (VS Code / VSCodium / Cursor)" section: AX `get-text`/`describe` work when Screen Recording is denied; reload a window to activate a freshly-installed extension; `type-text` not `type` into the palette; webview React buttons ignore AXPress and coordinate clicks; `@eN` ids are per-`describe`; verify activation from `exthost.log`.

### Docs
- Refreshed the skill/plugin inventories to match the current surface: `README.md` (skills highlights + `code` plugin command list), `skills/README.md` (new `learn` row), and `plugins/code/README.md` (added the missing `code:loop`/`code:review` rows alongside `code:ship`/`code:learn`, and a ship step in the manager loop).

## [0.1.30] - 2026-06-25

### Changed
- **`commands/finish.md`** — folded the sharp anti-stall enforcement from a personal-repo `/next` command into `/finish` (rather than ship a second near-duplicate "stop stopping" command). Expanded the "Forbidden endings" list with the trailing-question stalls `/next` named ("Want me to continue?", "Should I do X next?", "Stopping here — let me know if you want more", and any steering-wheel-handback question), and added a new **"Required instead"** block: every turn ends with an action — `"Next: [doing X]"` with the tool call in the *same turn*, never a question — with `AskUserQuestion` reserved for genuine forks (forward-moving options only, never a "stop" option). `/finish` is now the single canonical anti-stall driver that ships to users; no separate `/next` is added (it would duplicate `/finish`).

## [0.1.29] - 2026-06-25

### Added
- **`commands/done.md`** — added a **"Update Docs"** step (new Step 4; Commit/PR → Release → Task Management → Handle Remaining → Recap renumber to 5–9). Graduated from a richer personal-repo `/done` so it ships to all users via the system layer: walk every changed file and update the docs that move with the code (`AGENTS.md`/`README`/`docs/`/`CHANGELOG`/help text/in-code descriptions), with an explicit "what does NOT need docs" list and anti-patterns (don't spawn new `.md` files, don't duplicate, don't write tutorials in the map file). The closing recap (Step 9) now expects a justification when the docs step is skipped. References use the system `/tickets` command (not the personal `/issues`).
## [0.1.28] - 2026-06-25

### Changed
- **De-dup of the command sprawl** in the completion/ship cluster (audit-driven). No behavior is lost; duplicates collapse to a single source of truth.
  - **`commands/commit.md` is now a thin alias of `/code:commit`.** The two had drifted — root `/commit` was the older "stage all + conventional message" version (67 lines), while `plugins/code/commands/commit.md` is the canonical superset (max micro-commit splitting + secrets/binary gate, 92 lines). `/commit` keeps its ergonomic name but now forwards to the one canonical definition; behavior changes go in the `code` plugin only.
  - **`commands/review.md` is now a thin alias of `/code:review`.** Same story — root `/review` (295 lines) duplicated the canonical `plugins/code/commands/review.md` (305 lines, adds anti-overengineering guardrails + a security pass on risk-touching diffs). `/review` keeps its name and forwards.
  - **`/done` and `/finish` now cross-reference and own one job each.** Added a "which one" pointer to the top of both: `/done` = closing checklist + ship gate (verify → commit → PR → optional release → close tickets, then ask what's next); `/finish` = anti-stopping driver (refuses to stop at a recap/blocker/partial handoff; no release step). Both point at `/code:loop` for draining a queue to merged.
  - **`code:loop` now documents its single-item "land one branch" mode** (`plugins/code/skills/loop/SKILL.md`), so there is no need for a separate `/land` or `/merge` command — landing one branch is `/code:loop` with a queue of one. Records the decision not to add `/code:land`.
  - Updated `README.md` and `commands/README.md` to label `/commit` and `/review` as aliases.

## [0.1.27] - 2026-06-25

### Changed
- **`plugins/git`** (plugin `0.1.0` → `0.2.0`) — built out the `git` plugin as the canonical home for pure git plumbing.
  - **Renamed `/git:cleanup` → `/git:prune`** so the plugin command matches the always-on top-level `/prune` (they remain twins that coexist, same as root `/commit` vs `code:commit`). Command logic and data-loss guards are unchanged — only the name moved (`commands/cleanup.md` → `commands/prune.md`).
  - **Added `/git:tag-release`** (`commands/tag-release.md`) — creates an annotated git tag for a release and pushes it to `origin`. Resolves the version from `$ARGUMENTS`, else the newest `CHANGELOG.md` heading, else `package.json`, else a confirmed bump of the last tag. Pure git plumbing: only `git tag -a` and `git push <tag>` — never force, never `--tags`, never deletes or re-points an existing tag (stops if the tag already exists). Delegates full package publishing (npm/CDN + changelog + build) to the `release` skill; this is the git-tag slice only.
  - Updated `plugin.json`, the plugin README, and the `marketplace.json` entry to describe both commands.
- Intentionally left out of the plugin: `/commit` (charter keeps it in `code`), the `git-workflow` skill (referenced by the always-on rules, so it stays an always-available system skill, not opt-in), and `/rebase-clean` (the `git-guard` hook denies `rebase` outside worktrees and interactive rebase is unsupported in-harness).

## [0.1.26] - 2026-06-24

### Added
- **`plugins/git`** — the `git` plugin now ships as a system default (migrated from `.agents-extras`). Pure git plumbing that isn't tied to code logic. Ships one command today, `/git:cleanup`: deletes merged branches and worktrees locally and on `origin` behind hard data-loss guards — it skips any worktree with uncommitted changes, a non-empty stash, unmerged commits, a lock, or a detached HEAD, and uses `git rev-list --count origin/$MAIN..HEAD == 0` as the load-bearing "nothing to lose" check (strictly stricter than `git branch --merged`, so squash-merged branches are treated as unsafe). Never uses `--force` on branch deletes or worktree removes; always shows the plan and asks before acting. Registered in `.claude-plugin/marketplace.json`. This is the future home for other git-only workflows (`/tag-release`, `/rebase-clean`); the code-aware loop (`/commit`, `/code:review`, `/code:sprint`) stays in the `code` plugin. The standalone top-level `/prune` command remains as the always-on default — same coexistence the repo already keeps between root `/commit` and `code:commit`.

## [0.1.25] - 2026-06-24

### Fixed
- **`plugins/code/skills/sprint/SKILL.md`** — the "Sibling references" section pointed at a `/swarm` command that does not exist; corrected to `/teams`, the actual parallel-teams command.
- **`plugins/code/.claude-plugin/plugin.json`** — removed an invalid `skills` field that is not part of the plugin manifest schema.

## [0.1.24] - 2026-06-23

### Fixed
- **`hooks/03-linear-inject-tasks-context.sh`** — the SessionStart hook read Linear credentials with `security find-generic-password` (macOS Keychain), a binary that **does not exist on Linux**, so on Linux it printed `Linear credentials not found in Keychain` on every single session start. It now reads via `agents secrets get linear-api-key` / `linear-team-id`, which routes through the CLI's cross-platform keychain layer (macOS Keychain, Linux libsecret + encrypted-file fallback). macOS items stored by the previous `security -s linear-api-key` convention are read transparently (identical account+service lookup), so no migration is needed. The "not found" hint now points at `agents secrets set …`. Requires agents-cli with `secrets get/set` (phnx-labs/agents-cli#359).

## [0.1.23] - 2026-06-23

### Added
- **`commands/finish.md`** — the `/finish` command, ported from `.agents-extras` as a system default. An execution intervention (not a recap): recover the original contract from the conversation, convert each open item to a next action with evidence-backed verdicts, take the next action immediately, verify end-to-end on the real flow, ship, and keep going until the task is delivered or a hard external blocker is proven with three quoted attempts. Complements `/done` (which *checks* whether work is complete) by *driving* it to completion. Lightweight, no deps.

## [0.1.22] - 2026-06-23

### Added
- **`plugins/code`** — the `code` coding-workflow plugin now ships as a system default (graduated from `.agents-extras`). Bundles six skills (`dispatch`, `loop`, `review`, `verify`, `sprint`, `quality`) and their slash commands plus `/commit`: `/code:loop` drains a ticket/bug/TODO queue end-to-end (plan, code, test, review, rebase, fix CI, merge), `/code:dispatch` triages a single task and picks the delivery path, `/code:verify` runs the end-to-end gate from the project's canonical test per changed surface, `/code:review` reviews every PR opened in a session in parallel (with a security pass on risk-touching diffs) and merges per verdict, `/code:sprint` runs a time-boxed multi-track push via `agents teams`, `/code:quality` runs a read-only code-health diagnostic and opens an HTML report, and `/commit` splits the working tree into the maximum number of small logical commits. Registered in the new `.claude-plugin/marketplace.json` (marketplace `agents-system`); the system layer now tracks a `plugins/` directory.

## [0.1.21] - 2026-06-22

### Changed
- **`commands/test.md`** — the parallel-team step was modeled on the old `/debug` verification panel ("validate"/"synthesize"), which is the wrong shape for testing. Reworked into **Parallel Test Authoring**: the team now exists to *cut wall-clock by writing tests concurrently*, not to review. The lead decomposes the surface into slices that map to **separate test files** (so no two agents edit the same file), hands each a `parallel-teams` boundary contract (**Owns** / **Must NOT touch** / **Shared fixtures**, one canonical fixture owner), and spawns them in **`--mode edit`** to author in parallel. Vendor variety is explicitly *not* the goal here — throughput is. The lead then owns a mandatory integration pass: read each slice, **run the full suite itself**, write the cross-slice end-to-end flows no single author owned, dedup overlapping coverage, and report real pass/fail counts ("written" is not "passing"). Output reorganized around slices + a quoted suite result.
- **`commands/plan.md`** — Step 7 "Early Design Review" was *Recommended* (so it got skipped), `claude`+`codex` only, blinded with one line, and reconciled with four soft bullets. Replaced with **Independent Design Panel -> Adjudicate**, which runs **automatically** for medium+/architectural/unfamiliar work. Instead of a team *critiquing the lead's plan* (which anchors reviewers on its framing and lets their mistakes feed straight in), a vendor-varied panel (`codex`/`gemini`/`cursor`/`claude`, `--mode plan`) each produces a **full independent plan**. The brief is an explicit **SHARE / WITHHOLD** contract: planners get the goal, constraints, files to read, and the *factual* primitives inventory — but never the lead's approach, artifacts, or file-by-file plan (each named so it can't slip in). The lead then **adjudicates one merged plan**, adopting an idea only after verifying it against the actual code (file:line) — so a reviewer's error loses that point rather than corrupting the plan — and treating its own plan as one candidate among N, not the privileged answer. Genuine trade-offs become `AskUserQuestion` design questions; the Output gains an **Independent Plans** (adopted / rejected-with-reason / design-question) section.

## [0.1.20] - 2026-06-22

### Changed
- **`commands/debug.md`** — the independent-verification step is no longer an optional afterthought the agent had to be *told* to run. Restructured into seven phases where Phase 5 ("Independent Blind Review") fires **automatically** for any non-trivial bug, so the lead never stops to ask "should I spin up a team?". The lead now must commit to a defensible root cause itself first (Phase 4 is a gate — read the existing logs yourself, name a file:line), *then* spawn a panel via `agents teams … --mode plan` (read-only) to pressure-test it. The blinding is now an explicit **SHARE / WITHHOLD** contract: reviewers get the symptom, verbatim error, repro command, and *where to look* — but never the lead's root cause, mapped data path, hypothesis, or proposed fix (each named so it can't slip into the brief). **Variety across vendor agents (`codex`/`gemini`/`cursor`/`claude`) is the hard requirement** — three copies of one agent share blind spots; reviewer count is left to the lead's judgment, scaled to the bug's breadth. New Phase 6 ("Reconcile & Strengthen") builds a convergence matrix: independent agreement → report with high confidence; divergence → re-read the disputed file:line (the lead's own theory isn't privileged); a reviewer's new finding → folded into the report. The Output gains **Confidence** and **Independent Review** sections. This codifies, as the default flow, what previously had to be requested by hand every time.

## [0.1.19] - 2026-06-18

### Changed
- **`hooks/git-guard.sh`** — *starting* a rebase is now allowed when it runs inside an isolated worktree (`<repo>/.agents/worktrees/<slug>`), detected via the worktree path in the command (`git -C <wt> rebase`, `cd <wt> && git rebase`) or the session cwd already being inside one. Rewriting history on a branch nothing else uses, off the user's main checkout, is the blessed worktree flow — and `git push --force-with-lease` was already permitted, so the rebase round-trip now works end to end. Starting a rebase anywhere else (notably the primary checkout) stays denied. This is the natural successor to 0.1.18, which had only un-blocked *finishing* an in-progress rebase.

## [0.1.18] - 2026-06-14

### Changed
- **`hooks/git-guard.sh`** — finishing an in-progress rebase is now allowed (`git rebase --continue` / `--skip` / `--abort` / `--quit` / `--edit-todo` / `--show-current-patch`); only *starting* a rebase stays denied, since that's what rewrites history. Hand-resolving conflicts and advancing the sequence is safe and was previously blocked outright.
- **`.gitignore`** — ignore the local-only `/tests/` directory.

## [0.1.17] - 2026-06-14

### Fixed
- **`README.md` resolution table omitted the extras layer.** The real precedence is `project > user > extras > system`, but both the layer table and the resolve line listed only three layers. Added the extras row and corrected the order.

### Added
- **`README.md` "Going further: extras bundles" section.** New users land on this README but had no pointer to the heavier opt-in workflows (parallel coding loops, branded media, git plumbing). Documents `agents repo add gh:phnx-labs/.agents-extras` and why those skills stay out of system (heavier deps + paid keys; the default install stays fast and OS-portable). This is the deliberate alternative to porting them in — an investigation found each extras plugin is blocked from a system port for a concrete reason: `git:cleanup` duplicates the existing `/prune` command; the `code` plugin collides with the built-in `/loop` and `/verify` skills and overlaps system `/review` `/commit` `/test`, and its `code:` namespace is load-bearing; `creative` carries brand references plus Remotion/ElevenLabs/paid-API dependencies and is documented as intentionally kept out.

## [0.1.16] - 2026-06-14

### Added
- **`skills/git-workflow/`** — new skill holding the full PR worktree lifecycle: create the branch under `<repo>/.agents/worktrees/<slug>/` from the real default branch, work and verify end-to-end inside it, open the PR, wait for review, clean up after merge — with the bash recipes. Auto-loads on PR/worktree triggers; also invocable as `/git-workflow`.

### Changed
- **`rules/subrules/git-workflow.md` slimmed 40 → 10 lines.** The procedural bash (worktree creation, push, PR, after-merge cleanup) moved into the new `git-workflow` skill. The always-on rule now keeps only the behavioral invariants plus the correctness-critical "resolve the default branch dynamically (`git symbolic-ref refs/remotes/origin/HEAD`), never hardcode `main`" guard and a pointer to the skill. `rules/AGENTS.md` dropped 195 → 165 lines (1856 → 1749 words): less procedural detail diluting the always-on hard lines, with the full recipe one auto-load away. Establishes the pattern — invariants stay always-on, procedures load on demand.

## [0.1.15] - 2026-06-14

### Fixed
- **Broken rule cross-references.** `rules/subrules/parallel-teams.md` pointed at a `swarm` slash command that doesn't exist → now `/teams`. `rules/subrules/git-workflow.md` pointed at a `git-session-export` skill that doesn't exist → now the real `sessions` skill. Regenerated `rules/AGENTS.md` (with its `CLAUDE.md`/`GEMINI.md` symlinks) from the subrules; it stays a byte-exact concatenation in preset order.
- **macOS-only assumptions in the always-on rules.** `operational.md` and `tech-stack.md` hardcoded `pbcopy`, "use `find` on macOS (use `fd`)", and "macOS Keychain" — which break the very first clipboard/secrets/file-find action for Linux and cloud agents. Clipboard hand-off now lists `pbcopy` (macOS) **and** `xclip`/`wl-copy` (Linux); credentials read "OS keychain-backed"; the finder note no longer assumes the OS.

### Changed
- **`commands/README.md` and top-level `README.md` reconciled with the filesystem.** Both advertised phantom commands with no file (`/audit`, `/design`, `/redesign`, `/product`, `/secrets`, `/sessions`, `/spawn`) and omitted real ones (`/done`, `/prune`, `/review`). Tables now list exactly the 12 shipped commands; a note clarifies `/secrets`, `/sessions`, `/audit`, `/design` are skills, not commands. Top-level skills table expanded from 4-of-13 to a representative set pointing at `skills/README.md` as the source of truth.
- **`skills/README.md`** — added the four undocumented skills (`routines`, `run`, `secrets`, `sessions`); table now covers all 12.
- **`commands/continue.md`** — dropped the "don't use the older `/sessions` skill" line that contradicted the skill still shipping; now just names the `agents sessions` CLI as the context-recovery tool. Normalized command-description em-dashes across `continue`, `plan`, `recap`, `test`.

### Removed
- **`skills/composer/`** — empty, untracked phantom directory (no `SKILL.md`). The real composer skill lives in the `creative` plugin, not system.

## [0.1.14] - 2026-06-12

### Added
- **`skills/docs/`** — ported the documentation skill: `SKILL.md` plus `write-changelog.md`, `write-onboarding.md`, `write-runbook.md`, `write-technical.md`, `write-user.md`. Methodology is "less is more — only document what code can't tell you." Scrubbed of brand-specific file-path examples (generic `src/agent/execution.go` instead of internal paths).
- **`skills/reflect/SKILL.md`** — ported the reflect skill: enumerate every piece of feedback (REJECTED / CORRECTED / CONFIRMED / CONSTRAINT) from the conversation, identify the connecting thread, state the revised approach, then execute with all constraints active simultaneously. Brand-specific example constraint genericized.
- **`skills/release/SKILL.md`** — ported the release skill: discover repo structure, scaffold build/release scripts if missing, run tests, update changelog, publish to npm/CDN, and tag. Supports monorepos and semver prereleases. Scrubbed of internal package names and author metadata (generic `@your-scope/your-package`, `packages/app` examples).

### Changed
- **`commands/issues.md` → `commands/tickets.md`** — renamed the tracker command from `/issues` to `/tickets`. Auto-detect behavior across Linear/GitHub/Jira is unchanged. Updated every reference in `rules/AGENTS.md`, `rules/subrules/conventions.md`, `rules/subrules/tech-stack.md`, `README.md`, `commands/done.md`, `commands/recap.md`, `commands/continue.md`, and `commands/README.md`.
- **`skills/browser/SKILL.md`** — merged the generic "Adding a new domain-skill" workflow from the user copy (check `browser-use/awesome-prompts` upstream first, scaffold `domain-skills/<site>/`, match by directory name or explicit `domains:` array, auto-discovery via `agents browser start --url`). Scrubbed brand-specific app entries from the routing table; did not bring over the personal `app-skills/` or `domain-skills/` directories.

### Removed
- **`skills/scripts/`** — dropped the scripts skill. It encoded a convention (canonical `build.sh`/`test.sh`/`release.sh` layout), not an invocable capability, so it moves to the user's personal rules. Repointed the `tech-stack` tools table (and `rules/AGENTS.md`, `rules/rules.yaml`) from the `scripts` skill to the new `release` skill.

## [0.1.13] - 2026-06-11

### Added
- **`skills/computer/SKILL.md`** — new skill teaching agents the `agents computer` macOS automation surface: observe → act → verify loop, AX mode vs coordinate mode (origin/scale pixel mapping for AX-opaque surfaces like Parallels VMs and canvas editors), focus discipline (`raise` first, `--require-frontmost` on keyboard verbs, `frontmost:false` means dropped keystrokes), failure-mode playbook (`not_frontmost`, `window_offscreen`, `element_stale`, `rpc_timeout`), worked Windows-VM example, and safety rails (secure-field guard, hard-denied system surfaces). Mirrors agents-cli PR #258.

## [0.1.12] - 2026-06-11

### Added
- **`skills/secrets/SKILL.md`** — new section "Multiple Accounts on One Website": one domain-named bundle per site (`x.com`), keys grouped by account handle (`THEMUQSIT_USERNAME` / `THEMUQSIT_PASSWORD`, plus `_EMAIL` / `_TOTP_SECRET`), per-key `--note` recording when an agent should use each account. `view` prints notes in the clear with values masked, so agents pick the right account before revealing anything; reveal one pair via `export --plaintext | grep '^HANDLE_'` or bind the bundle to a browser profile (`agents browser profiles create -s <bundle>`). Mirrors agents-cli PR #255.

## [0.1.11] - 2026-06-08

### Added
- **`rules/subrules/operational.md`** — new rule: "Hand off commands the user must run — don't just print them." Markdown code fences aren't executable. Preferred order is pipe to `pbcopy` and tell the user it's copied; write a one-shot script to `/tmp/<slug>.sh` for anything multi-line; render the command inline only as last resort. Always quote what was copied so the user can verify before pasting.

### Changed
- **`rules/subrules/git-workflow.md`** — worktree recipe now fetches the actual default branch (`remote set-head origin --auto` + `symbolic-ref refs/remotes/origin/HEAD`) instead of hardcoding `origin/main`. The hardcode broke worktrees in repos whose default branch is `master`, `trunk`, etc.
- **`rules/AGENTS.md`** (and `CLAUDE.md`, `GEMINI.md` symlinks) — regenerated from subrules in preset order to pick up the new hand-off-commands rule and the worktree recipe update.

## [0.1.8] - 2026-06-07

### Added
- **`cli/linear-cli.yaml`** — first system-level CLI manifest. Declares `phnx-labs/linear-cli` as installable via `agents cli install linear-cli` (curl-bash one-liner from the upstream `install.sh`). Touch ID / Keychain integration is the CLI's own concern; the manifest just gets the binary onto PATH.

### Changed
- **`commands/issues.md`** — added a Step 2 "Installed CLI" check (`linear`, `gh`, `jira`, `glab` on PATH) ahead of the repo-signal probe, and pointed Linear detection at `agents cli install linear-cli` when the binary is missing. New anti-pattern: don't silent-install tracker CLIs — always confirm, since wrong-tracker false positives are real.

## [0.1.7] - 2026-06-03

### Changed
- **`rules/subrules/git-workflow.md`** — adopted earlier (commit 6a0a92a): worktrees now standardized at `<repo>/.agents/worktrees/<slug>/` with a full PR-open-but-don't-clean-up-until-merge lifecycle. This release trims the recipe (86 → 70 lines) and replaces the `[[git-readonly]]` wiki-link with a bare reference for cross-ref consistency.
- **`rules/subrules/operational.md`** — clarified the ask-vs-decide boundary. New rule: ask about scope (requirements, priorities), decide about implementation. Resolves apparent conflict with `workflow-proactive`'s "decide, state reasoning, keep going."
- **`rules/subrules/conventions.md`** — clarified ticket boundary: linear hook auto-injects context at session start; `/issues` is the explicit-action surface across Linear/GitHub/Jira. Dropped duplicate `scripts` skill mention (kept in `tech-stack` tools table).
- **`rules/subrules/workflow-proactive.md`** — gained the "Design before code" section, moved from `testing-strict.md` where it didn't belong topically.
- **`rules/subrules/testing-strict.md`** — slimmed: "Design before code" relocated (above).
- **`rules/subrules/parallel-teams.md`** — slimmed: the "After" bullet list collapsed into one line; the long-form playbook already lives in the `swarm` command.
- **`rules/subrules/tech-stack.md`** — slimmed: dropped the off-theme "LLM tool design" section (meta-guidance about building tools, not using them).
- **`rules/subrules/core-hard-lines.md`, `code-quality.md`, `operational.md`** — added one-line "Tier N of 3 — companion tiers" breadcrumb at the top of each tiered file so the tier structure is navigable.
- **`rules/AGENTS.md`** (and `CLAUDE.md`, `GEMINI.md` symlinks) — regenerated from subrules in preset order. The hand-maintained fallback was stale since 0.1.3 (May 13) and still referenced retired skills (`image-craft`, `linear`), the 24-rule scheme, and a `agents pty` recipe that's no longer in any subrule. Now matches the composed output.

## [0.1.6] - 2026-05-18

### Removed
- **`hooks/tests/`** — pytest suite for `02-expand-prompt-skill-refs.py`. The dir broke `agents add claude@2.1.143` sandbox image materialization: agents-cli walks `hooks/` with `fs.copyFile()` (file-only) and tripped EISDIR on the `tests/` subdir. Dev artifacts shouldn't live inside the runtime hooks tree. If we want a regression suite again, host it at repo-root `tests/` (outside the hooks walk) and rewrite the `Path(__file__).parent.parent` reference accordingly.

## [0.1.5] - 2026-05-17

### Added
- **`hooks/02-expand-prompt-skill-refs.py`** — UserPromptSubmit hook that expands `$skill-name` tokens in prompts into skill path + description. Searches `{cwd}/.agents/skills/` → `~/.agents/skills/` → `~/.agents-system/skills/` (first match wins). Per-agent protocol matches `02-expand-prompt-bang-commands.py` (Claude `<user-prompt-submit-hook>` replacement, codex/gemini JSON `additionalContext`).
- **`hooks/tests/test_expand_prompt_skill_refs.py`** — pytest suite for the skill-refs hook.
- **`agents.yaml`** — system-layer config: `run.claude.strategy: balanced`.

### Changed
- **`hooks/02-expand-prompt-skill-refs.py`** prunes `node_modules`, `.git`, `__pycache__`, `.venv`, `venv`, `dist`, `build`, `.cache`, `.tox`, `.mypy_cache` during `os.walk` to avoid descending into massive trees during fuzzy skill lookup.

## [0.1.4] - 2026-05-14

### Changed
- **`browser` skill restructured into multi-level subskills** — `SKILL.md` is now a router only; implementation detail moved to dedicated files.

### Added
- **`skills/browser/browser-use.md`** — full web automation reference updated to the new API (`AGENTS_BROWSER_TASK` env var, `tab add/focus/close`, `done`/`status`, `-t <tabId>` flag).
- **`skills/browser/electron-use.md`** — Electron desktop app automation: `--browser custom --electron` attach pattern, common gotchas (stale preload, hidden windows, no new tabs, debug port not exposed), `app-skills/` routing.

## [0.1.3] - 2026-05-13

### Changed
- **Rules ruleset tightened** to reduce compiled `CLAUDE.md`/`AGENTS.md` size. Prose trimmed across all 11 remaining subrules with no rule numbers dropped.
- **`rules/subrules/scripts-discipline.md` moved to a skill** at `skills/scripts/SKILL.md`. Agent invokes it when touching `scripts/`, `release.sh`, `build.sh`, or deploy/publish flows instead of carrying the contract in every session.

### Removed
- **`rules/presets/`** (`cautious.md`, `minimal.md`, `proactive.md`) — `rules/rules.yaml`'s `default` preset is the only one in use.
- **`rules/subrules/linear-tickets.md`** — `hooks/03-linear-inject-tasks-context.sh` already injects ticket context at session start; the rule was duplicative.
- **`rules/subrules/scripts-discipline.md`** — see above (moved to skill).
- **`rules/subrules/workflow-cautious.md`** — not referenced by any active preset.
- **`rules/subrules/product-mindset.md`** — not referenced by any active preset.

### Note
Users with `~/.agents/rules/subrules/{linear-tickets,scripts-discipline,workflow-cautious,product-mindset}.md` overrides at the user layer still get those rules — only the system-shipped copies were removed.

## [0.1.2] - 2026-05-13

### Security
- **PR session gist export defaults to secret, not public** (`commands/done.md`, `rules/subrules/git-workflow.md`). Session transcripts can leak repo internals, infra details, tool output, and bundle names. The previous `--public` default published this material to github.com/<user> as anonymously-indexable content. New default omits `--public`, producing a secret (URL-only) gist. Use `--public` explicitly only when the target repo is public AND the transcript has been reviewed for sensitive content.

## [0.1.1] - 2026-05-10

Public release cleanup. Streamlined commands, improved workflows, better documentation.

### Added
- **`/done` command** — comprehensive completion checklist: verify code, test E2E, commit, create PR with session gist, release if applicable, handle remaining items via tickets.
- **`/teams` command** — inline workflow for spawning parallel agents (single agent via `agents run`, teams via `agents teams`).
- **`/plan` enhancements** — web search for current best practices, user flows for UI features, primitive reuse requirement, optional early design review with agent team.

### Changed
- **Commands consolidated** — removed redundant skill redirects (`/secrets`, `/sessions`, `/teams` stubs) in favor of invoking skills directly.
- **`/spawn` removed** — use `agents run <agent> "prompt" --mode edit` for single-agent dispatch.
- **`/design`, `/redesign` removed** — covered by the `design` skill with multiple modes.
- **`/product` moved to rules** — now `rules/subrules/product-mindset.md` (opt-in, not in default preset).
- **Teams skill updated** — documents `agents run` for single-agent work.
- **README rewritten** — accurate command/skill tables, cleaner structure.

### Fixed
- Hooks documentation clarified: system uses `hooks.yaml`, user hooks go in `agents.yaml` under `hooks:` section.

## [0.1.0] - 2026-04-01

First tagged release. Consolidates agent configuration, permissions, hooks, and skills.

### Added
- **Stop completion gate hook** (`hooks/stop-completion-gate.sh`) -- blocks agents from claiming "done" without end-to-end verification. Extracts original user request from transcript, forces goal-by-goal self-audit before allowing session to end.
- **Permission rules for `2>/dev/null` redirections** -- read-only commands (`ls`, `cat`, `head`, `tail`, `wc`, `file`, `stat`, `which`, `grep`, `rg`, `readlink`, `diff`, `command -v`, `type`) now have allow patterns covering stderr suppression to `/dev/null`.

### Changed
- **AGENTS.md restructured by priority** -- rules reordered into 3 tiers by impact. "Done means it works end-to-end" promoted to Hard Line #1. Core workflow changed from `ACT -> SHOW -> CONTINUE` to `ACT -> VERIFY -> SHOW -> CONTINUE`. 8 sections consolidated to 5, 204 lines reduced to 144.
- **Private skills moved out of version control** -- skills with proprietary content (image-craft, writer, browser, linear, etc.) gitignored and managed separately.

### Fixed
- Cross-cutting changes rule promoted from buried Design Principles section to Hard Line #8.
- Testing section now cross-references Hard Line #1 to prevent "unit tests pass = done" loophole.
