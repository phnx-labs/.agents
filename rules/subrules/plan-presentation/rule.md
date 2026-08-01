# Present Plans as Browser-Ready HTML

**Whenever you produce an implementation plan — the harness's native plan mode
(the `ref-*.md` plan file), the `/plan` command, or `/swarm:plan` — do not leave it
in terminal scrollback. Render it as a self-contained HTML doc and open it in the
user's default browser on the machine they sit at.**

This is mechanically reminded by the bundled `plan-html-reminder` hook (PreToolUse on
`ExitPlanMode`): it nudges you to render + open before you present. The full LOOK — the
house structure, the product-brand theming, the light/dark toggle, and the open-on-Mac
transport — lives in the **`plan-render` skill**. Load it and follow it.

- **Structure (fixed).** Hero (kicker · headline · problem statement · metadata chips ·
  TOC), numbered sections, **≥1 hand-authored inline-SVG diagram** (timeline /
  architecture / before-after — never mermaid), callouts, tagged tables, code blocks.
  Start from the skill's `template.html`; `example.html` is the gold reference.
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
