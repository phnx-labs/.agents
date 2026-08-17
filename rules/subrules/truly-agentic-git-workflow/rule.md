# Truly Agentic Git Workflow

**The user's primary working tree is untouchable — on ANY branch. Every change is
a LINKED worktree + PR. Always.**

Never create, edit, or delete a tracked file with the agent's file tools
(Write/Edit/NotebookEdit), and never `git add`/`git commit`, while the target is
inside a repo's **primary working tree** — the user's own checkout — regardless of
which branch it is on. This is **mechanically enforced** by the bundled
`main-branch-guard` (PreToolUse), which protects the whole primary tree, not just
the default branch. The reason it is the whole tree: agents were checking out a
feature branch *in the user's main checkout* and never switching back, stranding
it on a branch and dozens of commits behind (the `review-2704` trap) — blocking
only the default branch let that through.

The ONLY place an agent writes, adds, or commits is a **linked worktree**
(`git worktree add` under `<repo>/.agents/worktrees/<slug>/`). Linked worktrees,
non-git paths (`/tmp`, scratchpad), and **gitignored paths** (the harness memory
dir under `.history/`, `.agents/scratch`, `.agents/artifacts`) are unaffected — a
gitignored file never dirties the tracked tree or lands in a PR. The guard gates
only the agent's tool calls — the user's own editor and `!`-prefixed session
commands are never blocked.

`git switch` and `git checkout` are **both banned** for the agent (enforced by
`git-guard`): switching the primary checkout onto another branch is exactly the
strand-the-tree trap. Never switch branches in place — create a linked worktree.

If you catch yourself about to edit a file in the primary checkout (any branch),
stop and make a worktree first (recipe below).

**Diagnose on the latest code, not your working-tree HEAD.** Before you read a
codebase to call something a bug, claim a regression, or open a "fix" PR,
`git fetch origin` and check how far behind you are
(`git rev-list --count HEAD..origin/<default>`). Your local checkout goes stale
the moment another agent pushes — on this fleet, constantly — and a fix built on
stale code is itself the regression (a real miss: a merged PR "restored" a routine
a newer commit had deliberately superseded, because the diagnosis ran against a
tree ~90 min / 39 commits behind). This is the same fetch-first discipline the
worktree recipe enforces for *writing*, applied to *reading*. See
`research-discipline` (current-code anchoring).

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
   Worktrees live **only** under `<repo>/.agents/worktrees/<slug>/`. The
   `origin/<default>` base is **mechanically enforced** — `main-branch-guard`
   denies `git worktree add -b/-B` with an implicit (current-HEAD) or local-branch
   base, **and** denies a remote-tracking base whose ref (or `FETCH_HEAD`) is older
   than `AGENTS_WORKTREE_FETCH_MAX_AGE_SEC` (default 900s / 15 minutes). Form-only
   `origin/*` was not enough: agents passed a days-stale `origin/main` and only
   discovered the lag at merge. Fetch first, then base off `origin/<default>` (a
   raw commit SHA or tag is still allowed for the rare deliberate pin).
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

The worktree recipe above is complete — there is no separate skill. After merge: `git -C "$REPO" worktree remove "$WT"` then `gh pr merge --rebase --delete-branch`.

## Open with evidence attached — screenshots, artifacts, a confidential transcript

Opening a **PR**, **GitHub issue**, or **ticket** (Linear/Jira) is not a stop and
a PR is not a handoff to the user to merge. Attach what the **non-author reviewer**
(automated bot or subagent) needs to judge the change without re-running your
session. Issues/tickets that need a human decision still land where the user is (F4).

**The description must be glanceable — lead with what changed and for whom.** The
reviewer reads the body, not the diff, so a wall of prose (or a one-liner) is a PR they
cannot glance. Open with a one-line **what + type** at the very top: a no-behavior-change
PR says **docs-only** / **refactor** / **test-only** so the reviewer calibrates
instantly. Then **highlight** the important parts — a `##` heading, a table, short
bullets — never a prose wall. For a **docs** PR, **state the audience** (maintainers vs
end users). If a reviewer can't tell in ten seconds what changed and why, rewrite it.

**Run it, look at the result, then open the PR — not the other way round.** You are an
agentic developer: before you open a PR you **run the feature you built, look at the real
output, and attach that result**. A PR is not "code written" — it is "ran it, here's the
proof" (this is F3 at the PR boundary). Do not open the PR until you
have. **The only exceptions are a release PR and a pure doc edit** — those need no run.

The body carries **the actual run result, not a description of it**:

- **A user-visible change ships a picture — a screenshot is required, not optional.**
  The reviewer should not have to read code or a hand-made table to believe it works;
  they should **see it work**. Capture the running feature (the web UI, the app screen),
  publish it with **`agents artifacts share <file>`** (§Attaching evidence), and embed the returned
  URL in the body with `![caption](url)`. When the change has a visible before/after, show
  **both** stills.
- **Prefer a recording when a still can't carry the flow.** You have the tools: capture a
  **web app** with the `browser` skill (record the click-through), or a **terminal flow**
  with `agents pty` (record the run), and attach the file.
- **A no-UI change still shows the run** — screenshot the passing run / the `curl`'d
  response, or `agents artifacts share` the run's output or log as an **asset** and link it. Pasted
  **source code** and **hand-authored tables are not proof of a run** and do not count. If
  there is genuinely no visible surface, **declare it** (refactor / test-only).
- **Link the context.** Include the **Linear ticket** for the work, and — if a plan was
  shared — a **shareable link to the plan file**. The same screenshot/recording also goes
  on the ticket when you close it (see `conventions`).

The bundled `pr-description-reminder` (PreToolUse) is the backstop, and it **reads the body
you actually ship** — an inline `--body`/`-b` and the file behind `--body-file`/`-F` alike
(the common multi-line path, and the hole that used to let evidence-free feature PRs through).
It nudges — a satisfiable block, `exit 2` — when that body shows **no run result** (no
image / recording / uploaded asset), and it is **not** cleared by a code block, a table, or a
bare ticket/plan link: those are context, not proof you ran it. It clears on a real run result
**or** an explicit no-run declaration — and a **checkable declaration is verified against the
branch's changed files**: `test-only` with non-test files changed, or `docs-only` with code
changed, **blocks** instead of clearing (2026-08-15, PR #2736 declared "test-only." on a
fifteen-file `fix(browser)` diff), and bare `release` only counts in release-shaped phrases
(`chore(release)` / "release PR" / "release:" / "release v"). Unverifiable declarations
(`refactor` / no-behavior-change) clear as before. It still **fails open** on a `--fill` /
`--template` / editor body it cannot read, on an unreadable `--body-file`, and on an
unreadable branch diff — a reminder must never block a legit PR.

### Attaching evidence on GitHub — the mechanics

`gh` **cannot upload an image inline.** `gh pr create/edit --body` only takes text, so a
local screenshot path in the body does **not** render on GitHub. Get the asset a public URL
and embed it with `![caption](url)`. Use these, in order:

1. **`agents artifacts share <file>` — the primary mechanic.** It publishes any static asset (a
   `.png`/`.jpg`/`.gif` screenshot, a `.mp4`/`.mov`/`.webm` recording, a `.pdf`) to your own
   Cloudflare R2 and prints a public URL that renders inline via `![caption](url)`. No
   browser and no manual drag-drop, so it works **headlessly** — the default way an agent
   attaches media. Not configured on this box? `agents artifacts share status` says so; configure it
   once with `agents artifacts setup` (provision your own endpoint) or `agents artifacts share join
   <baseUrl>` (use an existing one), then re-run. If you truly cannot configure it, hand the
   one-time `agents artifacts setup` to the user and use drag-drop meanwhile. **Public share is
   for shareable visual proof only** — never publish a private or secret asset (a
   raw transcript, anything carrying tokens or internal paths) to a public R2 URL; those stay in
   a secret gist or a local path (see the transcript rule below). `--expire 30d` bounds the
   link's life.

   **The one carve-out is `agents sessions share <id>`**, and it is narrow. That command
   does not publish a raw transcript: it publishes the **redacted render** (`agents sessions
   render`'s document — credential-shaped values, known secret values, and local home paths
   masked — plus email masking the raw render does not do), **unlisted** by default, with the
   30d expiry. Use it when a human deliberately asks you to send them a session. It is **not**
   an evidence mechanism: it does not license attaching a transcript to a PR, issue, or ticket
   body, which the transcript rule below still forbids outright — attach a **secret gist** there,
   or reference `<host>:<path>` on a public repo. And unlisted is **not** access control: R2
   reads are public, so anyone with the exact URL reads the page. Never call such a link
   private, encrypted, or access-gated.
2. **Web drag-drop (browser-only fallback).** When `agents artifacts share` isn't available, open the
   PR/comment box in the browser and drag the image/recording (`.png`/`.gif`/`.mp4`/`.mov`)
   in. GitHub uploads it and inserts a `https://github.com/user-attachments/assets/…` URL
   that renders inline via `![](…)`. Open the PR on the user's Mac to do it (`agents ssh
   <mac> 'open <pr-url>'`), or drive the upload with the `browser` skill.
3. **Comment after the fact.** Once you have a public URL (an `agents artifacts share` link or a
   `user-attachments` URL), `gh pr comment <pr> --body '![result](<url>)'` adds it without
   touching the body.
4. **Path fallback (fleet-local only).** If you genuinely can't upload anywhere, reference
   the artifact by **full host:path** (`<host>:/abs/path.png`) and `open` it on the user's
   machine so they see it. It won't render on GitHub, but a teammate on the fleet can open
   it. Say plainly that it's a path, not an embed.

Never commit a screenshot into the repo just to embed it — that is clutter; use `agents
share` or the upload flow.

Every `gh pr create` / `gh issue create` / ticket-open carries:

- **Screenshots and relevant materials of the user-visible outcome** — the rendered
  UI, the passing test run, the `curl`'d health response, a before/after. If you
  produced a visual while verifying end-to-end (F3), it belongs in
  the body. Publish it with `agents artifacts share <file>` and embed the URL (or drag it into the
  web UI); reference on-disk images by **full path** so the reviewer can click to preview.
- **A session transcript — kept confidential, always.** The transcript can carry
  secrets, tokens, internal paths, and raw reasoning, so it **never** goes inline in
  a PR/issue/ticket body and **never** touches a public repo or public tracker. On a
  **private** repo / internal tracker, attach it as a **secret gist** and link only:
  `gh gist create --secret <session-id>.jsonl` → paste the returned URL. On a
  **public** repo, omit the transcript entirely and instead reference the local path
  (`<host>:<session-dir>/<session-id>.jsonl`) so a teammate on the fleet can open it.
  Never paste transcript text anywhere it could be indexed or cached.

## PR open is NOT done — drive review + merge yourself

Opening a PR is not a stopping point and **not a handoff**. Do **not** open the
PR URL in the user's browser, drop a "please review + merge" link, or wait for
them to click anything. Authorization to do the work already carries through to
**rebase-merge on green** (see `gh-merge-guard`). You own CI, non-author review,
and the merge.

### Right after `gh pr create` — two tracks in parallel

1. **Watch CI** with the background-command + finish-echo pattern (never
   `Monitor`, `ScheduleWakeup`, or `until` loops — they fail silently):

```
(gh pr checks <pr> --watch --fail-fast; echo "CI settled rc=$? — next: non-author review, then merge on green")
```

   run with `run_in_background: true` — the harness re-invokes you when checks
   settle. If the PR has no checks configured, skip the watch and go to review.

2. **Check whether the automated code reviewer is functioning** — do this
   immediately, do not wait for CI to finish first:

   - **Is one configured?** Look for a checked-in config (this stack:
     `.github/rush.yml` declaring a `prix/code-reviewer` agent that posts as
     `prix-cloud` on `opened`/`reopened`/`synchronize`). A workflow listing alone
     is not enough — read the config file.
   - **Is it alive on this PR?** After open (and again after a short settle if
     needed), check for its review or comment (`gh pr view <n> --json
     reviews,comments` / `gh api repos/.../pulls/<n>/comments`). A prior PR on
     the same repo that got a bot review is weak evidence of config; **this PR's
     thread** is the live signal.

**If the automated reviewer is configured and posting** — wait for its verdict;
do not spawn a redundant subagent on top of a working bot.

**If it is missing, silent, down, or the repo has no automated reviewer** — do
**not** wait and do **not** hand the merge to the user. Spawn a non-author
subagent review **as soon as possible** (`code:review` / the review skill, or an
in-session `Agent` that did not author the PR). That subagent's clear verdict is
the non-author review that clears merge-on-green.

A non-author review **and** green CI = rebase-merge without asking; fall back to
`AskUserQuestion` only when the review finds problems, tests fail, or the merge
conflicts. Don't remove the worktree or delete the branch until merge. Never
stop with a limp "okay, I'll wait" or a PR link for the user to open.

The only real user handoff at this boundary is a **governance / product / identity
sign-off only they can give** (not "please merge this ordinary PR"). Park that
decision with F4; keep driving everything else.

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
