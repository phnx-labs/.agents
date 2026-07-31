---
description: Work with the project's issue tracker (Linear, GitHub Issues, Jira, etc.) — auto-detects whichever skill or CLI is available.
---

You're being asked to do something with the project's issue tracker: $ARGUMENTS

(If `$ARGUMENTS` is empty, default to "show me what's on my plate right now.")

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

## When you're starting a task (not just reacting to `/tickets`)

The `conventions` + `truly-agentic-git-workflow` rules ask every substantive task to run a
small ticket lifecycle; this command is the mechanism.

1. **Check first.** Look for an open ticket that already covers the task (the injected Linear
   context, or a quick `search` / `gh issue list`). Found one? Claim it (move to In Progress).
2. **Open if missing.** None, and Step 1 found a configured tracker? Create one scoped to the
   task before you start. No tracker? Skip this and describe the work in the PR.
3. **Close on delivery.** When it ships, post the PR link plus a screenshot or short screen
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

## Step 3: Report concisely

After doing the action, report:
- What you did (one line)
- Issue ID + title (so the user can click through)
- Anything blocking (auth missing, ambiguous match, etc.)

## Anti-patterns

- Don't assume Linear. The system repo doesn't ship a Linear skill — that's intentional. Detect first.
- Don't silent-install a tracker CLI. When detection says "Linear" but `linear` isn't on PATH, *suggest* `agents cli install linear-cli` and wait for confirmation — installs touch network and `$PATH`. Wrong-tracker false positives (e.g. repo on GitHub but team uses Jira) are real.
- Don't bypass the skill. If a `linear` (or `github`, etc.) skill is loaded, its SKILL.md is the source of truth — its commands are usually richer than what you'd reinvent (proof attachments, agent-lane labels, etc.).
- Don't close issues without proof. Engineering: PR URL or commit URL or screenshot of tests passing. Growth/content: published URL or metric.
- Don't create duplicates. Quick search before creating a new issue.
- Don't leak the session transcript. A transcript can help a reviewer, but it carries secrets/tokens/paths — keep it **confidential**: attach it only as a **secret gist link** on a private tracker, never inline, never onto a public issue. See the `truly-agentic-git-workflow` rule.
