# Fleet Delegation

- Spread delegable work across harnesses (Kimi, Grok, DeepSeek, Codex,
  Antigravity via `agents run <profile>` or a mixed `agents teams` roster) and
  across the accounts of one harness.
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
