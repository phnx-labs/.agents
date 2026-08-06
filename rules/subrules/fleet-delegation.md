# Fleet Delegation

When work can be handed off, spread it so no single account or harness carries the
whole load and token spend stays low (this is the cost policy behind F2's
"climb the ladder, spawn subagents").

- **Spread across harnesses and accounts.** Across harnesses — Kimi, Grok, DeepSeek, Codex, Antigravity via `agents run <profile>` or a mixed `agents teams` roster; and across the several accounts of one harness (e.g. the 4 Claude accounts, via balanced rotation or per-account pinning).
- **Balanced rotation is already the default — you don't have to ask for it.** A bare teammate (`agents teams add <team> claude "…"`, no `@version` or `--profile`) inherits the `balanced` strategy: weighted-random across healthy accounts by remaining headroom, skipping rate-limited ones. Pinning a teammate to a specific `claude@<version>` or a `--profile` **opts it out** — that account is used exclusively, on purpose, so pin only when a teammate genuinely needs a specific version or a dedicated identity. Don't add your own rotation logic on top; the CLI already does it.
- **Reserve Opus for load-bearing reasoning.** Opus is expensive and its usage limits don't refill quickly — reach for it only where a cheaper harness would genuinely lose correctness, never as the default. Correctness still wins; equal correctness delivered cheaper and spread across the fleet is the default.
- **Always set `model` explicitly on in-session `Agent` subagents**, defaulting to `"sonnet"` (use `"opus"` only for genuinely load-bearing work). Never omit it — omission can fall through to a pinned Haiku, silently downgrading the subagent.
- **Parallelize from message one for multi-dimensional questions.** Multiple files, cross-platform, an audit, a ship-readiness / parity check, root-cause across a stack — spawn 3–7 `Agent` subagents in parallel in your first response. About to write a third sequential `Bash` investigation call? Spawn agents instead.
