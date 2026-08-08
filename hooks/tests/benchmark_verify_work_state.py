#!/usr/bin/env python3
"""Cold-process latency benchmark for the hook-owned state pilot."""

from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import tempfile
import time
from pathlib import Path


def sample(command: list[str], payload: bytes, env: dict[str, str], iterations: int) -> dict[str, float]:
    values: list[float] = []
    for _ in range(iterations):
        started = time.perf_counter()
        subprocess.run(command, input=payload, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env, check=True)
        values.append((time.perf_counter() - started) * 1000)
    values.sort()
    return {
        "median_ms": round(statistics.median(values), 2),
        "p95_ms": round(values[max(0, int(len(values) * 0.95) - 1)], 2),
        "max_ms": round(max(values), 2),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=40)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    helper = root / "stop" / "verify-work-state.py"
    wrapper = root / "user-prompt-submit" / "04-verify-work-state.py"
    with tempfile.TemporaryDirectory() as temp:
        temp_path = Path(temp)
        env = {**os.environ, "VERIFY_WORK_STATE_DB": str(temp_path / "state.db")}
        prompt = json.dumps({"session_id": "bench", "agent": "claude", "prompt": "hello"}).encode()
        transcript = temp_path / "transcript.jsonl"
        transcript.write_text(
            '{"type":"assistant","message":{"role":"assistant","content":'
            '[{"type":"tool_use","name":"Read","input":{"file_path":"/repo/a.ts"}}]}}\n'
        )
        stop = json.dumps({"session_id": "bench", "agent": "claude", "transcript_path": str(transcript)}).encode()
        result = {
            "iterations": args.iterations,
            "ordinary_tool_overhead_ms": 0,
            "prompt_collector": sample(["python3", str(wrapper)], prompt, env, args.iterations),
            "stop_evaluator": sample(["python3", str(helper), "evaluate"], stop, env, args.iterations),
        }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
