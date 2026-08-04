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

Full recipe — worktree creation, PR, after-merge cleanup: the `git-workflow` skill.

## Open with evidence attached — screenshots, artifacts, a confidential transcript

Opening something for a human — a **PR**, a **GitHub issue**, or a **ticket**
(Linear/Jira) — is a handoff, not a stopping point. Identify which flow you're in
and attach what the reviewer needs to judge it without re-running your session.

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
  publish it with **`agents share <file>`** (§Attaching evidence), and embed the returned
  URL in the body with `![caption](url)`. When the change has a visible before/after, show
  **both** stills.
- **Prefer a recording when a still can't carry the flow.** You have the tools: capture a
  **web app** with the `browser` skill (record the click-through), or a **terminal flow**
  with `agents pty` (record the run), and attach the file.
- **A no-UI change still shows the run** — screenshot the passing run / the `curl`'d
  response, or `agents share` the run's output or log as an **asset** and link it. Pasted
  **source code** and **hand-authored tables are not proof of a run** and do not count. If
  there is genuinely no visible surface, **declare it** (refactor / test-only).
- **Link the context.** Include the **Linear ticket** for the work, and — if a plan was
  shared — a **shareable link to the plan file**. The same screenshot/recording also goes
  on the ticket when you close it (see `conventions`).

The bundled `pr-description-reminder` (PreToolUse) is the backstop: it nudges once when a
`gh pr create`/`edit` inline body shows **no run result** — no image/recording/asset, no
ticket/plan link, and no release/docs/no-surface declaration. A code block or table does
**not** clear it. Run it, capture the result, attach, retry. It **fails open** — a
`--body-file`/`--fill` body is never nudged — and is satisfiable, never a hard wall.

### Attaching evidence on GitHub — the mechanics

`gh` **cannot upload an image inline.** `gh pr create/edit --body` only takes text, so a
local screenshot path in the body does **not** render on GitHub. Get the asset a public URL
and embed it with `![caption](url)`. Use these, in order:

1. **`agents share <file>` — the primary mechanic.** It publishes any static asset (a
   `.png`/`.jpg`/`.gif` screenshot, a `.mp4`/`.mov`/`.webm` recording, a `.pdf`) to your own
   Cloudflare R2 and prints a public URL that renders inline via `![caption](url)`. No
   browser and no manual drag-drop, so it works **headlessly** — the default way an agent
   attaches media. Not configured on this box? `agents share status` says so; configure it
   once with `agents share setup` (provision your own endpoint) or `agents share join
   <baseUrl>` (use an existing one), then re-run. If you truly cannot configure it, hand the
   one-time `agents share setup` to the user and use drag-drop meanwhile. **Public share is
   for shareable visual proof only** — never publish a private or secret asset (a
   transcript, anything carrying tokens or internal paths) to a public R2 URL; those stay in
   a secret gist or a local path (see the transcript rule below). `--expire 30d` bounds the
   link's life.
2. **Web drag-drop (browser-only fallback).** When `agents share` isn't available, open the
   PR/comment box in the browser and drag the image/recording (`.png`/`.gif`/`.mp4`/`.mov`)
   in. GitHub uploads it and inserts a `https://github.com/user-attachments/assets/…` URL
   that renders inline via `![](…)`. Open the PR on the user's Mac to do it (`agents ssh
   <mac> 'open <pr-url>'`), or drive the upload with the `browser` skill.
3. **Comment after the fact.** Once you have a public URL (an `agents share` link or a
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
  the body. Publish it with `agents share <file>` and embed the URL (or drag it into the
  web UI); reference on-disk images by **full path** so the reviewer can click to preview.
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

When the merge genuinely needs the **user** (a governance/sign-off change you
authored and can't self-review, no CI/reviewer configured), that's a real
handoff — so **open the PR on the user's interactive device** so they can click
Merge/Approve there, don't just leave the link in this window (F4 — land the
handoff where the user is). The user runs many agents and won't be watching this
chat.

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
