# Query Structure Before Reading Whole Files (`mq`)

`mq` extracts one section of a file instead of reading the whole thing into
context. Its value is a smaller context footprint — but it has per-call overhead,
so that footprint saving only pays off when you use it the right way. Use the
decision rule below, not "always mq".

```bash
mq <file>  '.section("Name") | .text'   # extract one function/section (KNOW the name)
mq <file>  '.search("term")'            # find + show matches in one call
mq <dir>/  '.tree | depth(1)'           # map an unfamiliar directory
mq <file>  .tree                        # discover a file's structure (exploration only)
```

## When mq pays — and when it doesn't

**DO reach for mq when:**
- **You know the symbol/section you want → ONE call.** `mq <file> '.section("Name") | .text'`
  or `mq <file> '.search("term")'`. Go straight there. This beats reading the whole
  file (measured: ~18% cheaper AND faster on a 1849-line file, same answer).
- **You'll touch the same big file repeatedly** — `.tree` once, then many cheap
  extracts. The map amortizes.
- **Mapping an unfamiliar directory or searching across files** — `mq dir/ '.tree | depth(1)'`,
  `mq dir/ '.search("x")'`. One call replaces a flurry of `grep`+`cat`.
- **A large file (200+ lines) where you need a slice**, or context space is tight.

**DON'T use mq (just `Read`, targeted with offset/limit if you know the slice) when:**
- **The file is small (<~100 lines).** Reading it whole is cheaper than any mq round-trip.
- **It's a one-shot read and you need most/all of the file.**
- **You'd run `.tree` and then read the whole file anyway** — that's pure overhead.

## The #1 pitfall — the map-then-extract dance for a target you already named

If the task already names the thing (`explain foldLegacySystemRepo`, `what does
section X say`), do **not** run `mq <file> .tree` first and then `.section`. That
two-call dance was measured **2.3× more expensive and ~2× slower** than just
reading the file — worse than doing nothing. Skip `.tree`; extract in one call.
`.tree` is for *discovering* an unknown structure, not for a target you can name.

## It is not a docs-only tool

`mq` handles **source code (ts/py/go/rust/…), JSON/YAML/CSV, and Office
(xlsx/docx/pptx)** as well as md/html/pdf. Use it on the `.ts`/`.py` file you were
about to `cat`. Full recipe: the `mq` skill. Required host CLI (`agents doctor` →
Host CLIs; `agents cli install mq`).

**Why this exists:** a fleet audit found `mq` invoked 0 times across 835 sessions
in 3 days while 62% of tool calls were context reads (whole-file dumps; same file
re-read up to 34×/session). A follow-up A/B then showed *misused* mq (the dance)
is worse than reading — so the win depends on the discipline above, not on reaching
for mq blindly.
