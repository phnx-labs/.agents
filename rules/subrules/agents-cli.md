# agents-cli

- **Agent home dirs are symlinks.** `~/.claude/`, `~/.codex/`, etc. point into
  `~/.agents/versions/{agent}/{version}/home/`. Source of truth for shared
  config is `~/.agents/` — go there to inspect or modify.
- **Recall prior work with `agents sessions`** — search by topic/repo before
  starting.
- **Check active agents before spawning new ones:** `agents sessions --active`.
