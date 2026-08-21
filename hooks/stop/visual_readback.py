#!/usr/bin/env python3
"""Conservative transcript evidence for visual artifact delivery and read-back."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Iterable


VISUAL_SUFFIXES = (".html", ".png", ".jpg", ".jpeg", ".svg", ".pdf")
VISUAL_CLAIMS = (
    "you're looking at", "you’re looking at", "quick tour of", "here's the mockup",
    "here’s the mockup", "here's the tour", "here’s the tour", "on the left",
    "the header shows", "renders as", "here's what you'll see", "here’s what you’ll see",
)
SHIP_RE = re.compile(
    r"\b(?:scp|rsync|agents\s+share|open|xdg-open)\b"
    r"|agents\s+ssh\b[^\n]*\bopen\b"
    # `agents browser navigate --url file://<artifact>` (and `browser start --url`)
    # is now the recommended way to show the user a rendered plan/visual in one
    # reused tab instead of a raw `open`. Delivery is still only registered when
    # the command references a visual path (see `_derived_paths` below), so this
    # never false-positives on a bare `browser start` that shows no artifact.
    r"|agents\s+browser\s+(?:navigate|start)\b",
    re.I,
)
PATH_RE = re.compile(r"(?:file://)?(?P<path>(?:/|\.?\.?/)?[^\s'\"<>|;&]+\.(?:html|png|jpe?g|svg|pdf))", re.I)
WRITE_NAMES = {"write", "edit", "multiedit", "notebookedit", "apply_patch", "applypatch"}


def _blocks(record: dict[str, Any]) -> Iterable[dict[str, Any]]:
    item = record.get("item")
    if isinstance(item, dict) and item.get("type") == "command_execution":
        yield {"type": "tool_use", "id": item.get("id"), "name": "bash", "input": {"command": item.get("command") or ""}}
        output = item.get("aggregated_output")
        if output is not None:
            yield {"type": "custom_tool_call_output", "call_id": item.get("id"), "output": output}
    payload = record.get("payload") if record.get("type") in {"response_item", "event_msg"} else record
    if not isinstance(payload, dict):
        return
    message = payload.get("message") if isinstance(payload.get("message"), dict) else payload
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, list):
        yield from (block for block in content if isinstance(block, dict))
    if payload.get("type") in {"function_call", "custom_tool_call"}:
        yield {
            "type": "tool_use", "id": payload.get("call_id") or payload.get("id"),
            "name": payload.get("name") or "", "input": payload.get("arguments") or payload.get("input") or {},
        }
    if payload.get("type") in {"function_call_output", "custom_tool_call_output"}:
        yield payload


def _inputs(block: dict[str, Any]) -> dict[str, Any]:
    value = block.get("input") or block.get("arguments") or {}
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except Exception:
            return {"command": value}
    return value if isinstance(value, dict) else {}


def _paths(text: str) -> set[str]:
    return {match.group("path").removeprefix("file://").rstrip(",):") for match in PATH_RE.finditer(text)}


def _derived_paths(command: str) -> set[str]:
    paths = _paths(command)
    if re.search(r"\bartifacts\s+render\b", command):
        paths.update(path[:-3] + ".html" for path in list(paths) if path.lower().endswith(".md"))
    return paths


def _contains_image(value: Any) -> bool:
    if isinstance(value, dict):
        kind = str(value.get("type") or "").lower()
        if kind in {"image", "input_image", "image_url"} or "image_url" in value:
            return True
        return any(_contains_image(child) for child in value.values())
    if isinstance(value, list):
        return any(_contains_image(child) for child in value)
    return False


def inspect_transcript(transcript_path: str, start_offset: int = 0) -> dict[str, Any]:
    """Return only positive evidence; malformed/unsupported transcripts fail open."""
    result: dict[str, Any] = {
        "visual_authored": False, "visual_delivered": False, "visual_read_back": False,
        "latest_visual": "", "parser_supported": False,
    }
    path = Path(transcript_path)
    if not path.is_file():
        return result
    authored: dict[str, int] = {}
    delivered: set[str] = set()
    reads: dict[str, tuple[str, int]] = {}
    producers: dict[str, int] = {}
    readbacks: list[tuple[str, int]] = []
    index = 0
    try:
        with path.open("rb") as handle:
            handle.seek(max(0, start_offset))
            for raw in handle:
                record = json.loads(raw.decode("utf-8", "replace"))
                result["parser_supported"] = True
                for block in _blocks(record):
                    index += 1
                    kind = str(block.get("type") or "").lower()
                    if kind in {"tool_use", "function_call", "custom_tool_call"}:
                        name = str(block.get("name") or block.get("tool") or "").lower()
                        inputs = _inputs(block)
                        command = str(inputs.get("command") or inputs.get("cmd") or "")
                        target = str(inputs.get("file_path") or inputs.get("path") or "")
                        candidates = _derived_paths(command)
                        if target.lower().endswith(VISUAL_SUFFIXES):
                            candidates.add(target)
                        produces_visual = bool(
                            name in WRITE_NAMES
                            or re.search(r"(?:>|\b(?:artifacts\s+render|agents\s+browser\s+screenshot)\b)", command)
                        )
                        if produces_visual:
                            for candidate in candidates:
                                authored[candidate] = index
                        if SHIP_RE.search(command):
                            delivered.update(candidates)
                        call_id = str(block.get("id") or block.get("call_id") or "")
                        if call_id and produces_visual:
                            producers[call_id] = index
                        if call_id and target.lower().endswith(VISUAL_SUFFIXES):
                            reads[call_id] = (target, index)
                    elif kind in {"tool_result", "function_call_output", "custom_tool_call_output"}:
                        call_id = str(block.get("tool_use_id") or block.get("call_id") or "")
                        if call_id in producers:
                            output_paths = _paths(json.dumps(block.get("content") or block.get("output") or ""))
                            for output_path in output_paths:
                                authored[output_path] = index
                        if call_id in reads and _contains_image(block):
                            read_path, read_index = reads[call_id]
                            readbacks.append((read_path, max(read_index, index)))
    except (OSError, ValueError, json.JSONDecodeError):
        return result
    if authored:
        latest = max(authored, key=authored.get)
        result["visual_authored"] = True
        result["latest_visual"] = latest
        latest_index = authored[latest]
        result["visual_read_back"] = any(
            read_index > latest_index and Path(read_path).name == Path(latest).name
            for read_path, read_index in readbacks
        )
        result["visual_delivered"] = any(
            Path(sent).name == Path(written).name for sent in delivered for written in authored
        )
    return result


def makes_visual_claim(message: str) -> bool:
    lowered = message.lower()
    return any(token in lowered for token in VISUAL_CLAIMS)
