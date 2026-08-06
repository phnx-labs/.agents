# Plugins

A plugin bundles related commands and skills into one installable unit with its own
namespace. `/code:loop`, `/swarm:run`, and `/fleet:sync` all come from plugins.

The system layer ships the lightweight, no-paid-key plugins. Heavier or key-gated ones live
in the opt-in `.agents-extras` bundle instead, so the default install stays fast and works
anywhere with no setup.

## What ships here

| Plugin | Commands | What it's for |
|---|---|---|
| [`code`](./code/README.md) | 7 | The coding loop — `/code:loop`, `/code:verify`, `/code:review`, `/code:ship`, `/code:quality`, `/code:learn`, `/code:commit` |
| [`work`](./work/README.md) | 1 | Get a project's work done across the fleet, **any** kind — `/work:dispatch` routes ONE unit of work (coding *or* non-coding) to the plugin that owns it, using browser + secrets for real non-coding tasks |
| [`swarm`](./swarm/README.md) | 6 | Fan a task across parallel agents, then synthesize — `/swarm:run`, `/swarm:plan`, `/swarm:spec`, `/swarm:debug`, `/swarm:test`, `/swarm:qa` |
| [`fleet`](./fleet/README.md) | 3 | Fleet-wide ops — `/fleet:sync` brings every device to latest, `/fleet:onboard` brings a bare box to parity, `/fleet:mint-auth` self-mints setup tokens |
| [`git`](./git/README.md) | 2 | Pure git plumbing — `/git:prune` removes merged branches and worktrees with data-loss guards, `/git:tag-release` cuts and pushes a release tag |
| [`share`](./share/README.md) | 2 | Publish agent-generated HTML to a link on your own Cloudflare R2 — `/share:public` (auto OG cover), `/share:private` (unlisted, expiring) |
| [`design`](./design/README.md) | 1 | One keyless, offline-first front door for design — routes an intent to a mode and renders self-contained HTML/SVG |
| [`self`](./self/README.md) | 1 | Agent self-operations — `/self:close` cleanly self-terminates the session (guarded SIGTERM to the harness); the exit primitive `/done` builds on |

<p align="center">
  <img src="../.assets/share.png" alt="/share:public — one command turns any agent-generated HTML into a shareable link with an auto OG cover" width="82%">
</p>

## Layout

```
plugins/<name>/
  README.md      # what this plugin is, and its commands
  commands/      # <name>:<command>.md — the namespaced slash commands
  skills/        # skills the plugin's commands load
```

Each plugin's own `README.md` lists its commands in detail.

## Installing and disabling

Plugins here are registered in
[`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) and materialized into
every installed agent version on `agents sync`. To add a bundle from elsewhere:

```bash
agents repo add gh:phnx-labs/.agents-extras   # heavier, key-gated workflows
agents repo list
agents repo disable extras                     # turn off without deleting
```

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
