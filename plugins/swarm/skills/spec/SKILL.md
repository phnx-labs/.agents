---
name: spec
description: "Write the durable source-of-truth specification for a capability so other agents and humans do not invent wrong behavior — reverse-engineer SHALL requirements + Given/When/Then from real code, include mock-ups for any UI/flow surface, blind-verify with a swarm, drift-check every requirement. Not a change plan. Triggers on: 'swarm spec', '/swarm spec', 'specify this capability', 'source-of-truth spec', 'what does this system guarantee', 'requirements with scenarios'."
argument-hint: "[capability or system to specify]"
allowed-tools: Bash(agents teams*), Bash(agents run*), Bash(agents view*), Bash(rg*), Bash(fd*), Bash(ls*), Bash(git log*), Bash(git diff*), Read(*), Grep(*), Glob(*), Write(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# swarm:spec — write the contract others must not break

> Read the `swarm:orchestrate` skill first for the fan-out mechanics (team creation, briefs, blinded verification, monitoring). This skill is the **spec mode**: reverse-engineer a source-of-truth specification from the real code, **document the visual/flow contract with mock-ups when there is a UI**, then validate it against independent agents who spec the same capability blind and against the code's actual behavior.

You are specifying: **$ARGUMENTS**

**Why this exists:** a good spec is how other agents and people working on the same surface
avoid mistakes — inventing flags, UX, or error handling the code does not (or must not)
support. The deliverable is documentation of *what is guaranteed*, not a task list for a
change.

Shape: the durable **source-of-truth spec** in the form [OpenSpec](https://openspec.dev/)
gives its `specs/` files: a `## Purpose` plus a `## Requirements` list, where every
requirement is a testable `### Requirement:` with an RFC 2119 keyword (SHALL / SHOULD /
MAY) and one or more `#### Scenario:` blocks in Given/When/Then form — plus **mock-ups**
for any user-visible surface.

## spec vs plan — don't collapse them

| | `/swarm:plan` | `/swarm:spec` (this skill) |
|---|---|---|
| Question | What **delta** do we build next? | What does this capability **already guarantee**? |
| Shape | proposal + tasks + mock-ups | Purpose + Requirements + scenarios + mock-ups |
| Time | Forward | Present contract |
| Audience | Builders of the change | Anyone who must not re-invent or break it |

If the user wants a plan for a change, hand them to `/swarm:plan`. This command answers
*"what does this capability actually guarantee?"* and writes it down so a future change
(and future agents) can diff against it.

## 1. Scope the capability (read, don't guess)

Read `AGENTS.md` / `CLAUDE.md` if present. Name the capability's boundary precisely — its entry points, the surface it exposes, and where it ends. Grep for the feature's keywords, then **read** the files that own the behavior. Use `Agent(subagent_type: "Explore")` for breadth; read the load-bearing files yourself. You cannot specify what you have not read.

## 2. Reverse-engineer from reality — spec what the code does, not what you wish it did

A spec grounded in memory is fiction. Trace each behavior end to end and anchor every requirement to a **file:line** where the code actually enforces it. Where the code's behavior is ambiguous or contradicts the obvious intent, that ambiguity is a finding — record it, do not smooth it over (no fallbacks, no wishful requirements). If the capability must conform to an external contract — a protocol, an API, a standard, a spec'd wire format — **WebSearch with the current year**, `WebFetch` the authoritative source, and cite it; the requirement inherits its authority from that source, not your weights.

## 3. Mock-ups for any UI / multi-step surface (load-bearing)

A pure-behavior backend may skip this with an explicit `no UI surface` line. **Any
capability with screens, CLI interactive flows, dashboards, dialogs, or multi-step
journeys must document the visual/flow contract** so a later agent does not invent a
different UX while "following the spec."

Include in the spec (or a sibling `mockups.md` linked from Purpose):

1. **Canonical user flow** — happy path + the failure paths the code actually handles.
2. **ASCII mock-ups** of every distinct state the user can land in (empty, loading,
   error, success) — labels and primary actions matching the real product voice.
3. **State transitions** that matter (what click/command moves which state) when non-obvious.

These mock-ups are part of the contract, not decoration. Requirements that refer to UI
should point at a mock-up state by name.

## 4. Draft the source-of-truth spec

Write it in the OpenSpec `specs/` shape. Every requirement observable and testable; every scenario a concrete Given/When/Then a test could assert directly.

```markdown
# <Capability> Specification

## Purpose
<one paragraph: what this capability is for and the boundary of what it covers>

## Requirements

### Requirement: <Name>
The system SHALL <observable behavior, one RFC 2119 keyword per requirement>.

#### Scenario: <name>
- GIVEN <precondition>
- WHEN <action or event>
- THEN <expected, observable outcome>
- AND <further outcome, if any>

### Requirement: <Name>
The system SHALL <...>.

#### Scenario: <name>
- GIVEN <...>
- WHEN <...>
- THEN <...>
```

Rules that keep a spec testable:
- **One requirement, one keyword.** Split "SHALL X and SHOULD Y" into two requirements.
- **Behavior, not implementation.** "SHALL return 401 on an expired token", never "SHALL call `verifyJwt()`".
- **Every requirement has ≥1 scenario.** A requirement with no scenario is a wish, not a spec.
- **Cover the edges, not just the happy path** — the error, the empty, the concurrent, the boundary. Those are where specs earn their keep.

## 5. Verify — the swarm specs it blind, and drift-checks it against the code

Fan out via `agents teams` (mechanics in `swarm:orchestrate`). Check who's signed in (`agents teams doctor` / `agents view --json`), then run **two kinds of verification**, sized by judgment (more agents for a wide or load-bearing capability):

**a. Blind independent specs** — spawn 1–2 agents on **different** providers than yourself (`--mode plan`, read-only). Give each the capability boundary and the key files, but **NOT your draft**. Ask each to independently reverse-engineer the requirements + scenarios for the same capability from the code alone. Divergence is the signal:
- A requirement they wrote that you missed → a real gap in your spec.
- A requirement you wrote that they contradict → one of you misread the code; go re-read the file:line and resolve it.
- Different scenarios for the same requirement → the requirement is under-specified; the union of scenarios is the truth.

**b. Spec-vs-code drift check** — take your drafted requirements and have a verifier confirm each one against actual code behavior at the cited file:line (`--mode plan`). A requirement the code does **not** satisfy is either a bug in the code or a wrong requirement in your spec — surface it as **drift**, never quietly rewrite the requirement to match a buggy implementation. (Blinded verification per `swarm:orchestrate`: hand the requirement and the file, not your confidence.)

## Output

### Capability
One sentence. What is being specified, and where its boundary sits.

### Spec (`spec.md`)
The full source-of-truth spec in the format above — `## Purpose`, `## Requirements`, each `### Requirement:` with its `#### Scenario:` blocks. If the repo has an `openspec/specs/` tree, write it to `openspec/specs/<capability>/spec.md`; otherwise write `spec.md` at a sensible path and say where. Every requirement carries a file:line anchor to where the code enforces it (in an inline note or a trailing "Evidence" line per requirement).

### Mock-ups
Section 3 output (or `no UI surface`). Every UI-facing requirement should name the mock-up state it refers to.

### Research
External contracts the spec inherits authority from — each with a source URL (and year). State-of-the-world claims live here, verified — not in your memory.

### Verification
The independent specs the swarm produced. Where they converged (high-confidence requirements), where they diverged (the real ambiguities — each side cited to its teammate + file:line), and how you resolved each. Then the **drift** findings from the spec-vs-code check: requirement, cited file:line, and whether the gap is a code bug or a spec correction.

### Coverage gaps & ambiguities
Requirements you could not pin down from the code, behaviors that are genuinely unspecified, and any place two code paths disagree. Naming the gap is the deliverable — do not invent a requirement to paper over it.

### Relationship to change
If specifying this surfaced work to do, name it and point to `/swarm:plan` — this command specifies the *is*, plan proposes the *delta*. Don't blur into a task list here.

### Review artifact (HTML)
After the spec is written, author a Markdown source under `.agents/artifacts/yyyy-mm-dd/`,
render it to a self-contained HTML file with `artifacts-cli`, and open it on the machine
the user sits at — follow the **`plan-render`** skill for the LOOK (house structure,
product-brand theming, light/dark toggle, ≥1 hand-authored inline-SVG diagram — a
requirements map or a spec-vs-code drift table reads well as SVG) and the `/plan`
command's Step 9 for the open-on-Mac transport, using the injected **Host & Fleet**
context to pick and reach the browser host. Don't duplicate the recipe; reuse it.

## Constraints

Behavior, not implementation. No human-time estimates. No tasks or "we will" — that's `/swarm:plan`. No invented requirements to fill a gap; an honest "unspecified" beats a fabricated SHALL. Do exactly what was asked — specify the named capability, no scope creep into neighbors.
