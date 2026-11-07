"""What this turn did about opening pages for the owner, read from the transcript.

Prints "<opened> <page>": opened is yes, no or unknown (no owner prompt found), and
page is the first page this turn wrote under an artifact home, else an artifact its
reply names, else "-".
A turn starts at the owner's last prompt; harness-injected records don't count.
"""
import json, re, sys

SHOW = re.compile(r"\bbrowser\s+show\b")
records = []
with open(sys.argv[1], encoding="utf-8") as handle:
    for raw in handle:
        try:
            records.append(json.loads(raw))
        except Exception:
            pass

# Only the owner's own prompts reset the turn. Claude Code marks them with
# origin.kind "human"; older versions are told apart by what the harness injects
# as user records. Codex records the owner's prompt as an event_msg user_message.
INJECTED = ("<task-notification", "<bash-", "<command-", "<local-command",
            "[Request interrupted", "<environment_context", "<user_instructions",
            "# AGENTS.md", "This session is being continued")

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") in ("text", "input_text", "output_text"))
    return ""

def human(r):
    p = r.get("payload") or {}
    if r.get("type") == "event_msg":
        return p.get("type") == "user_message"
    if r.get("type") == "response_item":
        return False
    if r.get("type") != "user" or r.get("isMeta") or r.get("isCompactSummary"):
        return False
    origin = r.get("origin")
    if isinstance(origin, dict) and origin.get("kind"):
        return origin["kind"] == "human"
    content = (r.get("message") or {}).get("content")
    if isinstance(content, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
        return False
    text = text_of(content).strip()
    return bool(text) and not text.startswith(INJECTED)

def calls(r):
    if r.get("type") == "assistant":
        for b in (r.get("message") or {}).get("content") or []:
            if isinstance(b, dict) and b.get("type") == "tool_use":
                yield json.dumps(b.get("input"))
    p = r.get("payload") or {}
    if p.get("type") in ("function_call", "custom_tool_call", "local_shell_call"):
        yield json.dumps(p)

PAGE = re.compile(r"(?:\.agents|\.local/share/agents)/artifacts/[^\s\"'\\]+\.(?:html|md)")
NAMED = re.compile(r"(?:\.agents|\.local/share/agents)/artifacts/\d{4}-\d{2}-\d{2}/[\w.-]+(?:/[\w./-]*)?")

def said(r):
    if r.get("type") == "assistant":
        return text_of((r.get("message") or {}).get("content"))
    p = r.get("payload") or {}
    if p.get("type") == "message" and p.get("role") == "assistant":
        return text_of(p.get("content"))
    return ""

RENDER = re.compile(r"\bartifacts\s+render\s+(\S+)")

last = max((i for i, r in enumerate(records) if human(r)), default=None)
if last is None:
    print("unknown -")
else:
    turn = [c for r in records[last:] for c in calls(r)]
    opened = "yes" if any(SHOW.search(c) for c in turn) else "no"
    page = "-"
    for c in turn:
        if SHOW.search(c):
            continue
        hit = RENDER.search(c) or PAGE.search(c)
        if hit:
            page = hit.group(1) if hit.re is RENDER else hit.group(0)
            break
    if page == "-":
        # A reply that points the owner at an artifact is presenting it, even when
        # an earlier turn wrote it.
        for r in records[last:]:
            hit = NAMED.search(said(r))
            if hit:
                page = hit.group(0)
    print(opened, page)
