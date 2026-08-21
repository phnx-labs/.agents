# Query Structure Before Reading Whole Files (`mq`)

`mq` extracts one section of a file instead of reading the whole thing into
context. It has per-call overhead, so use the decision rule, not "always mq".

```bash
mq <file>  '.section("Name") | .text'   # extract one function/section (KNOW the name)
mq <file>  '.search("term")'            # find + show matches in one call
mq <dir>/  '.tree | depth(1)'           # map an unfamiliar directory
mq <file>  .tree                        # discover structure (exploration only)
```

**Use mq when:** you know the symbol/section you want (ONE call, straight
there); you'll touch the same big file repeatedly (`.tree` once, then cheap
extracts); mapping or searching an unfamiliar directory; a 200+ line file where
you need a slice.

**Don't use it when:** the file is small (<~100 lines); a one-shot read needs
most of the file; you'd run `.tree` and then read the whole file anyway.

**The #1 pitfall:** the map-then-extract dance for a target the task already
names — measured 2.3× more expensive than just reading the file. Skip `.tree`;
extract in one call.

Not a docs tool: it handles source code (ts/py/go/rust/…), JSON/YAML/CSV, and
Office as well as md/html/pdf. Install: `agents cli install mq`.
