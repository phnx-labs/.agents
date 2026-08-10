# Present Plans as Browser-Ready HTML

**Whenever you produce an implementation plan — the harness's native plan mode
(the `ref-*.md` plan file), the `/plan` command, or `/swarm:plan` — do not leave it
in terminal scrollback. Author a Markdown source under the repo's dated artifact
layout, render it to a self-contained HTML doc with `artifacts-cli`, and open it in
the user's default browser on the machine they sit at.**

## What every plan must contain — and do before presenting

Built-in plan mode (`/plan`, Shift+Tab, `--mode plan`) only restricts tools and asks
for an `ExitPlanMode` — it injects **no** methodology, on any harness. This section is
that methodology. Do all of it before you present a plan, whether you entered plan mode
by a keystroke, a flag, or just started planning.

**Research first — before you draft:**

1. **Search what previous agents did on this feature.** Run
   `agents sessions "<feature keywords>"` (and read the latest plan/PR on
   that surface) before drafting. **Extend** prior work; do not silently revert it —
   reverting an earlier agent's change is the most common regression on this fleet.
2. **Find the module's specification.** Locate where this module's spec lives (a
   `SPEC*.md`, a doc, an OpenSpec change). If none exists, propose writing a short one.
   Keep specs **succinct and current** — do not pile on rules nobody asked for.

**The plan must contain, in this order:**

3. **Focus for review (at the very top).** 2-5 bullets naming exactly what you want the
   user to weigh in on. Lead with this — it is the first thing they read.
4. **Intent.** Restate the user's ask in their own words, so the plan visibly tracks it.
5. **Current architecture.** How the affected module works **today** — the files
   involved and how they talk to each other. For an architectural change, show the
   communication pattern **before and after** as an inline-SVG figure.
6. **Implementation shown as real code.** For every file that changes, show the actual
   change as a **diff** — the relevant hunk only (not the whole file), added lines
   green, removed lines red — via the artifacts-cli `code-diff` component (fall back to
   a fenced ```` ```diff ```` block until it ships). Name every module that changes.
   Pick the load-bearing hunks; keep it readable, not exhaustive.
7. **A rendered to-do list.** Beyond creating the `TaskCreate` checklist (see *A
   multi-step plan also carries a checklist*, below), **render** it into the plan as a
   checklist section, so the user sees the steps and their status in the plan itself —
   not only in the harness's to-do UI.

**Two gates before you present:**

- **Adversarial review.** For any change to an API/CLI surface or the system
  architecture, get a **non-author** review before presenting — a subagent, or
  `agents run claude --mode plan "Adversarially review this plan's API surface and
  adherence to existing architectural conventions. Return file:line evidence."
  --attach <plan.md>` on harnesses with no subagent tool. It checks the surface is
  clean and intuitive and follows existing conventions (access centralized in one
  place, no duplicated surface, cross-cutting change made at the source). Fold its
  findings in before you present.
- **Render + open** the HTML (below).

Scale to the change: a trivial, single-file edit with no interface or architectural
impact skips the architecture figure and the adversarial review.

## Canonical artifact path (plans, HTML, and related items)

All agent-produced durable artifacts — **plans, rendered HTML, visuals, reports,
and other session outputs** — live under a single dated layout (not kind-based
subdirs like `plans/` or `viz/`):

```
.agents/artifacts/yyyy-mm-dd/<artifact-title>.md
```

Examples:

| Kind | Path |
| --- | --- |
| Plan source | `.agents/artifacts/2026-08-05/plan-auth-refresh.md` |
| Plan HTML (render next to source) | `.agents/artifacts/2026-08-05/plan-auth-refresh.html` |
| Visual / infographic | `.agents/artifacts/2026-08-05/fleet-status.md` |
| Report / scan | `.agents/artifacts/2026-08-05/signal-scan.md` |

- **Date** is the day the artifact is authored (`date +%F` → `yyyy-mm-dd`).
- **Title** is a kebab-case slug that names the artifact (`plan-<slug>`,
  `fleet-status`, `signal-scan`). No nested kind folder.
- Create the date directory if missing (`mkdir -p .agents/artifacts/$(date +%F)`).
- HTML builds land **next to** their Markdown source under the same date dir.

This is mechanically reminded by the bundled `plan-html-reminder` hook (PreToolUse on
`ExitPlanMode`): it nudges you to render + open before you present. The full LOOK — the
house structure, the product-brand theming, the light/dark toggle, and the open-on-Mac
transport — lives in the **`plan-render` skill**. Load it and follow it.

- **Source of truth is Markdown.** Write `.agents/artifacts/yyyy-mm-dd/plan-<slug>.md`
  and compile it with `artifacts render ... --format html`. The HTML is a build output;
  never hand-author a complete `.html` file.
- **Structure (fixed).** Hero (kicker · headline · problem statement · metadata chips ·
  **provenance chips — harness · agent · host · session · date, so a rendered plan is never
  an orphan** · TOC), numbered sections, **≥1 visual figure** (hand-authored inline SVG for timeline / architecture / before-after / charts — never mermaid), callouts, tagged tables, code blocks. Follow the
  `plan` template (`artifacts template plan`) or scaffold with `artifacts new plan`.
- **Quality is enforced, not suggested.** `artifacts check`/`render` **error** when a plan
  has no drawn live SVG figure, and they **do not write HTML** on validation failure.
  The ExitPlanMode hook greps the rendered HTML for `<svg` + a drawn primitive — a
  prose-only shell no longer clears the gate. Inline `` `code` `` alone is not enough:
  put commands in fenced blocks and risks/files in tables.
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

## A multi-step plan also carries a checklist

The same `plan-html-reminder` hook now gates a second thing: when the plan has
multiple steps, create a **task checklist** for it before you present (one
`TaskCreate` per step). The checklist is the plan's acceptance rubric — it shows in
`agents sessions`, drives the watchdog, and marks progress as you work. Trivial,
single-step plans are exempt (the gate skips them). Binding the checklist to the
task and to a tracker is covered by the **`task-checklists`** rule.
