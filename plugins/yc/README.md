# yc plugin

Local recreations of YC startup products whose core value can be delivered by a
general-purpose agent plus focused skills and deterministic scripts. Each recipe replaces a
hosted product workflow where local data and agent judgment are enough; it does not imitate
branding or claim parity with integrations the local machine does not have.

The first recipe is WorkWeave-style engineering intelligence. It uses data agents-cli
already indexes, with no API key, hosted dashboard, or transcript upload.

## Commands

| Command | What it does |
| --- | --- |
| `/yc:workweave [--since 30d\|90d\|all]` | Refresh the current repository's local session index, compose the existing behavioral, output, cost, resource, hook, command, and friction analytics, and open a WorkWeave-style HTML report. |

## What the report measures

- Agent-session volume, duration, cost, model/harness mix, and activity over time.
- Current-window versus prior-window deltas for agent generation volume, cost, duration, and
  sessions, with empty baselines shown as unavailable rather than fabricated growth.
- Generated output versus token burn from sanitized project session metrics; shipped PR and
  commit attribution from `agents insights output` when the installed CLI exposes JSON.
- Repeated workflow friction and behavioral opportunities from `agents insights`.
- Explicit skill/command use and dead weight from `agents sessions stats`.
- Hook and CLI command latency, hook blocks, and retry loops from `agents perf`.

The report paginates through every indexed session for the repository as its census. It
persists only sanitized analytic fields—never session IDs, paths, accounts, machines, prompt
topics, or transcript bodies. Time-windowed
analytics default to 30 days so recent movement remains legible; pass `--since all` for
all-time rollups. Metrics that cannot currently carry repository identity (notably guard
friction) are visibly labeled fleet-wide.

The HTML opens with a visual dashboard and carries at least eight accessible figures across
activity, composition, efficiency, process, and opportunities. “Output” is reserved for
shipped-work evidence; agent-token charts are labeled generated tokens. Each run also captures
four real screenshots of the rendered report for desktop and mobile verification.

## Requirements

- `agents` with `sessions`, `insights`, and `perf`.
- `artifacts` for Markdown-to-HTML rendering.
- A browser reachable through `agents browser` to open and inspect the result.

Changing something here? Read [`../AGENTS.md`](../AGENTS.md).
