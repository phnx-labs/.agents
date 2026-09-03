---
name: tickets
description: "Work with the project's issue tracker (Linear, GitHub Issues, Jira, GitLab, etc.) — auto-detect whichever tracker is available (a loaded tracker skill, an installed CLI, or a repo signal), then list / claim / comment / close / create / search issues, always closing with proof. Also drives the check-first / open-if-missing / close-on-delivery ticket lifecycle the conventions rule asks for. Triggers on: 'tickets', 'issues', 'issue tracker', 'my queue', \"what's on my plate\", 'claim/close/comment/create/search a ticket or issue', 'open an issue', 'move it to In Progress', 'linear', 'gh issue', 'jira', 'the board'."
---

You're being asked to do something with the project's issue tracker (arguments, if any, describe the action).

(If no action is given, default to "show me what's on my plate right now.")

## Step 1: Find the available tracker

Check in this order. Stop at the first one that's actually present.

1. **Skill-level integration.** Look for a skill in this loaded session whose name or description matches an issue-management system. Common names: `linear`, `github`, `jira`, `gitlab`, `shortcut`, `asana`. If one exists, read its `SKILL.md` and follow it — that file is the contract.

2. **Installed CLI.** No skill? Check what's already on `PATH`:
   - `linear --version` (Linear, via [phnx-labs/linear-cli](https://github.com/phnx-labs/linear-cli))
   - `gh --version` (GitHub Issues)
   - `jira --version` (Jira, via `jira-cli`)
   - `glab --version` (GitLab)

3. **Repo-level signal.** Still nothing? Check the repo for tracker breadcrumbs:
   - `git remote -v` → if origin is `github.com`, GitHub Issues is the likely tracker. Install `gh` if missing.
   - Look for `.linear/`, `linear.config.*`, or env vars like `LINEAR_API_KEY` / `LINEAR_TEAM_KEY` → Linear. The canonical CLI is shipped as `~/.agents-system/cli/linear-cli.yaml`; install with `agents cli install linear-cli` (one confirm, then `linear setup --api-key ...`).
   - Look for Jira/Atlassian config (`.jira-cli.yml`, `JIRA_URL` in env).

4. **Ask.** If nothing's detectable, ask the user where issues live (Linear team key, GitHub repo, Jira project, etc.) — once. Save the answer to memory if it'll keep coming up.

## When you're starting a task (not just reacting to a tracker request)

The `conventions` + `truly-agentic-git-workflow` rules ask every substantive task to run a
small ticket lifecycle; this skill is the mechanism.

1. **Check first — search wider than the exact title.** Look for an open ticket that already
   covers the task (the injected Linear context, and a real `search` — try the subsystem name,
   the file, the bug class, not just the exact phrase). Found one? Claim it (move to In Progress).
2. **Enrich before you create.** If a ticket partially overlaps — same subsystem, same surface,
   same bug class — **consolidate into it** instead of opening a parallel one: add your findings
   as a comment, sharpen its description, attach evidence. A more complete existing ticket beats
   a new near-duplicate. If several tickets already cover one problem, fold them: comment the
   full picture on the canonical one and cancel the rest with a "consolidated into <ID>" note.
3. **Open only if genuinely missing.** Nothing on the board covers it, a tracker is configured,
   and it's **work you're delivering now**? Create one scoped to the task. Not delivering it this
   session — just noticed it? Put it in your owner update, don't mint a Todo. No tracker? Skip
   and describe the work in the PR.
4. **Close on delivery.** When it ships, post the PR link plus a screenshot or short screen
   recording of the outcome, then move it to Done. Close only with proof.

## Step 2: Do the thing

Map the user's intent onto the tracker's primitives:

| Intent | What to do |
|---|---|
| "what's on my plate" / "my queue" | List issues assigned to the current user, scoped to the active sprint/cycle/milestone if the tracker has one. |
| "pick up X" / "claim X" | Move the issue to In Progress (or equivalent) and assign it to the current user. |
| "comment X: ..." | Append a comment. |
| "close X" / "done with X" | Move to Done with proof — link a PR, paste a screenshot or short screen recording, attach a deploy URL, or quote a metric. Don't close without evidence. |
| "create X" | New issue with title (and description if provided). Default priority Medium unless told otherwise. **Attach screenshots and relevant materials** (repro, error output, the visual you captured) so the issue is actionable without a back-and-forth. |
| "search X" | Free-text search; show top matches with status + assignee. |

If the skill (Step 1) gives you specific commands for these, **use them verbatim** — don't paraphrase the skill's CLI invocations.

### Ticket shape — a new ticket must be scannable at a glance

Once you've decided a new ticket is genuinely warranted (Step 1's "open only if missing"),
keep it small and legible — a board dies from unreadable tickets as fast as from too many:

- **Title** ≤ ~10 words, naming the concrete thing — no filler, no generic "typical words".
- **Body** = three bullets: **what** (the change), **why** (the motivating file/PR/error),
  **done-when** (the acceptance check). Not a running RCA wall.
- **One** closing comment on delivery — the PR link plus a single line — not a multi-paragraph
  log. (Amend the description for context, per `conventions`; comments are for delivery proof.)
- Default **priority Medium** unless told otherwise; **attach the repro/screenshot** so it's
  actionable without a back-and-forth.

## Step 3: Report concisely

After doing the action, report:
- What you did (one line)
- Issue ID + title (so the user can click through)
- Anything blocking (auth missing, ambiguous match, etc.)

## Anti-patterns

- Don't assume Linear. The system repo doesn't ship a Linear skill — that's intentional. Detect first.
- Don't silent-install a tracker CLI. When detection says "Linear" but `linear` isn't on PATH, *suggest* `agents cli install linear-cli` and wait for confirmation — installs touch network and `$PATH`. Wrong-tracker false positives (e.g. repo on GitHub but team uses Jira) are real.
- Don't bypass the skill. If a `linear` (or `github`, etc.) skill is loaded, its SKILL.md is the source of truth — its commands are usually richer than what you'd reinvent (proof attachments, delegation, etc.).
- Don't invent an ownership label. On Linear an issue is owned by its **delegate**, not by a label: `linear update <ID> --delegate <name>` claims it, `linear tasks --agent <name>` is that agent's queue, and an issue with no delegate is unowned. `agent:<name>` labels were retired in linear-cli 0.16.0 and confer nothing.
- Don't close issues without proof. Engineering: PR URL or commit URL or screenshot of tests passing. Growth/content: published URL or metric.
- Don't create duplicates or near-duplicates. Search wider than the exact title (subsystem,
  file, bug class) and, when something overlaps, **enrich or consolidate into it** instead of
  opening a parallel ticket. Default to not creating; a new Todo is the last resort, not the
  reflex. Boards die from parallel copies of the same problem, not from too few tickets.
- Don't leak the session transcript. A transcript can help a reviewer, but it carries secrets/tokens/paths — keep it **confidential**: attach it only as a **secret gist link** on a private tracker, never inline, never onto a public issue. See the `truly-agentic-git-workflow` rule.
