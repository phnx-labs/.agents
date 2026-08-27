# Present Plans as Browser-Ready HTML

Any implementation plan — native plan mode, `/plan`, `/swarm:plan` — is
authored as Markdown under the dated artifact layout, rendered to HTML with
`artifacts-cli`, and inspected before you present it. Plan mode injects no
methodology on any harness; this section is that methodology. Scale it to the
change: a trivial single-file edit skips the architecture section and the
adversarial review. It skips the whole section (which only warns), not the
figure inside a kept section — omit it or draw it; there is no table-shaped
middle.

**Research first:** search what previous agents did on this feature
(`agents sessions "<keywords>"`) and extend prior work — silently reverting an
earlier agent's change is the most common regression here. Locate the module's
spec if one exists. When a live product, competitor, or current docs page
exists, drive it and cite it (URL + year); search snippets are not a teardown.

**The plan contains at least these, in this relative order.** They are a floor
(`artifacts check` will not compile without the required headings and a figure).
A heading skeleton plus one invented SVG is not a plan a reviewer can judge.

1. **Focus for review** — 2–5 bullets naming exactly what the user should weigh
   in on.
2. **Intent** — the ask restated in the user's words.
3. **Current architecture** — a staff-engineer **system diagram** of how
   affected modules talk today: boxes for the modules, arrows for calls / data
   / control, layers distinct (orchestration ≠ machine ≠ isolation). Follow the
   artifacts diagram recipe. Before/after when the plan changes the shape.
   `artifacts check` errors on an architecture section with no figure
   (artifacts-cli 0.3.5+; older installs do not enforce it) — a table lists the
   parts and drops every relationship between them. A table may sit alongside
   the figure for per-file detail; it does not replace it.
4. **Implementation as real code** — the load-bearing hunks as diffs (fenced
   ```diff blocks), naming every module that changes.
5. **A rendered to-do checklist** (also created via `TaskCreate` — see
   `task-checklists`).

When the topic has a live product, a competitor, or a real architecture, carry
that **evidence** between Intent and the implementation diffs: the flows and
today's gap, field notes from driving the live thing, a drawn proposed
architecture, alternatives for load-bearing choices, panel findings, cited
URLs. Heading names are not a second checklist — put the evidence where it
reads; empty extra H2s are the heading-skeleton bug in a new costume. A
one-file bugfix skips this (one line for alternatives is enough). Do not drop
the floor headings to make room. No slop nouns.

**Two checks before presenting:** an adversarial non-author review for any
API/CLI-surface or architecture change (a subagent checks the surface is clean
and follows existing conventions — **findings land in the HTML**, not only
chat); and render + inspect the HTML.

**Artifact path:** durable outputs land in the DURABLE HOME —
`~/.agents/artifacts/yyyy-mm-dd/<slug>/plan.md`, HTML rendered next to the
source, plus an `.artifact.json` sidecar so the artifact is findable by slug days
later. One dated layout, no kind subdirs.

Outside any checkout, deliberately. A repo's `.agents/artifacts/` is tracked, so
stray files there collide on `git checkout` / `git merge`; it is also a primary
working tree, so `main-branch-guard` denies the write. The exception is a plan
deliberately committed WITH its feature — that still belongs in the repo, and
gets there through a worktree and a PR like any other tracked file.

**Mechanics** (the full look lives in the `artifacts` skill):

- Markdown is the source of truth; compile with `artifacts render <source>.md`.
  Never hand-author the HTML.
- Frontmatter needs `kind`, `title`, `surface` (`internal` / `cli` / `web` /
  `native` / `api` / `workflow`); provenance chips auto-fill at render. A
  user-visible surface shows current AND proposed appearance; internal plans
  use a real architecture/flow figure. `artifacts check`/`render` error on
  missing evidence and don't write HTML.
- Theme in the target product's brand (probe the repo for tokens); ship light +
  dark with the in-page toggle.
- Render headlessly every time and inspect a screenshot; open it on the user's
  machine only on request.

A multi-step plan also carries a `TaskCreate` checklist before you present. The
`plan-html-reminder` hook enforces both; trivial single-step plans are exempt.
