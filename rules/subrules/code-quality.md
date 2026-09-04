# Code Quality

- **No fallbacks, no band-aids.** Never add "just in case" code paths.
  Standardize at the source — every fallback hides a bug.
- **No duplicate code.** Search before writing; use or extend what exists.
- **Fewer concepts beat more code.** A codebase's cost is the number of
  distinct ideas a reader must hold to change it safely (every flag, command,
  config key, status value, type, and module is one), not its line count; and
  agents generate all of them for free, so concept sprawl is the limit that
  bites. Before adding a concept, ask whether it could be a value or mode of
  one that already exists, and make the ones you keep intuitive. Documentation
  earns its place only for a genuinely new core concept a reader cannot infer
  elsewhere, and even there the real win is needing fewer of them.
- **Delete what you supersede, in the same change.** When a change replaces an
  old path, remove that path with it: the dead function, its now-unused
  imports, the flag nothing reads — never left standing "for later". Finishing
  your own change this way is not scope creep. A codebase rots when every
  change only adds: the tell is file and concept count climbing with no new
  capability. Favor the change that leaves the tree smaller.
- **A comment is a smell before it is a fix.** When code needs a comment to be
  understood, first make the code clear enough that it doesn't (better names,
  smaller pieces, a truer structure), then delete the comment. Reserve prose
  for what code genuinely cannot carry: a non-obvious why, an invariant, a
  hard-won gotcha, the reason an odd shape is deliberate.
- **No scope creep.** Do exactly what was asked — no drive-by refactors,
  renames, or import reorganization.
- **Cross-cutting changes go to the source** — the canonical location, never
  ad-hoc logic in consumers. If no central place exists, propose refactoring
  first.
- **User-facing text must be human.** "13 minutes", not "12m 49s".
- **Write prose precisely; don't market.** Name the concrete file, function,
  flag, or error — not "things" or "surfaces". No slogans, no filler adjectives
  ("seamless", "robust", "simply"). Cap em-dashes at one per paragraph.
