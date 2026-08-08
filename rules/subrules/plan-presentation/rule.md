# Present Plans as Browser-Ready HTML

**Whenever you produce an implementation plan — the harness's native plan mode
(the `ref-*.md` plan file), the `/plan` command, or `/swarm:plan` — do not leave it
in terminal scrollback. Author a Markdown source under the repo's dated artifact
layout, render it to a self-contained HTML doc with `artifacts-cli`, and open it in
the user's default browser on the machine they sit at.**

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

This is mechanically enforced by the bundled `plan-html-reminder` hook: PreToolUse
catches native plan-exit tools, while Stop catches Codex and other harnesses whose
plan mode is collaboration state rather than a tool call. It nudges you to render +
open before you present. The full LOOK — the
house structure, the product-brand theming, the light/dark toggle, and the open-on-Mac
transport — lives in the **`plan-render` skill**. Load it and follow it.

- **Source of truth is Markdown.** Write `.agents/artifacts/yyyy-mm-dd/plan-<slug>.md`
  and compile it with `artifacts render ... --format html`. The HTML is a build output;
  never hand-author a complete `.html` file.
- **Declare the surface.** Every plan frontmatter sets `surface` to one of
  `internal`, `cli`, `web`, `native`, `api`, or `workflow`. Internal plans use a
  real architecture/flow/state figure. Every user-visible surface shows the
  **current** and **proposed** appearance in one product-faithful behavior figure;
  each side is a real capture when available or an explicitly labeled mockup.
- **Structure (fixed).** Hero (kicker · headline · problem statement · metadata chips ·
  **provenance chips — harness · agent · host · session · date, so a rendered plan is never
  an orphan** · TOC), numbered sections, **≥1 visual figure** (hand-authored inline SVG for timeline / architecture / before-after / charts — never mermaid), callouts, tagged tables, code blocks. Follow the
  `plan` template (`artifacts template plan`) or scaffold with `artifacts new plan`.
- **Quality is enforced, not suggested.** `artifacts check`/`render` **error** when
  surface metadata or required visual evidence is absent, and they **do not write
  HTML** on validation failure. The hook checks the Markdown surface plus semantic
  HTML: an architecture SVG cannot clear a CLI/UI plan that lacks current/proposed
  product views. Inline `` `code` `` alone is not enough:
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
