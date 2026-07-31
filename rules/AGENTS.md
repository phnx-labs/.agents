# Core Hard Lines (Tier 1)

> Tier 1 of 3 — companion tiers: `code-quality` (Tier 2), `operational` (Tier 3).

Non-negotiable. Ordered by impact.

1. **"Done" means end-to-end.** Not "code written" or "unit tests pass." Trigger the real flow and see real output. Verify the **user-visible outcome, not a proxy** — "Electron signed + CDP responded" is not "zero Keychain prompts"; "unit tests pass" is not "the image arrived in the iMessage thread"; "the integration is wired" is not "`ag run droid` works." Never write "confirmed end-to-end" when your own evidence shows a ⚠️, "hung", "skipped", or an untriggered hop — quote the gap and call it unverified instead. If a blocker prevents testing, work around it — reduce scope, override config, run the command directly. Re-read the conversation and verify every goal before claiming done.

2. **No unverified claims.** Every factual claim — code, counts, sizes, API capabilities — needs proof: file path, line number, code quoted from this conversation. "I think there are 26 files" is a violation. Run the tool, then report. When in doubt, spawn subagents — cost is irrelevant, correctness is everything.

3. **No lazy debugging.** Read every file in the data path. If data flows A → B → C → D, read all four and present file:line quotes from each.

4. **No fallbacks, no band-aids.** Never add "just in case" code paths. Standardize at the source. Every fallback hides a bug.

5. **Current date anchoring.** Your weights are stale. The real date is in the system prompt under `currentDate`. Every web query about state-of-the-world (models, APIs, prices, libraries, releases) must include the current YEAR.

6. **Web-search first for time-sensitive claims.** WebSearch before answering, not "if the user asks." Load search tools eagerly at session start: `ToolSearch select:WebSearch,WebFetch`.

7. **Ban Haiku for subagents.** Always set `model` explicitly on Agent calls. Default `"sonnet"`, use `"opus"` for load-bearing work. Omission falls through to subagent frontmatter, which may pin haiku.

8. **Investigation briefs demand evidence.** Every Agent prompt for investigation/debugging/review must end with: `Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.`

9. **Exhaust alternatives before declaring a blocker.** "I cannot do X. Period." is banned without three distinct attempts quoted. The fix is almost never "ask the user" — it's "try a different launch path."

10. **Never ask the user to verify env state you can check yourself.** You have the same shell, OS, and files. List, query, probe, dump.

11. **Parallelize from message one for multi-dimensional questions.** Multiple files, cross-platform, audit, ship-readiness, parity check, root-cause across a stack — spawn 3-7 Agent subagents in parallel in your first response. About to write a third sequential Bash investigation call? Stop and spawn agents instead.

# Proactive Workflow

**Pattern: ACT → VERIFY → SHOW → CONTINUE.**

- See a problem? Investigate, fix it. Don't ask permission for obvious fixes.
- Path clear? Take it. Don't narrate — do.
- Unsure which path? Decide, state reasoning in one line, continue. User will redirect.

**Never say:** "I noticed X — would you like me to investigate?" You should have already.

## Don't stop mid-task

After ACT → VERIFY → SHOW the next step is CONTINUE, not pause. Stopping is for:
- Hard blockers (quote the obstacle and three attempts to work around it)
- Genuine ambiguity in user intent (not "shall I proceed?")
- Task is actually delivered end-to-end (committed, pushed, **merged + shipped**, real-flow verified) — a PR merely being *open* is not a stop; merge autonomously on green review + CI (see `git-workflow`)

If the user types "check", "continue", or "status?" — you missed this rule.

**Specifically banned stops** (each cost a real correction in past sessions):
- Writing a plan, then stopping for an approval the user already gave. "Yeah do it" / "go" means build it — don't re-ask.
- Serial `AskUserQuestion` gates for steps that aren't genuinely ambiguous. Pick the clear default, state it in one line, continue — a round-trip you didn't need is a stop.
- Handing the user a command to run when you can run it yourself. You have the same shell + ssh; "Run what??" means you should have just run it. (See `operational` — only hand off what the user *must* run on their own machine.)

**`AskUserQuestion` is not an off-ramp.** Use it only for genuine intent ambiguity. Not for "should I do the obvious next step?"

## Waiting

- Short waits (<2 min): `sleep 45 && echo "checking..."`
- Long waits (2+ min): `run_in_background: true` with echo sleeve — `long-cmd && echo "DONE — next: <action>"`

## Design before code

Only for *new* design (UI flow, architecture, pipeline shape). Show mockup/diagram, then ship. For follow-ups and edits, skip the design step — go straight to code.

# Code Quality (Tier 2)

> Tier 2 of 3 — companion tiers: `core-hard-lines` (Tier 1), `operational` (Tier 3).

- **No duplicate code.** Search before writing. Use or extend what exists.
- **No scope creep.** Do exactly what was asked. No drive-by refactors, renames, or import reorganization.
- **Cross-cutting changes go to the source.** Edit the canonical location, never ad-hoc logic in consumers. If no central place exists, propose refactoring first.
- **User-facing text must be human.** "13 minutes" not "12m 49s", "30 seconds" not "30.0s". If a grandmother can't parse it, rewrite it.
- **Write prose precisely; don't market.** Wherever you write for a human to read (plans, PRs, commit messages, code comments, chat), name the concrete thing (the file, function, flag, number, or error), not a vague stand-in ("things", "surfaces", "stuff", "various") unless that word is the real technical term. Cut the marketing register: no slogans, no "Critically:" / "Notably:" drama, no filler adjectives ("seamless", "powerful", "robust", "leverage", "simply"). Cap em-dashes at one per paragraph; never stack appositive dashes (the "X — Y — Z" pattern). The reader is reviewing your claim, not being sold it.

# Strict Testing

- **Test file = source file, 1:1.** `read.go` → `read_test.go`, `parser.ts` → `parser.test.ts`.
- **Tests live in the codebase, not `/tmp`.** Fixtures in `testdata/` near source.
- **No mocking.** Real services only. Tests must exercise the actual critical path.
- **Only tests that catch real bugs:** merge logic, state corruption, algorithmic edges. Skip constants and trivial guards — if the test would pass with a broken implementation, it's ceremony.
- **Unit tests are necessary, not sufficient.** Verify end-to-end (core-hard-lines #1).

# Truly Agentic Git Workflow

**The default branch is untouchable. Every change is a worktree + PR. Always.**

Never create, edit, or delete a file with the agent's file tools
(Write/Edit/NotebookEdit), and never `git add`/`git commit`, while a repo is on its
default branch (`main`/`master`/whatever `origin/HEAD` points at). This is
**mechanically enforced** by the bundled `main-branch-guard` (PreToolUse). The
commit gate is the choke point: even a file changed by raw shell (`>`, `sed -i`,
`git rm`) on the default branch can never be *committed* there — so nothing lands
on the default branch outside a worktree + PR. No exceptions, no escape hatch.
Worktrees (feature branches), non-git paths (`/tmp`, scratchpad), and
**gitignored paths** (e.g. the harness memory dir under `.history/`, or
`.agents/scratch`, `.agents/artifacts`) are unaffected — a gitignored file can
never be committed, so a write there can't land on the default branch. The guard
gates only the agent's tool calls — the user's own editor and `!`-prefixed
session commands are never blocked.

If you catch yourself about to edit a file in a checkout that's on `main`, stop
and make a worktree first (recipe below).

## Allowed vs off-limits git ops

Allowed: `status`, `diff`, `log`, `show`, `remote`, `ls-files`, `cat-file`,
`rev-parse`, `describe`, `shortlog`, `blame`, `tag`, `check-ignore`,
`config --get`, `ls-tree`, `add`, `commit`, `push`, `clone`, `fetch`,
`worktree list`, `worktree add`, `worktree remove`. (`add`/`commit` only off the
default branch — see above.)

Off-limits without an explicit user ask: `checkout`, `switch`, `branch`, `stash`,
`reset`, `rebase`, `cherry-pick`, `revert`, `merge --abort`, `clean`, `reflog`,
`filter-branch`, `gc`, `prune`, `fsck`, `config` (write), force push.

**Why:** autonomous agents have caused real data loss with `git reset --hard`,
`git checkout -- .`, and force pushes — fast, irreversible, hard to audit. The
`git-guard` hook blocks these on the agent's own shell.

**On obstacles** (merge conflict, lock file, unexpected state): investigate and
resolve at the source. Don't `git reset` or `git clean` as a shortcut — that's how
in-progress work disappears.

## Worktree recipe

PR-bound work runs in an isolated worktree, never in the user's checkout. Don't
create a branch in place, don't switch the user's checkout, don't ask the user to
run git — `git worktree add -b` is the allowed, isolated branch-creation path.

1. **Always fetch first, base off the freshly-fetched default branch** so the
   worktree carries the latest remote changes. Never `git pull` the checkout
   (`pull` mutates it); `fetch` + base-off-`origin/<default>` gets latest without
   touching the user's tree. Never hardcode `main` — resolve the default:
   ```
   REPO=$(git rev-parse --show-toplevel)
   git -C "$REPO" fetch origin
   git -C "$REPO" remote set-head origin --auto
   BASE=$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')
   git -C "$REPO" worktree add -b <slug> "$REPO/.agents/worktrees/<slug>" "origin/$BASE"
   ```
   Worktrees live **only** under `<repo>/.agents/worktrees/<slug>/`.
2. **End-to-end inside `$WT`:** implement → test → verify the real flow → commit →
   push → open PR, all in the worktree.
3. **Worktree integrity (multi-agent safe).** Create worktrees **foreground**,
   never as a background task — a backgrounded `git worktree add` races other
   agents' index writes into a corrupted, half-populated checkout. After
   `git worktree add`, verify the checkout is complete before building:
   `git -C "$WT" status --short | grep '^ D'` must be empty. In a shared checkout,
   commit with an explicit pathspec — `git commit <path>`, never
   `git add <file> && git commit` — so a concurrent agent's staged files aren't
   swept into your commit. Reproduce CI/build failures in the clean worktree, not
   a dirty checkout (a dirty tree yields false-positive failures).

Full recipe — worktree creation, PR, after-merge cleanup: the `git-workflow` skill.

## Open with evidence attached — screenshots, artifacts, a confidential transcript

Opening something for a human — a **PR**, a **GitHub issue**, or a **ticket**
(Linear/Jira) — is a handoff, not a stopping point. Identify which flow you're in
and attach what the reviewer needs to judge it without re-running your session.
Every `gh pr create` / `gh issue create` / ticket-open carries:

- **Screenshots and relevant materials of the user-visible outcome** — the rendered
  UI, the passing test run, the `curl`'d health response, a before/after. If you
  produced a visual while verifying end-to-end (core-hard-lines #1), it belongs in
  the body. Upload the image to the PR/issue (`gh pr comment <pr> --body` with the
  asset, or drag it into the web UI); reference on-disk images by **full path** so
  the reviewer can click to preview.
- **A session transcript — kept confidential, always.** The transcript can carry
  secrets, tokens, internal paths, and raw reasoning, so it **never** goes inline in
  a PR/issue/ticket body and **never** touches a public repo or public tracker. On a
  **private** repo / internal tracker, attach it as a **secret gist** and link only:
  `gh gist create --secret <session-id>.jsonl` → paste the returned URL. On a
  **public** repo, omit the transcript entirely and instead reference the local path
  (`<host>:<session-dir>/<session-id>.jsonl`) so a teammate on the fleet can open it.
  Never paste transcript text anywhere it could be indexed or cached.

## PR open is NOT done — actively wait, never make the user ping

Opening a PR is not a stopping point. After `gh pr create`, **actively wait for
CI** with the background-command + finish-echo pattern (never `Monitor`,
`ScheduleWakeup`, or `until` loops — they fail silently), then review and merge:

```
(gh pr checks <pr> --watch --fail-fast; echo "CI settled rc=$? — next: non-author review, then merge on green")
```
run with `run_in_background: true` — the harness re-invokes you the moment checks
settle. If the PR has no checks configured, go straight to review. A non-author
review **and** green CI = rebase-merge without asking (see `gh-merge-guard`); fall
back to `AskUserQuestion` only when the review finds problems, tests fail, or the
merge conflicts. Don't remove the worktree or delete the branch until merge.
Never stop with a limp "okay, I'll wait" — that just makes the user ping you.

## Reconcile with rebase; never `reset --hard`; never stash

**Never stash — commit instead.** Uncommitted working-tree changes get committed
properly via the `/code:commit` skill (maximum small logical commits), never
`git stash`. Stash hides work somewhere easy to lose; a commit is durable,
reviewable, recoverable.

**Uncommitted changes on `main` → commit on a branch + WIP PR.** If the main
working tree has uncommitted changes, don't leave them dirty and don't commit
straight to `main`: move them to a worktree/branch and open a **WIP pull request**.

**Reconcile with rebase — `reset --hard` is never run.** To bring a behind/diverged
branch up to its upstream, use `git pull --rebase` / `git rebase origin/<branch>`:
it replays local commits and drops only those already upstream (patch-id match),
preserving genuinely unique work. **Never run `git reset --hard`, period** — it
discards commits unconditionally and irrecoverably. `rebase` needs explicit user
OK and the `git-guard` hook blocks it on the agent's shell — so hand a rebase to
the user via the `!` session prefix (`!git -C <repo> rebase origin/<branch>`),
which bypasses the agent hook.

# Merge & Admin-Bypass Guard

Authorization to do the work carries through to the merge — an in-session "build it / open a PR / fix this" authorizes a **rebase-merge on green**, no fresh ask needed. What still needs explicit authorization is merging *past* the safety rails: never bypass branch protection, never rubber-stamp your own code, never merge red.

- **Merge autonomously on green; ask only on red.** A non-author review **and** passing CI = rebase-merge without asking (see `git-workflow`). Fall back to `AskUserQuestion` (merge / iterate / close) only when the review finds problems, tests fail, or the merge conflicts. "Green" means a genuine independent review + CI, never a rubber stamp.
- **Never `gh pr merge --admin`.** Admin bypass merges past branch protection and required reviews. The bundled `merge-guard.sh` (PreToolUse) blocks it. Merge *without* `--admin` so protections still apply — if protections block the merge, that's a red to resolve, not a thing to bypass.
- **Never self-approve your own PR.** Reviewing and approving code you wrote, then merging it, is not review. The reviewer that clears the green must be someone — or some agent — other than the author.
- **Never transfer credentials or auth files** (tokens, `~/.rush/user.yaml`, keychain exports) to another host or VM without explicit authorization. Don't attempt the transfer first and surface a question only after a guard blocks you.

# No Claude-Code Footer

Never add the "Generated with Claude Code" promo line — or any `🤖 Generated with …`, `claude.com/claude-code`, or `claude.ai/code` variant — to PR bodies, GitHub issue bodies, or commit messages. Muqsit called it garbage. Applies to `gh pr create`/`edit`, `gh issue create`/`edit`, and `git commit`.

Enforced by the bundled `footer-guard.sh` (PreToolUse): a `gh`/`git commit` command whose inline body carries the footer is blocked. If you hit the block, delete the footer line and retry — don't work around the guard.

# Operational Guardrails (Tier 3)

> Tier 3 of 3 — companion tiers: `core-hard-lines` (Tier 1), `code-quality` (Tier 2).

- **Ask about scope; decide about implementation.** Unclear what the user wants (requirements, scope, priorities)? Ask — 30 seconds beats hours of wrong work. Unclear *how* to implement what they asked for? Decide, state reasoning briefly, keep going (see `workflow-proactive`).
- **No emojis** in code, comments, commits, or user-facing output — unless explicitly asked.
- **No credentials in env vars or config.** Use `agents secrets` (OS keychain-backed).
- **No locally built CLIs.** Install globally (`npm i -g`, `cargo install`); don't invoke `./bin/foo`.
- **No background shells left running.** Foreground or explicit `run_in_background` with a finish signal.
- **No toasts.** Silent success, inline errors.
- **No unsolicited .md files.** No README/docs/summary/notes unless asked.
- **Permissions:** Add permanent agent permissions to settings once; don't re-prompt across sessions.
- **Images:** Include the full file path so the user can click to preview.
- **Run it yourself when you can; only hand off what the user *must* run.** If you have the shell or ssh to execute it, execute it — don't hand the user a command for something you could run (a past session got "Run what??" for exactly this). Hand off only genuine user-only actions: an interactive login on their machine, a host you can't reach, an auth prompt that needs their biometric. **For those, don't just print them** — markdown code fences aren't executable. Prefer, in order: (1) pipe to the clipboard (`pbcopy` on macOS, `xclip -selection clipboard` / `wl-copy` on Linux) and tell the user "copied — paste it"; (2) write a one-shot script to a temp path (`mktemp` or `/tmp/<slug>.sh`), `chmod +x` it, and tell them to run that single path; (3) only as last resort, render the command in the message. Multi-line commands always go to a script. Quote what you copied so the user can verify before pasting.
- **Don't:** start/kill dev servers without asking; add backwards-compat shims you weren't asked for; reach for `find` when a faster finder like `fd` is available.

# Conventions

- **Memory file:** `AGENTS.md` is canonical. `CLAUDE.md` and `GEMINI.md` are symlinks (or synced copies).
- **Tickets:** Linear context is auto-injected at session start by the linear hook — read it before starting work. Use `/tickets` to take explicit action (query, update, close) on tickets across Linear/GitHub/Jira. Close only with proof.
- **Parallel work:** Multi-surface changes use `agents teams` — see `parallel-teams`.

# agents-cli

- **Agent home dirs are symlinks.** `~/.claude/`, `~/.codex/`, etc. point into `~/.agents/versions/{agent}/{version}/home/`. Source of truth for shared config (commands, skills, hooks, memory, MCP) is `~/.agents/` — go there to inspect or modify.
- **Recall prior work with `agents sessions`.** Search by topic/repo before starting. Use `--include`/`--exclude` to filter roles. `agents sessions --help` for full flags.
- **Check active agents before spawning new ones.** `agents sessions --active` lists everything running right now (terminals, teams, cloud, headless).

# Parallel Work via `agents teams`

Default to teams for changes touching 3+ independent surfaces. Single-threaded editing is the failure mode.

**Skip for:** exploration (use `Agent` subagents), single-surface bugs, plan-mode research.

## Boundary contracts are mandatory

Before spawning, present a distribution plan. Each teammate needs:

- **Owns** — explicit files.
- **Must NOT touch** — files owned by others.
- **Shared deps** — one canonical owner; everyone else imports.

If A waits on B's output to start, the split is wrong. Re-cut, or sequence with `--after`.

## Pattern

```bash
agents teams create my-feature
agents teams add my-feature claude "Owns: src/auth/*. Not: src/ui/*. ..." --name auth
agents teams add my-feature codex  "Owns: src/ui/*. Not: src/auth/*. ..." --name ui --after auth
agents teams start my-feature --watch
```

Every brief includes Mission, Full scope, Owns, Must NOT touch, concrete code pattern, success criteria, and ends with the line from core-hard-lines #8. The `/teams` command is the long-form playbook.

# Tooling & Stack Conventions

## Right tool for the job

| Task | Tool |
| --- | --- |
| Query large docs (.md, .html, .pdf) | `mq` — for files 100+ lines, probe then extract |
| Issue tracker (Linear/GitHub/Jira) | `/tickets` command — auto-detects |
| Browser automation | `browser` skill (a.k.a. `agents browser`) |
| Interactive terminal (REPLs, TUIs) | `agents pty` — see `agents pty --help` |
| Parallel coding agents | `agents teams` — see `parallel-teams` |
| Credentials | `agents secrets` — OS keychain-backed |
| Release/publish | `release` skill |

# Present Plans as Browser-Ready HTML

**Whenever you produce an implementation plan — the harness's native plan mode
(the `ref-*.md` plan file), the `/plan` command, or `/swarm:plan` — do not leave it
in terminal scrollback. Render it as a self-contained HTML doc and open it in the
user's default browser on the machine they sit at.**

This is mechanically reminded by the bundled `plan-html-reminder` hook (PreToolUse on
`ExitPlanMode`): it nudges you to render + open before you present. The full LOOK — the
house structure, the product-brand theming, the light/dark toggle, and the open-on-Mac
transport — lives in the **`plan-render` skill**. Load it and follow it.

- **Structure (fixed).** Hero (kicker · headline · problem statement · metadata chips ·
  TOC), numbered sections, **≥1 hand-authored inline-SVG diagram** (timeline /
  architecture / before-after — never mermaid), callouts, tagged tables, code blocks.
  Start from the skill's `template.html`; `example.html` is the gold reference.
- **Theme (adopted).** Skin the plan in the **target product's brand** — probe the repo
  for design tokens, tailwind/CSS vars, logo/manifest colors. Fall back to the dark +
  light editorial house palette only when the product declares no brand.
- **Light + dark.** Ship the in-page `◐` toggle, defaulting to the OS
  `prefers-color-scheme`, so the plan is readable in bright light and dim alike.
- **Open it proactively, every time.** Resolve the online macOS device from the
  **Host & Fleet** context (`agents ssh <host> 'open …'` when remote; local `open` /
  `xdg-open` otherwise). macOS `open` uses the user's **default browser**. **Never
  hardcode a host** — resolve it from `agents devices`. If the user is away, the plan is
  waiting in a tab when they return. Skip only the *open* (never the render) when no
  browser host is reachable.

A plan the user can't see rendered is not presented. Render, open, then discuss.
