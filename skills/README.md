# Skills

> Layered with `~/.agents/skills/`. Same name in your user repo wins; everything else unions in.

Skills give agents domain expertise they can load on demand. Each skill is a directory with a `SKILL.md` file containing instructions, workflows, and context for a specific capability.

## How Skills Work

When you invoke a skill (e.g., `/browser`) or when an agent detects relevant context (e.g., you ask to generate an image), the skill's instructions load into the agent's context. Skills can include:

- **Instructions** in `SKILL.md` - the core knowledge
- **Scripts** (`.sh` files) - automations the skill can invoke
- **References** - example content, datasets, style guides

Skills differ from commands: a command is a one-shot prompt expansion, while a skill stays loaded and provides ongoing capability.

## Environment Injection

Skills often need machine-specific values (hostnames, paths, credentials). We solve this with environment injection:

```markdown
## Environment

!`${CLAUDE_SKILL_DIR}/env.sh block`
```

The `!` syntax executes the script and injects its output into the skill at load time. The `env.sh` script sources `~/.agents/.environment` (gitignored) and prints the resolved values.

**Why this matters for sharing:** You can publish skills publicly without exposing sensitive data. Each machine has its own `.environment` file with local values. The skill references variables; the environment provides values.

Example `.environment`:
```bash
BROWSER_SSH_USER=myuser
BROWSER_SSH_HOST=my-server.local
API_KEY_REF=keychain:my-api-key
```

Example `env.sh`:
```bash
source ~/.agents/.environment 2>/dev/null
USER="${BROWSER_SSH_USER:-default}"
HOST="${BROWSER_SSH_HOST:-localhost}"
echo "SSH target: ${USER}@${HOST}"
```

## Creating Skills

A minimal skill:

```
skills/my-skill/
  SKILL.md     # Required
```

The `SKILL.md` frontmatter:

```yaml
---
name: my-skill
description: "One line - when should Claude load this?"
allowed-tools: Bash(pattern*)   # Optional: tools this skill can use
user-invocable: true            # Can user type /my-skill?
---
```

Keep skills focused. One capability per skill. A "do everything" skill is less effective than three focused ones.

## Learning from Others

The agent skills ecosystem is evolving fast. Some notable collections:

- **[gstack](https://github.com/garrytan/gstack)** - Garry Tan's opinionated setup with persona-based skills (CEO review, design review, QA). Notable for its "forcing function" patterns that surface hidden assumptions.
- **[awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code)** - Curated list of skill repositories, hooks, and orchestrators
- **[Trail of Bits Security Skills](https://github.com/trailofbits)** - Professional security-focused skills for static analysis and code review

Key patterns emerging in the community:

1. **Persona-based skills** - Each skill embodies a specialist role (security officer, QA lead, design reviewer)
2. **Pipeline chaining** - Skills write artifacts that downstream skills consume
3. **Forcing functions** - Skills that surface assumptions through structured questions
4. **Risk budgets** - Limiting how much a skill can change in one pass

## Challenges with Sharing Skills

When publishing skills, watch for:

1. **Embedded credentials** - API keys, hostnames, paths hardcoded in SKILL.md
2. **Machine-specific assumptions** - Paths like `/Users/yourname/` or `~/my-project`
3. **Implicit dependencies** - Scripts that assume certain CLIs are installed

The environment injection pattern solves (1) and (2). For (3), document dependencies in SKILL.md or add setup scripts.

## Skills in This Repo

Each subdirectory is a self-contained skill with its own `SKILL.md`. Invoke with `/skill-name` or let the agent auto-detect from context.

| Skill | What It Does |
|-------|-------------|
| `agents-cli/` | Manage AI coding agent CLIs. Install versions, sync configs, switch between agents, manage MCP servers. |
| `browser/` | Drive a browser to automate websites — uses the built-in `agents browser` command with per-agent profile isolation over CDP. |
| `cloud/` | Dispatch agent tasks to the cloud — Rush Cloud (GitHub repo + branch, auto-opens a PR), Codex Cloud (pre-built env), and Factory pods. Run, list, status, logs, message, cancel. |
| `computer/` | Drive native macOS apps — screenshot, click, type, drag via the `agents computer` Accessibility daemon. Covers AX-opaque surfaces (VMs, canvas editors) with coordinate mode. |
| `dither-kit/` | Default charting library for agent-authored data visualizations: Dither Kit canvas charts for HTML, React, dashboards, reports, plans, and blog visuals. |
| `docs/` | Write documentation — user-facing, technical, runbooks, onboarding, changelogs. Less is more: only document what code can't tell you. |
| `git-workflow/` | Run PR-bound work in an isolated worktree — create the branch from the real default branch, work end-to-end inside it, open the PR, clean up after merge. Backs the always-on truly-agentic-git-workflow rule. |
| `learn/` | Two modes. **Reflection** (default): reflect on a finished session and write durable lessons forward — recall what was used, distill only what generalizes (four gates against overfitting), route each to a skill / rule / memory / nothing, edit additively. **Target audit** (`/learn <skill\|plugin\|command\|workflow>`): mine every past session that used that target, surface the recurring problems as an HTML triage report (each framed expectation → what happened → why, anchored to the session that surfaced it, recency-weighted with a "maybe fixed" flag), then apply only the fixes the user approves. Discovers per-plugin learn skills. |
| `release/` | Publish packages to registries (npm, CDN, etc.). Discovers repo structure, runs tests, updates changelog, publishes, and tags. Supports monorepos and semver. |
| `routines/` | Schedule agents to run on a cron schedule or one-shot at a specific time. The scheduler auto-starts on first add. |
| `monitors/` | Durable event-triggered watchers — watch a source (command / HTTP / file / fleet device / webhook), detect a change, and fire an agent, a routine, or a notification. Routines fire on a clock; monitors fire on a change. The cross-agent layer. |
| `run/` | Execute a single agent headlessly or interactively — plan/edit/full modes, secrets injection, version pinning, fallback chains. |
| `secrets/` | Manage named bundles of environment variables backed by the OS keychain. Create bundles, add secrets, inject them into agent runs. |
| `sessions/` | Search, browse, and read prior agent conversation transcripts across Claude, Codex, Gemini, and OpenCode. |
| `teams/` | Organize AI coding agents into teams for parallel collaboration. Create, add, start, monitor, and collect results. |

## Further Reading

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Essential Claude Code Skills and Commands](https://batsov.com/articles/2026/03/11/essential-claude-code-skills-and-commands/)
- [A Practical Guide to AI Dotfiles](https://engineersmeetai.substack.com/p/a-practical-guide-to-ai-dotfiles)
