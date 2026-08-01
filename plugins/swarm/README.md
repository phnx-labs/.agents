# swarm plugin

Fan a task out across a team of parallel coding agents, then synthesize. The swarm runs on the **`agents teams` CLI** — the modern replacement for the deprecated Swarmify MCP (`@swarmify/agents-cli`, `mcp__Swarm__spawn`). Each command is a different *mode* of the same engine, and each invokes its **same-named skill**. `/swarm:run` is the generic mode; the rest are specializations of it.

## Commands

| Command | Use when |
| --- | --- |
| `/swarm:run` | The **generic** fan-out — any multi-agent task that doesn't fit a specialized mode. Decomposes an arbitrary goal into ≥2 independent tracks, spawns a mixed team, monitors to completion, and synthesizes. The front door to the shared engine; reach for a specialized command below when the task matches one. |
| `/swarm:plan` | Before building anything non-trivial. Reads the code, **researches the state of the world via web search**, drafts an **OpenSpec-grade change proposal** (`proposal.md` / `tasks.md` / delta spec), then has independent agents plan the same feature *blind* and reconciles where they diverge. |
| `/swarm:spec` | You need the durable **source-of-truth spec** of a capability — *what it guarantees*, not how to change it. Reverse-engineers requirements + Given/When/Then scenarios (OpenSpec `specs/` shape) from the **real code**, then has independent agents spec the same capability *blind* and **drift-checks every requirement against actual behavior**. The `is` to `/swarm:plan`'s `delta`. |
| `/swarm:debug` | A non-obvious bug where a wrong diagnosis is expensive. Traces the full data path (file:line at every hop), forms a root-cause hypothesis, then has verifiers on **different model providers**, blind to the hypothesis and **scaled to the bug** (1 for trivial, 3+ for gnarly), confirm it before any fix. |
| `/swarm:test` | A change wide enough that one agent can't hold every critical path. Splits the scope into areas, covers each in parallel, then synthesizes the cross-cutting tests that only appear across areas. |
| `/swarm:qa` | Behavioral QA of a *running* app. A smart orchestrator maps the QA surface, **provisions app instances on multiple ports**, and fans QA agents across them in **waves/innings** via `agents browser`, then ranks a ship/no-ship verdict with repro + evidence. |

The shared engine — provider discovery (`agents teams doctor` / `agents view --json`), judgment-based swarm sizing, boundary contracts, blinded verification, monitoring, synthesis — lives in the internal **`swarm:orchestrate`** skill (no command of its own), which every command reads first.

## Principles

- **`agents teams`, not Swarm MCP.** Run `agents teams --help` / `agents teams doctor` if unfamiliar. Disband teams when done.
- **Discover, then mix.** Probe which providers are installed and signed in (`agents teams doctor`, `agents view --json`), then mix across the available ones — diversity across claude/codex/gemini is the point, never three of one model "verifying" each other.
- **Size by judgment, not a table.** A capable orchestrator scales agent and verifier count to task complexity — wide for gnarly work, one for narrow.
- **Blinded verification.** When the swarm's job is to *check* a conclusion, withhold your hypothesis. Convergence, not confirmation.
- **`--mode plan` for read-only** (research, audit, verify, QA-observe); `--mode edit` only when a track changes code or writes bug reports.
- **Web-search first** for any state-of-the-world fact; fold citations into the brief.
- **Evidence or it didn't happen.** Every brief ends with `Return file:line quotes for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.`

## History

These shipped originally as `/swarm`, `/splan`, `/stest`, `/sdebug`, `/sclean`, `/srecap`, `/sconfirm` on the Swarmify MCP. When that MCP was deprecated the commands were folded into the base single-agent commands. This plugin brings the genuinely-multi-agent variants back as first-class `/swarm:*` commands on `agents teams` — the generic `/swarm:run` plus the specialized modes that earn their keep (plan, spec, debug, test, qa) with two upgrades: OpenSpec-grade planning and specification (`/swarm:plan` for the change delta, `/swarm:spec` for the source-of-truth requirements) and a hard web-search mandate.
