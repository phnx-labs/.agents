#!/usr/bin/env python3
"""Record a privacy-preserving goal boundary for verify-work-complete."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


def helper_path() -> Path | None:
    here = Path(__file__).resolve().parent
    for candidate in (here / "verify-work-state.py", here.parent / "stop" / "verify-work-state.py"):
        if candidate.is_file():
            return candidate
    return None


def main() -> int:
    helper = helper_path()
    if helper is None:
        return 0
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            return 0
        spec = importlib.util.spec_from_file_location("verify_work_state", helper)
        if spec is None or spec.loader is None:
            return 0
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        module.record_prompt(payload, module.default_db_path())
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
