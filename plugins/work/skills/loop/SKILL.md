---
name: loop
description: "General-purpose unattended work drain across every project and kind — code, browser, outreach, design, portal tasks. Spreads load with agents teams + balanced account rotation so one logout or rate-limit does not kill the night. No review/merge gate: finish agent-doable work, open PRs for the human to review later. Triggers on: 'work loop', '/work:loop', '/drain', 'overnight drain', 'drain the board', 'finish everything unattended', 'keep moving on all projects'."
argument-hint: "[empty = all open clear work | project/filter | overnight]"
allowed-tools: Bash(agents *), Bash(gh *), Bash(git *), Bash(linear *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Bash(curl *), Read(*), Write(*), Edit(*), Task(*), WebSearch(*), WebFetch(*)
user-invocable: true
---


# work:loop — get the work done, unattended

You are the **orchestrator of a general-purpose drain**. The board is every open, clear,
unblocked item across the user's projects — not one repo, not engineering only. Your job
is to **finish as much agent-doable work as possible without involving the user**, leave
what needs their eyes for later, and **never pin the night on a single account or host**.

This is the kind-agnostic sibling of `code:loop`. For pure engineering mechanics (worktrees,
claim/dedup, PR shape) you may **compose** `code:loop` ideas and patterns — but this skill
owns the overnight / multi-project / multi-kind contract. Do **not** run a merge-review
gate (`code:review` merge loop is off by default).

## Mindset (load-bearing)

1. **Done without the user.** Never call `AskUserQuestion`. Never wait for approval. If a
   decision is genuinely product/taste-only, park the item with a comment and continue.
2. **Maximize finished work.** Prefer opening a solid PR, sending the outreach, filling
   the form, publishing the asset — over perfecting a plan or waiting for review.
3. **No review flow.** Do not spawn a non-author review-and-merge loop. For engineering:
   implement → test → open PR → leave it for the human to review later. Note CI status in
   the ticket; do not idle on green for a merge click. For non-coding: complete the real
   outcome (message sent, form submitted, report filed) when the agent can do it alone.
4. **Spread load always.** One Claude logout or rate-limit must not collapse the night
   (real failure mode: m-box logouts and bwrap failures re-homing everything onto s0/s1).
   Default to `agents teams` / multiple `agents run` with **`--strategy balanced`**, mixed
   harnesses, and worker hosts — never one long single-account session for a whole queue.
5. **Re-home on death.** Auth 401, rate-limit, bwrap, host unreachable → re-probe, then
   move that track to another account / harness / host. Do not hammer the same dead path.

## Tools you already have — use them

| Surface | Use when |
|---|---|
| **`browser` skill / `agents browser`** | Web apps, portals, forms, dashboards, ordering, web outreach. Prefer signed-in fleet profiles; use `agents secrets` for bundles. |
| **`computer` skill / `agents computer`** | Native desktop apps (Finder, Electron hosts, anything not a browser). Element mode; do not steal the user's interactive machine when workers can run headless. |
| **`agents secrets` / `agents secrets exec`** | Credentials. Never invent logins; inject the named bundle. If a harness shows "not logged in", try minting/rotating via fleet paths before parking. |
| **`agents sessions`** | Prior conversations, decisions, mid-task context. Search by topic/ticket/id; load summaries; continue from real history. |
| **Tracker comments + PRs** | Prior human decisions, "do this not that", scope cuts. Prefer written history over guessing. |
| **Read the code** | When a ticket or product note is ambiguous — the repo is ground truth. Read entry points, AGENTS.md, recent CHANGELOG; do not invent APIs. |
| **WebSearch** | External/current facts (API shapes, pricing, how a third-party portal works this year). |

If you are confused: **sessions → ticket/PR comments → code → web**, in that order for
*this user's* intent, then external truth. Do not stop and ask the user for context you
can recover yourself.

## What is in the queue

`$ARGUMENTS` empty or `overnight` / `all` → pull **clear, unblocked, keep-worthy** items
across projects (Linear Todo/In Progress delegated or labeled for drain; open GitHub issues
with pilot labels if any; skip items that need cancel/priority taste — those are `/triage`).

A project name, label, or query scopes the queue. Human-only holds (`hold`, explicit "wait
for me") stay parked.

Normalize each item: id · title · kind (engineering | browser/web | design/content |
research | other) · project/repo · acceptance · host preference if any.

## Dedup and claim (same spine as code:loop)

Before building:

1. Open PR already for this id? → attach to that PR (land it further) or skip if clearly
   someone else's live work.
2. Live `agents sessions --active` already on it? → skip this round.
3. Claim: Todo → In Progress + comment (`Picked up by work:loop · <session> on <host>`).
4. Re-check status right before first real mutation.

Every engineering PR title/body carries the item id so other loops can find it.

## Spread strategy (mandatory)

When ≥2 independent items (or one item with ≥2 independent tracks):

```bash
# Discover capacity
agents teams doctor
agents view --json
agents devices list   # workers only for spawn; never flood the interactive laptop

# Fan out — balanced accounts, mixed harnesses
agents teams create <slug> --enable-worktrees   # edit-mode isolation when coding
agents teams add <slug> claude "..." --name <role> --mode auto   # hard / ambiguous
agents teams add <slug> codex  "..." --name <role> --mode auto   # grunt implement
# kimi / other cheap harnesses when signed in — use them for bulk mechanical work
agents teams start <slug> --watch
```

- **`--strategy balanced`** / bare `claude` (no pin) so accounts rotate by headroom.
- **Never** three of the same exhausted account "verifying" each other.
- **Hosts:** pin workers (`yosemite-s0`, `yosemite-s1`, …) or `--device auto`. Interactive
  machine (zion when interactive) stays light — orchestrator only.
- **Cap concurrency** by judgment and live capacity; prefer more smaller tracks over one
  fat track that dies with one logout.
- On track failure that is **auth/limit/infra**: re-home; do not rewrite the product code
  to paper over a dead host.

Single trivial item → one `agents run … --mode auto --strategy balanced` (or inline if
tiny). Still unattended.

## Routing by kind

| Kind | How you finish (unattended) |
|---|---|
| **Engineering** | Worktree off `origin/$BASE`; implement; run real tests; **open PR**; comment on ticket with PR link. **Do not** run `code:review` merge. **Do not** wait for the user to review. Optional: note CI. For a pure multi-ticket *code-only* slice you may hand a sub-queue to `code:loop` **only if** you override completion to "PR open, no merge-review" — otherwise keep engineering inside this skill so the no-review contract is not violated. |
| **Browser / portal / order / sign-in web** | `browser` + secrets; complete the real flow; screenshot or quoted UI state as proof; close ticket with proof. |
| **Native app** | `computer` skill; same proof bar. |
| **Design / assets** | `design` plugin / image skills; attach artifact. |
| **Outreach / content** | Browser or channel tools as appropriate; send only when the item clearly authorizes send; otherwise draft + leave a single link for the human (still unattended for the draft). |
| **Research** | Browser + WebSearch; write the brief/artifact; no user mid-flight. |

`/work:dispatch` remains the one-item primitive; this skill **batches** and **spreads**.

## What "done" means here

| Outcome | Counts as done for this loop |
|---|---|
| Engineering | PR open with id in title, ticket commented, CI noted if known |
| Non-coding agent-complete | Real-world action finished + proof (screenshot path, URL, send receipt) |
| Blocked | Ticket parked with *exact* missing decision/credential; continue others |
| Needs human review | Already the default for PRs — leave them; do not ping for merge |

Queue empty or only parked items → short recap: finished · PRs waiting on human · parked ·
what re-homed because of limits/logouts.

## Unattended rules

- No `AskUserQuestion`. No "want me to continue?".
- No Telegram unless the invocation prompt literally supplies a notify one-liner (Muqsit
  prefers no Telegram — skip phone notify unless the prompt overrides).
- Ticket comments are the durable record.
- Overlap: if another `work:loop` / drain is live on the same queue, coordinate (skip
  claimed ids); optional lock dir `/tmp/work-loop-<host>.lock` with staleness steal for
  cron invocations.

## Anti-patterns

- Running the whole night as one Claude session on one host
- Pinning a single account until it rate-limits, then stopping
- Invoking `code:review` / merge-on-green and waiting for the user
- Skipping browser/computer when the ticket is clearly a web/native task
- Asking the user for context that sessions, comments, or code already hold
- Flooding the interactive laptop with teammates
- Claiming "done" without a PR link or real-world proof

## Compose map

| Need | Use |
|---|---|
| Single clear item now | `/work:dispatch` (or this skill with a one-item queue) |
| Engineering patterns (worktree, claim) | Align with `code:loop`; **no** its merge/review completion |
| Board keep/cancel decisions | `/triage` — do not invent cancels unattended |
| Parallel fan-out mechanics | `swarm:orchestrate` / `agents teams` |
| Schedule every night | `agents routines` YAML calling this skill unattended |
