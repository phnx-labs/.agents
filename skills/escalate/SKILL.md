---
name: escalate
description: Reach the user out-of-band when genuinely blocked, then climb an escalation ladder (message -> watch for reply -> phone call) until you get their attention. The ONE move an agent makes instead of stopping in the chat window. The ladder is universal; the channels are per-user config, auto-detected, and degrade gracefully to the loudest available. Triggers on being blocked after exhausting self-serve, needing a decision/credential/sign-off you cannot obtain yourself, "get their attention", "ping the user and wait", "message then call if no reply".
allowed-tools: Bash(bash ~/.agents/skills/escalate/escalate.sh*)
---

# escalate — reach the user, watch for a reply, climb to a call

**When you are genuinely blocked and have exhausted self-serve (F2), you do NOT
stop in the chat window.** A chat message here is a note in an empty room — the
user runs many agents and is almost never watching this one. Get their attention
out-of-band and keep working everything else.

```bash
bash ~/.agents/skills/escalate/escalate.sh "<one-line blocker>" [--wait 15m] [--context <detail>]
```

1. **Sends a message** on the loudest configured channel (Telegram via OpenClaw).
2. **Watches for a reply** (where the channel supports it) and stands down if you get one.
3. **Climbs to a phone call** — the best rung — if no reply arrives within `--wait` (default 15m).

Returns immediately; the watcher self-terminates on reply or after the top rung.

## The ladder is universal; the rungs are yours

This skill ships with **no personal data**. Each user names their channels in
`~/.agents/escalate.json`:

```json
{
  "host":     "local",
  "telegram": { "account": "default", "target": "<your-telegram-chat-id>" },
  "call":     { "cmd": "~/.agents/skills/<your-call-cmd>/call.sh" }
}
```

The skill **auto-detects which rungs are actually live** and **degrades
gracefully**. The phone call is the best rung — but if it isn't set up, escalate
uses the loudest available and **tells you honestly how far it got**: it will say
*"no phone rung configured — re-pinging, this is as loud as I can get,"* never a
false "escalated."

## Know before you rely on it

```bash
bash ~/.agents/skills/escalate/escalate.sh --check
```

Prints which rungs are live and the **ceiling** this box can reach
(`MESSAGE + WATCH + CALL`, or `MESSAGE` only, or `NONE`). Run it once when you
set up a machine so you know how far an escalation can climb.

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `--wait N` | `15m` | wait for a reply before the top rung (`90s`/`15m`/`1h`) |
| `--context S` | — | extra detail / a link, appended to the message |
| `--no-call` | off | message + watch only; never place the call |
| `--poll N` | `30s` | reply-poll interval |
| `--dry-run` | off | print the plan and the ceiling; send nothing |
| `--check` | — | print rung readiness and the escalation ceiling |

Keep the message short — you are texting a manager. One line, lead with the one
thing you need, link the PR/ticket in `--context`. Then keep working.
