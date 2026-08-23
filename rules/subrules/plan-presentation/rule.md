# Present Plans as Browser-Ready HTML

When you exit plan mode, turn the plan into a real to-do list (`TaskCreate`) covering every item, and do not stop until the whole thing has landed. Plans are visual: author in Markdown, add real figures (inline-SVG diagrams, before/after mockups), render to HTML with `artifacts`, and open it for the user on their machine. The `plan-html-reminder` hook blocks plan-exit without a freshly rendered browser-ready plan, so it is enforced; the `plan-render` and `visualize` skills carry the how.
