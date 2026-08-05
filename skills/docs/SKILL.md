---
name: docs
description: "Write documentation — user-facing, technical, runbooks, onboarding, changelogs. Less is more: only document what code can't tell you."
user-invocable: true
---

# Documentation

Less is more. Agents and humans can gather context on the fly. Only document what's hard to see from code:

- **Architecture** — Component relationships, data flow, system boundaries
- **Why** — Decisions, constraints, tradeoffs (not what)
- **Operations** — Procedures that require specific steps
- **User interfaces** — Public APIs, CLIs, tools

## Routing Table

| Task | Subskill | When to Use |
|---|---|---|
| User-facing (CLI, API, tools) | `write-user.md` | Public interfaces, README, guides |
| Internal technical | `write-technical.md` | Architecture docs, system design |
| Runbooks | `write-runbook.md` | Operational procedures, troubleshooting |
| Onboarding | `write-onboarding.md` | New contributor guide |
| Changelogs | `write-changelog.md` | Release notes |
| For an agent, not a human | `write-agents-md.md` | `AGENTS.md` / `CLAUDE.md` / `GEMINI.md`, and the README that pairs with one |

Documenting a **directory** rather than a system? Use `write-agents-md.md` — it owns both
halves of the pair (`README.md` = the human catalog, `AGENTS.md` = the agent's contract)
and the rule for when a directory wants neither.

## Core Principles

**1. Don't document what code tells you.**
If someone can read the function and understand it, don't write docs. Comments rot. Code is truth.

**2. Architecture over implementation.**
Document component boundaries, data flow, integration points. Not how functions work internally.

**3. High-level, like a principal engineer.**
Write for someone who understands systems but doesn't know THIS system. Skip basics.

**4. Visuals over prose.**
One visual replaces paragraphs. Prefer hand-authored inline SVG or ASCII for
diagrams; Mermaid only when the target renderer supports it. No mandated chart kit.

**5. Reference the code, don't duplicate it.**
`See src/agent/execution.go:306-500` beats copying code into docs.

## Decision Tree

```
Need documentation?
├── Public interface (CLI, API)? → write-user.md
├── System architecture? → write-technical.md
├── Operational procedure? → write-runbook.md
├── New contributor setup? → write-onboarding.md
├── Release notes? → write-changelog.md
├── AGENTS.md / directory docs for agents? → write-agents-md.md
└── Implementation details? → DON'T DOCUMENT. Code is the doc.
```
