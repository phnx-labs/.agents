# clify plugin

Turn any web service into an **installable, verified CLI** — for humans and agents.

clify is the *factory*, not the *hands*. A browser driver (`agents browser`, Vercel's
`agent-browser`) drives a live session and forgets it. clify manufactures a durable tool: point it at
a service, and it leaves behind a typed CLI so no one has to drive the browser or re-guess the API
next session.

## Command

| Command | Use when |
| --- | --- |
| `/clify <target> [--mcp] [--lang=ts\|py]` | You want a persistent CLI wrapping a web service — from official docs, an authed API, captured traffic, or (last resort) the private web-app API. Invokes `clify:build`. |

## What it produces

- **Always** — a globally-installable CLI (`clify-<slug>`) with `--help`, typed subcommands, and
  credentials read from `agents secrets` (Keychain), never hardcoded.
- **With `--mcp`** — additionally an MCP server emitted from the *same* schema and registered via
  `agents mcp add` / `mcporter config add`, so the CLI and MCP surfaces never drift.

## The two disciplines that make it worth having

1. **The escalation ladder** — climb in order, only on failure: official docs/OpenAPI → authed API →
   HAR capture → content-script injection. Each endpoint is tagged with the rung it came from, so
   brittleness is visible.
2. **The verification gate** — no command enters the CLI until it has hit the *real* endpoint and
   returned real, shape-checked output. Guessed endpoints are quarantined and reported, never shipped.

## Pipeline

`clify:build` runs five stages, each with a focused subprompt under `skills/build/`:

1. `discover.md` — resolve the target, inventory the surface top-of-ladder-down.
2. `capture.md` — authenticate least-invasively; capture traffic → endpoint catalog.
3. `generate.md` — infer a command schema; scaffold + author the CLI (and optional MCP).
4. `verify.md` — the gate: verify every command against the real service.
5. Package, install globally, and prove it by running the installed binary.

## Builds on (no duplication)

`agents browser` (capture), `agents secrets` (token persistence, Keychain), `mcporter` / `agents mcp`
(the `--mcp` emit), and the `oss` skill (open-sourcing a generated CLI).

## Helper scripts (`skills/build/lib/`)

- `env.sh` — shared paths + `clify_*` shell helpers.
- `har_extract.py` — HAR → deduped endpoint catalog (path-templates ids, keeps a sample per endpoint).
  Tested by `har_extract_test.py`.
- `scaffold-cli.sh` — the deterministic TS CLI skeleton (bin wiring, secrets-backed http client,
  commander bootstrap). Per-endpoint command modules are authored on top.

## Conventions

- Assumes `agents-cli` is installed and on PATH.
- Captured secrets stay on-box in `agents secrets`; they are never written into generated source or
  transferred off the machine.
- Only build against services the user can legitimately authenticate to.
