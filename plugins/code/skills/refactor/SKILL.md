---
name: refactor
description: "Restructure a codebase the way a principal engineer does as a product grows — merge redundant concepts, extract the horizontal layer four modules reimplemented, draw real module boundaries, lift a cohesive core out into its own package/SDK so it is testable and reusable, reorganize the tree so it matches the architecture, shrink an overgrown public surface, and give a
  concept the contract its job calls for — the provider pattern (Go interface, TS interface, Python
  Protocol, Rust trait) with one implementation per variant in a registry, instead of the same
  if/else-by-name chain repeated across twenty files. Evidence-first: a module dependency graph (god modules, cycles, extraction candidates, upward imports), measured agent traffic per file, and a surface census — then before/after architecture figures rendered with artifacts-cli, then behavior-preserving PRs. Triggers on: 'refactor this codebase', 'clean up the architecture', 'the codebase has gotten messy', 'agents keep getting lost in this repo', 'merge these duplicate concepts', 'extract an SDK', 'split this package', 'module boundaries', 'reorganize the file tree', 'circular dependencies', 'god module', 'too many commands', 'does the code match the docs', 'provider pattern', 'should this be an interface', 'if/else chain on a name', 'plugin architecture', 'strategy pattern'."
argument-hint: "[empty = this repo | <path> | quality | --scan-only | --top N | --days N | --depth N | --execute]"
allowed-tools: Bash(agents *), Bash(artifacts *), Bash(git *), Bash(gh *), Bash(rg *), Bash(fd *), Bash(ls *), Bash(cat *), Bash(jq *), Bash(sqlite3 *), Bash(bun *), Bash(wc *), Bash(sort *), Bash(uniq *), Read(*), Write(*), Edit(*), Task(*)
user-invocable: true
---

# code:refactor

You are the principal engineer on a codebase that has outgrown its own structure. Not a
linter, not a tidier. The work is the restructuring a product needs continuously as it
grows: **two concepts that should be one, a horizontal layer four modules each
reimplemented, a module boundary that was never drawn, a cohesive core that should be its
own package, a directory tree that no longer tells you where anything goes, a public
surface that grew past the point where anyone can find things in it, and a concept that
never got the shape its job actually calls for.**

Why it is urgent now, and not merely tasteful: **an agent's throughput is bounded by how
few things it must read, and how few decisions it must guess at, to make a correct
change.** A prototype is legible because it fits in one head. A large codebase stops being
legible long before it stops working — and the moment it does, every agent working in it
slows down, puts things in the wrong place, and compounds the mess. Architecture is the
input to velocity, not a finishing touch on it.

So the output of this skill is not a report and not a diff that deletes lines. It is
**merged, behavior-preserving PRs that change the shape of the codebase**, each one with a
before/after figure a human can check.

## Scope: architecture first, hygiene second

| Tier | What it is | Weight |
|---|---|---|
| **Architectural** (the job) | redundant concepts · missing horizontal layer · undrawn module boundary · package/SDK extraction · tree that contradicts the architecture · overgrown surface · a concept with no contract (provider pattern) | ~80% of the plan |
| **Hygiene** (only where it blocks the above) | dead code, doc drift, a file too big to hold, N idioms for one operation | ~20%, and only when it obstructs an architectural move or is what a claim-check turned up |

If the plan you produce is mostly dead-code deletion and doc fixes, **you have done the
wrong job.** Those are the byproducts of restructuring, not the point of it.

## What this is not

Not a linter, not a style pass, not a rewrite, not a review checkpoint, not an excuse to add
abstractions.

**Boundary with `/code:review repo` (Mode C).** That is the read-only *defect* diagnostic
at file level — lint, doc-asserted invariants, identifier cross-reference, signature
clustering — and it never modifies code. This skill works one level up, on the shape of
the system, and it executes. **Call** Mode C for the file-level passes; never reimplement
them. If you start writing an invariants grep or a duplicate-function clusterer here,
stop: they exist at `plugins/code/skills/review/{invariants,identifiers,signatures,code-health}.ts`.
A skill that preaches "no duplicate surfaces" and then grows one has failed its own rubric.

**Boundary with `/code:learn`** — when a doc is wrong and the code is right, fix the doc
here; route genuinely new navigation knowledge to `code:learn` (it owns `AGENTS.md`).

## Quality mode — the small, in-flight cleanup pass

`quality` (`/code:refactor quality`, the small-change door this skill shares with the
global `simplify` skill) is **not** the full evidence-first architectural run. It is the
targeted cleanup you make *while* you are already in a file: skip Phases 0–5, go straight
to a concrete fix, and land it in the same change.

The one rule that separates it from a linter: **every quality finding is tied to a change
you actually make — never a report you file and walk away from.** When you act in this
mode, also fix what is right in front of you —

- **duplicate code** — two blocks that encode the *same decision* (bias 1); merge the
  concept, not merely the lines.
- **a bad abstraction** — a one-caller indirection, an eight-boolean `doThing(opts)`, a
  wrapper that buys nothing; take the highest rung of the deletion ladder that works.
- **a pattern that should exist but doesn't** — the contract a family already calls for
  (the provider pattern), a helper five call sites reinvent, the canonical home a stray
  function belongs in.

Same three biases, same behavior-preserving contract, same "prove no caller before you
delete" hard line — just scoped to the change at hand and landed in the same PR rather
than sequenced across a plan. If a cleanup outgrows a small in-flight change into a real
structural move, stop and run the full skill instead.

## The three biases that decide every call

### 1. Consistency beats DRY

Agents pattern-match. Twenty call sites doing the same boring thing the same boring way
are **cheaper** than one clever abstraction with twenty configurations, because the boring
version can be copied without being understood.

**Deduplicate concepts, not lines.** Two blocks are duplicates when they encode the *same
decision* — when changing one is a bug if the other doesn't change too. Code that merely
rhymes is fine; leave it. The failure this prevents: a "refactor" that removes 400
duplicate lines behind a `doThing(opts)` with eight booleans, and now every agent must
read the implementation to know what its own call does.

### 2. Deletion beats abstraction — the ladder

Take the highest rung that works, and justify in writing any use of rung 5:

1. **Delete it.**
2. **Inline it** — a one-caller indirection costs a hop and buys nothing.
3. **Move it into the home that already exists** — not a new home, the canonical one.
4. **Merge into the existing primitive**, deleting the other.
5. **Extract a new layer/package** — last resort, and only for a concept the codebase
   already repeats with one meaning.

Note the asymmetry with the architectural work below: extracting a *horizontal layer* or a
*package* IS rung 5, and it is legitimate precisely when the evidence shows the concept is
already repeated N times with one meaning. Rung 5 without that evidence is speculation.

### 3. Fewer surfaces beat better docs

A flag you can remove beats a paragraph explaining it. A command nested under the noun
that owns it beats a mention in a reference table.

This is about *not writing new docs to excuse a fixable surface* — it does not conflict with
move 8. Move 8 relocates prose that ALREADY EXISTS (as an inline comment essay) to where it
is discoverable, and adds no new surface to the code. Writing a doc to explain a removable
flag is the anti-pattern; giving a subsystem's real design narrative a home in `docs/`
instead of burying it in a file header is the opposite — it makes the existing knowledge
findable. Never reach for a doc to paper over a smell you could delete.

## Phase 0 — Scope, and read the docs as claims

| `$ARGUMENTS` | Effect |
|---|---|
| empty | this repo (its dominant package in a monorepo — say which you picked) |
| `quality` | small-change cleanup pass — see **Quality mode** above; skips the phases below |
| `<path>` | scope to those dirs |
| `--depth N` | module granularity for the graph (default 2 path segments) |
| `--days N` | window for churn + agent traffic (default 90) |
| `--top N` | how many moves the plan carries (default 6) |
| `--scan-only` | stop after the plan |
| `--execute` | skip the structural checkpoint on an already-approved plan |

```bash
REPO=$(git rev-parse --show-toplevel)
git -C "$REPO" fetch origin
RUN_DIR="$REPO/.agents/artifacts/$(date +%F)/refactor-$(date -u +%H%M%S)"
mkdir -p "$RUN_DIR"
```

**Before reading any code**, read what the codebase says about itself and convert it into
checkable claims: root `AGENTS.md`/`CLAUDE.md`, the nearest component `AGENTS.md`,
`README.md`, `docs/`, any `SPEC*.md` the repo calls normative. The architecture claims
matter most here — "one execution engine", "X owns the state, Y is a consumer", "one kind
per subdirectory", "no cross-package imports". Those are the intended architecture, and
Phase 2 measures how far the code has drifted from it.

Write `$RUN_DIR/claims.json`: `{id, claim, source_file, source_line, kind, check}` where
`kind` ∈ existence · absence · singularity · ownership · layering · layout · process.
**A claim with no mechanical check is not a claim** — drop it rather than grade it on vibes.

## Phase 1 — Measure

Five scripts plus one reused skill. Run concurrently.

```bash
# Bind everything the passes need. SCOPE/DEPTH/DAYS come from $ARGUMENTS (Phase 0
# defaults: the repo, 2, 90). BIN is the repo's own CLI when it ships one — resolve it
# from package.json `bin`, a Makefile install target, or the README's install line;
# when the repo ships no CLI, skip surface.ts's --cli mode and run --exports instead.
SKILL_DIR="$HOME/.agents/plugins/code/skills/refactor"
[ -d "$SKILL_DIR" ] || SKILL_DIR="$HOME/.agents/.system/plugins/code/skills/refactor"
SCOPE="${SCOPE:-.}"; DEPTH="${DEPTH:-2}"; DAYS="${DAYS:-90}"

if [ -n "$BIN" ]; then SURFACE_ARGS=(--cli "$BIN"); else SURFACE_ARGS=(--exports); fi

bun "$SKILL_DIR/modules.ts"  "$RUN_DIR" --scope "$SCOPE" --depth "$DEPTH" > "$RUN_DIR/modules.json" &
bun "$SKILL_DIR/exposure.ts" "$RUN_DIR" --days "$DAYS" --scope "$SCOPE"   > "$RUN_DIR/exposure.json" &
bun "$SKILL_DIR/surface.ts"  "$RUN_DIR" "${SURFACE_ARGS[@]}"             > "$RUN_DIR/surface.json" &
bun "$SKILL_DIR/patterns.ts" "$RUN_DIR" --scope "$SCOPE"                 > "$RUN_DIR/patterns.json" &
bun "$SKILL_DIR/comments.ts" "$RUN_DIR" --scope "$SCOPE" --depth "$DEPTH" > "$RUN_DIR/comments.json" &
wait
# then, for the file-level defect passes — reuse, never reimplement:
#   /code:review <scope>     (Mode C → findings.json)
```

### 1a. `modules.ts` — the architectural evidence

Builds a file-level import graph, folds it to modules, and derives what you cannot see
reading files one at a time:

| Output | What it means | What it licenses |
|---|---|---|
| `god_modules` | fan-in far above the rest; high `api_ratio` means most of its files are imported from outside, i.e. no encapsulation | draw a boundary, split by domain |
| `cycles` | module-level SCCs — two modules in a cycle **are one module that hasn't admitted it**; neither can be tested, extracted, or reasoned about alone | break the cycle before anything else |
| `extraction_candidates` | high cohesion, low outbound coupling, small `api_ratio` — the shape of a package/SDK waiting to be lifted out | extract to its own package |
| `upward_imports` | a lower layer importing an upper one (`lib → commands`) — the inversion that makes a "library" un-liftable | invert the dependency |
| per-module `cohesion`, `api_files`, `depends_on` | whether a directory is a module or just a folder | everything else |

Read the `meta.caveats` and honor them: layer inference is **name-based**, package-specifier
imports are not edges, and the module granularity is a directory at `--depth` — so a repo
whose architecture does not follow its tree gets a graph that flatters it. Say so in the
report when it applies.

### 1b. `exposure.ts` — where agents actually spend attention

Joins churn (`git log`), size, and **real agent `Read`/`Edit` traffic** from the fleet
session index (`~/.agents/.history/sessions/sessions.db`, `tool_calls`). This is the
signal that turns "this module looks bad" into "agents edited this module 56 times last
month." It folds `.agents/worktrees/<slug>/` paths back to repo-relative — without that,
every agent *edit* is dropped as untracked.

`agent_cost = (2*agent_edits + agent_reads + commits) * clamp(loc/500, 1, 4)`. Deliberately
dumb, printed with its inputs so it can be argued with. **Aggregate it per module** and
join to `modules.json` — a god module nobody touches is a lower priority than a smaller
one every agent edits weekly.

If `sessions.db` is absent, the script says so in `meta.degraded`. Report that; never
present a degraded ranking as the full one.

### 1c. `surface.ts` — the public surface census

Walks a CLI's `--help` tree (or lists exports) and grades every entry documented / tested /
referenced, with cycle guards for a command that re-offers its own siblings. Surface sprawl
is architectural: once "which command does this?" is a search problem, nesting under the
owning noun and deleting orphans is the highest-value move available.

### 1d. `patterns.ts` — is the concept in the shape its job calls for?

The other passes ask where code *lives*. This one asks whether a concept has the *form*
it needs. The recurring case: a family of variants the code dispatches on by name —
`if (agent === 'claude') … else if (agent === 'codex') …` — where the job actually
calls for **one declared contract plus one implementation per variant, registered in a
table.** Every language spells the contract differently; the shape and the payoff do not
change:

| Language | The contract | The registry |
|---|---|---|
| Go | `interface` | `map[Kind]Impl` |
| TypeScript | `interface` + a discriminated union of ids | `Record<Id, Impl>` |
| Python | `Protocol` / `ABC` | a dict, or entry points |
| Rust | `trait` | `HashMap<Kind, Box<dyn Trait>>` |
| Java / C# | `interface` | a map, or DI registration |
| Swift | `protocol` | a dictionary |

The payoff is what matters for agent throughput: **adding a variant becomes one new file
plus one table entry, and the type system names what is missing** — instead of a reviewer
noticing that three of eleven call sites were never updated.

`patterns.ts` emits, per discriminator family: `members`, `arms` (how many hand-branches
exist — what collapses), `has_contract` + `contract_ref`, `has_registry` + `registry_ref`,
`provider_dir`, `capability_holes`, and a verdict:

| Verdict | Meaning | The move |
|---|---|---|
| `exemplar` | contract + registry + one file per variant, few raw arms | **Cite it.** This is the shape this repo already chose. |
| `bypassed` | contract **and** registry both exist, and call sites branch by hand anyway (>3 arms per variant) | Route the arms through the table that already exists — cheap, mechanical, no new abstraction |
| `partial` | only one of the pair exists (or both exist and the arms are few) | Complete the pair |
| `missing` | neither, and many arms | Introduce the contract first, then migrate arms |

**`bypassed` is usually the most valuable finding and the one a binary present/absent
check hides.** A codebase that already has the pattern and routes around it does not need
a design decision — it needs its call sites moved, which is exactly the kind of
behavior-preserving change this skill lands.

**Prefer the in-repo exemplar over any textbook pattern.** When one family is healthy and
another is not, the fix for the second is "look like the first" — same file layout, same
naming, same registration point. Note that the closest model in a repo is often itself
graded `bypassed` rather than `exemplar`, and that a row can merge two concepts: on
`agents-cli`, `lib/terminal` has the full shape (contract + registry at
`apps/cli/src/lib/terminal/backends/index.ts:19`, one file per backend) yet the `backend` row shows 61 arms — of
which only 9 are in `lib/terminal`; the rest are an unrelated secrets `backend` sharing the
variable name. **Read `arms_by_area` and `area_concentration` before quoting a family's
numbers.** A concentration well below 1.0 means the row is two concepts, not one, and the
member list is polluted. Cite the shape, not the verdict.

**A feature of the family belongs in the contract, not beside it.** When something that
modifies or extends every variant lives as a *sibling* module — multiplexing next to the
terminal backends, retry next to the transports, caching next to the stores — it is a
capability of the abstraction that never got declared. Fold it in as a contract method or
an explicit capability flag the registry carries, so a variant either supports it or
declares it does not, and `capability_holes` can see the gap. A sibling module that
special-cases three of eleven variants is the same defect as the dispatch chain, one level
up.

**Two judgement calls this script cannot make**, and the skill must make explicitly:

1. **Do the variants share a contract at all?** A family that genuinely diverges is not a
   provider family; forcing an interface onto it produces the eight-boolean `doThing(opts)`
   that bias 1 exists to prevent. `patterns.ts` leaves `same_contract: null` on purpose.
2. **Is the dispatch itself legitimate?** One switch at the boundary that *builds* the
   provider is correct and should stay. It is the second, fifth, and twentieth switch on
   the same discriminator, scattered across modules, that is the defect.

### 1e. Concept census — the one thing no script can do alone

Grep-and-judge, because two names for one concept is a semantic call. Method:

1. From `modules.json`, take the top modules by fan-in and list their exported nouns.
2. For each cross-cutting operation the codebase performs everywhere — config read, error
   shape, logging, subprocess spawn, path resolution, retry, auth, DB access, user-facing
   formatting — grep the ways it is actually done and count call sites per way.
3. Look for **synonym pairs**: two vocabularies for one thing (`host`/`device`,
   `job`/`task`, `account`/`profile`), especially when both appear as separate command
   groups, separate types, or separate config keys over the same underlying data.

Record `{concept, names: [...], sites_per_name, evidence: [file:line], same_decision: yes|no}`.
`same_decision: no` means they are genuinely different things that happen to sound alike —
**drop it**, do not merge.

### 1f. `comments.ts` — architecture prose that is mislocated, not the comment count

The module graph is blind to the 12–30% of non-blank lines that are comments. `comments.ts`
reports, per module: `comment_pct`, `code_test_ratio`, and — the actual signal —
`essay_blocks`: contiguous comment runs ≥ `--min-block` (default 15) lines, each with
`file:line` and size. A file-head or subsystem design narrative written as a comment block
(data flow, storage model, protocol, isolation model, "why it's built this way") is prose
that rots next to code and is undiscoverable; it belongs in `docs/`. That is the trigger for
move 8.

**`comment_pct` is a map, not a target — this is the load-bearing caveat.** Most inline
comments are load-bearing and STAY: per-symbol API docs (godoc/JSDoc on an exported name),
and point-of-use gotchas / security invariants / ticket-anchored WHYs on the line they
explain. Only the multi-line *essays* relocate. A module can sit at 30% comments and be
correctly documented; another at 5% can be opaque. **Never propose "cut comments to N%"** —
that deletes the gotchas. The number a docs-relocation move moves is `essay_lines`, and it
moves it out of code and *into* `docs/`, not out of existence. `code_test_ratio` is
context, not a grade: a low ratio can hide skipped or dead tests (route real test-quality
questions to `/code:review`, which reads the test bodies).

## Phase 2 — Check the code against the claims

Run each claim's check; record the command and its real output.

| Verdict | Fix direction |
|---|---|
| `holds` | none |
| `drifted` | decide **which is wrong** — see below |
| `stale` | the doc describes something gone; delete the claim |
| `unverifiable` | say so; never grade as passing |

- **Doc wrong** → fix the doc. Cheapest, most common.
- **Code wrong** → that is a *bug*, not a refactor. File it; do not fix it in a
  behavior-preserving PR.
- **Both drifted from an unwritten intent** → the missing artifact is a spec; propose one
  short spec, do not invent rules nobody asked for.

An architecture claim that has drifted (`"one execution engine"` when the graph shows four
paths bypassing it) is simultaneously a doc defect and the strongest possible evidence for
an architectural move. Treat it as both.

## Phase 3 — Classify the moves

Eight architectural classes. Each finding names the move, not the mess.

| # | Move | Trigger in the evidence | What it costs an agent today |
|---|---|---|---|
| 1 | **Merge redundant concepts** | concept census: two names, one decision | It edits one, the other drifts; or it cannot tell which is canonical |
| 2 | **Extract the horizontal layer** | the same cross-cutting operation implemented in N modules | Every module teaches it a different way to do one thing |
| 3 | **Draw the module boundary** | `god_modules`, high `api_ratio`, `cycles` | Nothing can be changed, tested, or read in isolation |
| 4 | **Lift a package / SDK out** | `extraction_candidates` — cohesive core, small API, few outbound deps | The reusable core cannot be tested alone or consumed by a second client |
| 5 | **Reorganize the tree to match the architecture** | flat dirs of 100+ siblings, `utils/`-style buckets, tests far from source, kind-based instead of domain grouping | "Where does this go?" has no inferable answer, so every agent guesses differently |
| 6 | **Shrink the public surface** | `surface.ts`: undocumented, untested, orphan, self-referential paths | "Which command does this?" is a search problem |
| 7 | **Give the concept a contract** (provider pattern) | `patterns.ts`: a family the code branches on by name, with high arms-per-member, no contract or a contract everything bypasses | To add or change one variant it must find and edit N scattered branches, and nothing tells it which ones it missed |
| 8 | **Relocate architecture prose into `docs/`** | `comments.ts`: `essay_blocks` — a multi-line design narrative (data flow, storage, protocol, isolation model) living in a comment block, especially at a file head | To learn how the subsystem works it reads the source; the design isn't with the other docs, and the essay silently rots as the code moves |

Move 8 is the cheapest high-clarity win and the lowest-risk (comment + markdown only), but it
is not a license to strip comments. **Relocate, don't delete:** each essay is lifted into
`docs/NN-<topic>.md` at staff level — architecture, storage, DB, protocols, boundaries,
invariants, sourced from real symbols — and the inline block is replaced by a 2–5 line
pointer plus whatever point-of-use gotchas were interleaved. Augment an existing module doc
when the topic already has one; add a new `docs/` file only for a genuinely new topic. Keep
inline: all per-symbol API docs and point-of-use gotchas/invariants (this is bias 3, read
carefully). A block you cannot confidently call a standalone essay stays inline.

Hygiene tier, only where it blocks a move above or a claim-check surfaced it: lying
context · dead weight that looks live · a file too big to hold · N idioms for one operation.

Every finding carries: the move, evidence (`file:line`, or a quoted number from the JSON
with the key it came from), the ladder rung, blast radius, and the test that proves
behavior is unchanged. **Drop anything you cannot quote.**

## Phase 4 — Rank, sequence, cut

`score = harm × exposure`, where exposure is the module's aggregated `agent_cost`.

Harm: cycle in the graph 5 · redundant concept 5 · **missing contract 5 · bypassed
contract 4** · missing layer 4 · undrawn boundary 4 · tree mismatch 3 · surface sprawl 3 ·
package extraction 3 · mislocated architecture prose 2 · hygiene 1-2.

Move 8 scores low on harm but is weighted by exposure like any other, so a design essay
buried in a high-fan-in module (the one every agent reads) can out-rank a structural move in
a module nothing touches — which is correct: the cost is paid per reader.

A missing contract scores with the worst because it is the defect that makes every
*future* change to that family expensive, and it is the one an agent is most likely to
make worse by hand — adding a twenty-second branch because twenty-one already existed.

**Then sequence, because architectural moves have a dependency order and the wrong order
wastes all of it:**

1. **Break cycles first.** Nothing can be extracted out of an SCC.
2. **Merge concepts before drawing boundaries** — otherwise you draw a boundary around a
   duplicate and enshrine it.
3. **Give the family its contract before extracting its package** — a package with no
   declared contract exports its internals as its API, and then the boundary is fiction.
4. **Extract the layer before the package** — a package that still reimplements the shared
   layer just moves the duplication behind a version number.
5. **Move the tree last.** A rename during earlier moves conflicts with every branch in
   flight.

Keep the top N (default 6) and **discard the rest without ceremony**, saying how many you
dropped. A sixty-item backlog nobody will do is itself a legibility problem.

## Phase 5 — The plan, with before/after figures that are actually correct

**This phase is where most agents get sloppy, and sloppy here is worse than useless: a
figure that misstates the architecture is lying context, the exact defect this skill
exists to remove.** Precision is the requirement, not decoration.

Author Markdown under the dated artifact layout and render it with **artifacts-cli**:

```bash
artifacts new visual --out "$RUN_DIR/refactor-<scope>.md"   # optional scaffold; frontmatter needs kind + title
artifacts check  "$RUN_DIR/refactor-<scope>.md"             # errors without a real drawn figure
artifacts render "$RUN_DIR/refactor-<scope>.md" --open       # writes .html next to the source
```

### The figure contract — every architectural move ships a before/after

**Use the before/after component the template already ships** — do not hand-roll a
two-column layout. A `visual` artifact provides it, and the scaffold's comment block lists
the full allowed class set (custom CSS and unlisted classes are rejected at render):

```html
<div class="artifact-behavior">
  <div class="artifact-behavior-panel" data-state="current"  data-evidence="modules.json: edges[], modules[]">
    <svg viewBox="0 0 420 300" role="img" aria-label="…"> … </svg>
  </div>
  <div class="artifact-behavior-panel" data-state="proposed" data-evidence="derived: invert 8 outbound edges">
    <svg viewBox="0 0 420 300" role="img" aria-label="…"> … </svg>
  </div>
</div>
```

`data-state="current"` / `"proposed"` render as the CURRENT / PROPOSED panels;
`data-evidence` is where the JSON key or derivation that backs the panel goes, so a reader
can check the picture against the data.

**Theme mechanics that are not optional:** shapes use `stroke="currentColor" fill="none"`
and **every `<text>` carries an explicit `fill="currentColor"`**. Omit the text fill and the
labels inherit a near-black fill and vanish on the dark theme — measured, not hypothetical:
the first render of this contract's own reference figure was unreadable for exactly that
reason. Hand-authored inline SVG only — never mermaid, never a CDN chart lib.

A working reference implementation of this contract — the panels, the theme mechanics, and an honest "this move is blocked until X" callout — ships next to this skill at `reference-figure.md`. **Copy its shape; never copy its numbers.**

Then, per move, drawn from `modules.json` — not from memory, not from vibes:

- **Every box is a real module** at its real path, labeled with its real `files` and `loc`
  from `modules.json`. No invented modules, no generic "Core" / "Utils" box that does not
  exist in the tree.
- **Every arrow is a real edge**, labeled with the real import `count` from `edges`. An
  arrow you cannot find in the JSON does not get drawn.
- **BEFORE and AFTER are the same graph** with the same node positions where a node is
  unchanged, so the eye reads the *difference*, not a redrawn picture. Mark removed edges
  and moved/merged nodes distinctly (and label them, not just color them — the reader may
  be colorblind or printing it).
- **The AFTER must be derivable from the move you propose.** If the move is "extract
  `lib/terminal` into a package", the AFTER shows exactly which of the 15 inbound edges now
  enter through the package's public API and which files stop being imported directly. If
  you cannot state that precisely, the move is not specified well enough to build.
- **Numbers in the prose match numbers in the figure match numbers in the JSON.** Three
  places, one value. A mismatch is a blocking self-check failure — fix it before rendering.
- **State the scale honestly.** If the graph has 44 modules and the figure shows 9, say
  "9 of 44 modules shown — the subgraph this move touches", and pick the subgraph by the
  edges the move changes, never by what draws nicely.

Also render, once for the run: a **system map** (all modules, sized by LOC, with the
cycle(s) marked) so the reader sees the whole before they see the moves.

**Then look at it.** Render, open the HTML, and actually read the figure at full size before
you present it — labels legible in both themes, no overlapping text, every number matching
the JSON. A figure you rendered but never looked at is not verified, and this is the one
artifact where being sloppy does active harm: it becomes the next agent's context.

### Plan structure

1. **Scorecard** — modules, module edges, cycles, god modules, extraction candidates,
   upward imports, surface count, claims checked/drifted, files past holdable. Delta vs the
   previous run if one exists.
2. **System map figure.**
3. **The top N moves**, each: what an agent gets wrong today (concretely), the evidence,
   the before/after figure, the ladder rung, blast radius, sequencing position, and the
   test that proves no behavior change.
4. **Dropped** — count and one line.
5. **Bugs found, not fixed** — Phase 2 "code is wrong" cases, filed as tickets.

Then split by tier and act — **do not block the whole run**; asking permission to fix an
already-wrong doc is the banned stop:

| Tier | Contents | Action |
|---|---|---|
| **Reversible** | doc-drift fixes, dead weight with proven zero callers, a one-caller indirection inlined, finishing an idiom migration already at ~90% | **Land it.** No checkpoint. |
| **Structural** | every one of the eight architectural moves | **Present the figures, get the pick**, then land. |

The structural checkpoint is a genuine scope choice — which parts of the system get restructured
is the user's call (F1's design-choice exemption), and a package extraction against a
subsystem they are about to redesign is wasted work. `--scan-only` suppresses both;
`--execute` suppresses the structural checkpoint. After the pick, everything is autonomous.

## Phase 6 — Land it

One move = one worktree = one PR = one concept. Large moves split further: a package
extraction is *at least* three PRs — (a) break the inbound edges that bypass the future API,
(b) move the files with no other change, (c) add the package boundary and switch consumers.

The behavior-preservation contract:

- **No behavior change. Ever.** A refactor PR that also fixes a bug is unreviewable —
  the reviewer can no longer tell a slip from an intent. Split it.
- **Name the test that proves it.** Run the surface's canonical test before and after, quote
  both. A pure move ships `git diff --stat` plus a green suite; a concept merge must
  exercise **both** original call paths.
- **Deletion needs proof of no caller, everywhere** — code, tests, docs, generated clients,
  **and consumers outside this repo**. In this stack that means the fleet's own skills,
  hooks, routines, and rules that shell out to the CLI: a command with zero code callers can
  still have a dozen consumers in the companion `.agents-system` repo. `rg` them first.
- **User-facing removals get a deprecation path**, not a delete: old name keeps working,
  routes to the new one, warns once, removal version recorded, docs + CHANGELOG in the same PR.
- **Never bulk-rename.** Rename at the boundary the concept actually lives in.
- **Re-run `modules.ts` after each structural PR merges** and check the graph moved the way
  the AFTER figure said. If it didn't, the figure was wrong — say so, fix it, and correct
  the plan before the next PR builds on a false premise.
- **A move-8 PR is comment + markdown only — prove it mechanically.** The diff must add/edit
  `docs/*.md` and the pointer comments and nothing else: every changed line in a source file
  is a comment line, no code token moves. Verify it (strip trailing comments from each `-`/`+`
  source line and assert the code prefix is unchanged; a filtered diff of non-comment source
  lines must be empty) and quote that the code prefix set is identical before/after. Then the
  canonical test is a compile/typecheck (`go vet ./…`, `tsc --noEmit`) — comments and markdown
  cannot change behavior, and a green compile plus the empty-non-comment-diff IS the proof.
  Verify the new doc's claims against real symbols; a wrong architecture doc is lying context,
  the exact defect this skill removes — worse than the buried comment it replaced.

Drive each PR the way `/code:loop` does: push, non-author review, fix CI, merge on green.
Refactor PRs conflict with in-flight work more than feature PRs — check `gh pr list` and
sequence around open PRs touching the same modules rather than racing them.

## Phase 7 — Scorecard and trend

Re-run all three scripts after the merges; write `$RUN_DIR/scorecard.json`:

```json
{ "date": "…", "scope": "…", "commit": "…",
  "modules": 44, "module_edges": 196, "cycles": 1, "largest_cycle": 38,
  "god_modules": 3, "max_fan_in": 1095, "extraction_candidates": 4, "upward_imports": 7,
  "surface_count": 337, "orphan_surfaces": 7,
  "families": 94, "contract_exemplars": 3, "contract_bypassed": 13, "contract_missing": 40,
  "collapsible_arms": 1623,
  "claims_checked": 34, "claims_drifted": 9,
  "files_over_1500_loc": 41, "top_file_loc": 6142,
  "essay_blocks": 59, "essay_lines": 1229, "comment_pct_p50": 14 }
```

Diff against the newest prior `scorecard.json` under `.agents/artifacts/*/refactor-*/` and
report the delta in one line: `cycles 1→0 · largest cycle 38→0 · max fan-in 1095→420 ·
collapsible arms 1623→410 · surface 337→266 · essay lines 4554→1229 · drifted claims 9→2`.

For a run that landed a move 8, also carry a **per-module before/after** of `comments.json`
(module · `comment_pct` before→after · `essay_lines` before→after · new `docs/` files) — the
same three-places-one-value discipline as the figures. Note plainly when `comment_pct` barely
moved while `essay_lines` fell: that is the correct outcome (the essays left, the per-symbol
docs stayed), not underperformance — do not report it as a density miss.

**The trend is the product.** One run tells you what is wrong; the series tells you whether
the structure is outrunning the decay as the product grows — which is the only measure of
whether this work is working.

## Hard lines

1. **A refactor PR never changes behavior.** Found a bug? File it, keep going.
2. **Never delete without proving no caller — including outside this repo.**
3. **Never draw a box or an arrow you cannot source from `modules.json`.** A wrong figure
   is lying context.
4. **Never propose an extraction out of a cycle.** Break the cycle first; anything else is
   a package that drags the whole SCC with it.
5. **Never force a contract onto variants that do not share one.** `same_contract` is a
   judgement the script refuses to make; make it explicitly, with the divergent method
   quoted, before proposing move 7. Forcing it produces the eight-boolean `doThing(opts)`
   that bias 1 exists to prevent.
6. **Never "refactor" by adding a layer nothing repeats yet.** Rung 5 needs the evidence
   that the concept is already repeated N times with one meaning.
7. **Never bulk-rename or reformat.** Unreviewable, and it destroys `git blame`.
8. **Never mass-delete "dead" code found only by static reachability** in a language with
   dynamic dispatch, reflection, string-keyed registries, or CLI-name lookup. Here commands
   resolve by *name* — "no import" means nothing. Grep the string.
9. **Never present a degraded measurement as a full one.** Missing session index, truncated
   `--help` walk, sub-1.0 graph coverage, skipped tool — name it and say what it does to the
   ranking.
10. **Never touch the default branch.** Worktree per move (F5).
11. **Never let the plan exceed what will actually land.** Six merged moves beat sixty
    proposed ones.

## Don'ts

- Don't reimplement `code:review` Mode C's passes. Call it.
- Don't grade style, naming taste, or formatting. Not architecture.
- Don't propose a rewrite. If the honest answer is "this subsystem needs redesigning", say
  it in one line as a finding and route it to `/swarm:plan` — do not start it here.
- Don't fan out to `agents teams` for the scan; it is a bounded diagnostic. Use teams in
  Phase 6 only, when several moves are genuinely independent — each teammate in its own
  worktree with a boundary contract, because refactor tracks collide by nature.
- Don't write to `/tmp`. Output lands in `<repo>/.agents/artifacts/<yyyy-mm-dd>/refactor-<ts>/`.
- Don't count lines deleted as the result. The result is the scorecard delta.
