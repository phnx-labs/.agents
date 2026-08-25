---
name: insights
description: "Analyze how you and your agents work across harnesses — orchestrates agents insights, insights mix, perf, and sessions stats into one evidence-backed action list. No separate trends/perf slash commands. Triggers on: /insights, /sessions:insights, 'session insights', 'how have I been working', 'where do agents stall', 'skill dead weight', usage friction, harness mix."
argument-hint: "[--since 30d | --all] [--agent <harness>] [--project <name>] [--json] [--narrative]"
allowed-tools: Bash(agents insights*), Bash(agents perf*), Bash(agents sessions*), Bash(agents cost*), Bash(agents output*), Bash(jq *), Bash(ls *), Read(*), Write(*), Task(*)
user-invocable: true
---

# sessions:insights

You are the **conductor** over the local analytics engines. There is no separate
`/trends` or `/perf` plugin command — mix lives under `agents insights mix`. This skill
decides which engines to run, stitches their output, and returns a short list of
**evidence-backed actions**.

Never upload raw transcripts. Everything below stays on-machine unless the user
explicitly asked for a shareable HTML artifact.

## Engines (orchestrate; do not invent a parallel pipeline)

| Engine | CLI | Answers |
|---|---|---|
| **How you work** | `agents insights` | Tools, friction, rhythm; default group-by account (Claude attribution; other harnesses under `unattributed:<agent>`) |
| **Usage mix** | `agents insights mix` | Harness/model mix, token ratios, session volume, secrets-hot, browser activity |
| **Latency / friction** | `agents perf` | Slow hooks/commands/runs; `agents perf friction` for guard-block loops |
| **Resource dead weight** | `agents sessions stats` | Explicit skill/command invocations; installed-but-never-invoked |

Related (only if the ask needs them; not the default path):

- `agents cost` — what it cost
- `agents output` — what shipped
- `agents view` — live quota

If `$ARGUMENTS` already names one engine (`mix`, `perf`, `stats`, `insights` alone),
run that engine and still synthesize actions — do not dump a raw table as the whole
answer.

## Default recipe

Forward user flags (`--since`, `--agent`, `--project`, `--json`, `--narrative`, …) to the
engines that accept them. Defaults when unset: **last 30 days**, all harnesses in scope.

Run in parallel when the shell allows:

```bash
agents insights --since 30d --json
agents insights mix --days 30 --json    # or: agents insights harness-mix --json
agents perf --days 30 --json            # plus: agents perf friction --days 30 --json when relevant
agents sessions stats --since 30d --json
agents sessions stats --zero --since 30d --json   # dead weight
```

Adjust windows from `$ARGUMENTS` (`7d`, `90d`, `--all`). Prefer `--json` for the agent
pass; render a human table yourself. Use `--narrative` on `agents insights` only when the
user explicitly wants coaching prose from aggregate counts.

**First-run / low coverage:**

- `agents insights` caches facets; `--refresh` only if numbers look stale.
- `agents sessions stats` may need `agents sessions backfill resources` once when coverage
  is low — run it, then re-query; say so in the recap.

## What to return

Lead with **actions**, not a dashboard dump. Each action needs a quoted signal (a number,
a top row, a friction label) from the CLI output — no paraphrase without evidence.

Shape:

1. **Window + scope** — since, agents, projects actually queried.
2. **Top findings** (3–7 bullets) — each cites an engine + a concrete figure.
3. **Actions** (ranked) — what to change: drop a dead skill, fix a hot guard, rebalance
   harness mix, investigate a slow hook path, reclaim unused plugins.
4. **Gaps** — harnesses with no stats signal, missing backfill, unattributed buckets.

Skip vanity metrics. "13 minutes" not "12m 49s". If grandmother can't parse it, rewrite.

## Guardrails

- **Local only** by default. No shipping transcript bodies to a model or network path for
  this skill except the optional `agents insights --narrative` path the user opted into.
- **Explicit invocations only** for `sessions stats` — auto-loaded skills read as 0; say
  that when interpreting dead weight.
- **Do not invent** `agents sessions insights` unless `agents sessions insights --help`
  proves it exists on this install; the conductor is this skill, the engines are the four
  CLIs above.
- **Multi-harness:** run engines that accept `--agent` once per harness of interest when
  the user cares about parity; otherwise one pass with defaults and call out
  `unattributed:*` buckets.
