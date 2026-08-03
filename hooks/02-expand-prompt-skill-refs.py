#!/usr/bin/env python3
"""
UserPromptSubmit hook: expands $skill-name tokens into skill path + description.

Syntax:
  $higgsfield             -- fuzzy: finds any skill dir named "higgsfield"
  $browser/higgsfield     -- relative: matches path ending in browser/higgsfield
  $browser/domain-skills/higgsfield  -- deeper relative path

Search order (first match wins per token):
  {cwd}/.agents/skills/  →  ~/.agents/skills/  →  ~/.agents-system/skills/

Replacement:
  `higgsfield` (skill: /full/path — description from SKILL.md frontmatter)

Per-agent protocol matches 02-expand-prompt-bang-commands.py:
  claude  — <user-prompt-submit-hook> replaces prompt
  codex/gemini — JSON additionalContext appends
"""

import json
import os
import re
import sys


SKILL_TOKEN = re.compile(r'(?<![`\w])\$([A-Za-z][A-Za-z0-9_/-]*)')

# Never descend into these directories during skill search
_PRUNE = frozenset({
    'node_modules', '.git', '__pycache__', '.venv', 'venv',
    'dist', 'build', '.cache', '.tox', '.mypy_cache',
})


def find_skill(token: str, search_dirs: list[str]) -> str | None:
    """Return the first directory matching token (relative path or basename)."""
    has_slash = '/' in token

    for base in search_dirs:
        if not os.path.isdir(base):
            continue

        if has_slash:
            # Treat token as a relative path suffix: walk and check if any path ends with it
            for root, dirs, _ in os.walk(base):
                dirs[:] = [d for d in dirs if d not in _PRUNE]
                rel = os.path.relpath(root, base)
                if rel == token or rel.endswith('/' + token):
                    return root
        else:
            # Fuzzy: any directory whose basename matches
            for root, dirs, _ in os.walk(base):
                dirs[:] = [d for d in dirs if d not in _PRUNE]
                if os.path.basename(root) == token:
                    return root

    return None


def get_description(skill_path: str) -> str | None:
    """Extract description from SKILL.md frontmatter, else first content line."""
    skill_md = os.path.join(skill_path, 'SKILL.md')
    if not os.path.isfile(skill_md):
        return None
    try:
        with open(skill_md, 'r', encoding='utf-8') as f:
            content = f.read(2000)

        # Parse YAML frontmatter for description field
        if content.startswith('---'):
            end = content.find('\n---', 3)
            if end != -1:
                frontmatter = content[3:end]
                for line in frontmatter.splitlines():
                    m = re.match(r'^description:\s*(.+)', line)
                    if m:
                        return m.group(1).strip().strip('"\'')

        # Fall back to first non-header, non-empty line
        for line in content.splitlines():
            line = line.strip()
            if line and not line.startswith('#') and not line.startswith('---'):
                return line[:120]
    except Exception:
        pass
    return None


def format_replacement(token: str, skill_path: str) -> str:
    name = os.path.basename(skill_path)
    desc = get_description(skill_path)
    if desc:
        return f'`{name}` (skill: {skill_path} — {desc})'
    return f'`{name}` (skill: {skill_path})'


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    prompt = data.get('prompt', '')
    cwd = data.get('cwd', os.getcwd())
    event = data.get('hook_event_name', 'UserPromptSubmit')

    if not prompt or '$' not in prompt:
        sys.exit(0)

    tokens = SKILL_TOKEN.findall(prompt)
    if not tokens:
        sys.exit(0)

    home = os.path.expanduser('~')
    search_dirs = [
        os.path.join(cwd, '.agents', 'skills'),
        os.path.join(home, '.agents', 'skills'),
        # Canonical system layer (state.ts:57); the bare ~/.agents-system below is
        # the legacy pre-migration path (state.ts:64), kept for folded installs.
        os.path.join(home, '.agents', '.system', 'skills'),
        os.path.join(home, '.agents-system', 'skills'),
    ]

    expanded = prompt
    modified = False

    for token in dict.fromkeys(tokens):  # deduplicated, insertion order
        skill_path = find_skill(token, search_dirs)
        if not skill_path:
            continue
        replacement = format_replacement(token, skill_path)
        expanded = expanded.replace(f'${token}', replacement)
        modified = True

    if not modified:
        sys.exit(0)

    if os.environ.get('CLAUDE_PROJECT_DIR'):
        print('<user-prompt-submit-hook>')
        print(expanded)
        print('</user-prompt-submit-hook>')
        sys.exit(0)

    out = {
        'hookSpecificOutput': {
            'hookEventName': event,
            'additionalContext': 'Skill references expanded:\n\n' + expanded,
        }
    }
    print(json.dumps(out))


if __name__ == '__main__':
    main()
