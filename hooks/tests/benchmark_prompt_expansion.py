#!/usr/bin/env python3
"""Cold-process benchmark for the two UserPromptSubmit expansion hooks."""

import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import time


HOOKS = Path(__file__).parents[1] / "user-prompt-submit"
PROMPTCUT = HOOKS / "02-expand-prompt-user-shortcuts.sh"
BANG = HOOKS / "02-expand-prompt-bang-commands.sh"


def sample(command: list[str], payload: dict, runs: int) -> list[float]:
    encoded = json.dumps(payload)
    durations = []
    for _ in range(runs):
        started = time.perf_counter_ns()
        subprocess.run(command, input=encoded, text=True, capture_output=True, check=True)
        durations.append((time.perf_counter_ns() - started) / 1_000_000)
    return durations


def report(label: str, values: list[float]) -> None:
    ordered = sorted(values)
    p95 = ordered[max(0, round(len(ordered) * 0.95) - 1)]
    print(f"{label:35} median={statistics.median(values):7.2f}ms  p95={p95:7.2f}ms")


def main() -> None:
    runs = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    with tempfile.TemporaryDirectory() as home:
        promptcuts = Path(home) / ".agents/.system/hooks/promptcuts.yaml"
        promptcuts.parent.mkdir(parents=True)
        promptcuts.write_text('shortcuts:\n  "#tok": "EXPANSION"\n')
        env = os.environ | {"HOME": home}

        def promptcut_sample(payload: dict) -> list[float]:
            encoded = json.dumps(payload)
            durations = []
            for _ in range(runs):
                started = time.perf_counter_ns()
                subprocess.run(["bash", str(PROMPTCUT)], input=encoded, text=True, capture_output=True, check=True, env=env)
                durations.append((time.perf_counter_ns() - started) / 1_000_000)
            return durations

        report("promptcut: no marker", promptcut_sample({"prompt": "ordinary prompt"}))
        report("promptcut: !! marker + YAML", promptcut_sample({"prompt": "!!tok"}))

    report("bang: no marker", sample(["bash", str(BANG)], {"prompt": "ordinary prompt"}, runs))
    parallel = sample(
        ["bash", str(BANG)],
        {"prompt": "`! sleep 0.1; printf a` `! sleep 0.1; printf b` `! sleep 0.1; printf c`", "cwd": "/tmp"},
        max(5, runs // 3),
    )
    report("bang: 3 x 100ms commands", parallel)


if __name__ == "__main__":
    main()
