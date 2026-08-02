# Code Quality

> Tactics that keep the code clean. See `foundations` (F1–F5) for the load-bearing stance.

- **No fallbacks, no band-aids.** Never add "just in case" code paths. Standardize at the source. Every fallback hides a bug.
- **No duplicate code.** Search before writing. Use or extend what exists.
- **No scope creep.** Do exactly what was asked. No drive-by refactors, renames, or import reorganization.
- **Cross-cutting changes go to the source.** Edit the canonical location, never ad-hoc logic in consumers. If no central place exists, propose refactoring first.
- **User-facing text must be human.** "13 minutes" not "12m 49s", "30 seconds" not "30.0s". If a grandmother can't parse it, rewrite it.
- **Write prose precisely; don't market.** Wherever you write for a human to read (plans, PRs, commit messages, code comments, chat), name the concrete thing (the file, function, flag, number, or error), not a vague stand-in ("things", "surfaces", "stuff", "various") unless that word is the real technical term. Cut the marketing register: no slogans, no "Critically:" / "Notably:" drama, no filler adjectives ("seamless", "powerful", "robust", "leverage", "simply"). Cap em-dashes at one per paragraph; never stack appositive dashes (the "X — Y — Z" pattern). The reader is reviewing your claim, not being sold it.
