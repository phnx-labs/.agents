"""What this turn did about opening pages for the owner, read from the transcript.

Prints "<opened> <page>": opened is yes (an open whose result confirms it), failed
(tried, never confirmed), no, or unknown (no owner prompt found), and
page is the first page this turn wrote under an artifact home, else an artifact its
reply names, else "-"; then the
index of the owner prompt the turn started at, so a block counter resets per prompt.
A turn starts at the owner's last prompt; harness-injected records don't count.
"""
import json, os, re, sys

# browser show is the documented path; a direct Arc open on the owner's machine counts too.
SHOW = re.compile(r"\bbrowser\s+show\b|\bopen\s+-a\s+\"?Arc\b|tell application \\*\"Arc\\*\"[^\n]*(?:make new tab|open location|set URL)")
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

# An open counts only when its result confirms it: `browser show` prints
# "via": "none" when no viewer took the page (2026-11-07: Arc's front window was
# not on the Work space, twice), and a denied or failed command never opened anything.
# Only signals that name the open itself count: an exit code or an "error" line can
# come from another command chained after a successful open (review on #551).
FAILED = re.compile(r'"via"\s*:\s*"none"|No visible Arc window|execution error|AppleEvent handler failed'
                    r'|Permission (?:for this action was|to use \w+ .*?has been) denied', re.I)


HANDOFF = re.compile(r"^\s*agents\s+feed\s+post\s+(?!-h\b|--help\b)[^\n]*--blocked\b")


def handed_off(records, done, page):
    """A blocked ask to the owner that really went out and names the page: a shell
    command that starts with `agents feed post … --blocked` (not an echo, a heredoc or
    --help), whose result is not an error or a denial (review on #553)."""
    if page == "-":
        return False
    slug = re.search(r"/artifacts/\d{4}-\d{2}-\d{2}/([^/\s#]+)", absolute(page))
    folder = slug.group(1) if slug else os.path.basename(absolute(page).rstrip("/"))
    for r in records:
        if r.get("type") != "assistant":
            continue
        for b in (r.get("message") or {}).get("content") or []:
            if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                continue
            command = str((b.get("input") or {}).get("command") or "")
            if not HANDOFF.search(command) or folder not in command:
                continue
            text, is_error = done.get(b.get("id"), ("", True))
            if not is_error and not FAILED.search(text):
                return True
    return False


def results(records):
    """Tool results by call id, for Claude tool_result blocks and Codex outputs."""
    out = {}
    for r in records:
        if r.get("type") == "user":
            for b in (r.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    c = b.get("content")
                    text = c if isinstance(c, str) else json.dumps(c)
                    out[b.get("tool_use_id")] = (text, bool(b.get("is_error")))
        p = r.get("payload") or {}
        if p.get("type") in ("function_call_output", "custom_tool_call_output"):
            out[p.get("call_id")] = (json.dumps(p.get("output")), False)
    return out


def opens(records):
    """(call id, command text) for every attempt to open a page for the owner."""
    for r in records:
        if r.get("type") == "assistant":
            for b in (r.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    text = json.dumps(b.get("input"))
                    if SHOW.search(text):
                        yield b.get("id"), text
        p = r.get("payload") or {}
        if p.get("type") in ("function_call", "custom_tool_call", "local_shell_call"):
            text = json.dumps(p)
            if SHOW.search(text):
                yield p.get("call_id"), text


# Artifact homes only, anchored at the owner's home: an in-repo .agents/artifacts/
# path is a repository file, not a page made for the owner.
HOME_ART = r"(?:~|\$HOME|/home/[^/\s]+|/Users/[^/\s]+)/(?:\.agents|\.local/share/agents)/artifacts/"
PAGE = re.compile(HOME_ART + r"[^\s\"'\\`]+?\.(?:html|md)\b")
NAMED = re.compile(HOME_ART + r"\d{4}-\d{2}-\d{2}/[\w.-]+(?:/[\w./-]*)?")
RENDER = re.compile(r"\bartifacts\s+render\s+(\S+)")
WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
ADDED = re.compile(r"\*\*\* (?:Add|Update) File: (\S+)")


def absolute(path):
    path = path.rstrip(".,;:)]}'\"")
    return os.path.expanduser(path.replace("$HOME", "~", 1))


def written(r):
    """Pages this record wrote: a file tool's target, an `artifacts render`, or a
    Codex patch. Reading, grepping or listing an artifact writes nothing."""
    if r.get("type") == "assistant":
        for b in (r.get("message") or {}).get("content") or []:
            if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                continue
            args = b.get("input") or {}
            if b.get("name") in WRITE_TOOLS:
                target = str(args.get("file_path") or args.get("notebook_path") or "")
                if PAGE.fullmatch(target) or PAGE.match(target):
                    yield target
            command = str(args.get("command") or "")
            for hit in RENDER.finditer(command):
                if PAGE.match(hit.group(1)):
                    yield hit.group(1)
    p = r.get("payload") or {}
    if p.get("type") in ("function_call", "custom_tool_call", "local_shell_call"):
        blob = json.dumps(p)
        for hit in list(ADDED.finditer(blob)) + list(RENDER.finditer(blob)):
            if PAGE.match(hit.group(1)):
                yield hit.group(1)


def said(r):
    if r.get("type") == "assistant":
        return text_of((r.get("message") or {}).get("content"))
    p = r.get("payload") or {}
    if p.get("type") == "message" and p.get("role") == "assistant":
        return text_of(p.get("content"))
    return ""


last = max((i for i, r in enumerate(records) if human(r)), default=None)
if last is None:
    print("unknown - - no")
else:
    turn = records[last:]
    done = results(turn)
    tried = list(opens(turn))
    confirmed = [i for i, _ in tried if i in done and not FAILED.search(done[i][0])]
    opened = "yes" if confirmed else ("failed" if tried else "no")
    page = next((w for r in turn for w in written(r)), "-")
    if page == "-":
        # The turn's final reply pointing the owner at an artifact that exists is
        # presenting it, even when an earlier turn wrote it.
        final = next((t for t in (said(r) for r in reversed(turn)) if t.strip()), "")
        for hit in NAMED.finditer(final):
            if os.path.exists(absolute(hit.group(0))):
                page = hit.group(0)
                break
    # The one sanctioned way past an unopened page: a blocked ask filed to the owner.
    handed = "yes" if handed_off(turn, done, page) else "no"
    print(opened, absolute(page) if page != "-" else "-", last, handed)
