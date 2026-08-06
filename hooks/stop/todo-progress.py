#!/usr/bin/env python3
"""Fold a session's checklist state from its transcript and report what remains.

Reads a Claude/Codex/Kimi/etc. transcript (argv[1]) and prints a one-line JSON
object to stdout describing the CURRENT to-do / task list:

    {"total": N, "remaining": M, "next": "<title>", "in_progress": "<title>"}

`remaining` counts items that are NOT completed (pending + in_progress). `next`
is the item the agent should advance now: the in_progress one if any, else the
first pending one. When the session used no checklist, `total` is 0.

This mirrors the cross-harness parser the CLI already ships
(`extractTodoProgressFromEvents` / `extractTodoProgress` in
apps/cli/src/lib/session/state.ts): it folds both the SNAPSHOT checklist tools
(Claude `TodoWrite`, Kimi `TodoList`, Droid/OpenCode `todo_write`, Codex
`update_plan` — each call REPLACES the list) and Claude's event-log task tools
(`TaskCreate` appends one pending task; `TaskUpdate` mutates/deletes it by the
sequential id the tool assigns: "1", "2", ...). Kept a standalone script (not an
inline `python3 -c` heredoc) so it is unit-testable and side-steps the bash
quoting traps the shell hook documents.

Fails open: any parse error prints an empty/zero result and exits 0, so the Stop
hook that calls it never blocks a stop because this probe choked.
"""

import json
import sys

# Snapshot tools: the whole list is the tool input; the latest call wins.
SNAPSHOT_TODO_TOOLS = {"TodoWrite", "TodoList", "todo_write", "update_plan"}
TASK_CREATE_TOOL = "TaskCreate"
TASK_UPDATE_TOOL = "TaskUpdate"


def _is_completed(status):
    # Claude/Codex write "completed"; Kimi writes "done".
    return status in ("completed", "done")


def _content(item):
    for key in ("content", "text", "step", "title", "subject", "description", "activeForm"):
        val = item.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    return ""


def _iter_tool_uses(path):
    with open(path) as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            msg = rec.get("message") if isinstance(rec.get("message"), dict) else rec
            content = msg.get("content") if isinstance(msg, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    yield block.get("name") or "", block.get("input") or {}


def fold(path):
    """Return the folded checklist items (list of {content,status})."""
    items = []          # event-log tasks: [{taskId, content, status}]
    next_task_id = 1
    saw_checklist = False
    for name, inp in _iter_tool_uses(path):
        input_obj = inp.get("input") if isinstance(inp.get("input"), dict) else inp
        if name in SNAPSHOT_TODO_TOOLS:
            raw = input_obj.get("todos")
            if not isinstance(raw, list):
                raw = input_obj.get("plan")
            if isinstance(raw, list):
                items = [dict(t) for t in raw if isinstance(t, dict)]
                saw_checklist = True
            continue
        if name == TASK_CREATE_TOOL:
            content = _content(input_obj)
            if not content:
                continue
            items.append({"taskId": str(next_task_id), "content": content, "status": "pending"})
            next_task_id += 1
            saw_checklist = True
            continue
        if name == TASK_UPDATE_TOOL:
            task_id = str(input_obj.get("taskId", input_obj.get("task_id", "")))
            idx = next((i for i, it in enumerate(items) if str(it.get("taskId", "")) == task_id), -1)
            if idx < 0:
                continue
            if input_obj.get("status") == "deleted":
                items.pop(idx)
                continue
            prior = items[idx]
            updated = dict(prior)
            for key in ("subject", "description", "activeForm", "status"):
                val = input_obj.get(key)
                if isinstance(val, str) and val:
                    updated["content" if key == "subject" else key] = val
            items[idx] = updated
    return items if saw_checklist else None


def summarize(items):
    if not items:
        return {"total": 0, "remaining": 0, "next": "", "in_progress": ""}
    total = len(items)
    in_progress = ""
    next_title = ""
    for it in items:
        status = it.get("status")
        if not _is_completed(status) and status == "in_progress" and not in_progress:
            in_progress = _content(it)
    for it in items:
        if not _is_completed(it.get("status")):
            next_title = in_progress or _content(it)
            break
    remaining = sum(1 for it in items if not _is_completed(it.get("status")))
    return {"total": total, "remaining": remaining, "next": next_title, "in_progress": in_progress}


def main():
    try:
        items = fold(sys.argv[1])
        print(json.dumps(summarize(items)))
    except Exception:
        print(json.dumps({"total": 0, "remaining": 0, "next": "", "in_progress": ""}))


if __name__ == "__main__":
    main()
