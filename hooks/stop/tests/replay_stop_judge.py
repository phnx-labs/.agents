#!/usr/bin/env python3
"""Replay the stop judge's real model call on labelled stops and print the confusion table.

usage: replay_stop_judge.py SAMPLE.json LABELS.json [--jobs N]

SAMPLE items carry {id, request, final}; LABELS items {id, label} with label
SHOULD_CONTINUE, STOP_OK or UNCLEAR, written blind to the judge. Each stop goes
through judge() exactly as the hook builds it. Tool facts are not replayed: a stop
counts as armed when its final message says a watcher or poller is set (live, the
hook reads the real background tasks and Monitor/ScheduleWakeup/CronCreate calls).
Costs one real model call per stop.
"""
import argparse
import importlib.util
import json
import re
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

spec = importlib.util.spec_from_file_location("stop_judge", Path(__file__).resolve().parent.parent / "08-stop-judge.py")
judge_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(judge_mod)
ARMED = re.compile(r"\bwatcher\b|\bwatching\b|wakes? me|poll(ing|er)", re.I)


def replay(item: dict, caps: dict) -> dict:
    armed = bool(ARMED.search(item["final"]))
    snapshot = {
        "latest_request": item["request"][-1200:],
        "tool_counts_this_turn": {},
        "watcher_or_background_task_armed": armed,
        "text_before_first_evidence": "",
        "final_message": item["final"][-2500:],
        "capability_manifest": judge_mod.manifest_text(caps),
    }
    judge_mod.DEADLINE[0] = judge_mod.time.monotonic() + judge_mod.HOOK_BUDGET_S
    verdict = judge_mod.judge(snapshot, caps)
    return {"id": item["id"], "push": verdict["verdict"] == "continue" and not armed,
            "outcome": verdict["outcome"], "latency_ms": verdict["latency_ms"], "step": verdict["step"]}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("sample")
    ap.add_argument("labels")
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()
    sample = json.load(open(args.sample))
    labels = {x["id"]: x["label"] for x in json.load(open(args.labels))}
    caps = judge_mod.capabilities()
    with ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda it: replay(it, caps), sample))
    table = Counter((labels[r["id"]], r["push"]) for r in results)
    print(f"model {judge_mod.MODEL}\nlabel            push  pass")
    for label in ("SHOULD_CONTINUE", "STOP_OK", "UNCLEAR"):
        print(f"{label:<16} {table[(label, True)]:>4} {table[(label, False)]:>5}")
    print("model errors:", Counter(r["outcome"] for r in results if r["outcome"] != "ok"))
    lat = sorted(r["latency_ms"] for r in results if r["latency_ms"])
    if lat:
        print("latency p50/p90 ms:", lat[len(lat) // 2], lat[int(len(lat) * 0.9)])
    for r in results:
        if (labels[r["id"]] == "SHOULD_CONTINUE") != r["push"]:
            print(f"#{r['id']} {labels[r['id']]} push={r['push']} :: {r['step'][:160]}")
    json.dump(results, sys.stderr, indent=1)


if __name__ == "__main__":
    main()
