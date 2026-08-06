# work plugin

Get a project's work done across the fleet — **any** kind of work, not just code. The `code` plugin owns the engineering loop; `work` is the layer above it that routes a unit of work to whichever plugin owns it, and can do **non-coding** work (content, outreach, research, design, a real browser task) because the fleet holds browser + secrets.

## Commands

| Command | Use when |
| --- | --- |
| `/work:dispatch` | You have ONE unit of work — a ticket, a described task, or "the next thing on `<project>`" — to get done by the right agent on the right machine. Finds/pulls the ticket (deduping against in-flight work), classifies it as coding vs non-coding, files it clean if needed, then self-refers to the plugin that owns the execution (`code` for engineering; `design`/`share`/`browser` for non-coding) and drives it to done. Single-target; **not** a board sweep. |

## How it relates to the neighbours

- **`/triage`** is the *decision* layer — keep/cancel/reprioritize the whole board, surfacing calls that need the human. `work` does **not** triage or sweep in bulk; it dispatches one clear, decided item. If an item needs a human decision, `/work:dispatch` surfaces it for `/triage`, it does not build it.
- **`/dispatch`** (top-level) is the older single-task, engineering-leaning command; `/work:dispatch` generalizes it into a plugin command that is explicitly kind-agnostic.

## Conventions

- **Non-coding is first-class.** A blog post, a creator email, a funnel pull, an OG image, a portal task — all are work items an agent can *do* here via the `design`/`share` plugins + the `browser` skill + `secrets`.
- **Clean at filing.** `/work:dispatch` files nothing messy or duplicate — a specific title, scoped body, right label/priority, deduped against existing tickets and in-flight PRs/sessions.
- **Route to the fleet, keep the interactive box light.** Prefer an idle box (`--device auto` / the `fleet` plugin) for the execution; reserve the interactive machine for the user.
- **In flight ≠ done.** Every dispatch is watched to its real finish (merged PR / published post / completed task) and the ticket closed with proof, or handed off by naming the owner.
