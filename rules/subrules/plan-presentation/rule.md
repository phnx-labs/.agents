# Present Plans as Browser-Ready HTML

**Whenever you produce an implementation plan — the harness's native plan mode
(the `ref-*.md` plan file), the `/plan` command, or `/swarm:plan` — do not leave it
in terminal scrollback. Author a Markdown source in the repo's `.agents/artifacts/plans/`
directory, render it to a self-contained HTML doc with `artifacts-cli`, and open it in
the user's default browser on the machine they sit at.**

This is mechanically reminded by the bundled `plan-html-reminder` hook (PreToolUse on
`ExitPlanMode`): it nudges you to render + open before you present. The full LOOK — the
house structure, the product-brand theming, the light/dark toggle, and the open-on-Mac
transport — lives in the **`plan-render` skill**. Load it and follow it.

- **Source of truth is Markdown.** Write `plan-<slug>.md` in `.agents/artifacts/plans/`
  and compile it with `artifacts render ... --format html`. The HTML is a build output;
  never hand-author a complete `.html` file.
- **Structure (fixed).** Hero (kicker · headline · problem statement · metadata chips ·
  **provenance chips — harness · agent · host · session · date, so a rendered plan is never
  an orphan** · TOC), numbered sections, **≥1 visual figure** (Dither Kit for quantitative
  charts; hand-authored inline SVG for timeline / architecture / before-after
  diagrams — never mermaid), callouts, tagged tables, code blocks. Follow the
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
