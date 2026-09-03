#!/usr/bin/env python3
"""linear-guard — PreToolUse hook on Bash. Restrains agent tracker sprawl.

Two behaviors, both keyed on a `linear` CLI invocation in the command string:

1. DENY (exit 2) — creating a Linear PROJECT (`linear projects create`).
   Projects are the owner's structural call, not an agent's. Agents spinning up
   projects on their own (a real incident: a "FastWispr Growth" project appeared
   unasked) fragments the board and buries real work. There is no agent path to
   a new project — if one is genuinely needed, that's a one-line suggestion in
   the owner update, not a CLI call.

2. NUDGE (exit 0 + additionalContext) — creating an ISSUE (`linear create`).
   Non-blocking. Before an agent files a ticket, make it stop and reflect: if
   the thing can be fixed right now (by this agent, or by dispatching one), DO
   THAT — a fixable-now problem filed as a ticket is bloat, not tracking. It
   makes the board harder to review, hides the signal, and manufactures
   busywork. The conventions rule already says "default to NOT creating"; this
   is the enforcement at the point of action.

Why a hook and not just a rule: the rule has been in `conventions.md` for a
while and the board still inflated to 60+ AGI tickets, most never started. A
guard fires at the exact moment of the action, where the reflex forms.

Detection is deliberately simple (token adjacency, not a full shell parser) —
this is a restraint nudge + a block on one specific subcommand, not a security
sandbox. A determined evasion (eval, xargs, a computed string) walks past it;
ordinary `linear` usage does not. Fail-OPEN on any parse error: a guard that
can't read its input must not wedge every Bash call.

Exits 0 (allow, optionally with a nudge) or 2 (deny, message on stderr).
"""
import json
import re
import sys

# `linear projects create` (subcommand adjacency). The `archive`/`delete` alias
# is intentionally NOT blocked — cleaning up a stray project is allowed.
PROJECT_CREATE = re.compile(r"\bprojects\s+create\b")

# `linear [--global-flag val ...] create` — the issue-creation subcommand as the
# first non-flag token after `linear`. Matches `linear create`,
# `linear --team ENG create`, etc. Does not match `linear projects create`
# (handled above) or `linear tasks`/`update`/etc.
ISSUE_CREATE = re.compile(r"\blinear\b(?:\s+--?[\w-]+(?:\s+[^\s-][^\s]*)?)*\s+create\b")

HELP = re.compile(r"(?:^|\s)(?:-h|--help)(?:\s|$)")

DENY = (
    "blocked_op: linear.projects-create\n"
    "reason: Agents do not create Linear projects. Project structure is the "
    "owner's call — an agent minting a project (e.g. an unasked 'FastWispr "
    "Growth') fragments the board and buries real work. There is no agent path "
    "to a new project.\n"
    "do_this_instead: If a new project is genuinely warranted, put it in your "
    "owner update as a one-line suggestion for the owner to decide. To organize "
    "work now, use an existing project + milestone, or an epic issue with a "
    "checklist. To clean up a stray project, `linear projects archive` is allowed."
)

NUDGE = (
    "[linear-restraint] You're about to file a Linear issue. Stop and reflect "
    "first: can this be fixed RIGHT NOW — by you, or by dispatching an agent "
    "(`agents run` / `agents teams`)? If yes, do that instead of filing it. A "
    "problem you could fix now, filed as a ticket, is bloat: it makes the board "
    "harder to review, hides the real work, and manufactures follow-up churn. "
    "File an issue only for work that genuinely must be scheduled for later and "
    "that nobody is delivering in this session — and first search the board for "
    "an existing ticket to enrich instead of a near-duplicate. This is advisory; "
    "the command will still run."
)


def main():
    try:
        payload = json.load(sys.stdin)
        inputs = payload.get("tool_input") or payload.get("toolInput") or {}
        command = str(inputs.get("command") or inputs.get("cmd") or "")
    except Exception:
        return  # fail-open: unreadable payload must not wedge Bash
    if "linear" not in command:
        return
    if HELP.search(command):
        return  # `linear create --help` is not a create

    if PROJECT_CREATE.search(command):
        sys.stderr.write(DENY + "\n")
        sys.exit(2)

    if ISSUE_CREATE.search(command):
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "additionalContext": NUDGE}}))


if __name__ == "__main__":
    main()
