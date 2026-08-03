---
name: agents-md
description: "Write and maintain AGENTS.md files a coding agent will actually use — top-level guidelines, invariant-first declaratives, source-of-truth pointers greppable by symbol, narrowed per-package. Triggers on: create/update AGENTS.md/CLAUDE.md/GEMINI.md, 'context file', 'memory file', 'document this subsystem for agents', 'the AGENTS.md is stale', onboarding a repo or package for agents."
user-invocable: true
---

# Writing AGENTS.md files agents actually use

An `AGENTS.md` is not documentation for humans. It is read by a coding agent
mid-task, under token pressure, that navigates by `rg <symbol>` and will re-read
the source anyway unless the file earns its trust. Write for that reader.

## What the reader actually does (observed, not assumed)

Across a sample of ~100 subagent runs:

- **They go to code, not notes.** ~16× more source-file reads than doc reads. Most
  opened a code file; few opened any doc; almost none opened AGENTS.md.
- **They navigate by symbol.** Hundreds of `rg`/`grep` calls, near-zero
  structured-search calls. The unit they search for is an identifier
  (`mintToken`, `SessionRow`), not a prose heading.
- **They re-read to verify a contract, not to learn architecture.** The reads were
  overwhelmingly targeted line-slices answering *"does function X do/guarantee Y?"* —
  not whole-file "how does this work" reads.
- **They cross-check.** When an agent did read a note, it opened code too. Notes are
  safe from staleness today only because agents distrust them and re-derive.

The consequence: your file competes with `rg` + reading the source. It earns its
place only when it answers the exact question **faster than grepping** AND is
**trustworthy enough that the agent doesn't re-verify**. Every line that fails both
tests is dead weight that also rots.

## A worked example (self-contained)

This is a complete small `AGENTS.md` for a fictional service. The principles below
point back into it. Note: it says **where the scripts are** (not how to install),
states **invariants** with a **source-of-truth pointer** and an **enforcing test**,
and gives a **recipe** — and it stops there.

```markdown
# billing-service

Top-level guidelines for this repo. Package-specific detail lives in each
package's own AGENTS.md (see `api/AGENTS.md`, `worker/AGENTS.md`).

## Entry points (use these; don't hand-roll)
- build:   `scripts/build.sh`
- test:    `scripts/test.sh`      — real Postgres, no mocks; hits the actual path
- release: `scripts/release.sh <version>`  — gates on tests + CHANGELOG, then publishes
- deploy:  `scripts/deploy.sh`    — health-gated; auto-rolls-back on a failed check

## Conventions
- **Secrets never go in env or config** — use the keychain path in `src/secrets/`.
- **The default branch is untouchable** — every change is a worktree + PR.

## Auth (source of truth: `src/auth/session.ts`)
- Session tokens are minted in `mintToken`. **A token is single-use — the server
  rejects a replayed token** (enforced: `src/auth/session.test.ts` "rejects replay").
- **`refreshToken` never widens scope** — the new token carries the old token's
  scopes exactly, never a superset (enforced: `session.test.ts` "scope is preserved").
  Why: a silent scope-widen on refresh was a past privilege-escalation bug.

### Adding a new OAuth provider
1. Add it to `PROVIDERS` in `src/auth/providers.ts`.
2. Implement `exchangeCode()` for it.
3. Add its scopes to `config/scopes.yaml`.
4. Add a test under `src/auth/__tests__/` that hits the real token endpoint.
```

## The five things a good entry has

1. **State the invariant as a declarative, not a narration.**
   - Good (from the example): *"A token is single-use — the server rejects a replayed
     token."* / *"`refreshToken` never widens scope."*
   - Weak: *"There is a function that handles token refresh."* (An agent gets that
     faster from `rg`.)
   - An invariant is what is ALWAYS true across all paths: what a function always
     sets / never overrides, cardinality ("one session → exactly one row"), two paths
     that converge ("both `createJob` and `createJobDetached` route through
     `resolveLaunch`"), fail-closed/fail-open behavior.

2. **Name the source of truth for every claim — file, ideally file:symbol.**
   - *"source of truth: `src/auth/session.ts`"*, and put the symbol (`mintToken`) in
     the line. This makes the fact **greppable** (an agent's `rg mintToken` now hits
     your doc) AND **verifiable in one jump** — the agent confirms and moves on
     instead of re-deriving.
   - Point to files **inside this repo** only. Never cite a path from another repo or
     your own machine — the agent reading this may be on a fresh clone with no access
     to it. If the truth lives elsewhere, name the concept, not a private path.

3. **Say WHY when the invariant is non-obvious.** *"`refreshToken` never widens scope —
   a silent scope-widen was a past privilege-escalation bug."* The rationale is what a
   grep can never recover; it's the highest-value thing you add.

4. **Dense tables for enumerable facts** — key types, methods, endpoints, permission
   matrices. Scannable, and each row is a checkable claim.

5. **"Adding a new X" recipes** — the ordered steps to extend a subsystem the right
   way (the OAuth-provider steps above). This is the normative layer that stops an
   agent from inventing a parallel path.

## Point to the operational entry points (top-level, high value)

The single most useful thing a root `AGENTS.md` can carry is **where the build,
test, release, and deploy scripts live** — the stable operational entry points an
agent needs and would otherwise hunt for. Document the *location and one-line
contract* of each (`scripts/release.sh <version>` — "gates on tests + CHANGELOG,
then publishes"). Do NOT document the volatile basics — which versions are pinned,
install steps, environment specifics — those change under you and an agent can read
them live. Location of the entry point = durable; current state behind it = not your
job.

## What NOT to write (each rots and none earns its tokens)

- **File-layout restated as principle.** "There are two session packages" is a map
  note, not guidance — and if you enshrine an accidental split as a design goal, agents
  preserve a hazard. Flag duplication as a **hazard to converge**, not a virtue.
- **Narration a grep answers faster.** If the entry has no invariant, no rationale, and
  no pointer the agent couldn't find in one `rg`, cut it.
- **Basics an agent can read live** — installed versions, install/setup steps, flag
  laundry lists, changelog. Those belong in `--help` / README / CHANGELOG.
- **Cross-repo or machine-local paths.** The reader may be on a fresh clone with no
  access. Point only inside this repo.
- **Anything you can't keep true.** A stale contract is worse than none — it corrupts an
  agent's review verdict or bug diagnosis. If you can't guarantee freshness, write the
  **pointer** ("resolution logic: `src/discover.ts`"), not the derived fact.

## Two tiers, two trust levels

Separate them; a mixed blob gets one (wrong) trust level.

| Tier | Example | Checkable vs code? | How to treat it |
|---|---|---|---|
| **Contract / invariant** | "a token is single-use" | yes | State as truth, cite the source-of-truth file:symbol, and — best — cite the enforcing test. |
| **Intent / principle / rationale** | "prefer one pipeline with adapters over N copies" | no | Mark as intent, human-owned. An agent applies it to new work; it doesn't verify against code. |

The staleness fix falls out of this: the contract tier points to code (and ideally a
test), so drift is catchable; the intent tier is explicitly not a fact to trust blindly.

## Scope: top-level guidelines, narrowed per package

- **Root `AGENTS.md` = top-level guidelines.** Repo map, the operational entry points
  (above), repo-wide policy/conventions, and pointers to package files — nothing
  package-specific and nothing deep.
- **Each package narrows down.** A repo with multiple packages gives each its own
  `AGENTS.md` carrying that package's contracts + how-to-extend, scoped to the files
  agents actually re-read. Don't fan out one per source file, and don't restate the
  root's guidelines — link up to them.
- **Document the surprising, skip the self-evident.** The right entries are the
  non-obvious guarantees agents keep re-deriving.
- **`AGENTS.md` is canonical; `CLAUDE.md`/`GEMINI.md` are symlinks.** Edit `AGENTS.md`
  only — a symlink target edited directly gets stomped on sync.

## The other half: pair it with a README, split by audience

> This section is the canonical statement of the rule. A repo that adopts it records
> only its own instance (which directories, and any local exception) in its root
> `AGENTS.md`, and points back here rather than restating the policy.

An `AGENTS.md` has a sibling. Write both, and keep them doing different jobs — a
single file trying to serve a human browsing the repo and an agent mid-task serves
neither, and it is why most directory docs read as a tutorial nobody finishes.

| File | Reader | Shape |
|---|---|---|
| `README.md` | a human, deciding what exists and which thing to use | a **catalog**: two lines of what-this-is, then a table of every item with a one-line description linked to its source |
| `AGENTS.md` | an agent, mid-task, about to change something here | a **contract**: the invariants, the file format, what breaks if you get it wrong |

The test for the README: can a reader see everything available and pick one, in ten
seconds, without scrolling? If it explains *how the system works* instead of listing
*what is in it*, it has drifted into being the AGENTS.md, badly.

### The highest-value thing in the AGENTS.md: a what-must-stay-in-sync table

Most directory docs describe. The entry that actually prevents bugs is the one saying
**adding a file is not the whole change** — the second and third place that must be
updated, or the thing exists on disk and is invisible or dead:

```markdown
| Kind | Add | Also update |
|---|---|---|
| command | `commands/<name>.md` with `description:` frontmatter | the table in `commands/README.md` |
| hook | `hooks/<NN>-<name>.sh` **and** the `hooks:` entry in `agents.yaml` | the table in `hooks/README.md`; ship a `_test.sh` beside it |
| permission | a fragment in `permissions/groups/` | run `permissions/build.sh` to regenerate `default.yaml` |
```

Write the row for the sharpest edge first — the one where the file alone silently does
nothing. In the example above that is the hook: an unregistered script is dead code that
looks alive.

### When the pair is right, and when a README is wrong

The catalog shape earns its place in a **registry-shaped directory**: interchangeable
items of one kind, where the reader's question is "what is available and which do I
pick?" — `commands/`, `skills/`, `plugins/`, a rules directory, a chart library.

It is **wrong for an ordinary source directory**. `src/utils/` does not want a table of
its files; that list is `ls`, it rots on every commit, and it is the "file-layout
restated as principle" anti-pattern above. In a service repo, most directories want
neither file — only the packages an agent repeatedly re-reads get an `AGENTS.md`, and
the README stays at the root.

Do not generate this pair for every folder you touch. Ask first whether the directory is
a registry.

## Keeping it fresh (non-negotiable for the contract tier)

- **Update in the same PR as the behavior change.** A flag/command/contract change that
  leaves the doc describing the old behavior is a review-blocking defect. If the repo
  has an automated PR reviewer, make it enforce docs-in-sync.
- **Prefer contracts that a test enforces, and cite the test.** Then the invariant can't
  silently drift without CI going red.
- **Optional drift gate.** A tiny test that parses each `symbol — file` pointer in the
  doc and asserts the symbol still exists in that file turns a moved/renamed/deleted
  symbol into a red build. Cheap insurance for a file agents are meant to trust.

## Before you commit — the checklist

- [ ] Every entry states an invariant, a rationale, or a pointer an agent can't grep in one shot.
- [ ] Every claim names its source-of-truth file (or file:symbol), inside THIS repo, with the symbol in the line so `rg` finds it.
- [ ] The root lists where build/test/release/deploy scripts live — but not volatile basics (versions, install steps).
- [ ] Contracts are separated from intent; contracts cite code/tests.
- [ ] No cross-repo or machine-local paths, no flag dumps, no changelog, no file-layout-as-principle.
- [ ] Multi-package repo: each package has its own AGENTS.md that links up, not a restated copy.
- [ ] Edited `AGENTS.md` (not the `CLAUDE.md`/`GEMINI.md` symlink), in the same change as the behavior it documents.
- [ ] Registry-shaped directory: it has a README catalog too, listing every item, linked — and the AGENTS.md carries a what-must-stay-in-sync table. Ordinary source directory: no catalog README was invented for it.
