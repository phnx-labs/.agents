---
name: clean
description: "Make a codebase legible to agents, then land the cleanup. Reads the docs as claims, checks the code against them, measures where agents actually spend their reads, and ranks cleanup by agent-cost — doc drift, duplicate concepts, no-obvious-home sprawl, unholdable files, dead weight that looks live, N-ways-to-do-one-thing. Ships behavior-preserving PRs, one concept each, and records a legibility scorecard so the trend is visible across runs. Triggers on: 'clean up the codebase', 'organize this repo', 'reduce tech debt', 'why do agents keep getting lost in this repo', 'the codebase has gotten messy', 'consolidate duplicates', 'dead code', 'does the code match the docs', 'codebase legibility', 'surface sprawl', 'too many commands'."
argument-hint: "[empty = this repo | <path> | --scan-only | --top N | --days N | --execute]"
allowed-tools: Bash(agents *), Bash(git *), Bash(gh *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Bash(sqlite3 *), Bash(bun *), Bash(wc *), Bash(sort *), Bash(uniq *), Read(*), Write(*), Edit(*), Task(*)
user-invocable: true
---

# code:clean

A codebase is an agent's working memory. Every hop it has to make to answer "where does
this go?" or "which of these two is real?" is context it cannot spend on the task. So the
thing this skill optimizes is not beauty and not line count — it is **how few things an
agent must read, and how few decisions it must guess at, to make a correct change.**

That is a measurable property, and it decays in a specific way. A prototype is legible
because everything fits in one head. A large codebase stops being legible long before it
stops working: the docs describe a shape the code left behind, two subsystems grow a third
name for the same concept, a `utils/` bucket appears, one file crosses the point where no
agent reads all of it, and a flag survives whose last caller died six months ago. None of
that breaks a test. All of it makes every future change slower and more likely to land in
the wrong place.

You are here to find that decay with evidence, rank it by what it actually costs, and
**land the fix** — not to file a report.

## What this is, and what it is not

| | |
|---|---|
| **Is** | A codebase-shape audit that ends in merged, behavior-preserving PRs and a recorded scorecard. |
| **Is not** | A linter. A style pass. A rewrite. A review gate. An excuse to add abstractions. |

**Boundary with `/code:review repo` (Mode C).** That skill is the read-only *defect*
diagnostic at file level — lint, doc-asserted invariants, identifier cross-reference,
signature clustering — and it never modifies code. This skill operates one level up, on
the **shape of the codebase**, and it *executes*. It **calls** Mode C for the file-level
passes rather than reimplementing them. If you find yourself writing an invariants grep or
a duplicate-function clusterer here, stop: that already exists at
`plugins/code/skills/review/{invariants,identifiers,signatures,code-health}.ts`. A skill
that preaches "no duplicate surfaces" and then grows one has failed its own rubric.

**Boundary with `/code:prune`.** That's git plumbing — merged branches and worktrees. No
overlap.

**Boundary with `/code:learn`.** When Phase 2 finds the docs are wrong and the *code* is
right, the fix is a doc edit, and the durable form of that is `code:learn`'s job
(`AGENTS.md`). Fix the drift here; route genuinely new navigation knowledge there.

## The three fix biases

These are load-bearing and two of them are counterintuitive. Get them wrong and a cleanup
makes the codebase *less* legible while looking tidier.

### 1. Consistency beats DRY

Agents pattern-match. Twenty call sites that all do the same boring thing the same boring
way are **cheaper** for an agent than one clever abstraction with twenty configurations,
because the boring version can be copied without being understood and the clever one
cannot be used without reading it.

So: **deduplicate concepts, not lines.** Two blocks of code that merely *look* alike are
not duplicates. They are duplicates when they encode the **same decision** — when a change
to one is a bug if it doesn't happen to the other. That, and only that, earns a merge.
Repetition that happens to rhyme is fine. Leave it.

The failure this prevents: a cleanup that "removes 400 duplicate lines" by introducing a
`doThing(opts)` with eight booleans, and every subsequent agent now has to read the
implementation to know what its call does.

### 2. Deletion beats abstraction

Fix ladder, in order. Take the highest rung that works:

1. **Delete it.** Nothing beats code that isn't there.
2. **Inline it.** A one-caller indirection costs a hop and buys nothing.
3. **Move it into the home that already exists.** Not a new home — the canonical one.
4. **Merge into the existing primitive**, deleting the other.
5. **Extract a new abstraction.** Last resort, and only for a concept the codebase already
   repeats with one meaning.

Every new layer is a hop, and every hop is context. A cleanup whose net effect is one more
module to route through is not a cleanup.

### 3. Fewer surfaces beat better docs

A flag you can remove is worth more than a paragraph explaining it. A command that nests
under the noun that owns it is worth more than a mention in a reference table. When the
choice is "document it" or "delete it", the second one is the cleanup.

## Phase 0 — Scope, and read the docs first

Resolve scope from `$ARGUMENTS`:

| Pattern | Scope |
|---|---|
| empty | the repo you're in (or its dominant package in a monorepo — say which you picked) |
| `<path>` (one or more) | only those dirs/files |
| `--top N` | keep the top N ranked items (default 8) |
| `--days N` | measurement window for churn and agent traffic (default 90) |
| `--scan-only` | stop after Phase 5 — plan, no PRs |
| `--execute` | skip the plan gate and land the plan (only when the user already approved a plan) |

```bash
REPO=$(git rev-parse --show-toplevel)
git -C "$REPO" fetch origin
RUN_DIR="$REPO/.agents/artifacts/$(date +%F)/clean-$(date -u +%H%M%S)"
mkdir -p "$RUN_DIR"
SKILL_DIR="$(dirname "$0")"   # or the resolved path to this skill's directory
```

Then, **before you look at any code**, read what the codebase says about itself and turn it
into a list of checkable claims. Read, in this order: the root `AGENTS.md`/`CLAUDE.md`, the
component `AGENTS.md` nearest the scope, `README.md`, anything under `docs/`, and any
`SPEC*.md` / specification the repo declares as normative.

A **claim** is a sentence a command can falsify. Extract those; skip prose.

| Claim shape | Example | How it gets checked in Phase 2 |
|---|---|---|
| Existence | "`--host` is an alias of `--device`" | `rg` both; run `<bin> --help` |
| Absence | "there is no root `workspaces` field — don't add it back" | `jq`/`rg` for the token |
| Singularity | "one execution engine — every invocation goes through `buildExecEnv`" | count the call paths that bypass it |
| Ownership | "`apps/cli` owns session state; the ext is a consumer" | grep the consumer for its own state writes |
| Layout | "resources are one kind per subdirectory" | `ls` the directory |
| Process | "every user-visible change adds a CHANGELOG entry" | sample recent merges |

Write them to `$RUN_DIR/claims.json` as `{id, claim, source_file, source_line, kind,
check}`. **A claim with no mechanical check is not a claim** — drop it rather than grade it
on vibes.

This phase is non-negotiable and it comes first for a reason: the docs are what an agent
reads *before* it reads code, so a wrong doc is the highest-leverage defect in the repo. It
does not merely fail to help; it actively routes agents into the wrong change.

## Phase 1 — Measure

Four independent passes. Run them concurrently; none shares state.

```bash
bun "$SKILL_DIR/exposure.ts" "$RUN_DIR" --days "$DAYS" > "$RUN_DIR/exposure.json" &
bun "$SKILL_DIR/surface.ts"  "$RUN_DIR" --cli "$BIN" > "$RUN_DIR/surface.json" &
# file-level defects — reuse, do not reimplement
# /code:review <scope>   (Mode C: code-health, invariants, identifiers, signatures)
wait
```

### 1a. Exposure — where agents actually spend their attention

`exposure.ts` joins three signals per file and is the reason this skill's ranking is not
taste:

- **churn** — commits touching the file in the window (`git log`).
- **agent traffic** — how many times agents actually `Read`/`Edit`ed the file, from the
  fleet's own session index (`~/.agents/.history/sessions/sessions.db`, table `tool_calls`,
  `json_extract(input,'$.file_path')`). Paths appear both absolute and `[HOME]`-redacted;
  the script normalizes both. **This is the signal nobody else has** — it is the difference
  between "this file looks bad" and "agents read this file 40 times last month and it is
  6,000 lines long."
- **size** — lines, and whether the file is past the point where an agent stops reading all
  of it.

`agent_cost = (2*agent_edits + agent_reads + commits) * size_penalty`, `size_penalty =
clamp(loc/500, 1, 4)`. The formula is deliberately dumb and printed with its inputs so a
human can argue with it. Rank order matters; the absolute number does not.

If `sessions.db` is absent (a machine with no fleet history), the script says so and falls
back to churn × size. **Say that in the report** — do not present a degraded ranking as the
full one.

### 1b. Surface census — the sprawl count

`surface.ts` enumerates the product's user-facing surface and grades each entry. For a CLI
it walks `<bin> --help` recursively (bounded: depth 4, 800 nodes, concurrency 8) to get
every command path; for a library it lists exported symbols. Then per entry:

- Does any doc mention it?
- Does any test exercise it?
- How many callers/importers does it have?
- When was its file last touched?

An entry with **no docs, no tests, and no non-test caller** is an orphan candidate. A
top-level entry whose name is a verb already owned by a group is a nesting candidate.

Surface count is the number to put at the top of the report. When a CLI has grown past a
few hundred commands, "which command does this?" has become a search problem for every
agent that touches it, and nesting/removal is the highest-value cleanup available.

### 1c. Idiom census — N ways to do one thing

Pick 5-8 cross-cutting operations the codebase performs everywhere. Typical: read config,
emit an error, log, spawn a subprocess, read a file path, register a command/route, access
the DB, format user-facing output. For each, grep the ways it is actually done and count
call sites per way.

```bash
rg -n --no-heading 'process\.env\.' --glob '!*test*' | wc -l
rg -n --no-heading 'loadConfig\(|readConfig\(|getConfig\(' | wc -l
```

Record as `{operation, variants: [{idiom, sites, example_file_line}], canonical: <the one
the docs or the majority endorse>}`. Two variants where one has 90% of sites is a healthy
migration; three variants at 40/35/25 is a coin flip every agent has to make.

### 1d. File-level defects — call Mode C

Run `/code:review <scope>` and read its `findings.json`. Take from it: doc-asserted
invariant violations, identifier references with no live counterpart, and
behavioral-signature clusters (parallel implementations). Cite them by their existing
finding ids. Do not re-derive them.

## Phase 2 — Check the code against the claims

Walk `claims.json`. For each claim run its check and record a verdict with the command you
ran and its real output:

| Verdict | Meaning | Fix direction |
|---|---|---|
| `holds` | code matches the doc | none |
| `drifted` | doc and code disagree | decide which is wrong — see below |
| `stale` | the doc describes something that no longer exists at all | delete the doc claim |
| `unverifiable` | the check could not run | say so; never grade it as passing |

When a claim has drifted, the question **"which one is wrong?"** is the whole decision, and
you must answer it explicitly:

- **The doc is wrong** → fix the doc. Cheapest, most common, highest leverage.
- **The code is wrong** → this is a *bug*, not a cleanup. File it. Do not fix it in a
  cleanup PR (see the hard lines).
- **Both drifted from an intent nobody wrote down** → the missing artifact is the
  specification; propose one short spec, do not invent rules nobody asked for.

Output `$RUN_DIR/drift.md` — a table of every claim, its verdict, the evidence, and the
direction. A repo where a majority of claims drift has a documentation *process* problem,
and that is worth naming as its own finding.

## Phase 3 — Classify

Every finding lands in exactly one class. The class names describe **what it costs an
agent**, not what it looks like:

| # | Defect | What it costs an agent | Detected by |
|---|---|---|---|
| 1 | **Lying context** — docs assert what the code contradicts | It reads the doc first and makes a confidently wrong change | Phase 2 drift; Mode C invariants/identifiers |
| 2 | **Two homes for one concept** — same decision in N places; two names for one thing | It edits one, the other silently drifts; or it can't tell which is canonical | Mode C signatures; idiom census; grep for synonym pairs |
| 3 | **No obvious home** — `utils/`/`helpers/`/`common/`/`misc/`, or 3 plausible destinations for a new function | Every agent guesses differently; entropy compounds per session | Bucket names; directories with 100+ flat siblings; files importing from 4+ peer dirs |
| 4 | **A file you can't hold** — big *and* hot | It reads a slice, misses the invariant that lived elsewhere in the file, edits wrong | `exposure.ts` top rows |
| 5 | **Dead weight that looks live** — zero-caller exports, orphan commands, superseded paths kept "just in case", flags nothing reads | It finds them, believes they're live, and extends them | `surface.ts` orphans; zero-importer exports |
| 6 | **N ways to do one thing** | It copies whichever it saw first; inconsistency compounds | Idiom census |

Each finding carries: class, evidence (`file:line` + quoted code or command output),
exposure numbers, the proposed fix at its ladder rung, and blast radius.

**Drop anything you cannot quote.** A finding without a `file:line` or a command's real
output does not exist.

## Phase 4 — Rank by agent-cost, then cut

`score = harm(class) × exposure(file)`.

Harm weights: lying context 5 · two homes 4 · N ways 3 · unholdable file 3 · no obvious
home 2 · dead weight 2. Dead weight is *low* harm on purpose — deleting it feels
productive and usually buys the least. Lying context is highest because it is the only
defect that makes agents actively wrong rather than merely slow.

Sort, keep the top N (default 8), and **discard the rest without ceremony**. A 60-item
backlog nobody will do is itself a legibility problem. Say how many you dropped.

## Phase 5 — Write the plan

One artifact, rendered and opened, plus tickets. Author the Markdown under the dated
artifact layout and render it with `artifacts render` (see the `artifacts` skill) —
`$RUN_DIR/plan-clean-<scope>.md`.

Structure:

1. **Scorecard** — the numbers, first: surface count, claims checked/drifted, files over the
   holdable threshold, orphan surfaces, idiom split for each operation sampled. Diff against
   the previous run if one exists.
2. **The top N**, each as: what an agent gets wrong today (concretely — "an agent adding a
   session filter must read 6,142 lines of `commands/sessions.ts` to know where"), evidence,
   the fix and its ladder rung, blast radius, and the test that proves behavior didn't change.
3. **Dropped** — the count and one line on why.
4. **Bugs found, not fixed** — Phase 2 "code is wrong" cases, filed as tickets.

Then split the plan in two and act accordingly. **Do not gate the whole run** — asking
permission to fix a doc that is already wrong is the banned stop.

| Tier | What's in it | What you do |
|---|---|---|
| **Reversible** | doc-drift fixes, dead weight with proven zero callers, a one-caller indirection inlined, an idiom migration finished where one variant already holds ~90% | **Land it.** No gate, no ask. |
| **Structural** | splitting a hot file, merging two subsystems, removing or renaming a user-facing surface, anything that changes where code lives for other people | **Present and get the pick**, then land. |

The structural tier is a real scope choice — which parts of the codebase get restructured
is the user's to make, and a cleanup PR against a surface they are about to redesign is
wasted work. That is the F1 exemption, not a permission request. Present both tiers
together, say plainly which you are already landing, and ask only about the structural
ones. `--scan-only` suppresses both; `--execute` suppresses the structural gate. After the
pick, every phase is autonomous — do not re-ask.

## Phase 6 — Land it

One item = one worktree = one PR = **one concept**.

The behavior-preservation contract, per PR:

- **No behavior change. Ever.** A cleanup PR that also fixes a bug or adds a flag is not
  reviewable, because the reviewer can no longer tell a refactor slip from an intended
  change. Split it.
- **Name the test that proves it.** Run the surface's canonical test before and after and
  quote both. For a pure move/rename, `git diff --stat` plus a green suite is the proof; for
  a merge of two implementations, the test must exercise **both** original call paths.
- **Deletion needs proof of no caller, everywhere.** Code callers, tests, docs, generated
  clients — *and consumers outside this repo*. In this stack that specifically means the
  fleet's own skills, hooks, routines, and rules that shell out to the CLI: a command with
  zero code callers can still have a dozen consumers in `.agents-system`. `rg` the companion
  repos before you call anything dead.
- **User-facing removals get a deprecation path**, not a delete: keep the old name working,
  route it to the new one, warn once, and record the removal version. A breaking rename ships
  with the docs and CHANGELOG in the same PR.
- **Never bulk-rename.** A rename that touches 200 files is unreviewable and conflicts with
  every branch in flight. Rename at the boundary the concept actually lives in.

Then drive each PR the way `/code:loop` does: push, non-author review, fix CI, merge on
green. Cleanup PRs conflict with in-flight work more than feature PRs do — check
`gh pr list` first and sequence around open PRs that touch the same files rather than
racing them.

## Phase 7 — Scorecard and trend

Re-run `exposure.ts` and `surface.ts` after the merges and write
`$RUN_DIR/scorecard.json`:

```json
{ "date": "…", "scope": "…", "commit": "…",
  "surface_count": 536, "orphan_surfaces": 41,
  "claims_checked": 34, "claims_drifted": 9,
  "files_over_1500_loc": 22, "top_file_loc": 6142,
  "idiom_splits": { "config-read": [412, 88, 31] },
  "hot_and_huge": 7 }
```

Compare against the newest prior `scorecard.json` under `.agents/artifacts/*/clean-*/` and
report the delta. **The trend is the product.** One run tells you what's wrong; the series
tells you whether the codebase is getting more or less legible as it grows — which is the
only way to know if the cleanup is outrunning the decay.

Close with the delta in one line, e.g. `surface 536 → 511 · drifted claims 9 → 2 ·
files>1500 22 → 21`.

## Hard lines

1. **A cleanup PR never changes behavior.** Found a bug mid-cleanup? File it, keep going.
2. **Never delete without proving no caller — including outside this repo.**
3. **Never quote a finding you can't anchor to `file:line` or real command output.**
4. **Never "clean" by adding an abstraction.** If the diff's net effect is one more layer,
   it failed. Ladder rung 5 needs a sentence justifying why 1-4 didn't apply.
5. **Never bulk-rename or reformat.** Both are unreviewable and both destroy `git blame`.
6. **Never mass-delete "dead" code found only by static reachability** in a language with
   dynamic dispatch, reflection, string-keyed registries, or CLI-name lookup. In this stack,
   commands are resolved by *name*, so "no import" means nothing. Grep the string.
7. **Never present a degraded measurement as a full one.** No session index, no `--help`
   walk, a skipped tool — say which signal is missing and what that does to the ranking.
8. **Never touch the default branch.** Worktree per item, always (F5).
9. **Never let the fix list exceed what will actually land.** Ten merged PRs beat a
   sixty-item backlog.

## Don'ts

- Don't reimplement Mode C's passes here. Call it.
- Don't grade style, naming taste, formatting, or "add types for flexibility". Not defects.
- Don't propose a rewrite. If the honest answer is "this subsystem needs redesigning", say
  that in one line as a finding and route it to `/swarm:plan` — do not start it here.
- Don't fan out to `agents teams` for the scan. It's a bounded diagnostic. Use teams only in
  Phase 6, when several *independent* cleanup PRs can genuinely run in parallel — and give
  each teammate its own worktree and a boundary contract, because cleanup tracks collide by
  nature.
- Don't write to `/tmp`. Output lands in `<repo>/.agents/artifacts/<yyyy-mm-dd>/clean-<ts>/`.
- Don't count lines deleted as the result. The result is the scorecard delta.
