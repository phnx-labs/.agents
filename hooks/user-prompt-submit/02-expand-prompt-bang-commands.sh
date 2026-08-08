#!/bin/bash
# Executes backticked `! command` prompt blocks concurrently.

INPUT_JSON=$(cat)

# This hook sees every prompt. Keep the ordinary path below Python startup cost.
case "$INPUT_JSON" in
  *'`!'*) ;;
  *) exit 0 ;;
esac

if python3 --version >/dev/null 2>&1; then
  PYTHON=(python3)
elif py -3 --version >/dev/null 2>&1; then
  PYTHON=(py -3)
else
  exit 0
fi

"${PYTHON[@]}" - "$INPUT_JSON" <<'PY'
import json
import os
import re
import signal
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor


EXPLICIT_PATTERN = re.compile(r'`! ([^`]+)`')
TERSE_PATTERN = re.compile(r'`!([^\s`][^`]*)`')
BARE_IDENT = re.compile(r'[A-Za-z_][\w-]*')
COMMAND_TIMEOUT_SECONDS = 5
MAX_PARALLEL_COMMANDS = 8


def run_command(command, cwd):
    process = None
    try:
        process = subprocess.Popen(
            command,
            shell=True,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=os.name != "nt",
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0,
        )
        stdout, stderr = process.communicate(timeout=COMMAND_TIMEOUT_SECONDS)
        output = stdout.strip()
        if process.returncode != 0 and not output:
            output = f"[error: {stderr.strip()}]"
        return f"`{output}`"
    except subprocess.TimeoutExpired:
        if process is not None:
            if os.name == "nt":
                terminated = subprocess.run(
                    ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                if terminated.returncode != 0 and process.poll() is None:
                    process.kill()
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        return "`[timeout]`"
    except Exception as error:
        return f"`[error: {error}]`"


def command_matches(prompt):
    matches = []
    occupied = []
    for pattern, explicit in ((EXPLICIT_PATTERN, True), (TERSE_PATTERN, False)):
        for match in pattern.finditer(prompt):
            if any(match.start() < end and match.end() > start for start, end in occupied):
                continue
            body = match.group(1)
            if not explicit and BARE_IDENT.fullmatch(body):
                continue
            matches.append((match.start(), match.end(), body.strip()))
            occupied.append((match.start(), match.end()))
    return sorted(matches)


def expand_commands(prompt, cwd):
    matches = command_matches(prompt)
    if not matches:
        return prompt
    if len(matches) > MAX_PARALLEL_COMMANDS:
        return f"{prompt}\n\n`[error: at most {MAX_PARALLEL_COMMANDS} inline commands per prompt]`"
    with ThreadPoolExecutor(max_workers=min(len(matches), MAX_PARALLEL_COMMANDS)) as executor:
        outputs = list(executor.map(lambda match: run_command(match[2], cwd), matches))
    parts = []
    cursor = 0
    for (start, end, _), output in zip(matches, outputs):
        parts.extend((prompt[cursor:start], output))
        cursor = end
    parts.append(prompt[cursor:])
    return "".join(parts)


try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

prompt = data.get("prompt", "") or data.get("userPrompt", "") or ""
cwd = data.get("cwd") or data.get("workspaceRoot") or os.getcwd()
event = data.get("hook_event_name") or data.get("hookEventName") or "UserPromptSubmit"
expanded = expand_commands(prompt, cwd)
if expanded == prompt:
    sys.exit(0)

if os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("CLAUDECODE"):
    print("<user-prompt-submit-hook>")
    print(expanded)
    print("</user-prompt-submit-hook>")
    sys.exit(0)

context = "Inline `! cmd` blocks expanded to:\n\n" + expanded
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": event,
        "additionalContext": context,
    }
}))
PY

exit 0
