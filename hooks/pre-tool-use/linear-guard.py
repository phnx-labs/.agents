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

3. NUDGE (exit 0 + additionalContext) — adding a comment to amend a ticket
   (`linear update … --comment …`, without delivery-proof/status flags). Prefer
   updating the DESCRIPTION so the ticket stays one source of truth; a pile of
   context comments forces the next reader to reconcile first-vs-last and guess
   what's current. Stays quiet when the comment rides with `--proof`/`--done`/
   `--status` (legitimate closing evidence, not context-piling).

Why a hook and not just a rule: the rule has been in `conventions.md` for a
while and the board still inflated to 60+ AGI tickets, most never started. A
guard fires at the exact moment of the action, where the reflex forms.

Detection tokenizes the command with `shlex` and scans for an actual `linear`
invocation, then reads the subcommand position — it does NOT substring-match the
raw string, so a `linear projects create` sitting inside a quoted description /
grep pattern / commit message is not mistaken for a real invocation. It is a
restraint nudge + a block on one specific subcommand, not a security sandbox: a
determined evasion (eval, xargs, a computed string) walks past it; ordinary
`linear` usage does not.

Fail-CLOSED, blast-radius limited — the same shape as `git-guard.sh`: a raw
fast-path exits 0 for any command with no `linear` substring at all, so this
guard never touches the >99% of Bash calls that are not linear-related; but once
`linear` IS present and the payload cannot be parsed, it refuses (exit 2) rather
than waving a possible `linear projects create` through unchecked. This is the
`hooks/AGENTS.md` contract for a deny-capable guard (only advisory-only hooks may
fail open).

Exits 0 (allow, optionally with a nudge) or 2 (deny, message on stderr).
"""
import json
import shlex
import sys

# Global flags that take a following value — skipped (flag + value) when scanning
# for the `linear` subcommand, so `linear --team ENG create` reads `create`, not
# the flag value, as the subcommand.
VALUE_FLAGS = {"--team", "--project", "--milestone"}


def _tokens(command):
    """Shell-tokenize, tolerant of unbalanced quotes (fall back to whitespace)."""
    try:
        return shlex.split(command)
    except ValueError:
        return command.split()


def _linear_subcommand(tokens, i):
    """Given tokens[i] == a `linear` invocation, return (subcommand, rest) where
    `rest` is the token list after the subcommand — skipping global flags. A
    token scan, NOT a regex: no backtracking, so no ReDoS (py/redos)."""
    j = i + 1
    while j < len(tokens) and tokens[j].startswith("-"):
        j += 2 if tokens[j] in VALUE_FLAGS else 1
    if j >= len(tokens):
        return "", []
    return tokens[j], tokens[j + 1:]


def _is_linear(tok):
    # bare `linear` or an absolute/relative path ending in `/linear`
    return tok == "linear" or tok.endswith("/linear")

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

# Flags on `linear update` that mark a delivery/state change (proof of work,
# a status move) — a comment alongside these is legitimate closing evidence, not
# context-piling, so the comment nudge stays quiet for them.
DELIVERY_FLAGS = {"--proof", "--done", "--todo", "--pickup", "--status"}

COMMENT_NUDGE = (
    "[linear-restraint] Amending or adding context to a ticket? Update its "
    "description instead — rewrite it so the ticket stays the single source of "
    "truth. Piling on another comment forces the next reader to reconcile the "
    "first message against the last and guess which is current; a stale comment "
    "on an old ticket is worse than none. (Comments are fine for delivery proof "
    "— a PR link, a screenshot, a decision — just not for restating the ticket.) "
    "This is advisory; the command will still run."
)


def main():
    raw = sys.stdin.read()
    # Fast path (mirrors git-guard.sh:82): a command with no `linear` substring at
    # all is nothing for this hook — never parse, never fail closed on it. This is
    # what keeps the fail-closed policy below from touching the >99% of Bash calls
    # that are not linear-related.
    if "linear" not in raw:
        return
    # `linear` IS present. A deny-capable guard that cannot parse its input must
    # refuse, not wave a possible `linear projects create` through unchecked
    # (hooks/AGENTS.md contract; same as git-guard.sh:115-117).
    try:
        payload = json.loads(raw)
        inputs = payload.get("tool_input") or payload.get("toolInput") or {}
        command = str(inputs.get("command") or inputs.get("cmd") or "")
    except Exception:
        sys.stderr.write(
            "linear-guard: 'linear' present but the PreToolUse payload could not "
            "be parsed — refusing to run unchecked (fail-closed). If this is not a "
            "linear command, it will retry cleanly.\n")
        sys.exit(2)
    # Parsed cleanly but this event carries no shell command, or the command has
    # no `linear` token once extracted — genuinely nothing to police, allow.
    if "linear" not in command:
        return

    tokens = _tokens(command)
    nudge_text = None
    for i, tok in enumerate(tokens):
        if not _is_linear(tok):
            continue
        sub, rest = _linear_subcommand(tokens, i)
        if sub == "projects":
            # DENY `linear projects create` — but `--help`/`-h` on it is not a create.
            after = [t for t in rest if not t.startswith("-")]
            has_help = any(t in ("-h", "--help") for t in rest)
            if after and after[0] == "create" and not has_help:
                sys.stderr.write(DENY + "\n")
                sys.exit(2)
        elif sub == "create":
            # NUDGE on issue creation, unless it's `linear create --help`.
            if not any(t in ("-h", "--help") for t in rest):
                nudge_text = nudge_text or NUDGE
        elif sub == "update":
            # NUDGE when a comment is being added to amend/add context — but NOT
            # when it rides alongside delivery proof or a status change (that
            # comment is legitimate closing evidence, not context-piling).
            if "--comment" in rest and not any(f in rest for f in DELIVERY_FLAGS):
                nudge_text = nudge_text or COMMENT_NUDGE

    if nudge_text:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "additionalContext": nudge_text}}))


if __name__ == "__main__":
    main()
