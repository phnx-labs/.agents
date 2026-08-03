# Skills

A skill is a capability an agent loads on demand — instructions plus, often, its own scripts
and reference files. Each skill is a directory containing a `SKILL.md`.

Invoke one directly (`/browser`), or let the agent load it when the work matches its
`description`. Layered with `~/.agents/skills/`: a same-named skill in your user repo wins,
everything else unions in.

**Skill or command?** A [command](../commands/README.md) is a one-shot prompt expansion. A
skill stays loaded and brings tooling with it.

## Fleet and machines

| Skill | What it does |
|---|---|
| [`agents-cli`](./agents-cli/SKILL.md) | Manage agent CLIs — add and pin versions, sync config, manage MCP servers |
| [`devices`](./devices/SKILL.md) | Register and connect to your machines over Tailscale SSH |
| [`run`](./run/SKILL.md) | Execute one agent headlessly or interactively — modes, secrets injection, version pinning, fallback chains |
| [`teams`](./teams/SKILL.md) | Organize agents into teams that work a shared task in parallel, each in its own worktree |
| [`sessions`](./sessions/SKILL.md) | Search, browse, read, and move agent transcripts across Claude, Codex, Gemini, and OpenCode |
| [`cloud`](./cloud/SKILL.md) | Dispatch agent tasks to Rush Cloud, Codex Cloud, or Factory pods |
| [`routines`](./routines/SKILL.md) | Schedule agents on a cron schedule or one-shot at a specific time |
| [`monitors`](./monitors/SKILL.md) | Durable event-triggered watchers — watch a source, fire an agent, routine, or notification on change |
| [`escalate`](./escalate/SKILL.md) | Reach the owner out-of-band when genuinely blocked, climbing message → watch → call |

`routines` fire on a clock; `monitors` fire on a change. Reach for `escalate` only after the
self-unblock ladder is exhausted.

## Acting on the real world

| Skill | What it does |
|---|---|
| [`browser`](./browser/SKILL.md) | Drive a browser — fill forms, click, screenshot, scrape — with per-agent profile isolation over CDP |
| [`computer`](./computer/SKILL.md) | Drive native macOS apps — screenshot windows, click, type, drag, read text |
| [`secrets`](./secrets/SKILL.md) | Keychain-backed bundles of environment variables, injected into a run without landing on disk |

## Engineering workflow

| Skill | What it does |
|---|---|
| [`git-workflow`](./git-workflow/SKILL.md) | Run PR-bound work in an isolated worktree instead of mutating the user's checkout |
| [`release`](./release/SKILL.md) | Publish to registries — discover repo structure, run tests, update the changelog, publish, tag |
| [`mq`](./mq/SKILL.md) | Structure-aware query for large files — extract one section instead of reading the whole file |
| [`learn`](./learn/SKILL.md) | Reflect on a finished session and write the durable lessons back into skills, rules, or memory |

## Producing output for humans

| Skill | What it does |
|---|---|
| [`plan-render`](./plan-render/SKILL.md) | Render an implementation plan as a self-contained, review-grade HTML doc, opened where the user sits |
| [`visualize`](./visualize/SKILL.md) | Turn a concept, dataset, or finding into one self-contained shareable HTML visualization |
| [`dither-kit`](./dither-kit/SKILL.md) | The default charting library for any agent-authored chart or data visualization |
| [`docs`](./docs/SKILL.md) | Write documentation — user-facing, technical, runbooks, onboarding, changelogs |
| [`agents-md`](./agents-md/SKILL.md) | Write the docs a *directory* carries — `AGENTS.md` (the agent's contract) and the `README.md` catalog that pairs with it |

Reach for `dither-kit` before hand-rolling SVG or pulling in Chart.js. `docs` writes
about a **system**; `agents-md` writes about a **directory**, for an agent that will
re-read the source anyway.

## Machine-specific values stay out of the skill

Skills that need a hostname, path, or credential read it at load time instead of hardcoding
it, so a skill can be published without leaking your setup:

```markdown
## Environment

!`${CLAUDE_SKILL_DIR}/env.sh block`
```

The `!` syntax runs the script and injects its output when the skill loads. `env.sh` sources
`~/.agents/.environment` (gitignored, one per machine) and prints the resolved values.

## Further reading

- [Claude Code skills documentation](https://code.claude.com/docs/en/skills)
- [gstack](https://github.com/garrytan/gstack) — persona-based skills and forcing-function patterns
- [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — curated skill and hook collections

---

Plugins ship their own skills under `plugins/<name>/skills/` — see
[`plugins/`](../plugins/README.md). Changing something here? Read [`AGENTS.md`](./AGENTS.md).
