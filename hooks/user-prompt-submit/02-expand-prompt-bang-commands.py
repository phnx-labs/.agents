#!/usr/bin/env python3
"""
Expands `!command` and `! command` patterns in prompts by executing them in the session cwd.

Two forms:
  `! <cmd>`  — explicit (space after !). Always executes.
  `!<cmd>`   — terse (no space). Executes UNLESS body is a bare identifier,
               so collisions like `!important`, `!foo`, `!isReady` stay literal.

Examples:
  "List files in `! ls agents`"  -> "List files in `agent1.md agent2.md`"
  "Check `!pwd`"                 -> "Check `/home/user/project`"
  "Output: `!echo hello`"        -> "Output: `hello`"
  "CSS rule: `!important`"       -> "CSS rule: `!important`"  (literal — bare word)
  "Ruby bang: `!foo`"            -> "Ruby bang: `!foo`"        (literal — bare word)

Per-agent protocol:
  claude  — <user-prompt-submit-hook> wrapper; REPLACES prompt
  codex   — JSON with additionalContext; APPENDS (original `!cmd` stays)
  gemini  — JSON with additionalContext; APPENDS (original `!cmd` stays)
"""

import json
import os
import re
import subprocess
import sys


EXPLICIT_PATTERN = re.compile(r'`! ([^`]+)`')
TERSE_PATTERN = re.compile(r'`!([^\s`][^`]*)`')
BARE_IDENT = re.compile(r'[A-Za-z_][\w-]*')


def run_command(command: str, cwd: str) -> str:
    try:
        result = subprocess.run(
            f"cd {cwd} && {command}",
            shell=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        output = result.stdout.strip()
        if result.returncode != 0 and not output:
            output = f"[error: {result.stderr.strip()}]"
        return f"`{output}`"
    except subprocess.TimeoutExpired:
        return "`[timeout]`"
    except Exception as e:
        return f"`[error: {e}]`"


def expand_commands(prompt: str, cwd: str) -> str:
    def replace_explicit(match):
        return run_command(match.group(1).strip(), cwd)

    def replace_terse(match):
        body = match.group(1)
        if BARE_IDENT.fullmatch(body):
            return match.group(0)
        return run_command(body.strip(), cwd)

    prompt = EXPLICIT_PATTERN.sub(replace_explicit, prompt)
    prompt = TERSE_PATTERN.sub(replace_terse, prompt)
    return prompt


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    prompt = data.get("prompt", "")
    cwd = data.get("cwd", os.getcwd())
    event = data.get("hook_event_name", "UserPromptSubmit")

    if "`!" not in prompt:
        sys.exit(0)

    expanded = expand_commands(prompt, cwd)
    if expanded == prompt:
        sys.exit(0)

    if os.environ.get("CLAUDE_PROJECT_DIR"):
        print("<user-prompt-submit-hook>")
        print(expanded)
        print("</user-prompt-submit-hook>")
        sys.exit(0)

    context = "Inline `! cmd` blocks expanded to:\n\n" + expanded
    out = {
        "hookSpecificOutput": {
            "hookEventName": event,
            "additionalContext": context,
        }
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
