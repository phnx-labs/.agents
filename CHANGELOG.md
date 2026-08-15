# Changelog

## [Unreleased]

### Changed

- **The git guardrails now protect the user's whole PRIMARY working tree, on any
  branch — not just the default branch — and ban `git switch` alongside `git
  checkout`.** Agents were checking out a feature branch in the user's own
  checkout and never switching back, stranding it on a branch dozens of commits
  behind (the `review-2704` trap); blocking only the default branch let that
  through, and `git switch` (the modern `checkout`) was not blocked by the hook at
  all. Changes:
  - **`hooks/lib/git-facts.sh`** — adds a fork-free `primary` fact (a primary
    working tree has `.git` as a directory; a linked worktree has `.git` as a
    file) and a `git_facts_in_primary_tree` accessor; cache format bumped v1→v2.
  - **`rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh`** — protects
    the entire primary working tree (any branch) instead of only the default
    branch. The gitignore exemption (`.history/`, `.agents/scratch|artifacts`) and
    the non-git and linked-worktree allowances are preserved; linked worktrees
    under `.agents/worktrees/` remain the one place agents write, add, and commit.
  - **`hooks/pre-tool-use/git-guard.sh`** — adds `git switch` to the banned
    subcommands (`checkout` was already banned), catching every dressed form
    (`git -C <path> switch`, `FOO=1 git switch`, `cd … && git switch`, `sh -c`).
  - **`rules/subrules/foundations.md`** (F5), **`.../truly-agentic-git-workflow/rule.md`**,
    and the composed **`rules/AGENTS.md`** updated to state the primary-tree rule
    and the switch/checkout ban, so the rule text matches the mechanism.
  - Permission layer (`permissions/groups/99-deny.yaml` → built `default.yaml`)
    already denied plain `git checkout` / `git switch`; the hook is what now closes
    the dressed forms the permission prefix-globs cannot match.

- **Regression debugging now identifies who caused the change and how it escaped review.**
  `/debug` and `/swarm:debug` invoke the existing read-only `/blame` primitive for
  regressions, then report the culprit commit/PR and diff, the lost or weakened test,
  the responsible agent/session, and whether the PR flagged the loss or let it slip
  silently. The fleet-wide research rule now makes that attribution part of debugging
  discipline instead of allowing an investigation to stop at the technical root cause.

- **An orchestrator now owns what it spawns, and an armed watcher is a claim it must
  verify.** Changes to `rules/subrules/parallel-teams.md`, `skills/teams/SKILL.md`, and
  `commands/dispatch.md` (plus the regenerated `rules/AGENTS.md`). The failure they
  prevent, measured in session `ea913c60` on 2026-08-15: the orchestrator backgrounded a
  `while true; do … done` poll over `agents teams status`, told the user *"the background
  poll re-invokes me when the team settles, and I verify every PR's terminal state before
  reporting anything as done"* — and `ps` showed **no such process**. Four teammates were
  still `RUNNING` with nothing watching them. The session was idle while asserting it was
  not, which is the shape the owner reports as the single biggest source of lost time:
  *"they spin up sub-agents and then sit idle. They don't track if they're making
  progress. They don't even check if they were properly spawned."*
  The root cause was a gap in this repo's own text, not agent invention alone: both the
  teammate brief and the orchestrator contract said only *"keep waiting with a background
  watch"* — naming no mechanism — while `operational` separately bans exactly the
  `while`/`until` loop an agent reaches for to satisfy it. The three files now name the
  mechanism (`agents monitors add` for durable watches; a backgrounded command with a
  trailing finish-echo in-session), ban the silent-death loop forms outright, and require
  the postcondition: confirm each teammate actually reached `RUNNING`, then prove the
  watcher is alive (`agents monitors list`, `ps -p <pid>`) before telling anyone you are
  watching. They also separate progress-checking from debugging — `agents teams status`,
  `gh pr list`, and `git ls-remote` answer "is it moving?", while `agents teams logs` /
  `agents hosts logs` bill a teammate's whole transcript back as input and are reserved
  for grepping a failure — and name the stall case (`RUNNING` for 27 minutes with no
  branch pushed) as something to resume or re-dispatch rather than keep waiting on.

- **`/recap` closes the loop before it writes, and writes a back-from-vacation summary.**
  Two changes to `commands/recap.md`. First, a mandatory ordered step before any output:
  close every ticket the session delivered (with proof), file every follow-up it was about
  to *suggest* as a real ticket under its project, then confirm one owner update went out.
  The harness notifies the agent when a turn ends and never notifies the owner, so a recap
  that lives only in the session window reaches nobody. That third step routes through the
  fleet's existing single path — `agents feed post --level important`, which
  `feed.broadcast.owner` forwards to `agents notify` — and says explicitly that the
  `verify-work-complete` Stop hook's own close-out post *is* that update. Firing an
  independent notify here would have meant two phone buzzes per session for one delivered
  piece of work, multiplied across every concurrent agent.
  Second, the output shape. It was an engineering status report (Situation / In Progress /
  Hypotheses / Recommended Next Steps) written for someone who had watched the session;
  it is now the back-from-vacation summary F4 asks for — Project, What you asked for, What
  landed, What did not land, Still open, Needs you — written for a reader with zero
  context. The existing filters (HARD RULE 1/2, no wastebasket bullets, decide-or-delegate)
  carry over onto "Needs you", and the ticket-closing bullet that used to sit in the
  "execute first" examples is gone now that it is a required step. Historical-session mode
  is explicitly exempt: it transfers context and must not close another session's tickets
  or notify the owner about work it did not do.

### Fixed

- **Visual delivery read-back (`hooks/stop/visual_readback.py`, `verify-work-state.py`,
  `verify-delivery-chain.py`, and `00-agent-verify-work-complete.sh`).** A visual artifact
  authored under `/tmp` and sent with `scp`, `rsync`, `agents share`, or `open` now counts
  as a delivery. Narrow final-message claims such as “what you're looking at” require a
  paired image result after the latest render, including on the first
  `stop_hook_active` retry. The advisory `pre-tool-use/11-visual-readback-nudge.py` names
  the headless `agents browser` path without blocking transport commands.

- **UI rules now render without stealing focus.** `rules/subrules/ui-work-discipline.md`
  is included in `rules/rules.yaml`; it directs workers to a bare headless
  `agents browser` render, screenshot, and read-back. `plan-presentation` now renders and
  inspects every plan but opens it on the interactive host only when requested.

- **The repository pre-commit hook refuses local output under `.agents/`, while reviewed
  plans remain trackable under `.agents/plans/`.** It names offending additions or
  deletions before a commit can distribute per-machine agent output fleet-wide.

- **Stop hook: the command-handback gate stops false-firing on paste-into-a-form and
  send-a-message handoffs.** `00-agent-verify-work-complete.sh` blocked a stop when the
  session had written a script to a temp path AND the final message told the user to
  "run/paste" something. The "directs the user to run" side was too broad: it matched
  ordinary prose with pronoun objects, so a message like "paste that blurb into the
  application" or "paste it in and hit send" (an email the user must send under their own
  identity) tripped it, even when the temp script was the agent's own helper it had
  already run. The gate now **excludes the two shapes that are not running a command**:
  pasting/typing text into a UI form/field/composer, and sending a message/email/reply
  under the user's own identity (exempted like a biometric/login). It does this by
  excluding those patterns rather than demanding a positive command cue, which preserves
  recall: a plain "just run it when you're ready" after a temp-script write is still a
  handback and still blocks. The canonical target (`run /tmp/release.sh`, `paste it into
  your shell`) blocks; four new tests pin the false positives and a recall guard pins the
  cue-less handback.

### Added

- **F3 (done-ness): a message or application is done only when it is staged where it gets
  sent.** New `foundations` bullet. For a reply / reach-out / apply / DM task, done means
  the message is in the channel the user sends from (a draft in the Gmail or InMail thread,
  the LinkedIn or application composer), not draft text in a scratch `.md` file. "I wrote
  the reply" is not "ready to send", and calling a pile of `.md` drafts "send-ready" is the
  miss this bullet closes.

- **`code:refactor` gains a seventh move: give the concept the contract its job calls for.**
  The six existing moves all ask where code *lives*; none asked whether a concept has the
  *shape* its job needs. The recurring miss: a family of variants dispatched on by name
  (`if (agent === 'claude') … else if (agent === 'codex') …`) where the job actually calls
  for the provider pattern — one declared contract plus one implementation per variant in a
  registry. The skill now carries the language-agnostic table (Go `interface`, TS
  `interface` + discriminated union, Python `Protocol`/`ABC`, Rust `trait`, Java/C#
  `interface`, Swift `protocol`) and the payoff that matters for agent throughput: adding a
  variant becomes one file plus one table entry, and the type system names what is missing
  instead of a reviewer noticing that three of eleven call sites were never updated.
  New `patterns.ts` finds these mechanically — per discriminator family it reports members,
  `arms` (the hand-branches that would collapse), whether a contract and a registry exist
  with `file:line` for each, the provider directory and its coverage, capability holes, and
  a verdict. On `agents-cli` (`--scope apps/cli/src`) it reports 101 families:
  2 exemplar, 10 **bypassed**, 49 partial,
  40 missing, **1,906 collapsible arms**. The headline case is
  `agent` — 20 variants, **287 hand-branches**
  (14.3 per variant), while the contract (`apps/cli/src/lib/session/types.ts:11`) and a real
  registry (`apps/cli/src/lib/add-dir.ts:32`) already exist and are simply routed around. That is what
  the `bypassed` verdict is for, and it is the most valuable of the four because it needs no
  design decision — just moving call sites onto a table that already exists, which is exactly
  the behavior-preserving change this skill lands.
  `lib/terminal` is the closest thing to a model in this repo — contract and registry at
  `apps/cli/src/lib/terminal/backends/index.ts:19` with one file per backend. It is graded **bypassed**, but read
  that number carefully: the `backend` row carries 61 arms in total and only
  **9** of them are in `lib/terminal` — the rest belong to an unrelated secrets `backend`
  that collides on the variable name (`arms_by_area` now shows the split: commands 27,
  lib/secrets 22, lib/terminal 9). That collision is why `patterns.ts` emits `arms_by_area`
  and `area_concentration` at all: a merged row read as one family overstates it, which is a
  mistake this entry made twice before the data made it visible. The skill says to cite the
  shape, not the verdict, and to prefer an in-repo model over any textbook pattern: "look like
  that one" is a change an agent can make by pattern-matching.
  Two rules come with it. **A feature of the family belongs in the contract, not beside it** —
  multiplexing sitting next to the terminal backends, retry next to the transports, caching
  next to the stores is a capability of the abstraction that never got declared; fold it in
  so a variant either supports it or says it does not, and `capability_holes` can see the gap.
  And a new hard line: **never force a contract onto variants that do not share one** —
  `patterns.ts` leaves `same_contract: null` on purpose, because forcing it produces the
  eight-boolean `doThing(opts)` that the consistency-beats-DRY bias exists to prevent.
  Sequencing gained a step (contract before package extraction: a package with no declared
  contract exports its internals as its API) and the harm table now scores a missing contract
  with the worst — it is the defect an agent is most likely to make *worse* by hand, adding a
  twenty-second branch because twenty-one already existed.
  The detector went through two correction rounds against its own output, both caught by
  review: it first graded every family `exemplar` by falling back to "the first interface in
  the first file" (citing an unrelated `interface NpmPackageMetadata`), and then, once
  precise, it exposed that `bypassed` did not match its own documented definition, that
  `typeof x === 'string'` guards were inventing members, that `nameRelates` accepted
  `"headroom" ⊃ "head"`, and that optional-`export` matching reported local `const`s as
  missing capabilities. All fixed; every number above is read from the tool's output rather
  than asserted. Source: `plugins/code/skills/refactor/patterns.ts`,
  `plugins/code/skills/refactor/SKILL.md`, `plugins/code/commands/refactor.md`,
  `plugins/code/README.md`.

- **`/code:clean` becomes `code:refactor` — the architectural restructuring a product
  needs as it grows, not file-level tidying.** The old command was 113 lines of "search for
  cleanup opportunities in this priority order," which ranked by taste and never rose above
  single-file issues. The skill does the work a principal engineer does continuously: merge
  redundant concepts, extract the horizontal layer four modules each reimplemented, draw a
  module boundary that was never drawn, lift a cohesive core out into its own package/SDK so
  it is testable and reusable, reorganize the tree so it matches the architecture, and shrink
  an overgrown public surface. Hygiene (dead code, doc drift, oversized files) is explicitly
  the byproduct tier, ~20% of a plan; a plan that is mostly dead-code deletion means the wrong
  job got done.
  Three scripts supply the evidence. `modules.ts` builds a file-level import graph, folds it to
  modules, and derives god modules, module-level cycles (Tarjan SCCs), package-extraction
  candidates (high cohesion, low outbound coupling, small de-facto public API), and upward
  imports; on `agents-cli` it found `lib` at 193 files / 88,644 LOC with fan-in 1095 and 84% of
  its files imported from outside, **38 of 44 modules inside a single dependency cycle**,
  `lib/startup -> commands` 82 times, and `lib/terminal` as a clean extraction candidate
  (cohesion 0.84, 6 of 17 files forming its API, 3 outbound deps). `exposure.ts` joins git churn,
  file size, and real agent `Read`/`Edit` traffic from the fleet session index (`sessions.db`,
  `tool_calls`), folding `.agents/worktrees/<slug>/` paths back to repo-relative — without that
  fold every agent *edit* is dropped as untracked (1,385 recovered on `agents-cli`, moving
  `commands/inspect.ts` from ~30th on churn alone into the top 6). `surface.ts` walks a CLI's
  `--help` tree and grades each entry documented/tested/referenced: 337 command paths, 45
  top-level, 27 undocumented, 74 untested, 7 orphan candidates, 19 self-referential paths.
  Its two recursion guards are ancestry-scoped, never global — a global "seen this child set
  before?" check is wrong on exactly the CLIs this skill targets, because a well-shaped surface
  reuses one verb vocabulary across groups on purpose (`skills`, `permissions`, and `subagents`
  all offer add/list/remove/view), and a global check drops two of the three real groups. That
  bug cost 40 real commands in the first census.
  Moves are ranked `harm x exposure` and then **sequenced**, because architectural work has a
  dependency order: break cycles first (nothing extracts out of an SCC), merge concepts before
  drawing boundaries, extract the layer before the package, move the tree last. Every structural
  move ships a **before/after figure rendered with artifacts-cli** under a precision contract —
  every box is a real module at its real path with its real file/LOC count, every arrow is a real
  edge with its real import count, BEFORE and AFTER share node positions so the eye reads the
  difference, and numbers in the prose, the figure, and the graph JSON must be the same value.
  A figure that misstates the architecture is lying context, the exact defect the skill removes.
  Three biases decide the calls, two counterintuitive: consistency beats DRY (deduplicate
  *concepts*, not lines — two blocks are duplicates only when changing one is a bug if the other
  doesn't change), deletion beats abstraction (five-rung ladder; extracting a layer or package is
  rung 5 and legitimate only on evidence the concept already repeats with one meaning), fewer
  surfaces beat better docs. It calls `code:review` Mode C for file-level passes instead of
  growing a second copy. Source: `plugins/code/skills/refactor/SKILL.md`,
  `plugins/code/skills/refactor/{modules,exposure,surface}.ts`,
  `plugins/code/commands/refactor.md`, `plugins/code/README.md`, `plugins/README.md`,
  `commands/README.md`, `commands/AGENTS.md`.

### Fixed

- **`hooks/promptcuts.yaml` #275: `#debugit` is no longer swallowed into `#rethink`'s block scalar.** The shortcut key was mis-indented 6 spaces, so YAML parsed it as part of `#rethink`'s value, making `#debugit` / `!!debugit` a no-op and gluing the debug root-cause block onto every `#rethink` expansion. Re-indented `#debugit` to the canonical 2-space key + 4-space body and fixed the same mid-block drift in `#simplifyit`. Added `hooks/tests/promptcuts_test.sh` to assert the expected shortcut key set on every load so a swallowed cut fails loudly. Source: `hooks/promptcuts.yaml`, `hooks/tests/promptcuts_test.sh`.
- **`verify-work-complete` scopes PR refs to their repo (#264) and stops blaming
  no-op sessions for repo history (#245).** Bare-number PR refs used with
  `--repo owner/repo` now resolve against that repo, not the session cwd, closing
  the cross-repo collision that could falsely block or pass the open-PR stop
  gate. The delivery-chain gate also drops its `HEAD~10..HEAD` history fallback;
  it had attributed other sessions' commits to browser/ops/research sessions that
  made no repo change, producing false-positive "missing docs/CHANGELOG" blocks.
  Source: `hooks/stop/00-agent-verify-work-complete.sh`,
  `hooks/stop/verify-delivery-chain.py`,
  `hooks/stop/tests/00-agent-verify-work-complete_test.sh`.
- **`parallel-teams` brief feed line now matches the canonical `--title` form
  (#211).** `rules/subrules/parallel-teams.md`, `skills/teams/SKILL.md`, and
  `plugins/swarm/skills/orchestrate/SKILL.md` all carried the verbatim teammate
  brief line as a plain `agents feed post`, while `feed-status-posts.md` and the
  orchestrator examples require `agents feed post --title "<short subject>"`.
  The brief line now includes `--title`, and `rules/AGENTS.md` is regenerated.

- **Account guidance uses positional identity and target arguments (RUSH-2527).** Fleet sync, mint-auth, run, and agents-cli guidance now teach `accounts name <agent@version> <name>`, `attach <account> <target>`, and `sync <account> <device>` while keeping native OAuth material harness-owned.

- **`plugins/design/skills/design/interface-redesign.md` restored; `design-core.md` §4
  brand-probe now reads `BRAND.md` first (RUSH-2504 post-merge regression).** Two
  regressions introduced when PR #289 consolidated design: (1) The redesign options-gate
  — draw BEFORE, propose 2-3 distinct AFTER options with full ASCII layouts, fill a
  comparison table, then STOP and wait for the user's pick — was reduced to a single
  prose sentence in `interface.md` step 5, dropping the mandatory workflow. Restored as
  a companion file `interface-redesign.md` (ported from the deleted
  `create:design/design-redesign.md`), with `interface.md` step 5 routing to it.
  (2) The brand-probe cascade in `design-core.md` §4 listed 5 fall-through steps but
  never read `BRAND.md`, so a repo that defines its brand there fell straight to the
  house fallback. Added step 0: read `BRAND.md` at the repo root first, as the
  authoritative brand source. Source:
  `plugins/design/skills/design/interface-redesign.md` (new),
  `plugins/design/skills/design/interface.md` (step 5),
  `plugins/design/skills/design/design-core.md` (§4).

### Added

- **Bangcuts are on by default; promptcuts and bangcuts get stable public names (RUSH-2405).** `promptcuts` expands saved prompt shortcuts; `bangcuts` executes explicit backticked bang commands. Only `bangcuts` changes state here — it shipped `enabled: false` ("paste of untrusted text with a bang block is local RCE") and that line is now removed, so a prompt containing `` `!cmd` `` runs that command in the local shell on every machine, including a prompt injected by a watchdog, monitor, or another agent. `promptcuts` had no `enabled: false` on `main` and was already on; only its comments change. Turn either off from the user layer with `expand-bang-commands: {enabled: false}` / `expand-promptcuts: {enabled: false}` in `~/.agents/agents.yaml` plus `agents sync` — verified against `dist/lib/hooks.js:1562-1565`, which deletes a disabled hook before the registrar sees it. The `agents hooks enable|disable <feature>` CLI that would take the public names is **not shipped** (`agents hooks` has only `list|add|remove|view|profile`), so it is not documented as the off-switch. The internal manifest keys remain `expand-promptcuts` and `expand-bang-commands` so existing user-layer YAML keeps working. Source: `agents.yaml`, `hooks/README.md`, `hooks/promptcuts.yaml`, `hooks/registration_test.sh`.
- **Built-in `pr-merge-on-green` monitor (RUSH-2472).** A system-layer monitor
  that rebase-merges this machine's own pull requests once CI is green and a
  non-author has approved them. It is opt-in — shipped with no `enabled:` field,
  so the system layer keeps it DISABLED until `agents monitors enable
  pr-merge-on-green`, and a `~/.agents/monitors/` copy shadows it. The source is
  one `gh pr list --author @me` poll every 5 minutes (rate-limit friendly, no
  per-PR loop) filtered to APPROVED + all-checks-green PRs; the action dispatches
  `claude` to `gh pr merge <n> --rebase --delete-branch` (never `--admin`, never
  self-approve). Inert until agents-cli 1.22.36 (the system-monitors layer) ships
  on the release train — expected, and harmless meanwhile. Source:
  `monitors/pr-merge-on-green.yml`, `monitors/README.md`, `monitors/AGENTS.md`,
  the `monitor` row in `AGENTS.md`.

### Changed

- **Command-surface consolidation — retired the `git` plugin and three top-level commands.**
  Fewer, sharper primitives (the `distill to the fundamental operation` philosophy). Net:
  the `git` plugin is gone, `/clean` moved under `code`, `/done` is deleted, `/finish` is
  folded into `/next`, and the top-level `/restore` alias is dropped. Concretely:
  - **`git` plugin removed (plugin `0.11.0` → `0.12.1`).** `/git:prune` → **`/code:prune`**
    (`plugins/git/commands/prune.md` → `plugins/code/commands/prune.md`, body unchanged).
    `/git:tag-release` was **retired, not moved** — it duplicated the `code:release` skill,
    which already cuts and pushes the tag as its final step (`plugins/code/skills/release/SKILL.md`).
    The `plugins/git/` directory, its `README.md`, its `plugin.json`, and its
    `.claude-plugin/marketplace.json` entry are deleted.
  - **`/clean` → `/code:clean`** (`commands/clean.md` → `plugins/code/commands/clean.md`,
    body unchanged). No top-level `/clean` anymore.
  - **`/finish` folded into `/next`; `/finish` deleted.** `commands/next.md` gained a
    **Part A** — the old `/finish` drive-to-delivered ship gate (recover the contract →
    take the next action → verify end-to-end → docs/commit/PR/release-gate/tracker →
    no-stalling) — and keeps its next-task selection as **Part B**. `commands/finish.md`
    is removed.
  - **`/done` deleted.** Recap-then-exit is now `/recap` then `/self:close` — the exit
    primitive is unchanged. `commands/done.md` removed.
  - **Top-level `/restore` alias removed** (`commands/restore.md`). Re-opening crash
    windows is `/sessions:restore`; the canonical skill in the `sessions` plugin is
    untouched, and `/continue` / `/insights` aliases are kept.
  - Cross-references updated: `commands/README.md`, `commands/AGENTS.md`, `plugins/README.md`,
    `plugins/code/README.md`, `plugins/code/.claude-plugin/plugin.json`, root
    `.claude-plugin/marketplace.json`, `plugins/self/{README.md,commands/close.md,commands/hibernate.md,.claude-plugin/plugin.json}`,
    `plugins/sessions/{README.md,.claude-plugin/plugin.json,skills/restore/SKILL.md}`,
    `skills/sessions/SKILL.md`, `skills/learn/SKILL.md`, `commands/blame.md`, root `README.md`,
    and the `permissions/groups/12-self.yaml` comment (`permissions/default.yaml` rebuilt).
- **`verify-work-complete` evaluates the current goal instead of the entire
  session (RUSH-2113).** Each UserPromptSubmit boundary now records the transcript
  byte offset, and Stop classification plus delivery-chain checks read only the
  current goal's suffix. Authored or operated PRs remain session-owned in a
  separate SQLite ledger, while contextual tickets and observed PRs do not gain
  ownership. The hook also records compact gate/outcome/reason events so future
  effectiveness reports use structured telemetry instead of parsing injected
  prose. Existing version-1 databases migrate transactionally to version 2.
  Source: `hooks/stop/{verify-work-state.py,verify-delivery-chain.py,
  00-agent-verify-work-complete.sh}`, `hooks/stop/tests/`.

- **`pr-merge-on-green` monitor now retries a silently-failed merge instead of stranding the PR (RUSH-2488).** Its condition was `mode: match` (`[0-9].*`), which only re-fires when the mergeable-PR set *changes* — so if a dispatched merge failed silently (transient `gh` error, box down, agent crashes before merging), the PR stayed approved+green, the next poll's observation was identical, and the merge was never retried until some other PR incidentally re-triggered the monitor. It now uses `mode: every`, which fires every 5-minute tick that reports a non-empty set (empty stays silent) and re-fires while the same PR is still listed, so the merge is retried — bounded by the existing `rateLimit: 6/1h`. This is the "job that can no-op forever after a silent failure" case `unattended-verification` warns about. Requires the empty-safe `every` from agents-cli #2536 (>= 1.22.36); the monitor is opt-in and inert until then. Source: `monitors/pr-merge-on-green.yml`, `monitors/AGENTS.md`, `skills/monitors/SKILL.md`.

- **`plugins/design` is now the single design front door; the anticipate mode,
  anti-tells catalog, and brand identity are folded in (RUSH-2504).** Three
  competing design entries existed — this plugin, an older user-layer
  `create:design` skill, and a bare `create:design` command — and are now one.
  Added `skills/design/anticipate.md`: diagnose a flow's dead-end (terminal
  success, silent partial work, forced re-invocation, asymmetric confirms),
  propose the continuation as before/after ASCII, and stop — no implementation
  without approval. Added a 12-item anti-tells catalog (design-core §6): the
  aesthetic signatures that read as AI-generated (italic serif display,
  two-tone headlines, latin section markers, sodium-amber-on-warm-black,
  gradient-glow buttons, lucide-card grids, and the rest), with the working
  alternative for each — every mode now checks its render against it before
  calling it done. Added design-core §5: browse the live web via the `browser`
  skill for current inspiration instead of relying on frozen example files —
  this plugin never carried an `examples/` directory itself, but the older
  user-layer skill's hardcoded `examples/` (frozen product screenshots that go
  stale the moment they're written) were dropped rather than ported, in the
  companion PR below. Brand identity (`BRAND.md` — voice, positioning,
  references, anti-tells) now lives as part of the `system` mode, not a
  separate `brand` mode. `marketplace.json`'s design entry updated to match.
  Source: `plugins/design/skills/design/{design-core,system,anticipate,SKILL,
  asset,dataviz,deck,diagram,interface,critique}.md`, `plugins/design/README.md`,
  `plugins/design/commands/design.md`, `plugins/design/.claude-plugin/plugin.json`
  (0.1.0 → 0.2.0), `.claude-plugin/marketplace.json`. The duplicate
  `create:design` skill/command are removed from the user layer
  (`~/.agents/plugins/create/`), tracked separately.

- **Stop hook `verify-work-complete` no longer references the removed `agents pr
  land` command (RUSH-2466, RUSH-2473).** The durable PR-lander evidence the
  open-PR and keep-moving gates accept is now solely a native `ScheduleWakeup` /
  `Monitor` tool_use (the harness re-invoke path that outlives a headless agent).
  The `DETACH_LAND` string matcher — which cleared the gate on the command
  STRING regardless of whether the lander actually ran (RUSH-2473) — is deleted;
  the block messages now point agents at a native `ScheduleWakeup`/`Monitor` or
  `agents monitors enable pr-merge-on-green` instead of `agents pr land
  --detach`. Source: `hooks/stop/00-agent-verify-work-complete.sh`,
  `hooks/stop/tests/00-agent-verify-work-complete_test.sh`.

- **Plan presentation now gates Codex and requires product-faithful behavior evidence (RUSH-2425).** The `plan-presentation` subrule registers its reminder at both native plan-exit and Stop: Codex plan collaboration mode, which never emits `ExitPlanMode`, can no longer bypass the render gate. Plans declare `surface: internal|cli|web|native|api|workflow`; user-visible plans must render a semantic current/proposed comparison whose states are real captures or explicitly labeled faithful mockups. An unrelated architecture SVG no longer clears a CLI/UI plan. Source: `rules/subrules/plan-presentation/`, `skills/plan-render/`, `hooks/README.md`.

- **Hook tests moved into a `tests/` subdir of their own event dir (refactor, no
  behavior change).** `hooks/<event>/<name>_test.sh` is now
  `hooks/<event>/tests/<name>_test.sh`, so `ls hooks/<event>/` shows only the
  scripts that actually run on the harness event — the 15 per-hook tests across
  `pre-tool-use/`, `session-start/`, `stop/`, and `user-prompt-submit/` moved
  (`git mv`), plus `hooks/lib/git-facts_test.sh` for consistency. Every relative
  reference inside a moved test (the script under test, sibling helpers, and
  `agents.yaml`) got one extra `../`. `hooks/run_tests.sh` and
  `hooks/syntax_test.sh` now discover both the current `tests/` location and the
  legacy beside-the-script one; `hooks/registration_test.sh` needed no change,
  since its scan is one level deep and never descended into `tests/` anyway.
  Source: `hooks/AGENTS.md`, `hooks/README.md`, `AGENTS.md`.

- **Plan/artifact guidance: author directly, `artifacts new` is optional.** The
  `plan-presentation` rule and the `artifacts` skill said to scaffold with
  `artifacts new plan`, which nudged agents (especially weaker models) to run a
  scaffold step they don't need. `artifacts render` already auto-fills the
  provenance frontmatter (project · repo · branch · harness · agent · host ·
  session · date) from git + the agent env for any blank field
  (`validateMarkdown` → `detectArtifactContext`), so an agent authors the Markdown
  directly with only `kind` + `title` and render fills the rest + validates
  sections. Guidance now says so; `artifacts new` stays documented as an optional
  scaffold. Source: `rules/subrules/plan-presentation/rule.md`, `skills/artifacts/SKILL.md`.

- **Account guidance now matches bundle-backed accounts (RUSH-2470).** The
  `agents-cli` and `run` skills explain that one provider account is one
  prompt-free `agents secrets` bundle, document per-harness defaults and explicit
  worker sync, and distinguish those bundles from harness-native signed-in
  identities whose auth material is never copied.

- **Fleet plugin commands aligned to the bundle-backed account model (RUSH-2509).**
  Four files updated to match the `agents accounts add`/`sync` model from agents-cli
  PR #2470 and remove the old `agents secrets create auth --backend file` /
  `AGENTS_SECRETS_PASSPHRASE` recipe:
  - **`plugins/fleet/commands/mint-auth.md`**: step 4 now stores the minted
    setup-token or API key with interactive `agents accounts add <name> --provider
    <provider> --auth <type>` (or `--from-secrets <bundle>:<key>`); step 5
    verifies headless via `agents run --account <name>`; new step 6 copies the
    bundle to worker devices with `agents accounts sync <name> --device <target>`.
    No `AGENTS_SECRETS_PASSPHRASE`, no reserved `auth` bundle.
  - **`plugins/fleet/commands/sync.md`**: `agents repos refresh -y` (deprecated)
    replaced with `agents sync --yes --local`; its unattended path covers every
    installed version of every agent type. New step 4 reports
    account readiness gaps per device with exact `agents accounts sync <account>
    --device <device>` remediation commands and never copies credentials
    automatically.
  - **`plugins/fleet/commands/onboard.md`**: step 8 now stores credentials via
    `agents accounts add` / `agents accounts sync`; sanctioned-paths hard line
    and safety rules clarified.
  - **`plugins/fleet/README.md`**: command summary rows updated to match the new
    model.

- **`/plan` Step 6 no longer mandates ASCII mockups for UI changes.** The command
  told agents to draw each screen as an ASCII box (`+---+ | Logo | +---+`), which
  Muqsit's `ui-work-discipline` rule (his personal ruleset layer) forbids and which
  agents were told is "terrible" —
  a user cannot judge look-and-feel from pipes and dashes. Step 6 now requires a
  **real mockup** built with the `artifacts` CLI that reads like the actual product
  (probe the repo's design tokens), the user flow as a rendered inline-SVG figure
  (not ASCII), and 2-3 side-by-side variations with one-line tradeoffs for a genuine
  design choice. Source: `commands/plan.md`.

### Added

- **The reviewer defends the concept budget.** New hunt class: *a new concept where an existing one could have been extended*. Deliberately distinct from `Duplicate surface, bypassed seam` — that one is two ways to do one thing, this one is a new thing that should have been a parameter of an existing thing. Every new flag, command, config key, status value, type, or module is a surface every future reader learns and every future change keeps consistent, so it has to earn that cost. One test: could this be a value, mode, or argument of something that already exists? A `--json-pretty` beside `--json`, a `list-active` beside `list`, a `PendingRetry` beside `Pending` — variants wearing the costume of new concepts. The finding requires naming the existing concept by file:line and what the extension would be, so it cannot degrade into "do not add things"; a genuinely new operation is exactly what should be added. Source: `subagents/code-reviewer/AGENT.md`.
- **Review findings land on the diff lines, not in one wall of text.** `code:review` B6 now posts a single review through `POST /repos/{owner}/{repo}/pulls/{n}/reviews` with a `comments[]` array — one notification, each finding anchored to the line it is about. Findings are split first: `IN-DIFF` ones (the cited line is on the right side of this diff) become inline comments, `OUT-OF-DIFF` ones (an absent call site, an orphaned path, a missing test — often the most valuable) go in the review body with the verdict and the `Filtered:` line. The subagent's output format gained an `Anchor:` field so the split is stated rather than guessed. `event: COMMENT`, never `REQUEST_CHANGES` unless `formal-review` is passed, never `APPROVE`. If anchoring fails — stale `commit_id` after a force-push, a moved line — it falls back to the whole report as one comment and says why, rather than dropping findings. Source: `plugins/code/skills/review/SKILL.md`, `subagents/code-reviewer/AGENT.md`.

- **The `code-reviewer` subagent hunts the expedient mechanism.** A new class for the change that *works* and works by reaching around the surface built for the job — which is exactly why it survives review. Two faces. **Ambient global state instead of declared configuration**: a new env var carrying a flag, endpoint, toggle, or inter-process value when the project already has a config file, CLI flag, or function argument that owns it. The reviewer names why that is not a neutral choice — every child inherits the whole environment, a Linux co-tenant can read `/proc/<pid>/environ`, values land in crash dumps and any log line printing the environment, and anything in the process tree can silently *override* it, so it is a disclosure surface and a hijack surface at once, invisible to whoever reads the config expecting to see current behavior. It counts the delta and cites the surface that should have carried it; a secret in an env var is a finding on its own. **Silencing the signal instead of fixing the cause**: a lint disable, type ignore, skipped or quarantined test, widened `catch`, retry wrapping a race, `sleep` standing in for a real wait, or a hook-bypassing commit — asking what the check was telling the author and whether the diff answers it or mutes it. Report a line under one class only, the most specific; face 1 is a finding only when the durable mechanism can be named by file:line, face 2 only when the suppression is live rather than inert. Publishable values are carved out by name (`VITE_`/`NEXT_PUBLIC_`, Stripe `pk_`, PostHog `phc_`, anon JWTs, referrer-restricted `AIza`, OAuth `client_id`), as is the case where the environment *is* the declared surface (12-factor, CI-provided, container entrypoint). Source: `subagents/code-reviewer/AGENT.md`.
- **Corrected what the rules claim about environment variables.** `operational.md` said "any co-tenant process can read another's via `/proc/<pid>/environ`" and that "anything in the same shell or process tree can read — or silently override — whatever you set". Measured on yosemite-s0: `/proc/<pid>/environ` is mode 400, so a same-user read succeeds and a cross-user read is denied; and a child's `export` does not reach its parent — only an ancestor sets what it spawns. The claims now say same-user rather than any co-tenant, and ancestor-sets rather than anything-overrides, in both the subrule and the composed ruleset. The old wording would have collapsed the moment an author pushed back with `ls -l /proc/<pid>/environ`, in exactly the place the argument has to hold. Source: `rules/subrules/operational.md`, `rules/AGENTS.md`.

- **A rendered artifact's `session` provenance is now a deep link back into the session.** Documented in the artifacts authoring reference: the session value
  renders as `agents://session/<id>`, and clicking it in an opened plan/report
  reopens that session's terminal in its input bar via agents-cli's `agents open`
  (which resolves the owning host). The behavior ships in artifacts-cli (render) and
  agents-cli (the `agents open` handler + `agents://` scheme registration).

- **A `code-reviewer` subagent ships in the system layer, reaching every subagents-capable harness.** Installing agents-cli now gives you a non-author reviewer with no per-repo setup — the case `agents-cli` is in today with `prix/code-reviewer` paused (#1767). It is adversarial twice: it hunts the input that breaks the change, then tries to kill each candidate finding (the guard is elsewhere / the line is unreachable / the repo sanctions it) and reports only survivors plus a count of what it filtered. Before judging it reads the **requirement** — the ticket the branch names and any committed plan — and answers conformance per acceptance criterion. It bounds what it reports to a **finding radius**: the diff, plus what the diff broke (stale callers, disagreeing siblings, and the old path this change orphaned but nobody deleted); pre-existing rot gets one line, never a finding. New hunt class: **design divergence at a declared surface**, diffing a new endpoint / CLI command / schema / component against three to five existing siblings (API envelope, error shape, pagination, auth attachment; CLI noun-then-verb and `--json`; UI tokens, scale, component reuse, full state set). It never edits, pushes, or merges. `code:review` spawns it as `subagent_type: "code-reviewer"` and its per-PR brief carries only the requirement, context, and canonical patterns.

  It lives at `subagents/code-reviewer/AGENT.md`, **not** inside the `code` plugin. A plugin's `agents/<name>.md` is the Claude plugin format: the file is copied into every harness home but only a plugin-format harness registers it. Measured on yosemite-m1 with the plugin installed and that file present, `~/.claude/agents/`, `~/.grok/agents/`, `~/.kimi-code/agents/`, `~/.cursor/agents/`, and `~/.codex/agents/` were all empty. The top-level `subagents/` layer writes those native paths via `SUBAGENT_TARGETS`, so one definition reaches Claude, Codex, Grok, Kimi, Cursor, Droid, OpenCode, Copilot, Kiro, Goose, Antigravity, and OpenClaw. `code:review`'s security pass also became its own concurrent agent instead of check #6 inside the reviewer's brief, and it defers to an installed `security`/`audit` skill when the box has one. Source: `subagents/code-reviewer/AGENT.md`, `plugins/code/skills/review/SKILL.md`, `subagents/README.md`.
- **`#noslop` promptcut — a hard gate against vague, imprecise prose.** Type `#noslop` / `` `#noslop` `` / `!!noslop` alongside a prompt and it expands into a discipline that bans the words agents reach for to avoid committing to a verifiable claim: approximation hedges (`directionally`, `roughly`, `basically`, `-ish`), vague placeholder nouns (`things`, `stuff`, `various`, `several`), empty verbs that hide the mechanism (`gate`, `handle`, `manage`, `leverage`), unearned marketing adjectives (`seamless`, `powerful`, `robust`, `simply`), false-confidence connectives (`clearly`, `obviously`), and drama headers (`Critically:`, `Notably:`). It requires naming the concrete referent (file, function, flag, error, count, byte size) and describing the topic at full resolution — including the edge cases the tidy summary omits — and ends with a pre-send self-check that replaces each banned word with the fact it stood in for. It is `code-quality` ("Write prose precisely; don't market") turned up to a per-turn gate. Verified end-to-end through the real UserPromptSubmit hook on all four markers plus the codex append path. Source: `hooks/promptcuts.yaml`.
- **Plans carry a cross-harness planning contract.** Built-in plan mode (`/plan`, Shift+Tab, `--mode plan`) only toggles a permission mode and injects no methodology on any harness — so the `plan-presentation` rule (the one lever loaded during plan mode on claude/codex/kimi/grok/droid) now carries what every plan must do: search prior sessions on the feature first (`agents sessions`, so agents extend rather than revert prior work), locate/propose the module spec, and lead with **Focus for review** + restated **Intent**, a **Current architecture** section (before/after figure for architectural changes), an implementation shown as a **per-file diff** (not a path table), and a **rendered to-do list**. Two gates before presenting: a non-author **adversarial review** of API-surface cleanliness + adherence to existing architectural conventions (via a subagent or `agents run`), and render+open. `commands/plan.md` gains the prior-work step (Step 0) and the panel's API/convention criterion (Step 7); `skills/plan-render/SKILL.md` documents the section order and the `code-diff`/`checklist` render components. Motivated by two real sessions (codex `019fe962`, kimi `5908db92`) where the agent never showed the interface, never restated intent, and iterated a bad API surface until the user authored it. Sibling of RUSH-2140; coordinates with PR #256. Source: `rules/subrules/plan-presentation/rule.md`, `commands/plan.md`, `skills/plan-render/SKILL.md`.

### Changed

- **Agent launch guidance uses durable credential accounts (RUSH-2402).** The `agents-cli` and `run` skills now teach `agents accounts add`, `agents run --account`, and device-local credential installation instead of attaching credentials to harness definitions.

### Performance

- **Shared short-TTL git-fact cache for PreToolUse guards (RUSH-2293).**
  `main-branch-guard` was forking `git rev-parse` + two `symbolic-ref` calls on every
  Write/Edit/Bash fire (15k+ calls / 30d, `cacheMissPct: 100`). Full-hook `cache:` is
  unsafe here — the agents-cli shim always exits 0 on hit and would soft-allow after a
  branch switch onto the default branch. New `hooks/lib/git-facts.sh` caches only the
  derived facts (repo root, current branch, origin/HEAD default, on-default) under
  `~/.agents/.cache/state/git-facts/` with a 5s TTL, and re-reads the worktree HEAD file
  on every lookup so a `git switch` invalidates immediately inside the TTL. Warm loads
  skip the three git forks; correctness tests cover branch-switch invalidation, TTL
  expiry, linked worktrees, and origin/HEAD defaults. Source: `hooks/lib/git-facts.sh`,
  `hooks/lib/git-facts_test.sh`, `rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh`.

### Fixed

- **`pr-description-reminder` now inspects the body an agent actually ships — the `--body-file` hole is closed.** The PreToolUse backstop that requires a run-evidence screenshot only ever looked at an inline `--body`/`-b`; a `--body-file`/`-F` body (the path agents route nearly every multi-line PR through) was waved through unread, so evidence-free feature PRs landed unreviewable (real case: agents-cli PR #2460, a `feat(cli)` with no screenshot — replaying its exact body through the old hook via `--body-file` returns exit 0, the new hook returns exit 2). The hook now reads the referenced file and inspects its content, and a bare Linear ticket / plan-`.html` link no longer clears the requirement on its own — clearing needs a real run result (image/recording/asset) or an explicit no-run declaration (`release`/`docs-only`/`refactor`/`test-only`). It still fails open on a `--fill`/`--template`/editor body it cannot read and on an unreadable `--body-file`. Source: `rules/subrules/truly-agentic-git-workflow/pr-description-reminder.sh` (+ `_test.sh`, 26 cases), rule text in `rule.md` (regenerated into `rules/AGENTS.md`).

- **Guard denials now return the safe next command, not just a block (RUSH-2295).** `git-guard`, `rm-guard`, and `large-file-add-guard` print a structured stderr block on every deny:
  ```
  blocked_op: git.reset
  reason: …
  do_this_instead: reconcile with `git rebase origin/<default>`; never `reset --hard`
  ```
  Sessions were burning dozens of retries on the same `failureId` (`rm.protected-path` 87×, `git.reset` 43×) because the model only saw "denied". The `do_this_instead` line is what kills the loop. Source: `hooks/pre-tool-use/git-guard.sh`, `rm-guard.sh`, `large-file-add-guard.sh` (+ their `_test.sh` fixtures).

### Removed

- Removed the 8 daemon-housekeeping routines (usage-refresh, fleet-cache-warm, session-cache-warm, device-probe, auto-dispatch, watchdog, tmux-reconcile, launch-health) — each was a thin `agents __daemon-tick <name>` cron wrapper. RUSH-2495 takes this housekeeping out of routines entirely as a hard cut: `tmux-reconcile`, `launch-health`, and `auto-dispatch` are deleted outright; `session-cache-warm` is dropped because `agents sessions --active` self-refreshes on read; and `watchdog`, `device-probe`, `usage-refresh`, and `fleet-cache-warm` become plain daemon-core timers. Only `check-updates` remains a system-level routine. This is the config-repo half; RUSH-2495 does the daemon side separately. Removing the YAMLs is safe on its own — a removed routine is simply not fired, and the reader commands self-refresh their caches.
- **The `escalate` skill and its `escalate-on-notification` hook.** Reaching the owner when genuinely blocked is now `agents feed post --blocked` (opens a needs-you record + delivers out-of-band) — the escalate ladder was superseded by it and still hard-wired Telegram, which the no-Telegram rule forbids. Deletes `skills/escalate/` (incl. `escalate.sh`, `owner.py`), `hooks/notification/12-escalate-on-notification.{sh,_test.sh}`, and the `escalate-on-notification` entry in `agents.yaml` (hook count 19 → 18); removes the rows from `skills/README.md` and `hooks/README.md`.

### Added

- **A "what earns a command or skill" philosophy in the maintenance contract.** The top-level `AGENTS.md` now states the bar for the command/skill surface: add only a *fundamental operation* (not a variant — those are modes/arguments of an existing one), make it general across *all* work not just code, and write it concretely enough that a *weak* model can execute it step by step. Source: `AGENTS.md`.

### Fixed

- **Stop gate no longer accepts an in-process `gh pr checks --watch` as a PR handoff (RUSH-2394).** A headless agent that backgrounds that command and exits strands its own PR — the watcher is a child of the agent process tree and dies with it (observed on agents-cli PR #2334 / #2352). The open-PR and keep-moving gates now accept only a durable lander (`agents pr land --detach`) or a ScheduleWakeup/Monitor tool_use as evidence that something outlives the agent, and the block message tells agents to use `--detach` instead of the in-process watch. Source: `hooks/stop/00-agent-verify-work-complete.sh`, `hooks/stop/00-agent-verify-work-complete_test.sh`.

- **`usage-refresh` routine drops from every 1 minute to every 5 minutes (RUSH-2451).** The routine's own cadence gate already refreshes each account on a fixed 5-minute internal schedule, so the 1-minute cron was checking 5x more often than any account could ever be due — each check a full `agents __daemon-tick usage-refresh` CLI subprocess spawn. Source: `routines/usage-refresh.yml`.

### Changed

- **`reflect` skill consolidated into the self plugin.** The flat top-level `skills/reflect` moved to `plugins/self/skills/reflect` (now the `self:reflect` skill), so the skill lives with its `/self:reflect` command instead of floating in the shared `skills/` list. Source: `plugins/self/skills/reflect/`, `plugins/self/commands/reflect.md`, `plugins/self/README.md`, `skills/README.md`.
- **`skills/README.md` now lists the `artifacts` skill** (it was on disk but missing from the catalog).

- **`/blame` — regression forensics.** A new top-level command that traces a regression (a feature that worked and silently broke) to the culprit change, the removed/skipped/commented-out test that let it through, and the agent + session behind it — read-only, no fix. It pins expected vs observed, maps the code path, bisects the suspect commits, hunts for disabled tests in the same window, and attributes via `git blame` + `agents sessions`. Hand the verdict to `/debug` or `/finish` to repair. Source: `commands/blame.md`, `commands/README.md`.
- **`/output` moved into the work plugin as `/work:output`.** The fleet token-burn/output report is a work action, so it now lives beside `/work:loop` and `/work:dispatch` (top-level `/output` removed). Source: `plugins/work/commands/output.md`, `commands/README.md`, `plugins/work/README.md`, `plugins/README.md`.

- **git-guard now blocks remote branch deletion.** The `git push` handler denies `--delete`/`-d` and a leading-colon refspec (`git push <remote> :<branch>`), closing the remote counterpart to the already-denied local `git branch -d/-D`. Deleting an *already-merged* PR branch is safe and stays allowed via `gh pr merge --delete-branch` — only the forms that can drop unmerged commits are banned. Source: `hooks/pre-tool-use/git-guard.sh`, `git-guard_test.sh`, `git-guard.md`, plus the `AGENTS.md` north-star wording.

- **Hook-owned session state convention + evidence-based `verify-work-complete` delivery classification (RUSH-2113).** Programmable hooks may keep their own namespaced SQLite database under `~/.agents/.history/hooks/<stable-hook-id>/`, keyed by harness/native session id with launch-id reconciliation; agents-cli does not gain a generic state command. The first pilot records privacy-preserving goal boundaries and materializes positive session evidence during Stop. Browser/external-app work, read-only diagnostics, requested ticket creation, and review-only sessions no longer become supposed code deliveries merely because the final message says “done” inside a Git cwd. Repository mutation, authored/operated PRs, and deployments retain the full delivery chain. No raw prompts, transcripts, commands, or tool output are stored. Source: `hooks/stop/verify-work-state.py`, `hooks/user-prompt-submit/04-verify-work-state.py`, `hooks/stop/00-agent-verify-work-complete.sh`.

- **`verify-work-complete` delivery gate no longer fires on no-delivery turns.** The delivery close-the-loop check (`verify-delivery-chain.py`) treated a conversation that merely *mentioned* a user-facing thing (the words "command", "flag", "feature", etc.) as a delivery, so a read-only analysis turn whose only write was a gitignored `.agents/artifacts/` file was gated for "missing docs and CHANGELOG". The user-facing keyword heuristic (which drives the docs/CHANGELOG demand) now counts only when the session produced a real change to document — a tracked file changed outside scratch/artifact/worktree/tmp paths, or a responsible PR. It cannot be gamed: a genuine change always shows in `git diff` or a PR. Real deliveries missing docs/CHANGELOG still gate exactly as before, and release verification is untouched — a release cut from already-merged code (no diff, no PR) still gates on its own tag/publish/verify evidence. Source: `hooks/stop/verify-delivery-chain.py`, `hooks/stop/verify-delivery-chain_test.sh`.

- **A "safe autonomy" north star in the repo maintenance contract.** The top-level `AGENTS.md` (canonical; `CLAUDE.md`/`GEMINI.md` are symlinks) now opens with the goal every change here serves: give agents *more autonomy, safely* — guardrails that counter laziness rather than merely forbid, cross-harness / cross-platform / cross-device by default, predictability over cleverness, and protecting against irreversible loss (branch deletion stays banned). Source: `AGENTS.md`.

- **Promptcuts accept explicit and hashtag-free markers; inline bang commands run concurrently (#243).** A shortcut stored as `#name` now expands from `#name`, `` `#name` ``, `!!name`, or `` `!!name` ``, so prompts can reserve `#` for hashtags and use backticks when the shortcut should be visually explicit. Both UserPromptSubmit expansion hooks now reject ordinary prompts in shell before paying Python/YAML startup cost and select the live interpreter (`python3`, then Windows `py -3`) instead of trusting the Microsoft Store alias. Multiple backticked bang commands execute concurrently with at most 8 workers, retain source-order output, keep a 5-second timeout per command, and kill the timed-out process tree on POSIX and Windows. A cold-process benchmark records the no-marker, expansion, and three-command paths. Source: `hooks/user-prompt-submit/02-expand-prompt-user-shortcuts.sh`, `hooks/user-prompt-submit/02-expand-prompt-bang-commands.sh`, `hooks/tests/benchmark_prompt_expansion.py`.

- **Routine guidance now uses explicit execution projects/CWDs and the native single-flight contract (RUSH-2290).** The routines skill teaches `--project-anchor` separately from metadata-only `--project`, target-side relative CWD resolution for Linear-imported projects without checkout bindings, readiness/repair before activation, transactional YAML edits, routine-first history, and the scheduler's slot plus active-run claims. The obsolete prompt-level `/tmp` overlap lock recipe is removed.

- **`hooks/syntax_test.sh` — a parse gate for every hook script.** A hook that does not
  parse still runs, and bash exits 2 on a syntax error, which the harness reads as
  **block** — so a typo silently becomes a gate no session can get past (see the
  `verify-work-complete` entry under Fixed). It runs `bash -n` on every `.sh` under
  `/bin/bash` (3.2 on macOS) *and* the PATH bash, plus `py_compile` on every `.py`.
  Checking 3.2 explicitly is the point: the break that motivated this parses cleanly
  under bash 5, so a Linux-only check would have missed it. Picked up automatically by
  `run_tests.sh`. Source: `hooks/syntax_test.sh`, `hooks/README.md`, `hooks/AGENTS.md`.

- **8 built-in daemon housekeeping routines (RUSH-2353).** `watchdog`,
  `device-probe`, `tmux-reconcile`, `launch-health`, `fleet-cache-warm`,
  `session-cache-warm`, `usage-refresh`, and `auto-dispatch` ship here as
  `command:` routines, migrated off hardcoded `setInterval` timers that used to
  live inside agents-cli's daemon (`runDaemon()`). Same schedules, same
  effects — now declared, listed (`agents routines list`), run-tracked
  (`agents routines stats`), individually pausable, and device-pinnable.
  `auto-dispatch` is the notable one: as a hardcoded tick it could not be
  pinned to a single device, so every daemon on a fleet independently polled
  the same Linear queue with no coordination; pin it with
  `agents routines devices auto-dispatch --set <device>`. Requires an
  agents-cli build that ships `agents __daemon-tick` (companion PR in
  `phnx-labs/agents-cli`). Source: `routines/watchdog.yml`,
  `routines/device-probe.yml`, `routines/tmux-reconcile.yml`,
  `routines/launch-health.yml`, `routines/fleet-cache-warm.yml`,
  `routines/session-cache-warm.yml`, `routines/usage-refresh.yml`,
  `routines/auto-dispatch.yml`.

- **Root README guide: what to run, which plugin, how to automate.** Ships a
  goal→command table, situation FAQ (overnight drain, rate-limits, crash restore),
  plugin pick matrix, and automation recipes (`/drain`, `/code:loop`, routines,
  one-shot dispatch). `plugins/README.md` and `commands/README.md` point at it.
  Audience: end users and agents that need a front door without reading every skill.
  Source: `README.md`, `plugins/README.md`, `commands/README.md`.

- **`work:loop` + top-level `/drain` — general-purpose unattended work drain.** The
  overnight failure mode (Claude logouts, rate-limits, bwrap, everything collapsing onto
  two hosts) needed a verb that is not engineering-only. `work:loop` drains clear work
  across projects and kinds (code, browser/portal, outreach, design), always spreads load
  (`agents teams` + balanced accounts + worker hosts + re-home on auth death), and may use
  browser / computer / secrets / prior sessions / code reads for context. **No review/merge
  gate** — engineering stops at PR open for the human to review later; non-coding finishes
  the real outcome when the agent can. Composes patterns from `code:loop` without its
  merge-oriented "done." Top-level `/drain` is a thin alias. Source: `plugins/work/skills/loop/`,
  `plugins/work/commands/loop.md`, `commands/drain.md`, `plugins/work/README.md`,
  marketplace + plugin.json 0.2.0.

- **`/learn` is now outcome-anchored — reflection weighs the user's goals and
  delivery, not just tool friction (RUSH-2291).** A new **Phase 0 — Anchor to the
  user's goals and delivery** runs before recall: it loads two lenses — the Linear
  ladder (projects → milestones → cycles → tasks, and which milestones are
  *slipping*, read from the injected SessionStart context or `linear tasks
  --by-milestone`) and the delivery signal (`agents output`: PRs merged, commits,
  cost-per-PR, output-per-$). Phase 3 then **ranks the gate-surviving lessons by
  outcome leverage** — a lesson that unblocks a slipping milestone or lifts the weak
  delivery metric comes first and earns the most care; a general lesson tied to no
  active goal is low-leverage. Leverage decides ordering and effort only; it never
  lets a lesson skip the four gates. The north star shifts from "grow the skill
  library" to "remove whatever is between the user and their next met milestone."

- **`verify-work-complete` Stop hook is now task-aware — keep moving instead of
  stopping with unfinished checklist items (RUSH-2113).** Prior PRs #158/#161
  stopped the gate from *looping*; this adds the keep-**moving** half the ticket
  asked for. A new gate folds the session's own checklist — the snapshot tools
  (`TodoWrite`/`TodoList`/`todo_write`/`update_plan`) plus Claude's
  `TaskCreate`/`TaskUpdate` event log, via the new standalone
  `hooks/stop/todo-progress.py` (mirrors the CLI's `extractTodoProgressFromEvents`
  so checklist state is read the same way everywhere) — and blocks a plain
  declarative stop while any item is still pending/in_progress, naming the next one
  to advance. This also answers enhancement A: recognizing a background watcher on
  one item is no longer blanket permission to stop; the agent is redirected to the
  next advanceable item and only stops when nothing is left. It stays a legitimate
  stop (no block) when the final message asks the user a real question, is in plan
  mode, names a genuine external blocker, explicitly hands the remaining work to a
  named owner, or points at a **live** background watcher/monitor that owns the
  remaining step (evidence-gated on a real `gh pr checks --watch` /
  `ScheduleWakeup` / `Monitor` tool_use, never phrasing alone — the same bar the
  open-PR gate uses). Fails open, respects `stop_hook_active` (fires at most once
  per stop), and de-escalates with the shared repeated-gate guidance after the 3rd
  fire. Source: `hooks/stop/00-agent-verify-work-complete.sh`,
  `hooks/stop/todo-progress.py`, `hooks/stop/00-agent-verify-work-complete_test.sh`
  (18 new assertions).

- **Current-code anchoring — diagnose against live code, not a stale checkout.**
  New hard rule across three surfaces: a `foundations` F3 bullet, a
  `research-discipline` bullet (the git analog of current-date anchoring), and an
  intro note in `truly-agentic-git-workflow`. Before diagnosing a codebase,
  claiming a bug/regression, or opening a "fix" PR, `git fetch origin` and check
  `git rev-list --count HEAD..origin/<default>` — a local checkout goes stale the
  moment another agent pushes, and a fix built on stale code is itself the
  regression. Source: `rules/subrules/foundations.md`,
  `rules/subrules/research-discipline.md`,
  `rules/subrules/truly-agentic-git-workflow/rule.md`.

### Changed

- **Command surface: moved `/fork` into the sessions plugin as `/sessions:fork`; converted the top-level `/tickets` command into a portable `tickets` skill.** Skills work on every harness; commands do not (not on `openclaw`, `kimi`, `hermes`; limited on `codex`). Every "route through `/tickets`" reference now points at the `tickets` skill. Committed the missing `clis/CLAUDE.md`/`clis/GEMINI.md` convention symlinks. Source: `plugins/sessions/commands/fork.md`, `skills/tickets/SKILL.md`, `commands/README.md`, `plugins/sessions/README.md`, `plugins/README.md`, `skills/README.md`, and tracker-reference updates across commands and rules.

- **Removed the top-level `/recover` command; crash-recovery is now `/continue recover`.** The standalone `/recover` command was a thin alias for `sessions:continue` recover mode — the mode, keyword, and all behavior remain intact. Users reach it via `/continue recover`. The `sessions:continue` skill already implements recover mode; only the redundant standalone command and its references were removed. Source: `commands/continue.md`, `plugins/sessions/skills/continue/SKILL.md`, `plugins/sessions/skills/restore/SKILL.md`, `commands/README.md`, `plugins/README.md`, `plugins/sessions/README.md`, `README.md`.

- **`code` plugin simplified to 0.9.0 — `code:loop`, `code:review` (three modes),
  `code:learn`, `code:commit`.** Dropped `code:verify` (folded into `code:loop` as an
  inline verification step — identify changed surfaces, run each one's canonical test,
  quote real output; never needed a dedicated skill call) and `code:ship` (replaced by
  the new top-level **`/release`** command — publishing a distributable is a general
  release-flow concern, not a code-plugin one; `skills/release/SKILL.md` gained a
  per-artifact live/active verify table folded in from the old `code:ship`, including the
  full VS Code extension dual-registry + `exthost.log` activation check). `code:quality`
  is gone as a separate command — it's now `code:review`'s third mode
  (`repo`/a path/`--since <date>`): the same architecture-and-quality rubric a PR review
  applies to a diff, run over a whole scope instead, still read-only with an HTML report
  and never a merge verdict. `code:review`'s PR rubric gained an explicit architecture
  check (reuse of primitives, cross-cutting logic at the source, no duplicate surfaces,
  load-bearing seams, doc-asserted invariants vs code) and the fat session-recap body
  that used to live in `plugins/code/commands/review.md` moved into the skill (now a
  thin `Invoke the code:review skill`) as its default "Session PRs" mode.
  **`code:learn` reframed**: its primary output is now durable navigation notes written
  into the *project's* own `AGENTS.md` (structure, entry points, invariants, gotchas) —
  folding a coding-*workflow* lesson back into this plugin is secondary and still gated
  by the top-level `learn` engine. Source: `plugins/code/`, `commands/{release,review}.md`,
  `commands/README.md`, `skills/release/SKILL.md`, `skills/computer/SKILL.md`,
  `plugins/swarm/README.md`, `plugins/README.md`, `.claude-plugin/marketplace.json`.
- **`swarm` plugin simplified to 0.5.0 — four modes + top-level `/swarm`.** Dropped
  unused `/swarm:test` and `/swarm:qa` (commands + skills). Kept `/swarm:run`,
  `/swarm:plan`, `/swarm:spec`, `/swarm:debug` on the shared `swarm:orchestrate`
  engine. Added top-level **`/swarm`** router: leading `plan`/`spec`/`debug`/`run`
  selects the skill; bare `/swarm <task>` → `swarm:run`. **`swarm:plan`** now
  requires mock-ups (user flow + ASCII screens/states + before/after) for any
  UI/multi-step surface. **`swarm:spec`** reframed as the durable contract *so
  other agents and humans do not invent wrong behavior*, with the same mock-up
  bar for UI/flow surfaces. Marketplace + plugin.json + README catalogs updated.
  Source: `plugins/swarm/`, `commands/swarm.md`, `commands/README.md`,
  `.claude-plugin/marketplace.json`.

- **Command surface: removed the top-level `/commit` alias (use `/code:commit`); moved `/release` into the code plugin as `/code:release`.** Both the command (`plugins/code/commands/release.md`) and the `release` skill now live under `plugins/code/` (invoked as the `code:release` skill). Updated the tech-stack rule, catalogs, and cross-references. Source: `plugins/code/commands/release.md`, `plugins/code/skills/release/`, `commands/README.md`, `plugins/code/README.md`, `plugins/README.md`, `plugins/git/README.md`, `skills/README.md`, `rules/subrules/tech-stack.md`, root `README.md`.

### Added

- **New `sessions` plugin — `/sessions:continue`, `/sessions:insights`,
  `/sessions:restore`.** Consolidates session lifecycle and analytics that used
  to live as fat top-level commands. **Skill-first:** full procedures live in
  `plugins/sessions/skills/{continue,insights,restore}/SKILL.md`; plugin commands
  and top-level aliases only say `Invoke the \`sessions:…\` skill` so harnesses
  that prefer skills still get the procedure. `sessions:continue` finishes prior
  work **in this window** (reattach only on a genuine live signal; group-capable;
  recover mode covers multi-session crash triage — prefer finish over resurrect).
  `sessions:insights` is the conductor over `agents insights`, `agents trends`,
  `agents perf`, and `agents sessions stats` — one evidence-backed action list;
  no separate trends/perf plugin commands. `sessions:restore` re-opens crash/
  reboot casualties as terminal windows. Top-level `/continue`, `/insights`,
  `/restore` are thin aliases; `/recover` invokes `sessions:continue` in recover
  mode. Source: `plugins/sessions/`, `commands/{continue,insights,restore,recover}.md`,
  `.claude-plugin/marketplace.json`, `plugins/README.md`, `commands/README.md`,
  `skills/sessions/SKILL.md`.
- **Keep browser action loops warm with `agents browser stream`.** Agents can send
  newline-delimited JSON requests through one long-lived CLI process instead of
  launching Node once per screenshot, ref lookup, click, or type action.

- **New `self` plugin — `/self:close`, the agent self-exit primitive.** An agent
  had no first-class way to end its own session: `/done` inlined a `kill -TERM
  $PPID` blob that the auto-mode permission classifier blocked in headless runs,
  so a dispatched session could not cleanly self-terminate. `/self:close` is the
  low-level primitive — a read-only `ps -o comm= -p $PPID` guard (refuses
  shell/tmux/sshd parents) then **exactly** `kill -TERM $PPID`. That exact form
  is allowlisted by the new `permissions/groups/12-self.yaml`
  (`Bash(kill -TERM $PPID)`, scoped to the direct parent + `TERM` only, never a
  general `kill`), so the self-exit runs without a prompt in auto mode. `/done`'s
  Step 2 **forwards to `/self:close`** rather than duplicating the guard+signal —
  one home for the exit logic, the same alias pattern as `/commit` → `/code:commit`
  (`/finish` deliberately does not self-exit — it drives work to delivered and
  stays). Source: `plugins/self/`, `permissions/groups/12-self.yaml`,
  `permissions/default.yaml` (rebuilt), `commands/done.md`,
  `.claude-plugin/marketplace.json`, `plugins/README.md`.

### Changed

- **`/continue` procedure (now `sessions:continue`) defaults to resuming in place,
  not reattaching.** The common case is an interrupted / rate-limited / headless
  session, not a live pane. Reattach only on a genuine live-interactive signal;
  otherwise load the transcript and continue here. Carried into the plugin skill
  when the fat command moved. Source: `plugins/sessions/skills/continue/SKILL.md`.

- **Command surface reorg — removed top-level aliases, moved commands into plugins, renamed `/drain`→`/loop`.** Removed top-level `/review` (use `/code:review`), `/test` (follow the Strict Testing rule), `/monitors` (use `agents monitors` CLI), and `/prune` (use `/git:prune`). Moved `/profile`→`/fleet:profile`, `/hibernate`→`/self:hibernate`, and `/reflect`→`/self:reflect` into their respective plugins. Renamed `/drain`→`/loop` (still a thin alias of `/work:loop`). Source: `commands/README.md`, `plugins/README.md`, `plugins/fleet/README.md`, `plugins/self/README.md`, `plugins/work/README.md`, `plugins/work/commands/dispatch.md`, `plugins/work/skills/loop/SKILL.md`, `plugins/code/README.md`, `plugins/git/README.md`, `plugins/swarm/README.md`, `commands/AGENTS.md`, `plugins/AGENTS.md`, `README.md`.

## [0.2.0] - 2026-08-06

### Highlights

Behavioral cut of the 2026-08-03 → 2026-08-06 wave. Fleet boxes land this by
`agents repo pull system` (or `check-updates` / SessionStart autosync) and
`agents sync` — there is no separate npm package for this repo. Tag `v0.2.0`
names the train; `main` remains what most hosts pull day-to-day.

- **Multi-harness system hooks** (claude / codex / kimi / grok / cursor / droid /
  antigravity): snake_case + camelCase stdin; shell/read tool names ported.
- **Stop / done contract:** no PR-link handoffs; waiting sessions stop looping;
  done-claim files follow-ups, recaps, and self-exits headless runs.
- **SessionStart denser:** Linear projects + milestones, project-aware in-flight,
  device topology cache, git pull-forward on clean trees.
- **Teams / feed:** completion + cross-track contracts; feed record vs owner
  deliver (`agents notify`); balanced rotation + `--remote-cwd` documented.
- **New commands:** `/triage`, `/dispatch`, `/work:dispatch`, `/fork`, `/profile`,
  historical `/recap`; `/debug` full loop; `reflect` restored.
- **Artifacts:** Markdown → `artifacts-cli` HTML; date-based paths; plan HTML
  requires a drawn SVG figure.
- **Four hooks re-registered** after months of silent unregistration (rm-guard,
  large-file-add-guard, linear inject, prompt expanders).

### Security & defaults (this cut)

- **`expand-bang-commands` defaults to `enabled: false`.** UserPromptSubmit
  `` `! cmd` `` expansion runs a shell; paste of untrusted text is local RCE.
  Re-enable in the user layer with a full entry + `override: true` (see
  `agents.yaml` comment and README §Hooks).
- **`/finish` transcript attach** uses `gh gist create --secret` and prefers
  `agents sessions render` (redacted). Public repos omit the gist.
- **Personal contact surfaces scrubbed** from escalate / hibernate examples and
  tests (placeholders instead of a live chat id / `muqsit@mac-mini`).

### Removed

- **Relocated the `social` plugin out of this brand-agnostic mirror.** `social`
  (audit / align / schedule) hard-codes one user's growth infra — `rush http
  POST /api/v1/social/post`, the `getlate` pipeline, the OpenClaw draft corpus,
  and the `sergey`/`marc` workspaces — so it fails the `.system` bar (generic +
  brand-agnostic + safe to public-mirror). It now lives in the user layer next
  to `create` (marketplace `agents-cli`). Dropped its entry from
  `.claude-plugin/marketplace.json`, the `plugins/README.md` catalog row, the
  two `social`/`social:schedule` routes in `plugins/work/commands/dispatch.md`,
  and the `social` mention in the `work` plugin description. Paired add:
  muqsitnawaz/.agents#227.

### Known risks (follow-ups — not fixed in 0.2.0)

These remain after this tag; tracked for 0.2.1+ / agents-cli companions:

1. **Indirect prompt injection** — Linear titles/descriptions and open PR titles
   land in SessionStart context without trust fences (mailbox inject is the
   pattern to copy).
2. **`session_id` as path component** in attention-sentinel / vacation-recap /
   escalate-fired can traverse if a harness ever supplies a hostile id.
3. **`escalate.sh` watcher** still interpolates `$MSG` into a `bash -c` string
   (initial send is base64-safe).
4. **Permission allows** `Bash(agents:*)` / `Bash(cat:*)` bypass Read denies on
   credential files — cooperative agent speed-bump only.
5. **No first-class `agents hooks enable|disable` CLI yet** — user-layer
   `enabled: false` works today; a dedicated command is planned.
6. **`check-updates` routine** unpinned `npm i -g @latest` + ff system `main`
   is a supply-chain surface when enabled.

### Changed

- **`hooks/session-start/03-linear-inject-tasks-context.sh` routes "Your Tasks"
  by Linear's native `delegate`, not by an `agent:<name>` label.** The hook never
  fetched `delegate` at all, so an issue delegated to Claude through Linear's own
  delegation UI landed in generic team output while a stale `agent:claude` label
  on an unowned issue read as yours. It now selects `delegate { name }` and
  matches it against the running harness case-insensitively (Linear returns the
  roster spelling, `Claude`; the harness is `claude`). A leftover `agent:*` label
  is shown as an ordinary label and confers nothing.
- **"Your Tasks" comes from its own delegate-filtered query instead of the
  active-cycle page.** Linear caps that page, so the personal queue was whichever
  of your issues happened to land in the first page — on this workspace it showed
  3 of 100+. The hook now asks Linear for `delegate = <harness>` directly (an
  aliased field on the same single round trip, so no extra request), prints the
  top 10 by priority, and says how many more there are. The Cycle-by-project
  section skips only what Your Tasks actually printed, not everything delegated
  to you: the two lists come from different queries, so skipping by delegate
  dropped your own over-the-cap issues out of the brief entirely.
- **"Other agent lanes" counts the whole cycle instead of one page.** The
  active-cycle query carried no `first:`, so Linear served its default 50 — of
  334 open issues here — making the counts both wrong and unstable between runs.
  Raising it to `first: 250` was not enough (Linear caps a page there), so the
  lanes now come from a second, delegate-name-only sweep that pages to the end:
  measured Antigravity=34, Codex=7, Droid=2, Grok=11, Kimi=7, OpenClaw=4 against
  the page-derived Antigravity=25, Codex=2, Droid=1, Grok=7, Kimi=4 and no
  OpenClaw lane at all. The sweep is strictly additive — it asks for nothing but
  delegate names, and if any page fails the hook falls back to counting the
  cycle page and says so with an "of the first N" qualifier. Typical run
  measured at 1.9s. The sweep is bounded to 3 pages at 1s, so the worst case is
  8 + 3 = 11s against the `timeout: 15` this hook is registered with. The 4s of
  headroom is not slack: the timeout covers wall-clock, and this script spawns up
  to nine python3 interpreters — ~0.85s idle, ~1.2s under contention, which is
  exactly when SessionStart runs. A budget that merely fit inside 15s on paper
  measured a harness kill and **zero bytes of brief**, because the sweep runs
  before anything prints. Live sweep pages measure 0.23-0.26s, so 1s is still
  ~4x headroom, and 3 pages cover 750 issues against 327 open in this cycle.
- **`AGENT_SELF` is sanitized to `[A-Za-z0-9_-]` everywhere it is used**, not
  only in the GraphQL string literal. It is also printed into the injected
  context of every session, where an unsanitized value could inject arbitrary
  text and newlines into the prompt.
- **No-priority issues sort last in the injected brief, not first.** `pri_rank`
  returned Linear's raw `priority`, where `0` means "no priority set" — so
  unprioritized issues sorted above Urgent ones. Harmless when every issue was
  listed; actively hiding work now that "Your Tasks" is capped at 10. Matches
  `linear-cli`'s `issue_sort_key`.
- **`skills/routines/SKILL.md`, `plugins/code/skills/loop/SKILL.md`,
  `commands/tickets.md`, `clis/linear-cli.yaml`** — the ticket-drain design used
  `agent:<worker>` labels for *machine* routing and `agent:hold` as an opt-out,
  which read as agent ownership and collided with delegation. Machine routing is
  now `host:<worker>` and the opt-out is `hold`; agent ownership is the delegate,
  everywhere.

- **Skills and commands re-synced with today's team/feed/session rule changes.**
  The rule edits (`parallel-teams`, `feed-status-posts`, `fleet-delegation`,
  `remote-fleet-dispatch`) had moved ahead of their long-form playbooks, so the
  policy lived only in the rules an agent skims, not in the skills it opens
  mid-task. `skills/teams` gained the feed/notify brief line, the teammate
  completion contract, the orchestrator cross-track (seam) contract, and the
  balanced-rotation default; `plugins/swarm` orchestrate got the verbatim
  feed/notify + completion lines in its brief template and orchestrator posting
  in the monitor loop; `commands/teams` gained the completion-contract line;
  `skills/run` now documents `--remote-cwd` as an `agents run`-only flag that
  hard-errors on `teams add`, with the resolve-on-the-remote path gotcha.
  `skills/sessions` gained a Resume & Fork lifecycle section (`agents sessions
  fork`/`resume`, resume on the owning device); `commands/README` indexes
  `/fork`; `skills/release` Phase 1 now refuses to double-release into a
  serialized train/lease before it publishes, matching `/finish`. `/done` gained
  a Step 0 close-out (file follow-ups, clean loose ends) matching what the
  `verify-work-complete` Stop gate already requires; `03-vacation-recap` stopped
  pointing at a `session-handoff-summary` rule that does not exist in the system
  layer (now the back-from-vacation summary under F4 in `foundations`); and the
  stale `post-tool-use/` hook-directory references were removed from
  `hooks/README.md` and `hooks/AGENTS.md` (no PostToolUse hook ships today).

- **`session-start/03-linear-inject-tasks-context` injects every project with milestones + top open tickets, not only the cwd-matched focus + agent-sorted cycle dump.** SessionStart now prints: (1) Team & Agents, (2) **Projects** — all non-completed/canceled projects (cwd match marked ★, each with milestones and priority-sorted top open issues), (3) active cycle with Your Tasks first, then remaining open work **grouped by project** (capped), plus other-agent lane counts. Credentials stay on `~/.linear-cli/config.json` / env only — still never `agents secrets`, keychain, or Touch ID. Tests cover multi-project + milestone rendering, completed-project filter, agent lane routing, and the no-agents-CLI invariant. Source: `hooks/session-start/03-linear-inject-tasks-context.sh`, `_test.sh`; `hooks/README.md`.

- **`/finish` no longer offers to publish in a repo that has a release train.**
  Its "Release (if applicable)" step detected a publishable package and asked
  whether to release it, which contradicts `release-to-fleet`: a repo with a
  scheduled or lease-held releaser is done at *merged + a changelog fragment*,
  and a feature agent must not run the release script, tag, or publish. Leaving
  it meant every `/finish` on `agents-cli` would offer to publish, reintroducing
  through this entry point exactly the contention that jammed that pipeline on
  2026-08-02 (four release attempts, zero published versions, two sessions
  racing the same release into a `merged tree != built tree` refusal). The step
  now checks for a train first — including a release script that claims a lease,
  which is already serialized — and defers to `release-to-fleet` as the
  authority. Repos without a train are unchanged.

### Added

- **`operational` now spells out why env vars are unsafe for config and secrets,
  not just that credentials belong in `agents secrets`.** The prior rule was a
  single bullet scoped to credentials only. It's now backed by rationale (child
  process inheritance, `/proc/<pid>/environ`, crash-dump/log leakage, silent
  override by anything in the same process tree), broadened to configuration in
  general (feature flags, endpoints, toggles belong in real config files, not env
  var overrides that shadow them invisibly), and adds a direct rule against
  creating unnecessary env vars — a proper config entry, CLI flag, or function
  argument should be tried first. The existing `agents secrets` guidance for
  credentials is unchanged.

- **Codex run guidance now matches the safe permission-profile defaults.** When no
  configured run default exists, omitted Codex mode is writable with network and
  on-request approvals; explicit plan stays
  filesystem-read-only with network; only explicit skip removes approvals and the
  sandbox. The permissions maintenance guide now distinguishes launch profiles from
  the coarser canonical permission-resource translation.

- **The done-claim Stop gate now closes the loop instead of leaving a dangling
  optional idea.** `00-agent-verify-work-complete.sh`'s final self-audit gate
  (fires when the agent claims a delivery is done) gained a third close-out step
  alongside the existing goal re-audit and `agents feed post`: file any genuine
  follow-up ideas as tickets right now instead of dangling them ("say the word",
  "let me know if you want this") — that pattern (screenshot evidence: a session
  that shipped and verified everything, then ended with an open-ended "the only
  optional follow-up is X — say the word") is exactly the "588 hours burned
  idling" failure mode F1 already bans, just reached via a different final
  message shape than the gate previously closed. Once every goal is verified,
  follow-ups are filed (or dropped), and the feed post is up, a headless/
  dispatched/background run now also self-exits the way `/done` does (SIGTERM to
  its own harness parent) instead of sitting idle — explicitly skipped when the
  session looks interactive, so a live terminal someone is watching is never
  killed out from under them. Source:
  `hooks/stop/00-agent-verify-work-complete.sh`, `_test.sh` (5 new assertions,
  98/98 passing).

- **The done-claim gate now requires an actual recap before self-exiting, not
  just a SIGTERM.** Follow-up to the entry above: the close-out sequence's
  self-exit step said "run /done's Step 2 self-exit recipe," which named only
  the exit half and could read as license to skip `/done`'s own Step 1 (the
  handoff recap, built via `/recap`'s discipline) — a self-exit with no recap
  first is not a clean handoff. Now says to run `/done` as a whole (Step 1
  recaps, Step 2 self-exits) for a headless/dispatched run, or `/recap` alone
  (no self-exit) when the session looks interactive. Also added: worktree/branch
  cleanup and closing any tickets the session actually finished as part of the
  same close-out step, and follow-up tickets must carry real context, not a
  one-line stub. Source: `hooks/stop/00-agent-verify-work-complete.sh`,
  `_test.sh` (4 more assertions, 102/102 passing).

- **New `/profile` command.** Profiles a sluggish machine, attributes the load to agents-cli surfaces (daemon, menu-bar helper, `doctor`/`sessions` pollers), reads the logs to root-cause it, and files a GitHub issue on the public agents-cli repo with the evidence — codifying the load-300 crash-loop diagnosis (an un-notarized menu-bar helper crash-looping and spawning an orphaned `doctor --json` pile-up).

### Changed

- **`agents teams` guidance closes three gaps mined from real orchestrator
  failures (a fourth candidate gap was already fixed upstream, see below).**
  (1) `teams add --remote-cwd` hard-errors, not a silent no-op — never
  documented, so agents kept retrying it blind (`teams.ts:1217`,
  `teams.ts:1529-1530`). (2) Balanced account rotation is already the default
  for a bare teammate, and pinning `@version`/`--profile` opts out — neither
  fact was written down anywhere (`rotate.ts:120-135`, `rotate.ts:275-276`).
  (3) Teammates run headless, so `edit` mode can stall on an approval prompt
  nobody answers; `auto` is usually the right unattended default
  (`teams.ts:1501`). Also clarified (no behavior change, just wording): local
  and `--device`-pinned remote worktrees both fetch `origin` and branch off
  `origin/<default>` — a genuine divergence existed here as recently as
  `agents-cli@234fa139` (2026-08-04), but it was already fixed before this
  doc PR was written, so the guidance now states the current (safe) behavior
  instead of warning about a bug that no longer exists. Source:
  `rules/subrules/{parallel-teams,fleet-delegation,remote-fleet-dispatch}.md`,
  `rules/AGENTS.md`, `skills/teams/SKILL.md`,
  `plugins/swarm/skills/orchestrate/SKILL.md`.

- **Feed delivery now has one policy path.** The legacy `feed-forward` PostToolUse hook is removed because it forwarded every plain milestone outside `feed.broadcast`, bypassing `minLevel: important` and duplicating owner delivery.

- **Multi-harness hook protocol (claude / codex / kimi / grok / cursor / droid / antigravity).**
  Guards and inject scripts accept both Claude-style snake_case stdin
  (`tool_input.command`, `tool_name`, `session_id`) and Grok-style camelCase
  (`toolInput.command`, `toolName`, `sessionId`). Shell tools recognized as
  Bash / Shell / `run_terminal_command`; file-read tools as Read / `read_file` /
  ReadFile. Stripped ignored `agents:` filters from `agents.yaml` (field is
  deprecated in agents-cli) and documented real coverage limits: Grok ignores
  SessionStart stdout; Antigravity has no SessionStart/UserPromptSubmit/
  Notification mapping; Gemini CLI is hard-deprecated in favor of antigravity.
  Source: `hooks/pre-tool-use/{git-guard,rm-guard,01-git-require-clean-tree,large-file-add-guard,10-mq-read-nudge,09-mailbox-inject}`,
  `hooks/post-tool-use/13-feed-forward.py`,
  `hooks/user-prompt-submit/02-expand-prompt-{bang-commands,user-shortcuts}`,
  `hooks/README.md`, `agents.yaml`.

### Fixed

- **`stop/00-agent-verify-work-complete` parses again — it was blocking every session on macOS.** The RUSH-2113 keep-moving gate (`2615e49`) added a `$(python3 - <<'PY' … PY)` whose body carried a lone `'` in a regex character class (`[)\]\'\"]`). bash 3.2 — `/bin/bash` on every macOS box, and what `#!/usr/bin/env bash` resolves to there — tracks quotes inside a heredoc nested in a `$(…)`, so the whole script became unparseable. bash 5 parses it fine, which is why it passed on Linux. An unparseable hook still *runs*: bash exits 2 on a syntax error, and 2 is the harness's **block** code, so every Stop was refused with `line 547: unexpected EOF while looking for matching ')'` and no session could end. The regex now spells the two quote characters as `\x27` / `\x22`, so the heredoc body carries no quote at all; the matched character set is unchanged. This also switches the keep-moving gate on for the first time — its 8 tests had been red since it landed. Source: `hooks/stop/00-agent-verify-work-complete.sh`.

- **`session-start/04-session-identity` no longer wipes Factory join keys on by-pid merge (RUSH-2192).** SessionStart rewrote `~/.agents/.cache/terminals/by-pid/<pid>.json` with the real `sessionId` but only preserved `agent` / `cwd` / `tmuxPane` / `startedAtMs` — dropping `terminalId` and `launchId` the launcher had stamped. That left `agents sessions --active` rows without `terminalId`, so Factory status-bar join by `AGENT_TERMINAL_ID` (Grok / Codex / `--device`) could not bind. Merge now keeps `terminalId`, `launchId`, `actor`, `initiatedBy`; if no prior registry file, falls back to `AGENT_TERMINAL_ID` / `AGENT_LAUNCH_ID` env. Tests cover preserve + env fallback. Source: `hooks/session-start/04-session-identity.sh`, `_test.sh`.

### Changed

- **Feed milestones now distinguish record-only progress from owner delivery (RUSH-2193).** Plain `agents feed post` updates stay in the activity stream under `minLevel: important`; phone-worthy successful updates use `--level important`; `--blocked` remains reserved for genuine human blockers. Guidance also says session identity auto-resolves and documents `--session` only as an escape hatch. The completion stop gate now requests an important post explicitly.

- **After opening a PR, agents no longer open the PR link for the user — they drive review + merge themselves.** F4 no longer uses "review + merge PR #N" as the handoff example (routine PRs are not handoffs). `truly-agentic-git-workflow` replaces "open the PR on the user's interactive device" with: watch CI and **immediately check whether the automated code reviewer is functioning** (config + live post on this PR); if the bot is working, wait for it; if it is missing, silent, down, or unconfigured, **spawn a non-author subagent review as soon as possible** (`code:review`) and merge on green — never hand the merge to the user because the bot is down. `gh-merge-guard` states the same non-author review source rule. `code:review` skill documents when it is the default path vs skip-when-bot-posted. The `verify-work-complete` Stop gate no longer treats "prix-cloud is down / no reviewer configured + needs you to click merge" as a valid stop; its PRGATE text tells the agent to spawn a subagent review instead. Tests updated (reviewer-down + needs-you blocks; explicit named handoff still allows). Source: `rules/subrules/{foundations,truly-agentic-git-workflow,gh-merge-guard}/`, `hooks/00-agent-verify-work-complete.sh`, `plugins/code/skills/review/SKILL.md`, `rules/AGENTS.md`.

### Removed

- **Built-in Watchdog routine removed.** Session recovery remains available through explicit `agents watchdog` commands, but the system DotAgents layer no longer schedules the two-minute watchdog routine by default. Source: `routines/watchdog.yml`, `routines/README.md`.

- **Skill and plugin bloat cut (discovery surface).** Deleted top-level skills `dither-kit` and `git-workflow` (git procedure lives only in the always-on `truly-agentic-git-workflow` rule), folded `agents-md` into `skills/docs/write-agents-md.md`, and removed system plugins `clify` and `cloud` (Rush Cloud docs belong in the product/extension; marketplace entries dropped). Stripped Dither Kit from `tech-stack`, plan-presentation, docs, and related catalogs. Source: skills/, plugins/, `.claude-plugin/marketplace.json`, `rules/subrules/`.

### Added

- **`vacation-recap` UserPromptSubmit hook.** Tracks a per-session last-prompt
  timestamp (`~/.agents/.cache/state/last-user-prompt/<session_id>`, same
  convention as the attention sentinel) and, when a new prompt arrives more than
  `AGENTS_VACATION_RECAP_THRESHOLD_SEC` (default 7200s / 2h) after the previous
  one, reminds the agent to open with a quick back-from-vacation recap — problem,
  what was accomplished, suggested next step — before addressing the new prompt.
  Additive only: plain stdout for Claude (never the `<user-prompt-submit-hook>`
  replace wrapper the other two UserPromptSubmit hooks use), JSON
  `additionalContext` for other harnesses. Source:
  `hooks/user-prompt-submit/03-vacation-recap.py`, `agents.yaml`.

- **`/triage` and `/dispatch` commands.** `/triage` sweeps the whole issue tracker, grounds
  in the real product goal spine (Linear Initiative→Project→Milestone, or a repo's
  roadmap/milestones for GitHub), then forces every open item to exactly one of two
  outcomes — keep-and-schedule into the current cycle (building it now if it's small
  enough) or cancel outright. `Backlog` status, `--cycle none`, and "Low, revisit someday"
  are banned as landing states — they're hedges that let a ticket rot instead of forcing
  the decision. `/dispatch` is the single-task counterpart: understand the repo once, spec
  fast (routing bugs through the `swarm:debug` skill instead of guessing a root cause),
  show a quick plan, file the ticket, then dispatch to `run`/`teams`/`code:loop` depending
  on scope. Source: `commands/triage.md`, `commands/dispatch.md`, `commands/README.md`.

- **`reflect` command and skill restored as system defaults.** `/reflect` handles mid-conversation feedback recall before another revision; `/learn` remains the post-session workflow that writes durable lessons forward. Source: `commands/reflect.md`, `skills/reflect/SKILL.md`.

- **`session-start/09-git-pull-forward.sh` — SessionStart fast-forward of the cwd
  git repo when clean.** Fetches upstream and runs `git merge --ff-only` only when
  the tree is clean, HEAD is not detached, an upstream is configured, and HEAD is
  an ancestor of upstream. Never force, never rebase, never autostash, never
  overrides local commits. Opt out: `AGENTS_NO_GIT_PULL_FORWARD=1`. Source:
  `hooks/session-start/09-git-pull-forward.sh`, `_test.sh`, `agents.yaml`.

### Changed

- **Hooks layout is `hooks/<event-name>/<hook-file>`.** Every system hook lives under
  a kebab-case event dir (`session-start/`, `pre-tool-use/`, `post-tool-use/`,
  `user-prompt-submit/`, `stop/`, `notification/`). `agents.yaml` `script:` paths are
  relative to `hooks/` (e.g. `session-start/04-session-identity.sh`). `promptcuts.yaml`
  stays at `hooks/` root. agents-cli discovers one-level event dirs (companion
  agents-cli#2053). Subrule guards stay co-located under `rules/subrules/<rule>/`
  via `hooks.yaml` — not moved into `hooks/<event>/`. Source: `hooks/`, `agents.yaml`,
  `hooks/README.md`, `hooks/AGENTS.md`, `rules/subrules/*/hooks.yaml`.

- **Agent artifacts (plans, HTML, visuals, reports) now use a single dated layout: `.agents/artifacts/yyyy-mm-dd/<artifact-title>.md`.** Replaces the kind-based `plans/` and `viz/` subdirs. The `plan-presentation` rule documents the layout for plans and any related durable outputs; `plan-html-reminder` scans `.agents/artifacts/` (dated day dirs) for fresh figure-bearing plan HTML and teaches the new path in its block message; `plan-render`, `visualize`, `/plan`, `/swarm:plan`, `/swarm:spec`, and `commands/output` write under the date dir. HTML still renders next to its Markdown source. Source: `rules/subrules/plan-presentation/`, `skills/plan-render/`, `skills/visualize/`, `commands/plan.md`, `plugins/swarm/skills/plan|spec/SKILL.md`, `rules/AGENTS.md`.

- **`03-linear-inject-tasks-context.sh` no longer uses `agents secrets`; it reads the Linear CLI's own `~/.linear-cli/config.json` (`apiKey` + `teamId`, 0600) with `LINEAR_API_KEY`/`LINEAR_TEAM_ID` env still winning.** The secrets-broker path was biometry-gated whenever the broker hold expired, and its skip path nagged for an unlock on every session start. The config.json path is plaintext, silent, and identical on macOS/Linux/Windows — the `agents secrets status` gate, the `agents secrets exec` self re-exec, and `_HOOK_SECRETS_TRIED` are deleted. Missing or malformed config degrades to a one-line skip naming `linear setup`. `hooks/README.md` now states the invariant: a hook must never pop Touch ID or hang a session — documented `--json`-style flags and plaintext tool configs only, never `agents secrets`. New `hooks/session-start/03-linear-inject-tasks-context_test.sh` proves credentials come from the fixture config, env wins, and the `agents` CLI is never invoked. Companion: agents-cli RUSH-2190 gates `devices list`'s keychain-scanning "Leased boxes" tail behind `--all`, closing the same Touch ID sheet in `07-inject-device-topology.sh` without changing the hook.

- **The sessions and devices skills now teach direct live-state filters and the real fleet default.** `agents sessions --working`, `--idle`, `--waiting`, `--orphan`/`--orphaned`, `--crashed`, `--closed`, `--abandoned`, `--queued`, and `--unknown` each imply the live scan and compose as a union. Both skills now state that interactive/live views include registered online devices, `--local` opts out, non-interactive history needs explicit `--host`/`--device`, and `--all` widens historical directory/time scope rather than device scope. Companion: agents-cli issue #2009.

- **Friendlier plan figure gate copy.** Skills now describe the compiler error as `No SVG figure found` and steer agents to add a visualization via **plan-render** / **artifacts**, matching `@phnx-labs/artifacts-cli@0.2.1`.

### Changed

- **Plan quality gate: prose-only plan HTML no longer clears ExitPlanMode.** `plan-html-reminder` now greps the rendered HTML for a live `<svg` with a drawn primitive (`rect`/`path`/`text`/…); empty touch files and wall-of-text shells block. Companion: `artifacts-cli` rejects `kind: plan` without a drawn SVG and refuses to write HTML on validation errors. Skills (`plan-render`, `artifacts`) and the plan-presentation rule document the bar; `plan-render` template ships a filled before/after SVG. Source: `rules/subrules/plan-presentation/`, `skills/plan-render/`, `skills/artifacts/`.

- **`artifacts` skill: multipurpose `links` frontmatter.** Agents are steered to attach ticket/PR/issue/design URLs (Linear, Jira, GitHub, …) in a list of plain `https://` strings or `{url, label?}` objects, seed them at first draft, and append any tickets opened mid-session before re-rendering. Labels auto-derive for common trackers; `tracking` remains a short optional id. Companion change in `artifacts-cli` renders the list as a linked chip row. `plan-render` is unchanged this pass. Source: `skills/artifacts/SKILL.md`, `skills/artifacts/references/authoring.md`.

### Added

- **`hooks/registration_test.sh` — the failing test that "is this hook registered" never had (RUSH-2119).** A hook needs two things to fire: the script and its `hooks:` entry in `agents.yaml`. Only the script was ever tested, so a dropped registration was invisible — the script kept passing its own `_test.sh` while never running. It happened twice as collateral in commits whose subjects said nothing about it: `606db6e` (deleted the whole 27-line manifest, silently unregistering `expand-promptcuts`, `expand-bang-commands`, `linear-tasks`, `stop-completion-gate`) and `8b006a6` (dropped `rm-guard` **and** `large-file-add-guard`; only `rm-guard` was later restored, so the data-loss guard `large-file-add-guard` was off from Jun 24 to Aug 3). The test asserts every `*.sh`/`*.py` in `hooks/` (minus the test harness) is either registered in `../agents.yaml`, invoked by a script that itself is registered (the `verify-delivery-chain.py` case — piped by the registered `00-agent-verify-work-complete.sh`), or in an `INTENTIONALLY_UNREGISTERED` allowlist with a reason (seeded with `02-expand-prompt-skill-refs.py`, an unfinished feature that `git log -S` shows was never registered). Case 2 searches only registered scripts, so the inverse trap does not pass: `02-expand-prompt-bang-commands.py` is referenced by the *unregistered* `02-expand-prompt-skill-refs.py`, which does not count. Proven to **fail** when `606db6e`'s exact drop is reproduced against the current tree — naming those three scripts and nothing else — so it cannot pass only against the fixed state. `agents.yaml` was not touched (source-of-truth). Source: `hooks/registration_test.sh`.
- **`hooks/run_tests.sh` — the pre-PR gate.** Runs every `*_test.sh` in `hooks/` and `rules/subrules/*/` (including the registration check), non-zero on any failure. Named in `hooks/AGENTS.md` as the gate to run before any PR touching `hooks/`, `rules/subrules/`, or `agents.yaml`.

### Changed

- **`08-inject-repo-inflight` now injects the agents actively *working* on this project, not a raw session dump.** The SessionStart hook was listing every live session whose `cwd` sat under the checkout regardless of state, and anchored on `git rev-parse --show-toplevel` — so a session started inside a worktree (`…/.agents/worktrees/<slug>`) saw a different anchor than its main checkout and missed sibling agents. It now: (1) anchors on the project's **main repo root** via `--git-common-dir` (parent), unifying every worktree with its main checkout; (2) shows only agents whose CLI-derived `activity` is `working`, dropping idle, `waiting_input`, orphaned, abandoned, and dead (`pidAlive:false`) sessions; (3) ranks them most-recently-active first (`lastActivityMs`) and caps at 5, summarizing the rest as `+ N more agents working on this project (next: …)`; and (4) surfaces each agent's opened PR (`prLink` → `PR #<n>`) and Linear ticket (`ticketId`) from the session JSON when present, never fabricated. Every external call stays wrapped in the `_to` timeout and the whole section fails open (no git / no `gh` / no `agents` CLI / malformed JSON → silent `exit 0`). Source: `hooks/08-inject-repo-inflight.sh`, `hooks/08-inject-repo-inflight_test.sh`.

- **`/debug` (`swarm:debug`) is now the full daily-driver loop, not just the verify step.** It gained a front and a back around the existing blind mixed-provider verification: **(1) intent vs observed** — pin Intended / Observed / Delta before touching code, reading any screenshot/clip in the report; **(2) spec-gap check** — locate the capability's spec + tests and answer *why it slipped* (a missing spec/test is itself the finding), reusing `swarm:spec`'s extraction discipline; and **(6) close the loop** — render a viewable artifact via `plan-render`, cut a `/tickets` ticket, and dispatch the fix to the worker boxes. Verifiers now default to `--device yosemite-s0,yosemite-s1` to keep the interactive machine responsive. Motivated by a 30-day fleet usage audit: `/debug`+`/swarm:debug` is the most-used real workflow command (24 invocations) while `/spec` sits at ~0, so the spec-gap step was folded into the command that actually gets typed rather than left behind a separate command. Source: `plugins/swarm/skills/debug/SKILL.md`, `commands/debug.md`.
- **The plan-presentation rule, `/plan`, `/swarm:plan`, and `/swarm:spec` now route rendered artifacts through `artifacts-cli` into the repo's `.agents/artifacts/plans/` directory.** The standing rule and the `plan-html-reminder` hook previously pointed agents at hand-authored `/tmp/plan-<slug>.html` files and the `template.html` gold reference. They now require a Markdown source in `<repo>/.agents/artifacts/plans/plan-<slug>.md` rendered with `artifacts render ... --format html`, matching the recently updated `plan-render` and `visualize` skills. The hook detects fresh rendered HTML under the repo artifact path (falling back to `/tmp` only outside a git repo), and its reminder message names the Markdown + `artifacts-cli` recipe. Source: `rules/subrules/plan-presentation/rule.md`, `plan-html-reminder.sh`, `plan-html-reminder_test.sh`, `commands/plan.md`, `plugins/swarm/skills/plan/SKILL.md`, `plugins/swarm/skills/spec/SKILL.md`, `commands/output.md`, `rules/AGENTS.md`.

### Fixed

- **`main-branch-guard` now denies stale `origin/*` worktree bases, not just wrong form.** The worktree gate already required `origin/<default>` (not local `main` / implicit `HEAD`), but a days-old remote-tracking ref still passed — agents forked off stale main and only hit the cost at merge. After the form check, the guard now requires the remote-tracking ref (or `FETCH_HEAD`) to be newer than `AGENTS_WORKTREE_FETCH_MAX_AGE_SEC` (default 900s). Deny message tells the agent to `git fetch origin` and retry. Set the env var to `0` to disable the age gate. Source: `rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh`.

## [0.1.94] - 2026-08-03

### Fixed

- **Both escalation hooks resolved the escalate skill from the layer it does not ship in, so neither has ever run.** `12-escalate-on-notification.sh:37` and `13-feed-forward.py:23` defaulted `SKILL` to `$HOME/.agents/skills/escalate` — the **user** layer — while the skill ships in the **system** layer (`.system/skills/escalate`). No box has a user-layer copy, so the shell hook's `[ -x "$SKILL/escalate.sh" ] || exit 0` matched nothing and the Python hook's `owner_json()` never found `owner.py`. Both exited silently on every machine, every time, since they landed: the escalation ladder and the status-forwarding hook were dead code that looked healthy. Verified on a live box — user layer `owner.py` absent, system layer present. Both now resolve **user → system**, matching the documented `project → user → system` order, with `ESCALATE_SKILL_DIR` / `OWNER_PROFILE` overrides still winning for tests. Found while tracing why a blocked agent never reached the owner (RUSH-2110), where this was one of five independent silent failures on the same path.
- **The hook tests could not have caught it.** Every case in `12-escalate-on-notification_test.sh` and `13-feed-forward_test.sh` forced `ESCALATE_SKILL_DIR`, so the default-resolution branch — the code that was broken — had zero coverage. Each suite gains a case that builds a fake `HOME` with the skill in the **system layer only**, exactly as the fleet has it, plus a case asserting the user layer still wins when both exist. Both new cases are proven to **fail against the pre-fix hooks** and pass after, the same regression standard used for the promptcuts system-layer bug in 0.1.92.

## [0.1.93] - 2026-08-03

### Fixed

- **`hooks/AGENTS.md` claimed the `NN-` filename prefix orders hook execution. It does not.** The prefix is cosmetic: registration order is `Object.entries(manifest)` order (`apps/cli/src/lib/hooks.ts:1696`), i.e. YAML declaration order, and there is no `.sort()` anywhere between `parseHookManifest` and any registrar's write — the manifest currently declares `10-`, `05-`, `00-`, `08-`, `06-`, `12-` in that order. Claude then runs them concurrently regardless: *"All matching hooks run in parallel, and identical handlers are deduplicated automatically"*, with a per-hook `timeout` and all `additionalContext` values delivered. The section now states the real rule — a hook must be independent, may not read a file another hook writes in the same event, and may not assume ordering; two steps that genuinely must be ordered belong in one script, which is exactly why `04-session-identity.sh` merged three former hooks that all parsed the same `SessionStart` stdin. The claim was introduced in 0.1.92 and shipped for a few hours.

### Changed

- **`inject-device-topology` is cached; `inject-repo-inflight` deliberately is not.** Measured `SessionStart` cost: `inject-repo-inflight` 5648ms, `inject-device-topology` 2255ms, `linear-tasks` 318ms, `session-identity` 18ms, `session-start-autosync` 5ms — the first two are 96% of the total. `inject-device-topology` now declares `cache: {ttl: 60s, key: global, prefetch: background}`: its output has no session or cwd dependency, so a shared entry is the correct answer for every caller. Verified against a generated shim, 2217ms cold to 68ms warm with byte-identical output. TTL is 60s rather than 5m because the load figures steer "prefer an idle box" and a five-minute-old reading can route work to a box that is now busy — and because a background refresh that keeps failing currently has no backoff, so a shorter TTL bounds how long one stale entry can be served.

  **`inject-repo-inflight` is left uncached on purpose, and the first draft of this change got it wrong.** The hook excludes the *calling* session from the live-session list it prints (`self_sid`, `hooks/08-inject-repo-inflight.sh:72`), so its correct output differs per session. `key: per-cwd` hashes only `cwd` (`apps/cli/src/lib/hooks/cache.ts:429-434`), never `session_id` — so agent B starting in the same checkout within the TTL would be served the snapshot computed for agent A, filtered to exclude A rather than B, and would not see that A is running. That is precisely the "don't take over a surface another live session is mid-flight on" failure the hook exists to prevent. `key: per-session` would be correct but pointless: `SessionStart` fires once per session, so every fire would be a miss. A cache that serves the wrong context is worse than a slow hook.

- **`inject-repo-inflight`'s session probe was 77ms away from silently losing its data on every session start.** `agents sessions --active --json --local` measures **4923ms** against the hook's `_to 5` (5000ms) budget, and the surrounding `|| true` makes a timeout indistinguishable from "nothing is running" — so under any extra load the entire "Active sessions in this checkout" section vanishes with no error. This was pre-existing on `main`, not introduced here; it surfaced when an attempt to run the hook's two probes concurrently pushed the probe over its budget and the section disappeared. That optimisation was reverted (a ~0.6s gain was not worth the fragility) and the budget raised to `_to 8`, still inside the manifest-level `timeout: 10`. The real fix is making `agents sessions --active --local` faster; this stops the silent data loss meanwhile.

### Known drift recorded (not fixed here)

- **OpenClaw's capability table claims hook support it never receives.** `apps/cli/src/lib/agents.ts:374` declares `hooks: true`, but no `registerHooksForOpenClaw` exists and `registerHooksToSettings` has no `openclaw` branch, so it falls through to `return { registered: [], errors: [] }` (`hooks.ts:1449`). agents-cli's own review conventions name this failure mode: *"A map asserting a capability the code doesn't implement is a lying table."* The fix belongs in agents-cli — either flip the flag or write the registrar — and is tracked separately.


### Fixed

- **`13-feed-forward` still called `rush message send` — a version-skewed path that often does not exist.** After RUSH-2123, owner delivery is `agents notify` / `agents send --to owner` (channel registry). The hook now prefers `agents notify`, keeps OpenClaw Telegram as fallback, and uses a non-login local shell so PATH stubs (and the real agents binary) resolve correctly. Tests stub `agents` instead of `rush`. `cli/rush.yaml` no longer teaches `rush message send` as the agent-facing notify path.

### Changed

- **PR/issue visual evidence now routes through `agents share`, so screenshots and recordings embed inline headlessly.** The `truly-agentic-git-workflow` "Open with evidence attached" and "Attaching evidence on GitHub — the mechanics" sections made web drag-drop the only inline-embed path — a browser-bound step an agent can't do headlessly, so agents skipped the visual. `agents share <file>` publishes any static asset (PNG/JPEG/GIF/WebP screenshot, MP4/MOV/WebM recording, PDF) to the user's Cloudflare R2 and returns a public URL that renders via `![caption](url)`, needing no browser. The mechanics list is reordered — `agents share` primary, drag-drop the fallback, then comment-after-the-fact, then the host:path last resort — the "ships a picture" bullet now names the command and asks for before/after stills, and the confidentiality rule is kept (public share is for shareable proof only, never a transcript or a secret). Paired with agents-cli's fix that content-types static media (`agents share` served PNG/MP4 as `application/octet-stream`, which GitHub's camo proxy refuses to render). `rule.md` + composed `AGENTS.md` updated in lockstep.
- **Historical context commands now keep the resolved source machine attached to the transcript read.** `/recap <selector>` passes the metadata-only resolver's full ID and machine to its isolated read-only subagent, which reads markdown and artifacts with `--host <machine>`; exit code 2 remains an incomplete fleet answer and cannot become a false match or no-match. `/continue <id> --device <machine>` (or `--host`) now parses the generated source locator and uses it when a dead session's transcript must be loaded from another box, while live attachment remains fleet-aware.
- **The `verify-work-complete` Stop hook no longer loops sessions that are correctly waiting or genuinely blocked.** A fleet audit of the last ~6 days (1,594 sessions) found the open-PR gate fired **434×** across 82 sessions — 22 looped ≥10×, 7 ≥20× (one hit its usage limit mid-loop). Attribution was already precise (382/382 cited PRs were the session's own; no blind strands), so the defect was over-firing, not blindness. Three changes:
  - **Repeated-gate guidance.** After a gate fires ≥3 times on the same item this session, it asks the agent to re-check live state and choose the most useful next move instead of prescribing a fixed escalation route. It offers retrying differently, self-unblocking, advancing another in-scope item, coordinating ownership, or escalating a genuinely human-only step as possibilities while preserving the agent's judgment. Prior fires are counted from the transcript, anchored to the injected `Stop hook feedback:` prefix.
  - **Live-watcher recognition (evidence-gated).** The open-PR gate now treats a real background `gh pr checks --watch` (or a `ScheduleWakeup`/`Monitor`) tool_use as a valid handoff — the repo's own watch-then-stop pattern. Only a genuine tool_use clears it (48% of open-PR blocks were sessions doing exactly this, mis-scored); phrasing alone never clears the gate.
  - **Context awareness.** Plan mode (cannot push/merge) is accepted as a correct stop rather than abandonment. (A later Unreleased change removes the former escape that treated "automated reviewer down/unconfigured + needs you to merge" as a valid stop — that path now requires a subagent review, not a user handoff.)
  - Test harness extended with 13 fixtures (evidence-gate regression, plan-mode incidental-mention guard, banner threshold). Verified by replaying the 5 worst-looping real transcripts through the patched hook.

## [0.1.92] - 2026-08-03

### Fixed

- **Four hooks that had been silently dead for months are registered again.** Each was working code whose `hooks:` entry in `agents.yaml` was dropped as collateral in an unrelated commit, and nothing failed — a hook has no test for "am I registered", so each script kept passing its own `_test.sh` while never running. `606db6e` (May 13, subject: *"fix(hooks): handle missing YAML frontmatter in pre-commit validator"*) removed **27 lines** from `agents.yaml`, taking `expand-promptcuts`, `expand-bang-commands`, `linear-tasks`, and `stop-completion-gate` with it; `8b006a6` (Jun 24, *"chore: remove legacy agents hook config"*) removed **34 lines**, taking `rm-guard` and `large-file-add-guard`. In both cases one sibling was later restored (`stop-completion-gate` returned as `verify-work-complete`, `rm-guard` was re-registered) and the rest were forgotten. All four are verified working before re-registration: `#checkit` expands to the full verification block; `` `!echo HELLOTEST` `` expands to `HELLOTEST`; the Linear hook fails soft with a clear message when the `linear.app` bundle is absent (`rc=0`); and `large-file-add-guard.sh` blocks an 11 MiB `git add` with `rc=2`. `agents.yaml` goes from 13 registered hooks to 17. All 6 hook test suites pass.
- **Promptcuts never loaded the system layer on a fresh install — the deeper bug behind the dead registration.** `02-expand-prompt-user-shortcuts.sh` read its system defaults from `~/.agents-system/hooks/promptcuts.yaml`, the **pre-migration** path (`state.ts:64`), never the canonical `~/.agents/.system/` (`state.ts:57`). On any install that was not folded from a legacy layout that file does not exist, so the system layer contributed nothing and the hook produced no output at all. Proven against a synthetic `HOME` holding only the system layer: the `origin/main` script emits **nothing** for `#checkit`; this branch expands it. Re-registering the hook without this fix would have shipped a feature that still did nothing on a clean machine. The canonical path is now first, the legacy path retained for folded installs. Same one-line bug fixed in `02-expand-prompt-skill-refs.py`'s skill search path.
- **`02-expand-prompt-user-shortcuts_test.sh` is new, and it is the test whose absence let this run for months.** Six cases: the canonical system layer loads, the legacy path still loads, the user layer wins a key collision, a prompt with no token produces no output, and a missing `promptcuts.yaml` exits 0 without blocking the prompt. Verified to actually catch the regression — run against the `origin/main` script it fails the canonical-layer case (`5 passed, 1 failed`); against the fixed script, 6 pass.
- **`03-linear-inject-tasks-context.sh` bounds its own network call.** The `curl` to `api.linear.app` carried no `--max-time`, so the only limit was whichever harness's hook runtime enforced `timeout: 15`. A reachable-but-slow API would stall every session start. Now `--connect-timeout 3 --max-time 8`.
- **`promptcuts.yaml` cited a rule scheme that no longer exists.** 22 references to `Hard Line #N` survived the 0.1.83 migration that replaced `core-hard-lines` with the F1–F5 foundations, so every promptcut that fired pointed at a rule name nothing defines. Each is rewritten to its real home, mapped from the pre-removal `core-hard-lines.md` (an 11-item list): #1 → `F3`, #9/#10 → `F2`, #2/#3/#5/#6/#8 → `research-discipline`, #4 → `code-quality`, #7/#11 → `fleet-delegation`. One reference, `#15` ("cross-cutting changes go to the source"), predates that file entirely — it traces to an older numbered list in the root `AGENTS.md` — and is mapped to `code-quality` on content, not on the `core-hard-lines` numbering.
- **`hooks/README.md` and `hooks/AGENTS.md` now describe the fixed state**, not the broken one. The Promptcuts section no longer opens with "currently inert", the four restored hooks have rows in the event tables, and the drift section is down to the single script that was *never* registered (`02-expand-prompt-skill-refs.py` — `git log -S` over the manifest returns zero commits, so it is an unfinished feature, not a regression). The root `AGENTS.md` mistakes table now names the actual failure mode: a bulk edit dropping registrations under an unrelated subject.
## [0.1.91] - 2026-08-03

### Fixed

- **Historical `/recap` resolution no longer reads transcript content in the receiving agent.** The full-ID `--preview` and positional prefix/keyword paths added in 0.1.89 parsed transcript events before the isolated subagent boundary. Every historical selector now uses the metadata-only `agents sessions --resolve <selector> --json` contract from agents-cli #1759; only the selected full ID crosses into the isolated transcript-reading subagent.
- **`hooks/AGENTS.md` said six scripts "do not run"; one of them does.** `verify-delivery-chain.py` has no `hooks:` entry, but `00-agent-verify-work-complete.sh` pipes into it directly, so it fires on every Stop. Corrected to five, with `verify-delivery-chain.py` called out as the exception that shows "no manifest entry" means *unregistered*, not *dead*. The inverse trap is recorded too: `02-expand-prompt-bang-commands.py` **is** referenced, but only by `02-expand-prompt-skill-refs.py`, which is itself unregistered — referenced is not reachable unless the chain ends at a registered entry point. The grep in that section now excludes tests and docs so it stops producing false positives.

### Added

- **A "common mistakes in this repo" table in the root `AGENTS.md`, so an agent that has never worked here checks itself before shipping something inert.** Every entry has actually happened in this repo, and they share a shape: the change looks complete, nothing errors, and the thing silently does not work. Hand-editing a generated file (`rules/AGENTS.md` is composed from `subrules/` + `rules.yaml`; `permissions/default.yaml` is built by `build.sh`) so the next regeneration erases it; adding a hook script without its `hooks:` entry in `agents.yaml` — five scripts in `hooks/` are in that state, while `verify-delivery-chain.py` has no entry either yet runs on every Stop because `00-agent-verify-work-complete.sh` pipes into it, so "no manifest entry" means unregistered, not dead; writing maintenance notes into `rules/AGENTS.md`, which is the composed ruleset synced into every agent's memory file; editing `~/.agents/.system/` in place when it is a pull-only mirror; citing a `file:line` or symbol without opening it, which is worse than no pointer because the next agent trusts it; and assuming merged means live when merged is not published and published is not installed. Each row carries the concrete check that catches it.
- **A section stating how repo instructions reach an agent the repo has never met.** Three things travel with a clone and none needs the contributor to configure anything: the committed `AGENTS.md` (with `CLAUDE.md`/`GEMINI.md` symlinked), which every harness reads out of the clone; a committed `<repo>/.agents/` layer (`commands/`, `skills/`) resolving at **project** precedence ahead of the user's own `~/.agents/`; and a committed `<repo>/.agents/rules/`, compiled into the repo's `AGENTS.md` by `compileRulesForProject`. The composition semantics are stated precisely because "project shadows user" is wrong: `composeRules` (`compose.ts:173-225`) does **per-name shadowing** for the preset's named subrules, then **auto-appends** every subrule in a non-system layer the preset never named — so dropping `.agents/rules/subrules/<topic>.md` into a repo ships it to every contributor with no `rules.yaml` edit and no preset. The only wholesale override is the preset *definition*, since `resolvePreset` takes the first layer defining that name. Also records the limit: no production caller selects a non-default preset (`sync.ts:546`, `project-launch.ts:108` both pass none), so a `review` preset defined in a repo would compile for nobody, and mode-specific instruction must live in content every agent already reads.

## [0.1.90] - 2026-08-03

### Changed

- **Document `agents run --device auto` / `--host auto` across the system.** `code:loop`, `skills/run`, `rules/subrules/remote-fleet-dispatch.md`, and `plugins/code/README.md` now list automatic fleet placement as the default for "send to the fleet" — the CLI picks a reachable device by 14-day affinity + live headroom, degrading to local when no device is eligible. Named `--device <box>` is now reserved for tasks that must land on a specific machine.

## [0.1.89] - 2026-08-03

### Added

- **The `agents-md` skill now ships in the system layer.** It was stranded in one machine's user layer (`~/.agents/skills/agents-md/`), so no other box or person had it. It is the evidence-based guide to writing an `AGENTS.md` a coding agent will actually use — grounded in an observed sample of ~100 subagent runs where agents did roughly 16x more source-file reads than doc reads and navigated by symbol (`rg mintToken`) rather than by prose heading, which is why it insists every claim name a greppable `file:symbol` source of truth.
- **`agents-md` gains the other half of the pair: the README.** New section covering the audience split (`README.md` is a **catalog** for a human deciding what exists; `AGENTS.md` is a **contract** for an agent about to change something), the **what-must-stay-in-sync table** that is the highest-value entry an `AGENTS.md` can carry (adding a file is rarely the whole change — an unregistered hook script is dead code that looks alive), and an explicit boundary: the catalog shape is right for a **registry-shaped** directory (`commands/`, `skills/`, `plugins/`) and wrong for an ordinary source directory, where a table of files is just `ls` that rots on every commit. Added a matching checklist item.
- **Authoring guidance for new capabilities, in the root `AGENTS.md`.** Group related skills into a plugin rather than shipping them loose in the flat `skills/` list, especially when they share an industry or function. Give every user-facing skill a slash command that routes to it, since a skill loads only when the model matches its `description` while a command fires when the user types it. But keep the command a thin accelerator and never the only door: from the capability table in `apps/cli/src/lib/agents.ts`, skills reach every harness while commands are absent on `openclaw`, `kimi`, `hermes`, and on `codex` above 0.117.0, and plugins are absent on `amp` and `kiro` — so a capability reachable only through its command is broken on four harnesses.

### Changed

- **The `docs` skill's routing table no longer dead-ends on directory docs.** It had five subskills (user, technical, runbook, onboarding, changelog) and **zero** mentions of `AGENTS.md`, so an agent asked to document a directory was routed to `write-user.md` and never learned the pair exists. It now routes that case to `agents-md`, which owns both halves.
- **`/recap` now transfers context from a selected historical session while preserving bare `/recap`.** `/recap <full-id|prefix|keywords>` resolves one prior session through `agents sessions`, delegates the raw transcript read to an isolated read-only subagent, and returns only the source goal, facts, decisions, progress, files, tests, unresolved questions, and explicitly historical last-known state. It does not resume the session, inherit its ID, or treat recorded state as current.

## [0.1.88] - 2026-08-03

### Changed

- **Every directory now carries a `README.md` for humans and an `AGENTS.md` for agents, split by audience.** The docs had drifted into one inconsistent surface: `permissions/AGENTS.md` was a 114-line reference while its `README.md` was a 34-line pointer, `skills/README.md` listed 15 of the 20 shipped skills (missing `devices`, `escalate`, `mq`, `plan-render`, `visualize`), `commands/README.md` grouped commands under headings that no longer matched the files, and the root `README.md` restated the commands, skills, and plugins catalogs that belong in those directories. Adopting the split used by [mattpocock/skills](https://github.com/mattpocock/skills): **`README.md` is the human catalog** — what lives here plus a table of every item with a one-line description linked to its source — and **`AGENTS.md` is the agent's maintenance contract**, the invariants and what must stay in sync. New: root `AGENTS.md` (with `CLAUDE.md`/`GEMINI.md` symlinked to it, matching the convention `permissions/` and `rules/` already used), `commands/AGENTS.md`, `skills/AGENTS.md`, `hooks/AGENTS.md`, `plugins/AGENTS.md` + `plugins/README.md`, `cli/AGENTS.md` + `cli/README.md`, `routines/AGENTS.md` + `routines/README.md`, `subagents/README.md`, `webhooks/README.md`. Rewritten: the root, `commands/`, `skills/`, `hooks/`, `permissions/`, and `rules/` READMEs. The root README drops from 253 to ~150 lines by moving each catalog to the directory that owns it. Every relative link in the repo was verified to resolve.
- **`rules/` is the documented exception and keeps its contract in `README.md`.** `rules/AGENTS.md` is not a maintenance file — it is the *composed ruleset* that syncs into every agent as its memory file, so a maintenance note written there would be injected into every agent's context on the fleet. `rules/README.md` now opens with that warning and holds the rule-authoring contract instead.

### Fixed

- **Documented hook and permission facts that were wrong.** `hooks/README.md` described a manifest schema that no longer exists — a root `hooks.yaml` (folded into the `hooks:` section of `agents.yaml`, `apps/cli/src/lib/migrate.ts:292`) and the legacy `~/.agents-system/` path (`~/.agents/.system/` since `state.ts:57`; `~/.agents-system` is migration-only at `state.ts:64`). `permissions/README.md` claimed its `AGENTS.md` was "also synced into agent context"; it is not — only `rules/` is (`profiledKind` maps `rules` -> `'memory'`, `resources.ts:64-65`), verified against the composed 1219-line `~/.claude/CLAUDE.md`, which carries the ruleset and no other directory's `AGENTS.md`. `permissions/AGENTS.md`'s layout section listed a `16-mcp.yaml` that does not exist and claimed the `01-18` range was "currently empty" while 13 group files occupy it. `hooks/README.md`'s Promptcuts section described `#shortcut` expansion and `` `!cmd` `` bang commands as working, with a troubleshooting bullet for when one "did not run" — but both implementing scripts are unregistered, so they never run; the section now says so and links the unregistered-scripts list.

### Known drift recorded (not fixed here)

- **Six hook scripts are present but unregistered**, so they do not run: `02-expand-prompt-bang-commands.py`, `02-expand-prompt-skill-refs.py`, `02-expand-prompt-user-shortcuts.sh`, `03-linear-inject-tasks-context.sh`, `large-file-add-guard.sh`, `verify-delivery-chain.py`. None appears in the `hooks:` section of `agents.yaml`, and none in the user layer on the machine this was checked on. Recorded in `hooks/AGENTS.md` so they are not mistaken for live behavior; registering or deleting them is a separate change.
- **`user-invocable` is set on 17 of 20 `SKILL.md` files and read by nothing here** — `grep -rn "user-invocable"` over `apps/cli/src` returns no match. Recorded in `skills/AGENTS.md` so no behavior gets built on it.

## [0.1.87] - 2026-08-02

Backfills the entries for work merged after 0.1.86 (PRs #145, #147, #149, #150), which shipped without a changelog record.

### Added

- **A system-level escalation ladder, driven by an `owner.md` profile (#147).** When an agent is genuinely blocked, `skills/escalate/` climbs message → watch for reply → call, instead of idling on a chat message the user is not watching. The owner's contact profile and preferences live in `~/.agents/owner.md` (gitignored, per machine; schema in `skills/escalate/owner.example.md`), parsed by `skills/escalate/owner.py` using only the standard library. `hooks/12-escalate-on-notification.sh` fires the ladder from the agent's own `Notification` event, so the escalation starts from the harness's existing "needs the user" signal rather than a new convention the agent has to remember.
- **A command-handback gate in the Stop hook (#145).** The gate caught agents that finished by *preparing* work for the user — a script written to `/tmp` with "run this", a stand-down that hands ownership back — rather than doing it. Narrowed after review to fire only on a hand-back to a human target, and its message kept generic so it does not name an unbuilt command.
- **Deliberate feed status posts now forward to the owner's phone (#149).** `hooks/13-feed-forward.py` (PostToolUse) forwards a status post made through the feed, so a long headless run reaches the user out-of-band; the Stop hook prompts for a manager-style status post when the work is genuinely done.
- **Guards self-report their blocks as friction events (#150).** `hooks/` guards now emit a friction event when they block, making the guard surface measurable instead of invisible. Two follow-up fixes: the backgrounded friction call detaches stdout and stdin, and the redirections sit on the subshell rather than the inner command — either one left unhandled hangs the session.

## [0.1.86] - 2026-08-02

### Removed
- **`code:dispatch` skill and `/code:dispatch` command are removed.** The primitives have matured past the wrapper: `agents run` (local), `agents run --device` (fleet), `agents run --lease` (disposable cloud box), `agents teams` (parallel), and `cloud:run` (Rush Cloud) are the dispatch. The skill was also operationally broken here (`rush` CLI not installed; `autodev` workflow missing) and duplicated the `cloud` plugin.
- **`code:sprint` skill is removed.** Its useful planning/verification/boundary-contract content is folded into `/teams` and `code:loop`; the separate skill was just another entry point for the same `agents teams` primitive.

### Changed
- **`code:loop` no longer references `code:dispatch`.** It routes single items directly to the right primitive and fans out multi-surface queues via `agents teams`.
- **`plugins/code/skills/quality/SKILL.md` and `render.ts` no longer emit `/code:dispatch` clipboard actions.** Findings copy as `/code:loop` tasks or Linear tickets.
- **`plugins/code/skills/learn/SKILL.md` map updated** to remove `code:dispatch` and `code:sprint`; routing lessons belong in `code:loop` or the relevant tool skill.
- **Hardcoded `main` branches removed from code plugin skills/commands.** `code:loop`, `code:verify`, `code:ship`, and `/review` now use `$BASE` / the default branch.
- **Remaining "HARD LINE" terminology in code plugin replaced with F1–F5 references.** `code:verify`, `code:ship`, and `code:quality` now cite F1/F3 instead of legacy hard-line names.
- **`commands/clean.md` no longer waits for user approval.** Cleanup identifies, proposes, and executes autonomously; only genuine ambiguity or risk surfaces to the user.
- **`commands/recap.md` no longer defaults to `AskUserQuestion` for small decisions.** Low-stakes calls are made and noted; questions are reserved for genuine ambiguity.
- **`plugins/code/skills/review/SKILL.md` drops `--haiku` and aligns BLOCKED handling** with the autonomous `/review` command.

### Fixed
- **`commands/finish.md` resolves the default branch dynamically** instead of hardcoding `main/master`.

## [0.1.85] - 2026-08-02

### Changed
- **`/continue` now reattaches to a live session before falling back to transcript recovery.** `commands/continue.md` adds a Step 0: resolve the session id, then run `agents sessions focus <id> --attach-only`. If the session is still alive in a tmux pane or terminal tab — locally or on a remote device reached via `--device`/`--host` — the agent joins it and hands off cleanly instead of spawning a redundant copy that abandons the original. Only when attach fails (dead, headless, no tmux/Ghostty rail, ambiguous id, or no TTY) does it load the transcript and continue as before. `commands/README.md` updated to describe the new behavior.
- **`/recover` now tries live reattachment first.** `commands/recover.md` instructs the agent to run `agents sessions focus <id> --attach-only` for each interrupted session before falling back to headless recovery.
- **Removed F1-violating permission gates from code/swarm plugins.** `plugins/code/commands/review.md`, `plugins/code/skills/dispatch/SKILL.md`, `plugins/code/skills/sprint/SKILL.md`, `plugins/swarm/skills/orchestrate/SKILL.md`, and `plugins/swarm/skills/run/SKILL.md` no longer require an explicit user "go" before acting on verdicts, dispatches, or swarm plans. Replaced stale "HARD LINE" / "CLAUDE.md hard line" language with F1–F5 foundations references, fixed `code:dispatch` to resolve the default branch dynamically instead of hardcoding `main`, removed Haiku paths, and updated merge rules to require green CI + non-author review.

## [0.1.84] - 2026-08-01

### Added
- **Every rendered plan now carries a provenance chip row — a plan is no longer an anonymous orphan.** Plans render as durable HTML artifacts that outlive the session, but the `plan-render` house structure captured only `files touched / new helpers / status` in the hero — nothing said *who* produced the plan, *on what box*, or *which session to reopen* to continue the work. The hero now has a second `.meta.prov` chip row with five values sourced from the session at render time: **harness** (claude / codex / grok / …), **agent** (the model / profile, e.g. `opus-4.8`), **host** (the machine, e.g. `yosemite-s0`), **session** (the short session id), and the render **date** — plus an optional `session-label` chip. The same line repeats in the `.foot` so it survives a scroll-to-bottom or a print/PDF. `skills/plan-render/template.html` (new `.prov` style + hero row + foot line), `example.html` (gold reference updated to match), `skills/plan-render/SKILL.md` (new "Provenance" subsection with a per-field source table, updated Hero/foot bullets, new checklist item), and the `plan-presentation` rule (`rules/subrules/plan-presentation/rule.md` + regenerated `rules/AGENTS.md`).

## [0.1.83] - 2026-08-01

### Changed
- **The system ruleset is now founded on five principles (`rules/subrules/foundations.md`), rendered first, instead of the `core-hard-lines` + `workflow-proactive` pair.** The two files restated the same ~7 themes (done=end-to-end was independently written 8 times), which trains skimming and buries the load-bearing anti-stop rule. `foundations.md` states each once as F1–F5 and every tactic references them by name (F1–F5) instead of re-deriving: **F1** you own the whole task end-to-end and do not stop to ask permission (leads with the measured 588h/30d idle-stop cost + the four agents' own verbatim stop-sentences + the ONLY four legitimate stops); **F2** unblock yourself before you stop (the tool ladder + self-unblock playbook: rotate creds via `browser`, triage CI via `git blame`+`agents sessions`, owner-contact last); **F3** "done" = the verified user-visible outcome (merged≠deployed, run the installed artifact, docs+CHANGELOG in the same delivery, status-question≠release-trigger, swarm cross-track seam); **F4** involve the human minimally and land it where they are; **F5** protect what you can't undo (worktree+PR, never `reset --hard`/force-push, transcript confidentiality, irreversible-escalation sign-off).
- **`core-hard-lines.md` and `workflow-proactive.md` are removed; every operative rule they held was rehomed, nothing lost.** New homes: `research-discipline.md` (no-unverified-claims, no-lazy-debugging, date-anchoring, web-search-first, investigation-brief evidence line, no-human-estimates); `fleet-delegation.md` (spread across harnesses/accounts, reserve Opus, set subagent `model` explicitly, parallelize from message one); no-fallbacks → `code-quality.md`; ACT→VERIFY→SHOW + waiting mechanics + design-before-code → `operational.md`. `rules.yaml` lists `foundations` first, then `research-discipline`, `fleet-delegation`. Every `core-hard-lines #N` citation across subrules, skills, and commands was rewritten to the F1–F5 references (`testing-strict`, `parallel-teams`, `truly-agentic-git-workflow`, `git-workflow`/`learn`/`clify`/`fleet` skills). The `gh-merge-guard`, `no-pr-footer`, `plan-presentation`, and `truly-agentic-git-workflow` guard subrules (and their live hooks) are unchanged — enforcement is untouched. Verified: composition renders foundations-first, each theme appears once, no dangling references, all F1–F5 cited by tactics.

## [0.1.82] - 2026-08-01

### Fixed
- **The swarm integration Stop gate no longer false-fires on a session that merely *searches for* its own trigger strings.** The gate (added in 0.1.74) detected an edit-mode swarm by substring — `'agents teams start' in cmd` — so any tool command that *contained* that text, e.g. `grep -cE "agents teams start|agents teams create" transcript.jsonl` (or an echo, a heredoc, or editing this hook's own fixtures), counted as having run a swarm and blocked the stop with the composed-flow demand. It fired on the very session hardening the hook. Detection now uses an anchored regex requiring `agents teams start|create` (or `agents teams add … --mode edit`) at an actual command position — start of the command, or after a newline / `;` / `&&` / `$(` — and deliberately omits a bare `|` separator, since piping *into* `agents teams start` is never a real invocation but is exactly how a grep alternation reads. Verified against the real false-positive transcript (old detection → `YES`, new → `no`); a real `agents teams start` invocation still triggers. `hooks/00-agent-verify-work-complete.sh` + 2 new fixtures in `_test.sh` (27 pass).

## [0.1.81] - 2026-08-01

### Changed
- **`rules/subrules/core-hard-lines.md` now opens with the agent-vs-chatbot identity frame plus the *measured* cost of idle-stops.** Building on the `YOU ARE AN AGENT, NOT A CHATBOT` identity block and its three chatbot tells (PR #126), a grounded evidence block now sits directly under it (PR #129): a 30-day, on-box, redacted mining of ~12,459 Claude sessions across the fleet measured **588 hours** lost to avoidable permission-stops — 1,045 incidents, with the phrases "want me to…?" and "say the word…" alone accounting for 80% of the lost hours. Four of the agents' own worst verbatim stop-sentences are quoted (the one that wrote "that's the natural next step" then idled 345 minutes instead of taking it), so the anti-stop rule is concrete rather than abstract, followed by a restatement that the only legitimate stop is a decision genuinely the user's. Passed a non-author review that corrected the 80%-by-hours framing, an em-dash violation, and condensed-vs-verbatim quotes; the mining stayed strictly on-box (no transcript content leaves the machine) and the block is live across every installed harness on the reachable fleet.

## [0.1.80] - 2026-08-01

### Fixed
- **`rules/subrules/no-pr-footer/footer-guard.sh` no longer fails OPEN when `jq` is absent.** The guard extracted the tool command with a single `jq` call and `|| cmd=""`, then `[ -n "$cmd" ] || exit 0` — so on any host without `jq` (notably stock Git Bash on Windows) it silently allowed the banned "Generated with Claude Code" footer onto every PR/issue/commit. It now uses the same `jq -> node -> python` `_json_field` helper the sibling guards (`main-branch-guard.sh`, `merge-guard.sh`) already carry and fails CLOSED (exit 2 with an explanatory message) when no JSON parser is on PATH, since the command already matched the gh/git fast path. Verified: clean commit allowed (rc 0), inline footer blocked via jq and via the node fallback (rc 2), and no-parser input refused (rc 2).

### Added
- **A multi-step plan now also requires a task checklist before it can be presented, and the checklist expectation extends past plan mode.** `rules/subrules/plan-presentation/plan-html-reminder.sh` gains a second gate after the HTML-render check: when the `ExitPlanMode` plan text carries 3+ step-like lines, the hook blocks once (exit 2) unless a checklist tool (`TaskCreate`/`TodoWrite`/`todo_write`/`update_plan`) fired since the last genuine human turn. It fails open (no transcript, a trivial plan, or no locatable human turn allows the presentation), so a simple plan is never blocked. A new `rules/subrules/task-checklists.md` (added to the `default` preset in `rules/rules.yaml`) extends the checklist expectation to any real multi-step work in auto/edit mode and binds the checklist to a Linear ticket via `TaskCreate` `metadata.ticket`; `rules/subrules/plan-presentation/rule.md` documents the gate and `plan-html-reminder_test.sh` covers it (13 pass).

### Fixed
- **`rules/subrules/task-checklists.md` — capped em-dashes at one per paragraph** per the `code-quality` precise-prose rule the file itself is subject to: the "acceptance rubric" paragraph had two, and the second is now a colon.

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
