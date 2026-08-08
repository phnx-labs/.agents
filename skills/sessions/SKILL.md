---
name: sessions
description: "Search, browse, read, and move agent conversation transcripts across Claude, Codex, Gemini, and OpenCode. Use this skill to find previous sessions, recover context, inspect what agents have done, or export/import sessions as portable bundles over the SSH fleet."
argument-hint: "[search query or session ID]"
allowed-tools: Bash(agents sessions*)
user-invocable: true
---

# Sessions Skill

Search and browse agent conversation transcripts. This skill teaches you how to use the `agents sessions` CLI effectively.

## Basic Usage

```bash
# Interactive picker: browse and search recent sessions
agents sessions

# List sessions from current project
agents sessions | head -20

# Search sessions by text
agents sessions "add auth middleware"

# Filter by project across all directories
agents sessions --project agents-cli --all
```

## Resume & Fork (session lifecycle)

`agents sessions resume` and `agents sessions fork` are the canonical lifecycle path —
the `sessions` plugin skills drive them: `/continue` and `/recover` → `sessions:continue`,
`/restore` → `sessions:restore`, `/fork` → `sessions:fork`. Prefer those skills
over hand-rolling resume flags.

```bash
# Resume — reopen the SAME conversation by canonical id (from any device)
agents sessions resume 019fd114                 # reopen one, full context
agents sessions resume 019fd114 --host zion     # scope identity to the owning device
agents sessions resume                          # picker: multi-select into tabs/splits

# Fork — copy a session under a NEW id so the two diverge (original untouched)
agents sessions fork 4f3a9c21                    # prints: Forked <src> -> <new-id>
agents sessions fork 4f3a9c21 --name "try redis" # label the branch
agents sessions resume <new-id>                  # then continue the fork
```

- **resume vs fork:** `resume` continues the *same* thread; `fork` copies it under a new id so the two branches diverge without touching the original. Fork is a file copy of the transcript — no re-run, no tokens; the new session carries full context natively.
- **Resume a remote session on its owning device** — pass `--host <machine>` so identity resolves on the box that owns the session instead of being masked as an unknown command locally.
- **Native fork supports claude today.** For other harnesses, branch by starting a fresh agent and seeding it with `/continue <id>` — the source stays put.

## Filters

| Filter | Example | Description |
|--------|---------|-------------|
| `--agent` | `--agent claude` | Filter by agent type |
| `--all` | `--all` | Include sessions from every directory |
| `--project` | `--project myapp` | Filter by project name |
| `--since` | `--since 2h` | Only sessions newer than this |
| `--until` | `--until 2026-01-01` | Only sessions older than this |
| `--limit` | `--limit 10` | Maximum sessions to return |
| `--active` | `--active` | Only currently running sessions |
| `--working` | `--working` | Live sessions actively doing work |
| `--idle` | `--idle` | Live sessions stopped between turns |
| `--waiting` | `--waiting` | Live sessions waiting on the user |
| `--orphan` | `--orphan` | Live agents whose terminal client disappeared |
| `--crashed` | `--crashed` | Sessions whose terminal and process disappeared uncleanly |
| `--teams` | `--teams` | Include team-spawned sessions |

Every live-state flag implies `--active`. The remaining lifecycle filters are
`--closed`, `--abandoned`, `--queued`, and `--unknown`; `--orphaned` is
accepted as an alias of `--orphan`. Several status flags form a union.
`--working` is narrower than `--active`: it excludes idle, waiting, and
lifecycle-failure rows.

The interactive listing and live-state filters already fold in every registered
online device. Use `--local` to opt out. Non-interactive historical queries
stay local unless given `--host`/`--device`. `--all` does not control
devices; it widens historical directory and time scope.

## Reading Sessions

```bash
# Render session as markdown
agents sessions --markdown <session-id>

# Output as JSON
agents sessions --json <session-id>

# Include only specific roles
agents sessions --markdown --include user,assistant <session-id>

# Show only first/last N turns
agents sessions --markdown --last 10 <session-id>
```

## Artifacts

```bash
# List all files written or edited during a session
agents sessions --artifacts <session-id>

# Read a specific artifact
agents sessions --artifact <filename> <session-id>
```

## Export & Import (portable recall over the fleet)

Bundle sessions into a portable archive and restore them on another machine — recall that travels over the SSH fleet without depending on cloud sync.

```bash
# Export sessions into a portable bundle (by id, query, or the same
# selection flags as the picker — --since / -a / --project …)
agents sessions export <id...> -o bundle.tar
agents sessions export --since 1d -a -o today.tar     # everything from the last day
agents sessions export <id> --stdout | ...            # pipe straight into an import
agents sessions export <id> -o secure.tar --encrypt   # seal each transcript body (AES-256-GCM)

# Import a bundle into the local store, deduping against what you already have
agents sessions import bundle.tar                 # keep local on conflict (default)
agents sessions import bundle.tar --dry-run       # show what would land, write nothing
agents sessions import bundle.tar --overwrite     # replace local files that differ
agents sessions import secure.tar --decrypt       # key optional if the r2.backups sync key is set

# Pull sessions live from a remote peer over SSH — no file, no cloud
agents sessions import --from-host yosemite-s0
agents sessions import --from-host yosemite-s0 --from-host mac-mini   # repeatable
```

- Export **redacts secrets** from transcript bodies before writing the bundle; `--encrypt` additionally seals each body.
- Import is **dedup-aware** — a session already present locally is skipped (or replaced only with `--overwrite`); use `--dry-run` first to preview.
- `--from-host` is the SSH-first path: it bundles on the peer and streams it back, so cross-machine recall works without R2 sync configured.

## Live Tailing

```bash
# Live-tail a session file (Claude and Codex only)
agents sessions tail <session-id>
# Press Ctrl+C to stop

# Or the unified viewer: resolves a session id OR a host-dispatch run (from
# `agents run --host`), and -f follows either
agents logs <id>          # show the transcript / run log
agents logs <id> -f       # follow a live one
```

## Tips

- Use `--active` for the full live roster, or a direct status flag such as `--working`, `--idle`, `--orphan`, or `--crashed`
- Use `--teams` to see what team-spawned agents are doing
- Use `--since 1h` for recent activity
- Combine filters: `agents sessions --project myapp --since 1d --agent claude`
