# Fleet Delegation

- Spread delegable work across harnesses (Kimi, Grok, DeepSeek, Codex,
  Antigravity via `agents run <profile>` or a mixed `agents teams` roster) and
  across the accounts of one harness. Mixed rosters are enforced, not advised:
  `parallel-teams`' bundled `teams-roster-guard` blocks a 3rd same-harness
  teammate on any multi-harness machine unless the brief carries a
  `single-harness: <reason>` token. Two facts you cannot derive: a profile
  forked from a host harness (`agents run <profile>`) diversifies the model,
  not the harness; and read-only verifier tracks need a harness whose headless
  `plan` mode is real — others silently downgrade `plan` to `auto`.
- Balanced rotation is already the default: a bare teammate (no `@version` or
  `--profile`) rotates across healthy accounts by remaining headroom. Pinning
  opts out — pin only when a teammate genuinely needs a specific version or
  identity. Don't add your own rotation logic on top.
- Reserve Opus for load-bearing reasoning. Equal correctness delivered cheaper
  and spread across the fleet is the default.
- Always set `model` explicitly on in-session `Agent` subagents — default
  `"sonnet"`, `"opus"` only for genuinely load-bearing work. Omission can fall
  through to a pinned Haiku.
- Parallelize from message one for multi-dimensional questions: spawn 3–7
  subagents in your first response. About to write a third sequential Bash
  investigation call? Spawn agents instead.
