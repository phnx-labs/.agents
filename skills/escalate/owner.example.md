---
# ~/.agents/owner.md — the OWNER PROFILE. Copy this to ~/.agents/owner.md and
# edit. One source of truth for every "reach the human" behavior: escalation,
# out-of-band notifications, and the session-summary handoff. Read by a
# Notification hook (the escalation TRIGGER) — an agent's existing "I need you"
# signal is what fires it, so there is NO command to remember.
#
# Frontmatter is parsed stdlib-only (no PyYAML dependency — it must work on every
# box, and PyYAML is not everywhere). Keep it to this shape: top-level scalars, a
# `channels:` list of flat maps, and a `policy:` map of string lists.
name: Your Name
timezone: America/Los_Angeles
quiet_hours: "23:00-07:00"          # local; intrusive rungs held during these unless severity=critical

# Contact channels, in PRIORITY ORDER (the escalation ladder climbs this list).
#   watch: true       a reply here is a valid ACK that stands down escalation
#   intrusive: true   the loud rung (a call) — subject to quiet_hours
# Supported transports: openclaw (telegram/imessage/slack via OpenClaw), twilio
# (a phone call via a call cmd). Add only the channels YOU use — the ladder is
# yours, nothing is hardcoded.
channels:
  - id: telegram
    transport: openclaw
    host: mac-mini                  # where openclaw runs ("local" = this box)
    account: default
    target: "<your-telegram-chat-id>"
    watch: true
  - id: call
    transport: twilio
    cmd: ~/.agents/skills/muqsit-cli/call.sh
    creds: twilio                   # agents secrets bundle holding the transport creds
    intrusive: true

# Escalation policy per severity — an ordered list of steps. A step is either
#   <channel>          fire immediately, or
#   <channel>@<delay>  fire only if no ACK after <delay> (90s / 15m / 1h).
# Want to NEVER be called? Just leave `call` out of every policy — that is a
# first-class choice, not a degradation. Want SMS-only, Slack-only, or
# PagerDuty? Declare those channels and reference them here.
policy:
  low:      [telegram]                     # message only, no chase
  normal:   [telegram, call@15m]           # message; call if no ack in 15m
  critical: [telegram, call@0m]            # message + call immediately
default_severity: normal

# Auto-escalation: when true, an agent's "I need you" Notification automatically
# fires the ladder above (deduped per session). OFF by default — turn it on only
# after you've run `escalate --check` and done a wiring test, so it never
# surprises you. With it off, the ladder is still available on demand.
auto_escalate: false

# Forward status updates: when true, an agent's DELIBERATE `agents feed post`
# (a milestone / completion recap) is forwarded to your phone by the feed-forward
# hook — event-driven, no polling. Fine-grained checklist crossings are NOT
# forwarded (they stay on the feed). OFF by default.
forward_status: false
---

# Your Name

A few lines about who you are and how you like to be reached — the agent reads
this for context (role, working hours, what "urgent" means to you). Example:
"Founder; prefer Telegram; a call means it's real; usually reachable, assume away
if quiet ~15 min."
