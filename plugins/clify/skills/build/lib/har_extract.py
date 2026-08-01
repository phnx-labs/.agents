#!/usr/bin/env python3
"""Extract a deduped endpoint catalog from a HAR capture.

Reads a HAR 1.2 file (from `agents browser har --with-bodies`, or
`agents browser requests --format har`) and emits a JSON list of distinct API
endpoint candidates — one per (method, path-template) — each carrying a sample
request/response so a command schema can be inferred downstream.

    har_extract.py capture.har                    # catalog JSON on stdout
    har_extract.py capture.har --host api.x.co     # only that hostname
    har_extract.py capture.har --json-only         # drop non-JSON responses
    har_extract.py - < capture.har                 # read HAR from stdin

The interesting logic is path-templating: /users/123/posts/9 and /users/7/posts/2
collapse to one endpoint GET /users/:id/posts/:id, so the catalog lists real
endpoints, not one row per id.
"""
import argparse
import json
import re
import sys
from urllib.parse import urlsplit, parse_qsl

_UUID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
_HEXLONG = re.compile(r"^[0-9a-fA-F]{16,}$")


def _is_id(seg: str) -> bool:
    """A path segment that looks like an identifier (collapsed to :id)."""
    if not seg:
        return False
    if seg.isdigit():
        return True
    if _UUID.match(seg):
        return True
    if _HEXLONG.match(seg):
        return True
    return False


def normalize_path(path: str) -> str:
    return "/".join(":id" if _is_id(p) else p for p in path.split("/"))


def _truncate(s, n: int = 2000):
    if s is None:
        return None
    return s if len(s) <= n else s[:n] + "…[truncated]"


def _looks_json(content_type) -> bool:
    return bool(content_type) and "json" in content_type.lower()


def _header(headers, name: str):
    lname = name.lower()
    for h in headers or []:
        if h.get("name", "").lower() == lname:
            return h.get("value")
    return None


def extract(har: dict, host: str | None = None, json_only: bool = False) -> list[dict]:
    entries = har.get("log", {}).get("entries", [])
    catalog: dict[str, dict] = {}
    for e in entries:
        req = e.get("request", {})
        resp = e.get("response", {})
        url = req.get("url", "")
        sp = urlsplit(url)
        if not sp.scheme.startswith("http"):
            continue
        if host and sp.hostname != host:
            continue
        resp_ct = _header(resp.get("headers", []), "content-type")
        if json_only and not _looks_json(resp_ct):
            continue
        method = req.get("method", "GET").upper()
        template = normalize_path(sp.path)
        key = f"{method} {sp.hostname}{template}"
        if key in catalog:
            catalog[key]["count"] += 1
            continue
        post = req.get("postData") or {}
        content = resp.get("content") or {}
        catalog[key] = {
            "method": method,
            "host": sp.hostname,
            "path_template": template,
            "example_path": sp.path,
            "query_keys": sorted({k for k, _ in parse_qsl(sp.query)}),
            "request_content_type": _header(req.get("headers", []), "content-type"),
            "request_sample": _truncate(post.get("text")),
            "status": resp.get("status"),
            "response_content_type": resp_ct,
            "response_sample": _truncate(content.get("text")),
            "count": 1,
        }
    return sorted(catalog.values(), key=lambda c: (c["host"] or "", c["path_template"], c["method"]))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Extract a deduped endpoint catalog from a HAR file.")
    ap.add_argument("har", help="path to HAR file, or - for stdin")
    ap.add_argument("--host", help="only include entries for this hostname")
    ap.add_argument("--json-only", action="store_true", help="drop non-JSON responses")
    args = ap.parse_args(argv)

    raw = sys.stdin.read() if args.har == "-" else open(args.har, encoding="utf-8").read()
    har = json.loads(raw)
    catalog = extract(har, host=args.host, json_only=args.json_only)
    json.dump(catalog, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
