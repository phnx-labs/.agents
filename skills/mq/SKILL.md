---
name: mq
description: "Structure-aware context query for large files — probe structure, then extract only the section you need, instead of reading whole files into context. Works on Markdown, HTML, PDF, JSON, YAML, CSV, XLSX, DOCX, PPTX AND source code (Go/Python/TS/Rust/...). Triggers on: reading any file 200+ lines, exploring a directory you haven't seen, extracting one section/function/endpoint from a large file, searching a topic across many files, 'use mq', or when reading a full file would waste context."
---

# mq Skill: Structure-Aware Context Query

`mq` doesn't compute answers — it externalizes a file's structure into your context so you extract only what you need instead of dumping the whole file. Probe, then extract.

```
File or dir → mq query → structure/section enters your context → you reason → answer
```

## When to use mq — and when NOT

mq's benefit is a smaller context footprint; its cost is per-call round-trips. Net
win only when the saving beats the overhead. This is a real tradeoff, measured — not
"always mq".

| Situation | Do this |
|---|---|
| You **know** the function/section you want | **One call:** `mq <file> '.section("Name") \| .text'` or `mq <file> '.search("term")'`. Beats reading the whole file (~18% cheaper + faster, measured). |
| You'll read the **same big file repeatedly** | `.tree` once, then many cheap `.section` extracts. Map amortizes. |
| **Unfamiliar directory** / search across files | `mq dir/ '.tree \| depth(1)'`, `mq dir/ '.search("x")'` — one call replaces many grep+cat. |
| Large file (200+ lines), you need a **slice** | Extract the slice; don't slurp the file. |
| **Small file (<~100 lines)** | Just `Read` it — mq's round-trip costs more than the file. |
| **One-shot** read, you need **most/all** of the file | Just `Read` it (targeted with offset/limit if you know the slice). |

**The #1 pitfall — the `.tree`→`.section` dance for a target you already named.**
If the task names the thing, do NOT run `.tree` first. That two-call dance was
measured **2.3× more expensive and ~2× slower** than just reading the file — worse
than doing nothing. `.tree` is for *discovering* an unknown structure, not for a
target you can name. Go straight to the one-call extract.

## It is NOT a docs-only tool

`mq --help` lists its formats: **Markdown, HTML, PDF, JSON, YAML, CSV, XLSX, DOCX, PPTX, and Code (Go / Python / TS / Rust / …)**. So `mq` maps the structure of a **source file** just as well as a markdown doc:

```bash
mq src/lib/router.ts .tree                       # every function/class + line ranges
mq src/lib/router.ts '.section("handleRequest") | .text'   # just that function
mq config.json .tree                             # JSON key structure
mq data.csv .tree                                # columns + row count
```

Reach for it on the `.ts`/`.py`/`.go` file you were about to `cat` — not only on `README.md`.

## The Pattern

**Fast path (most tasks) — one call.** If you can name the target, extract it directly:
```
mq <file> '.section("Name") | .text'    → the one function/section you need
mq <file> '.search("term")'             → find + show matches in one shot
```

**Exploration path — only when the structure is unknown, or you'll revisit the file:**
```
1. Map     →  mq <dir>/ '.tree | depth(1)'         → what's here (files, sizes, sections)
2. Narrow  →  mq <file> .tree                        → sections/symbols + line ranges
3. Extract →  mq <file> '.section("Name") | .text'   → the part you now know you need
```

Don't run the exploration path for a target you can already name — that's the #1
pitfall above. Your context accumulates structure; don't re-query what you already see.

## Quick Reference

```bash
# Structure (your working index)
mq file.md .tree            mq page.html .tree        mq report.pdf .tree
mq router.ts .tree          mq config.yaml .tree      mq dir/ .tree

# Search
mq file.md   '.search("term")'      mq report.pdf '.search("term")'
mq src/      '.search("handler")'   mq log.jsonl  '.search("error")'

# Extract
mq file.md   '.section("Name") | .text'    mq api.ts '.section("createUser") | .text'
mq file.md   '.code("python")'             mq page.html .links
mq file.md   .metadata                     mq log.jsonl '.record(7)'
```

## Anti-Patterns

**Bad** — read the whole file when you need one part:
```bash
cat src/lib/router.ts        # dumps 800 lines into context for one function
```
**Good** — if you can name the target, extract it in ONE call:
```bash
mq src/lib/router.ts '.section("handleRequest") | .text'   # just that function, one call
```
**Also bad** — running `.tree` first for a target you already named:
```bash
mq src/lib/router.ts .tree                        # unnecessary discovery step...
mq src/lib/router.ts '.section("handleRequest") | .text'   # ...you knew the name already
# the two-call dance measured 2.3x costlier + ~2x slower than just reading. Use .tree
# ONLY when the structure is unknown, or you'll extract from this file more than once.
```

**Bad** — re-`cat`/`grep` the same large file repeatedly to find different things. That's the single most common waste: the same file gets re-read many times in one session. Map it once with `.tree`; the structure stays in your context.

**Bad** — re-querying structure you already have (`mq dir/ .tree` twice). Use what's in context.

## When to just read

Files under ~100 lines: read them directly, `mq` is overkill. The win is on large files, directories you haven't mapped, and cross-file search.

## Scale

Warm cache (after first parse): a 30K-line markdown dir `.tree` in <1s; 123 PDFs / 365MB `.tree` in ~3s, `.search` in ~4s. Cold PDF parse is slow (minutes) but one-time — the cache persists across sessions, so every later query is sub-second.

## Examples by task

```bash
# Named target -> ONE call (the common case):
#   Pull one function            mq src/api.ts '.section("createUser") | .text'
#   Pull one doc section         mq GUIDE.md   '.section("Deploy") | .text'
#   Pull a PDF section           mq report.pdf '.section("Results") | .text'
# Unknown target -> search or map first, THEN extract:
#   Find how auth works          mq src/ '.search("auth")'     # locate it...
#                                mq src/auth.ts '.section("Overview") | .text'   # ...then extract
#   Explore an unfamiliar file   mq src/api.ts .tree           # only when you don't know the section names
# Inspect a JSONL session        mq session.jsonl '.search("deploy")' ; mq session.jsonl '.record(8)'
```
