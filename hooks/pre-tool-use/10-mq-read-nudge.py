#!/usr/bin/env python3
"""PreToolUse hook (Read): nudge `mq` before the agent reads a large file whole.

Fires only on the Read tool. When the target is a large (>=16 KiB) file in a
format `mq` supports (code, docs, data, Office), it injects a one-time — per
session + per file — suggestion to extract just the needed part in a single mq
call (`mq <file> '.section("X") | .text'` / `.search`) instead of reading the
whole file. It explicitly steers AWAY from the `.tree`->`.section` dance for a
named target: an A/B measured that two-call dance at ~2.3x the cost and ~2x the
latency of just reading, while one-call mq is ~18% cheaper AND faster. `.tree`
is for discovering unknown structure or amortized repeat access only.

Advisory only: it NEVER blocks the read (always exit 0). Fail-open everywhere —
any error is swallowed so a nudge can never break a tool call.

Skips (already efficient, or not mq-addressable):
  - a targeted Read (offset/limit set) — the agent is already narrowing.
  - small files (<16 KiB) — reading whole is fine.
  - unsupported/binary formats (images, archives, no extension).
  - a file already nudged this session (dedup marker in tmp).

Why: a fleet audit found `mq` invoked 0 times across 835 sessions / 3 days while
62% of tool calls were context reads — whole-file dumps and the same file re-read
up to 34x per session. The tool already collapses that; this closes the reach-gap
at the moment of the read. Claude only — relies on PreToolUse additionalContext.
"""
import os
import sys
import json
import hashlib
import tempfile

MIN_BYTES = 16 * 1024  # ~200-400 lines depending on line length; below this, reading whole is fine

# formats mq can map/extract (from `mq --help`), lowercased, no dot
SUPPORTED = {
    # docs
    "md", "mdx", "markdown", "html", "htm", "pdf", "rst", "adoc",
    # data
    "json", "jsonl", "ndjson", "yaml", "yml", "csv", "tsv", "xml", "toml",
    "xlsx", "docx", "pptx",
    # code
    "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "rs", "java", "kt",
    "c", "cc", "cpp", "h", "hpp", "swift", "rb", "php", "sh", "bash", "zsh",
    "lua", "scala", "cs", "sql",
}


def _marker_for(session_id, path):
    key = hashlib.sha1(f"{session_id}:{path}".encode("utf-8", "replace")).hexdigest()
    d = os.path.join(tempfile.gettempdir(), "agents-mq-nudge")
    return d, os.path.join(d, key)


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        return  # fail open

    if payload.get("tool_name") != "Read":
        return
    ti = payload.get("tool_input") or {}
    if not isinstance(ti, dict):
        return

    # Already a targeted read — the agent is narrowing; don't nudge.
    if ti.get("offset") is not None or ti.get("limit") is not None:
        return

    path = ti.get("file_path")
    if not isinstance(path, str) or not path:
        return

    ext = os.path.splitext(path)[1].lstrip(".").lower()
    if ext not in SUPPORTED:
        return

    try:
        size = os.path.getsize(path)
    except OSError:
        return
    if size < MIN_BYTES:
        return

    session_id = str(payload.get("session_id") or os.getppid())
    mdir, marker = _marker_for(session_id, os.path.abspath(path))
    try:
        os.makedirs(mdir, exist_ok=True)
        # O_CREAT|O_EXCL: first nudge wins; a second read of the same file no-ops.
        fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
    except FileExistsError:
        return  # already nudged this file this session
    except OSError:
        pass  # can't write marker — still nudge once (fail open toward helping)

    kb = size // 1024
    note = (
        f"[mq] About to read `{os.path.basename(path)}` whole (~{kb} KiB). If you "
        f"already know the part you need, get it in ONE mq call instead of reading "
        f"the whole file:\n"
        f"  mq {path} '.section(\"<name>\") | .text'   (a specific function/section)\n"
        f"  mq {path} '.search(\"<term>\")'            (find + show matches)\n"
        f"Go straight to that one call — do NOT run `.tree` first for a target you "
        f"can already name (the map-then-extract dance costs more than just reading). "
        f"Run `mq {path} .tree` first ONLY to discover an unknown structure, or if "
        f"you'll read this file more than once. mq handles this format ({ext}) — code, "
        f"docs, data, Office. If you genuinely need the whole file, just read it."
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": note,
        }
    }))


if __name__ == "__main__":
    main()
