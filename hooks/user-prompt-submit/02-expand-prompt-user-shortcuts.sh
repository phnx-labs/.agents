#!/bin/bash
# Expands prompt shortcuts defined in promptcuts.yaml.
#
# Accepted markers for a shortcut stored as "#name":
#   #name / `#name`   — original marker, bare or explicit
#   !!name / `!!name` — alternate marker when # is being used as a hashtag
#
# Per-agent protocol:
#   claude  — prints <user-prompt-submit-hook> wrapper; REPLACES prompt
#   codex   — prints JSON with additionalContext; APPENDS (token stays)
#   gemini  — prints JSON with additionalContext; APPENDS (token stays)
#
# Layered lookup (user wins on key collision):
#   ~/.agents/hooks/promptcuts.yaml         (user shortcuts)
#   ~/.agents-system/hooks/promptcuts.yaml  (system-shipped defaults)
#
# This file lives in the system repo; the user repo can override individual
# shortcuts by adding the same key to its own promptcuts.yaml.

INPUT_JSON=$(cat)

# UserPromptSubmit runs for every prompt. Avoid Python + YAML startup entirely
# when neither promptcut marker can possibly be present.
case "$INPUT_JSON" in
  *'#'*|*'!!'*) ;;
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
import json, os, sys, yaml

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

prompt = data.get("prompt", "") or data.get("userPrompt", "") or ""
event = data.get("hook_event_name", "") or data.get("hookEventName", "") or ""
if not prompt:
    sys.exit(0)

home = os.path.expanduser("~")
paths = [
    # System defaults. The canonical location is ~/.agents/.system (state.ts:57);
    # ~/.agents-system is the pre-migration path (state.ts:64) that only exists on
    # a folded legacy install. This read pointed ONLY at the legacy path, so on any
    # fresh install the system layer never loaded and every shortcut resolved from
    # the user's own copy alone.
    os.path.join(home, ".agents", ".system", "hooks", "promptcuts.yaml"),
    os.path.join(home, ".agents-system", "hooks", "promptcuts.yaml"),  # legacy
    os.path.join(home, ".agents", "hooks", "promptcuts.yaml"),         # user overrides
]

shortcuts = {}
for p in paths:
    try:
        with open(p) as f:
            data_yaml = (yaml.safe_load(f) or {}).get("shortcuts", {}) or {}
            # Later layers (user) override earlier layers (system).
            shortcuts.update(data_yaml)
    except FileNotFoundError:
        continue
    except Exception:
        continue

if not shortcuts:
    sys.exit(0)

matched = None
for token, expansion in shortcuts.items():
    name = token[1:] if token.startswith("#") else token
    markers = (f"`#{name}`", f"`!!{name}`", f"!!{name}", token)
    for marker in markers:
        if marker in prompt:
            matched = (token, marker, expansion.strip())
            break
    if matched:
        break
if not matched:
    sys.exit(0)

token, marker, expansion = matched

# Claude Code harness: replace prompt via wrapper.
if os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("CLAUDECODE"):
    replaced = prompt.replace(marker, expansion)
    print("<user-prompt-submit-hook>")
    print(replaced)
    print("</user-prompt-submit-hook>")
    sys.exit(0)

# Codex / Kimi / Grok / Cursor / Droid: append as additionalContext.
# Event name differs by harness; output shape is the Claude-compatible JSON.
event_name = event or "UserPromptSubmit"
context = f"Shortcut `{marker}` expands to:\n\n{expansion}"
out = {
    "hookSpecificOutput": {
        "hookEventName": event_name,
        "additionalContext": context,
    }
}
print(json.dumps(out))
PY

exit 0
