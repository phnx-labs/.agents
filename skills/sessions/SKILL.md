---
name: sessions
description: "Search, browse, read, and move agent conversation transcripts across Claude, Codex, Gemini, and OpenCode. Use this skill to find previous sessions, recover context, inspect what agents have done, or export/import sessions as portable bundles over the SSH fleet."
argument-hint: "[search query or session ID]"
allowed-tools: Bash(sessions*)
user-invocable: true
---

# Sessions Skill

Search and browse agent conversation transcripts. This skill teaches you how to use the `sessions` CLI effectively.

## Basic Usage

```bash
# Interactive picker: browse and search recent sessions
sessions

# List sessions from current project (skip the TTY picker)
sessions --no-interactive | head -20

# Search sessions by text
sessions "add auth middleware"

# Filter by project across all directories
sessions --project agents-cli --all
```

## Resume & Fork (session lifecycle)

`agents run --resume` and `agents fork` are the canonical lifecycle path —
the `sessions` plugin skills drive them: `/continue` and `/recover` → `sessions:continue`,
`/fork` → `sessions:fork`. Prefer those skills over hand-rolling resume flags.

```bash
# Resume — reopen the SAME conversation by canonical id (from any device)
agents run --resume 019fd114                 # reopen one, full context
agents run --resume 019fd114 --device zion   # scope identity to the owning device
agents run --resume                          # picker: multi-select into tabs/splits
agents run claude --resume                      # same picker, filtered to Claude
agents run claude#work --resume                 # picker filtered to that Claude account

# Fork — copy a session under a NEW id so the two diverge (original untouched)
agents fork 4f3a9c21                    # prints: Forked <src> -> <new-id>
agents fork 4f3a9c21 --name "try redis" # label the branch
agents run --resume <new-id>                  # then continue the fork
```

- **resume vs fork:** `resume` continues the *same* thread; `fork` copies it under a new id so the two branches diverge without touching the original. Fork is a file copy of the transcript — no re-run, no tokens; the new session carries full context natively.
- **Resume a remote session on its owning device** — pass `--device <machine>` so identity resolves on the box that owns the session instead of being masked as an unknown command locally.
- **Native fork supports claude today.** For other harnesses, branch by starting a fresh agent and seeding it with `/continue <id>` — the source stays put.

Resume uses the conversation's account and native context with the installed
harness binary. A recorded vendor version is provenance, not an account selector.
Keep the saved model, mode and working directory unless the user overrides them.
If the CLI cannot prove readable native context, inspect its reason; never bypass
that refusal by recreating the old UUID. Context replay starts a new conversation
and requires an explicit choice. A model-specific limit is not evidence that every
model on the account is unavailable.

## Filters

Historical search (the `sessions` CLI). `sessions --active` and the old status
flags exit 2; the live roster is `agents ps`.

| Filter | Example | Description |
|--------|---------|-------------|
| `--agent` | `--agent claude` | Filter by agent type |
| `--all` | `--all` | Include sessions from every directory |
| `--project` | `--project myapp` | Filter by project name |
| `--since` | `--since 2h` | Only sessions newer than this |
| `--until` | `--until 2026-01-01` | Only sessions older than this |
| `--limit` | `--limit 10` | Maximum sessions to return |
| `--teams` | `--teams` | Include team-spawned sessions |
| `--host` / `--device` | `--device zion` | Read another machine's index over SSH |

Live roster (`agents ps`). Status flags take `--status <state>`:

| Command | Description |
|--------|-------------|
| `agents ps` | Currently running sessions (fleet-wide) |
| `agents ps --status working` | Actively producing work |
| `agents ps --status idle` | Stopped between turns |
| `agents ps --status waiting` | Waiting on the user |
| `agents ps --status orphaned` | Agent outlived its terminal client |
| `agents ps --status crashed` | Terminal and process disappeared uncleanly |
| `agents ps --json --local` | This machine only, machine-readable |

`--all` widens historical directory and time scope. It does not control devices.

## Reading Sessions

```bash
# Render session as markdown
sessions --markdown <session-id>

# Output as JSON
sessions --json <session-id>

# Include only specific roles
sessions --markdown --include user,assistant <session-id>

# Show only first/last N turns
sessions --markdown --last 10 <session-id>
```

## Artifacts

```bash
# List all files written or edited during a session
sessions artifacts <session-id>

# Read a specific artifact
sessions artifacts <session-id> <filename>
```

## Sharing a session with a human

When someone asks you to send them a session, publish it as a link instead of pasting
the transcript or handing over a `.jsonl` path:

```bash
sessions share <id>                   # → https://share.agents-cli.sh/<you>/session-<shortid>
sessions share <id> --reasoning fold  # keep the reasoning in collapsible sections
sessions share <id> --expire 7d       # auto-expire window (30d, 12h, or a date)
```

It renders the same redacted document `sessions render` writes, wraps it in a
self-contained page, and publishes it to your share endpoint. The slug is
`session-<shortid>`, so re-sharing one session updates one URL and keeps the prior page
as a revision (`artifacts share revisions <slug>`). One session per link.

- **Unlisted by default** — kept out of your public gallery and out of `artifacts
  share list`.
- **Unlisted is not access control.** R2 reads are public: anyone with the exact URL reads
  the page. Never describe such a link as private, encrypted, or access-restricted.
- **Redacted** — credential-shaped values, known secret values, and local home paths, plus
  email masking the plain render does not do. `--no-redact` exists and must not be used on
  anything you publish.
- **Not an evidence mechanism.** This does not license attaching a transcript to a PR,
  issue, or ticket body — that still takes a **secret gist** on a private repo, or a
  `<host>:<path>` reference on a public one. See the `truly-agentic-git-workflow` rule.
- Needs a share endpoint: `artifacts share status` reports it, `artifacts share
  setup` provisions one.

## Export & Import (portable recall over the fleet)

Bundle sessions into a portable archive and restore them on another machine — recall that travels over the SSH fleet without depending on cloud sync.

```bash
# Export sessions into a portable bundle (by id, query, or the same
# selection flags as the picker — --since / -a / --project …)
sessions export <id...> -o bundle.tar
sessions export --since 1d -a -o today.tar     # everything from the last day
sessions export <id> --stdout | ...            # pipe straight into an import
sessions export <id> -o secure.tar --encrypt   # seal each transcript body (AES-256-GCM)

# Import a bundle into the local store, deduping against what you already have
sessions import bundle.tar                 # keep local on conflict (default)
sessions import bundle.tar --dry-run       # show what would land, write nothing
sessions import bundle.tar --overwrite     # replace local files that differ
sessions import secure.tar --decrypt       # key optional if the r2.backups sync key is set

# Pull sessions live from a remote peer over SSH — no file, no cloud
sessions import --from-host yosemite-s0
sessions import --from-host yosemite-s0 --from-host mac-mini   # repeatable
```

- Export **redacts secrets** from transcript bodies before writing the bundle; `--encrypt` additionally seals each body.
- Import is **dedup-aware** — a session already present locally is skipped (or replaced only with `--overwrite`); use `--dry-run` first to preview.
- `--from-host` is the SSH-first path: it bundles on the peer and streams it back, so cross-machine recall works without R2 sync configured.

## Live Tailing

```bash
# Live-tail a session file (Claude and Codex only) -- the standalone sessions CLI
sessions tail <session-id>
# Press Ctrl+C to stop

# Or the unified viewer: resolves a session id OR a device-dispatch run (from
# `agents run --device`), and -f follows either
agents logs <id>          # show the transcript / run log
agents logs <id> -f       # follow a live one
```

## Tips

- Use `agents ps` for the live roster, or `agents ps --status working` / `idle` / `orphaned` / `crashed`
- Use `--teams` to see what team-spawned agents are doing
- Use `--since 1h` for recent activity
- Combine filters: `sessions --project myapp --since 1d --agent claude`
- For a trajectory: `sessions trace <id>` (compact tool-call timeline)
