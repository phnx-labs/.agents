---
name: spec
description: "Write the durable source-of-truth specification for a capability so other agents and humans do not invent wrong behavior — describe how it actually behaves in plain language: what it is for, what it does, the sharp cases, and what must not change, grounded in the real code. Includes mock-ups for any UI/flow, blind-verified by a swarm. Not a change plan. Triggers on: 'swarm spec', '/swarm spec', 'specify this capability', 'source-of-truth spec', 'how does this behave', 'what does this guarantee'."
argument-hint: "[capability or system to specify]"
allowed-tools: Bash(agents teams*), Bash(agents run*), Bash(agents view*), Bash(rg*), Bash(fd*), Bash(ls*), Bash(git log*), Bash(git diff*), Read(*), Grep(*), Glob(*), Write(*), WebSearch(*), WebFetch(*)
user-invocable: true
---

# swarm:spec — write down how a capability actually behaves

> Read the `swarm:orchestrate` skill first for the fan-out mechanics (team creation, briefs, blinded verification, monitoring). This skill is the **spec mode**: reverse-engineer a source-of-truth description of how the real code behaves, **document the visual/flow shape with mock-ups when there is a UI**, then validate it against independent agents who describe the same capability blind and against the code's actual behavior.

You are specifying: **$ARGUMENTS**

**Why this exists:** a good spec is how other agents and people working on the same surface
avoid mistakes — inventing flags, UX, or error handling the code does not (or must not)
support. The deliverable is a plain-language description of *how the capability behaves*, not
a task list for a change.

This is a **behavioral spec, not a technical one.** It says what the thing does and how it
should behave from the user's intent. It does not prescribe how to implement or code it, and
it does not use requirement-contract grammar (no SHALL/SHOULD/MAY, no Given/When/Then
scenario blocks). Write it the way a sharp engineer describes a feature to a teammate: the
intent, how it behaves today, the sharp cases, and what must not change.

## spec vs plan — don't collapse them

| | `/swarm:plan` | `/swarm:spec` (this skill) |
|---|---|---|
| Question | What **delta** do we build next? | How does this capability **behave today**? |
| Shape | proposal + tasks + mock-ups | intent + behavior + sharp cases + mock-ups |
| Time | Forward | Present behavior |
| Audience | Builders of the change | Anyone who must not re-invent or break it |

If the user wants a plan for a change, hand them to `/swarm:plan`. This command answers
*"how does this capability actually behave?"* and writes it down so a future change
(and future agents) can diff against it.

## 1. Scope the capability (read, don't guess)

Read `AGENTS.md` / `CLAUDE.md` if present. Name the capability's boundary precisely — its entry points, the surface it exposes, and where it ends. Grep for the feature's keywords, then **read** the files that own the behavior. Use `Agent(subagent_type: "Explore")` for breadth; read the load-bearing files yourself. You cannot specify what you have not read.

## 2. Reverse-engineer from reality — spec what the code does, not what you wish it did

A spec grounded in memory is fiction. Trace each behavior end to end and anchor every claim to a **file:line** where the code actually does it. Where the code's behavior is ambiguous or contradicts the obvious intent, that ambiguity is a finding — record it, do not smooth it over (no fallbacks, no wishful behavior). If the capability must conform to an external contract — a protocol, an API, a standard, a spec'd wire format — **WebSearch with the current year**, `WebFetch` the authoritative source, and cite it; the behavior inherits its authority from that source, not your weights.

## 3. Mock-ups for any UI / multi-step surface (load-bearing)

A pure-behavior backend may skip this with an explicit `no UI surface` line. **Any
capability with screens, CLI interactive flows, dashboards, dialogs, or multi-step
journeys must document the visual/flow shape** so a later agent does not invent a
different UX while "following the spec."

Include in the spec (or a sibling `mockups.md` linked from the top):

1. **Canonical user flow** — happy path plus the failure paths the code actually handles.
2. **ASCII mock-ups** of every distinct state the user can land in (empty, loading,
   error, success) — labels and primary actions matching the real product voice.
3. **State transitions** that matter (what click/command moves which state) when non-obvious.

These mock-ups are part of the spec, not decoration. Behavior that refers to UI
should point at a mock-up state by name.

## 4. Write the spec in plain language

Write it the way the owner describes a feature. Six parts, in order:

```markdown
# <Capability> Specification

## What this is & why
<one paragraph: what this capability is for, and the boundary of what it covers>

## How it behaves today
<plain behavior, not code-level. Describe what happens, in order, for the main path.>

## What it does — the behavior and the sharp cases
- When <situation>, it <observable behavior>.
- The sharp / edge cases as `input -> outcome` lines, edges first:
  - <input / precondition> -> <observable outcome>
  - empty / error / concurrent / boundary -> <what actually happens>

## What must NOT change / out of scope
- <the explicit "don't touch this" list — the parts that are correct and load-bearing>
- <what this spec deliberately does not cover>

## Mock-ups
<section 3 output, or `no UI surface`>

## Evidence
<file:line anchors for the behavior claimed above>
```

Rules that keep a spec honest and useful:
- **Behavior, not implementation.** "When the token is expired it returns 401 and the
  user sees *Session expired*", never "it calls `verifyJwt()`".
- **Name the sharp cases as `input -> outcome`.** One line each, edges first (empty, error,
  concurrent, boundary). That is where a spec earns its keep, and it reads far cleaner than a
  scenario-grammar block.
- **Say what must not change.** The parts that are correct and load-bearing get an explicit
  "don't touch this" — that is what stops the next agent from breaking them.
- **Ground every claim in file:line.** A behavior you cannot point at in the code is a guess;
  mark it as unverified rather than asserting it.

## 5. Verify — the swarm describes it blind, and checks it against the code

Fan out via `agents teams` (mechanics in `swarm:orchestrate`). Check who's signed in (`agents teams doctor` / `agents view --json`), then run **two kinds of verification**, sized by judgment (more agents for a wide or load-bearing capability):

**a. Blind independent descriptions** — spawn 1–2 agents on **different** providers than yourself (`--mode plan`, read-only). Give each the capability boundary and the key files, but **NOT your draft**. Ask each to independently describe how the capability behaves from the code alone. Divergence is the signal:
- Behavior they described that you missed → a real gap in your spec.
- Behavior you wrote that they contradict → one of you misread the code; go re-read the file:line and resolve it.
- Different sharp cases for the same behavior → it is under-specified; the union is the truth.

**b. Spec-vs-code check** — take your drafted behavior and have a verifier confirm each line against actual code behavior at the cited file:line (`--mode plan`). Behavior the code does **not** actually do is either a bug in the code or a wrong line in your spec — surface it, never quietly rewrite the spec to match a buggy implementation. (Blinded verification per `swarm:orchestrate`: hand the claim and the file, not your confidence.)

## Output

### Capability
One sentence. What is being specified, and where its boundary sits.

### Spec (`spec.md`)
The full spec in the plain-language shape above — What this is & why, How it behaves today, the behavior and sharp cases, What must NOT change, mock-ups, and file:line evidence. Write it to a sensible path (`spec.md` beside the code it describes, or a `docs/` location the repo already uses) and say where. Every behavior claim carries a file:line anchor.

### Mock-ups
Section 3 output (or `no UI surface`). Every UI-facing line names the mock-up state it refers to.

### Research
External contracts the spec inherits authority from — each with a source URL (and year). State-of-the-world claims live here, verified — not in your memory.

### Verification
The independent descriptions the swarm produced. Where they converged (high-confidence behavior), where they diverged (the real ambiguities — each side cited to its teammate + file:line), and how you resolved each. Then the findings from the spec-vs-code check: the claim, the cited file:line, and whether the gap is a code bug or a spec correction.

### Coverage gaps & ambiguities
Behavior you could not pin down from the code, things that are genuinely unspecified, and any place two code paths disagree. Naming the gap is the deliverable — do not invent behavior to paper over it.

### Relationship to change
If specifying this surfaced work to do, name it and point to `/swarm:plan` — this command specifies the *is*, plan proposes the *delta*. Don't blur into a task list here.

### Review artifact (HTML)
After the spec is written, author a Markdown source under `.agents/artifacts/yyyy-mm-dd/`,
render it to a self-contained HTML file with `artifacts-cli`, and open it on the machine
the user sits at — follow the **`artifacts`** skill for the LOOK (house structure,
product-brand theming, light/dark toggle, ≥1 hand-authored inline-SVG diagram — a
behavior map or a spec-vs-code table reads well as SVG) and the `/plan`
command's Step 9 for the open-on-Mac transport, using the injected **Host & Fleet**
context to pick and reach the browser host. Don't duplicate the recipe; reuse it.

## Constraints

Behavior, not implementation. No SHALL/SHOULD/MAY, no Given/When/Then blocks — plain language and `input -> outcome` sharp cases. No human-time estimates. No tasks or "we will" — that's `/swarm:plan`. No invented behavior to fill a gap; an honest "unspecified" beats a fabricated claim. Do exactly what was asked — specify the named capability, no scope creep into neighbors.
