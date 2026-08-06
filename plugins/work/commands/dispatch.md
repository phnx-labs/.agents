---
description: Dispatch ONE unit of work — coding or not — to the right executor across the fleet. Finds/pulls the ticket, routes engineering work to the code plugin and non-coding work (content, outreach, research, design, a real browser task) to the plugin that owns it, then drives it to done. The general-purpose superset of /dispatch, which is scoped to one project and leans engineering.
---

You're being asked to dispatch work: $ARGUMENTS

`/work:dispatch` takes ONE unit of work — a ticket id, a described task, or "the next thing to do on <project>" — and gets it done by the right agent on the right machine. Unlike `/dispatch`, it is **not engineering-only**: a work item can be code (a fix, a feature, a release) OR non-coding (a blog post, creator outreach, a research pull, a design asset, a form/portal task). Because the fleet holds **browser + secrets**, an agent can actually *do* the non-coding work, not just file it.

This is a **single-target dispatch**, not a board sweep. There is **no survey, no bulk pass** — deciding the whole board (keep/cancel/reprioritize) is `/triage`'s job, and cancel/priority calls that need the human are surfaced there, never auto-dispatched here.

## Step 1: Resolve the target — find the ticket

- **`$ARGUMENTS` names a ticket** (e.g. `RUSH-1234`) → that's the target.
- **`$ARGUMENTS` describes a task** → look for an existing ticket first (`/tickets` detection; e.g. `linear tasks --query`, `gh issue list`) and **check for in-flight work** (an open PR or a live `agents sessions --active` on it). Never dispatch a duplicate of something already being built — that is the #1 waste on a busy board.
- **`$ARGUMENTS` says "next work on <project>"** → pull that project's board, pick the top **clear, unblocked, keep-worthy** item. Skip anything that needs a human decision (is it wanted? cancel? reprioritize?) — surface it for `/triage`, don't dispatch it.
- **Ground once** in the project (its `AGENTS.md`/`README`/`CHANGELOG`, or the Linear goal spine) so the spec isn't re-derived per call.

## Step 2: Classify — coding or not

The *kind* of work decides the executor:

- **Engineering** — a code change, bug, refactor, test, or release.
- **Non-coding** — content, outreach, research, design, a data pull, or a real web task.

## Step 3: Spec it clean — file nothing messy

A tight spec: what, why, acceptance criteria. A **specific title** that names the concrete thing (no filler / generic "typical words"), the right label + priority (never default-High). For a bug, route the root cause through `/debug` first and dispatch the **confirmed** cause, not a guess. If no ticket exists yet, file **one clean, deduped** ticket before dispatching so the work has an owner of record. A messy or duplicate ticket is a defect, not progress.

## Step 4: Route to the executor — self-refer to the plugin that owns it

Hand the work to the plugin/skill built for it, on a machine that makes sense (an idle box via `--device auto` / the `fleet` plugin; keep the interactive box light). Reference the ticket in the brief so the executor updates it, not a duplicate.

| Work kind | Executor (self-refer) |
|---|---|
| One coding ticket | `/dispatch`, or the `run` skill (`agents run`) |
| Coding, parallel / independently verified | the `teams` skill (`agents teams`) |
| A queue of coding tickets | `/code:loop` |
| Design / images / assets | `design:design` (keyless, offline-first) |
| Publish an artifact / plan / report | `share:public` / `share:private` |
| Research / data pull | the `browser` skill + research skills, `secrets` for authed sources |
| A real web task (form, portal, dashboard) | the `browser` skill + `secrets` |

If the right executor isn't obvious, pick the closest plugin and say why in one line — don't stall.

## Step 5: Not done at "dispatched"

In flight is not done. Watch it to its real finish — a merged PR, a published post, a completed task — with a background watch + finish-echo, or hand it off by **naming who/what now owns it**. On completion, set the ticket to Done **with proof** (the PR/post URL, the artifact, the metric).

## Anti-patterns

- **Treating this as engineering-only.** Non-coding work is first-class here — that's the whole point of `work` over `code`.
- **Doing a survey / bulk sweep.** That's `/triage`. This is ONE target.
- **Dispatching a duplicate** of in-flight work — check for an open PR / live session first.
- **Filing a messy ticket** to dispatch — clean it at filing.
- **Auto-dispatching a call that needs the human** (cancel / is-this-wanted / reprioritize) — surface it, don't build it.
- **Stopping at "dispatched."** It's in flight, not shipped.
