---
name: build
description: "clify:build — reverse-engineer a web service into an installable, verified CLI. Triggers on: 'clify', 'turn this API into a CLI', 'make a CLI for <service>', 'wrap this web app as a command-line tool', 'generate a CLI from these API docs / this HAR', 'clify build <target>'. Climbs a discovery ladder, infers a command schema, emits a CLI (plus an optional MCP server), and verifies every command against the real endpoint before it ships."
argument-hint: "[target] [--mcp] [--lang=ts|py]"
allowed-tools: Bash(*), Read(*), Write(*), Edit(*), WebFetch(*), WebSearch(*), Task(*)
user-invocable: true
---

# clify:build — the API-to-CLI factory

Point clify at a web service; it leaves behind a **typed, installable CLI** that humans and
agents both invoke — no one has to drive the browser or re-guess the API next session. clify is
the *factory*, not the *hands*: a browser driver (agents browser, Vercel's agent-browser) drives a
live session and forgets it; clify manufactures a durable tool.

The scaffolder is trivial. clify's value is two disciplines the rest of this skill enforces:

1. **The escalation ladder** — climb rungs in order, only when the one above comes up short.
2. **The verification gate** — no command enters the CLI until it has hit the *real* endpoint and
   returned *real*, shape-checked output.

## The artifact you produce

- **Always:** a standalone, globally-installable CLI (`clify-<slug>`) with `--help`, subcommands,
  typed args, and credentials read from `agents secrets` (Keychain) — never hardcoded.
- **With `--mcp`:** additionally emit an MCP server from the *same* inferred schema and register it
  (`agents mcp add` / `mcporter config add`), so the two emitters never drift.
- **Language:** TypeScript by default (`--lang=ts`); `--lang=py` for a Python (typer) emit.

The end state is not "the package builds" — it is **the installed CLI runs a command and returns
real output you can quote**. That is the done-gate (core-hard-lines #1).

## The escalation ladder

Record, per endpoint, which rung produced it — brittleness must be visible in the manifest.

| Rung | Source | Cost / stability | Climb to the next rung when… |
| --- | --- | --- | --- |
| 1 | **Official docs / OpenAPI / GraphQL schema** | cheapest, most stable | no machine-readable spec, or it's incomplete |
| 2 | **Authed REST/GraphQL** with a real token/key | stable if the API is public | the capability is only reachable through the private web app |
| 3 | **HAR capture** of the logged-in web app | brittle (private endpoints) | the call you need never appears in captured traffic |
| 4 | **Content-script injection** (`agents browser evaluate`) | most brittle, last resort | — |

## Pipeline

Run the stages in order. Each links a focused subprompt in this directory — read it when you enter
that stage.

### Stage 1 — Discover  → [`discover.md`](discover.md)
Resolve the target to a base URL and inventory its surface from the top of the ladder down: search
for official docs / an OpenAPI or GraphQL schema (WebSearch + WebFetch), then the developer portal,
then infer. Output: a candidate endpoint list with the rung each came from.

### Stage 2 — Authenticate & capture  → [`capture.md`](capture.md)
Establish auth the least-invasive way that works (API key → OAuth → logged-in browser session).
Persist every captured secret in an `agents secrets` bundle — **never** on disk or in the generated
code. For rungs 3–4, capture real traffic with `agents browser` and turn it into an endpoint catalog
via `lib/har_extract.py`.

### Stage 3 — Generate  → [`generate.md`](generate.md)
Infer a **command schema** (one object: resources → commands → typed params) from the discovered
endpoints. Scaffold the deterministic CLI wiring with `lib/scaffold-cli.sh`, then author one command
module per endpoint against that skeleton. If `--mcp`, emit the MCP server from the same schema.

### Stage 4 — Verify (the gate)  → [`verify.md`](verify.md)
For **every** generated command: invoke it against the real service with the stored credentials and
confirm a real, well-shaped response. A command that only 404s/401s/500s is **quarantined** — it does
not ship; it lands in the build `--report` tagged with its rung and the failure. Ship only the green set.

### Stage 5 — Package, install, prove
- Build and **install globally** (`npm i -g .` / the package's install path) — no `./bin/foo`
  (operational guardrail).
- Run the installed binary end-to-end and **quote the real output** in your report.
- If `--mcp`: register the server and confirm `mcporter list` shows its tools.
- Offer to open-source the generated CLI with the `oss` skill.

## Guardrails

- **Auth boundaries.** Only build against a service the user can legitimately authenticate to. If no
  legitimate auth path exists, stop and say so — do not brute-force, scrape past a paywall, or evade
  bot protection.
- **Secrets stay on-box.** Captured tokens/cookies live in `agents secrets` (Keychain) and are read at
  runtime by the generated CLI. Never write them into the CLI source, a `.env`, or a committed file;
  never transfer them off the machine.
- **No fabricated endpoints.** The gate is absolute — if you can't verify it against the real service,
  it does not ship. Report it as unverified; never guess-and-pray.
- **Tag brittleness.** Rung 3–4 endpoints are private-API-dependent and may break; the generated
  `--help` and the manifest must say so, so consumers know what's load-bearing.

## Helper scripts (`lib/`)

| Script | Does |
| --- | --- |
| `lib/env.sh` | Shared paths + `clify_*` shell helpers; source it first. |
| `lib/har_extract.py` | HAR → deduped endpoint catalog (path-templates ids, keeps a request/response sample per endpoint) so schemas can be inferred. |
| `lib/scaffold-cli.sh` | Lays down the deterministic TS CLI skeleton (bin wiring, secrets-backed http client, commander bootstrap). The agent authors per-endpoint commands into `src/commands/`. |

## Capture note (browser)

The richest capture is `agents browser har --with-bodies` (full request/response HAR). Until that
subcommand lands, use the shipping path: `agents browser requests --format har` for the request
inventory, then `agents browser responsebody <url>` per endpoint to fill in bodies. Feed either into
`lib/har_extract.py`.
