#!/usr/bin/env bash
# investigate-first-reminder — UserPromptSubmit hook for claude, interactive only.
#
# A Stop hook cannot take back text already on screen, so the "You're right." opener
# has to be prevented before the agent writes its first token. This injects the rule
# into context on every message the owner sends. investigate-first-gate.py enforces it
# at Stop. Headless runs (CLAUDE_CODE_ENTRYPOINT=sdk-cli) are machine prompts and get
# nothing. Stdout of an exit-0 UserPromptSubmit hook is added to the model's context.
set -u
cat >/dev/null
[ "${CLAUDE_CODE_ENTRYPOINT:-}" = "cli" ] || exit 0
cat <<'EOF'
Investigate first: your first action for this message is a tool call that gathers what it needs. Do not open by agreeing, conceding, or concluding before evidence comes back. Before asking the owner for anything (a token, key, login, file, fact, merge, or click), check what you can reach yourself: secrets bundles (search names), logged-in browsers, fleet devices, sessions, a reviewer subagent.
EOF
exit 0
