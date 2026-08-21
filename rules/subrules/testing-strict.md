# Strict Testing

- Test file = source file, 1:1 (`parser.ts` → `parser.test.ts`). Tests live in
  the codebase, fixtures in `testdata/` near source — never `/tmp`.
- **No mocking.** Real services only; exercise the actual critical path.
- Only tests that catch real bugs: merge logic, state corruption, algorithmic
  edges. If a test would pass with a broken implementation, it's ceremony.
- Unit tests are necessary, not sufficient — verify end-to-end (F3).
