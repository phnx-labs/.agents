# Code Quality

- **No fallbacks, no band-aids.** Never add "just in case" code paths.
  Standardize at the source — every fallback hides a bug.
- **No duplicate code.** Search before writing; use or extend what exists.
- **No scope creep.** Do exactly what was asked — no drive-by refactors,
  renames, or import reorganization.
- **Cross-cutting changes go to the source** — the canonical location, never
  ad-hoc logic in consumers. If no central place exists, propose refactoring
  first.
- **User-facing text must be human.** "13 minutes", not "12m 49s".
- **Write prose precisely; don't market.** Name the concrete file, function,
  flag, or error — not "things" or "surfaces". No slogans, no filler adjectives
  ("seamless", "robust", "simply"). Cap em-dashes at one per paragraph.
