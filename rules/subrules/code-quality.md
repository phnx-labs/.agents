# Code and Tests

Solve problems at their canonical source: no fallbacks or band-aids, no
duplicate code (search first, extend what exists), no ad hoc fixes in consumers,
no scope creep. A cross-cutting change goes to its canonical location; if none
exists, propose the refactor first. Fewer concepts beat more code: before adding a flag, command,
config key, type, or module, ask whether it can be a mode of one that exists. A
comment is a smell before it is a fix; reserve prose for a non-obvious why, an
invariant, or a deliberate odd shape. Keep user-facing text human and precise:
"13 minutes", the concrete file or flag, no marketing filler, at most one
em-dash per paragraph.

Keep meaningful tests beside their source with fixtures in nearby `testdata/`;
exercise real services, no mocks; keep only tests that catch distinct failures.
Unit coverage is not delivery proof: verify the real flow (F3).

Do not encode ordinary judgment as a new narrow skill or command. Extend the
nearest broad one, and only for a non-derivable platform fact or a genuinely new
capability.
