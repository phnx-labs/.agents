#!/usr/bin/env python3
"""stop-judge — Stop hook, LOG-ONLY. Interactive Claude sessions only.

Records, per interactive stop, what a model-based Stop judge WOULD block. It never
blocks: every path exits 0 and nothing is written to stdout or stderr. It adds no
latency to the turn: the foreground process only runs the scope checks, hands
the payload to a detached child (its own session, stdio on /dev/null) through a
0600 file in the disposable cache dir, and exits. The child deletes that file
as soon as it has read it, then does the judging below.

One small model call extracts structured items from the agent's final message
(handoffs, offers, waits, blocker and done claims; rubric in 08-stop-judge.txt,
installed beside this script as its data sidecar). Code, not the model, decides
would-block/pass from those items plus facts: the tool calls made since the
owner's latest message, the Stop payload's `background_tasks` / `session_crons`,
and the names of the secrets bundles on this machine.

State (see hooks/AGENTS.md "Hook-owned session state"):
  durable:    ~/.agents/.history/hooks/system.stop-judge/state.db
  disposable: ~/.agents/.cache/state/hooks/system.stop-judge/
No message text, prompt, quote, or credential is stored: a row holds codes,
counts, latency, and a sha256 of the final message for later joining.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOOK_ID = "system.stop-judge"
MODEL = "claude-haiku-4-5"
MODEL_TIMEOUT_S = 12.0
CATALOG_TIMEOUT_S = 2.0
MANIFEST_TTL_S = 600
RETENTION_DAYS = 30
BUSY_TIMEOUT_MS = 100
SCHEMA_VERSION = 1
NO_AUTH_EXIT = 77

# Tool calls that record or schedule work but gather no evidence (as in
# 07-investigate-first-gate.py).
BOOKKEEPING = {
    "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "ToolSearch",
    "ScheduleWakeup", "AskUserQuestion", "ExitPlanMode", "EnterPlanMode",
}
CMD_FAMILIES = ("secrets", "browser", "devices", "sessions")

# User records the owner did not type (as in 07-investigate-first-gate.py).
SYNTHETIC = re.compile(
    r"^\s*(?:<(?:system-reminder|task-notification|local-command-stdout|local-command-stderr"
    r"|local-command-caveat|bash-stdout|bash-stderr)>|Base directory for this skill:"
    r"|[A-Za-z]+ hook feedback:|\[Request interrupted|Caveat: )"
)

KINDS = {
    "merge_or_approve_pr", "publish_or_release", "run_command", "provide_credential",
    "provide_fact", "decide_scope", "decide_taste", "signoff_destructive",
    "permission_next_step", "offer_investigate", "offer_extra_work", "what_next",
    "announced_not_taken", "wait_claim", "blocker_claim", "done_claim", "agreement_first",
}
# Decisions that belong to the owner, and claims that hand nothing over: never block.
OWNER_KINDS = {
    "decide_scope", "decide_taste", "signoff_destructive", "offer_extra_work",
    "done_claim", "wait_claim",
}
EXCUSED_BLOCKER = re.compile(r"touch ?id|biometric|2fa|password|interactive login", re.I)

# What the judge would tell the agent if it blocked. Stored as the static
# template only; placeholders are never filled from message content.
HINT = {
    "zero-tools": "Nothing was read, run, or searched since the owner's message: investigate, then answer from evidence.",
    "merge_or_approve_pr": "Merge gates are satisfied by a non-author reviewer subagent: spawn it on {o}, post the verdict, merge.",
    "publish_or_release": "Publish it yourself: agents ssh {h} / secrets exec {b} --host {h} -- <release cmd>.",
    "run_command": "You have the same shell: run it and report the output.",
    "permission_next_step": "Already authorized: do it, then report.",
    "offer_investigate": "Do the check now instead of offering it.",
    "what_next": "Pick the next step of the goal and do it.",
    "announced_not_taken": "You announced a step and stopped: do it now.",
    "agreement_first": "Verify the claim with tools, then answer from evidence.",
    "provide_credential": "This machine has a matching secrets bundle: secrets exec {b} -- <cmd>.",
    "provide_fact": "Find it with tools before asking the owner.",
    "blocker_claim": "Verify the blocker with tools before handing it back.",
}

# Runs under `secrets exec auth`: exports the session account's setup-token (or
# the first one) as CLAUDE_CODE_OAUTH_TOKEN, drops the rest, execs the judge.
AUTH_SHIM = r"""
keys=$(env | sed -n 's/^\(CLAUDE_CODE_OAUTH_TOKEN_[A-Za-z0-9_]*\)=.*/\1/p' | sort)
k="$1"; shift
if [ -z "$k" ] || [ -z "$(printenv "$k")" ]; then k=$(printf '%s\n' "$keys" | sed -n 1p); fi
[ -n "$k" ] || exit 77
CLAUDE_CODE_OAUTH_TOKEN=$(printenv "$k"); export CLAUDE_CODE_OAUTH_TOKEN
for v in $keys; do unset "$v"; done
exec "$@"
"""


def _home() -> Path:
    return Path(os.path.expanduser("~"))


def db_path() -> Path:
    return _home() / ".agents" / ".history" / "hooks" / HOOK_ID / "state.db"


def cache_dir() -> Path:
    path = _home() / ".agents" / ".cache" / "state" / "hooks" / HOOK_ID
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


# --- snapshot (code only) ---------------------------------------------------


def owner_typed(record: dict) -> bool:
    """A user record carrying text or an image the owner sent."""
    if (record.get("type") != "user" or record.get("isMeta") or record.get("isSidechain")
            or record.get("isCompactSummary")):
        return False
    content = (record.get("message") or {}).get("content")
    if isinstance(content, str):
        return bool(content.strip()) and not SYNTHETIC.search(content)
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return False
        texts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        has_image = any(isinstance(b, dict) and b.get("type") == "image" for b in content)
        return has_image or any(t.strip() and not SYNTHETIC.search(t) for t in texts)
    return False


def read_records(path: str) -> list[dict]:
    records = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                rec = json.loads(line)
            except ValueError:
                continue  # blank or half-written last line
            if isinstance(rec, dict):
                records.append(rec)
    return records


def request_text(record: dict) -> str:
    content = (record.get("message") or {}).get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def turn_facts(records: list[dict]) -> tuple[str, dict[str, int], str]:
    """(latest owner request, tool counts since it, assistant text before the first evidence)."""
    start = max((i for i, r in enumerate(records) if owner_typed(r)), default=-1)
    request = request_text(records[start]) if start >= 0 else ""
    counts: dict[str, int] = {}
    names: dict[str, str] = {}
    opening: list[str] = []
    evidence = False
    for record in records[start + 1:]:
        content = (record.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if record.get("type") == "assistant" and kind == "text" and not evidence:
                if block.get("text", "").strip():
                    opening.append(block["text"])
            elif record.get("type") == "assistant" and kind == "tool_use":
                name = str(block.get("name", ""))
                names[block.get("id", "")] = name
                counts[name] = counts.get(name, 0) + 1
                command = str((block.get("input") or {}).get("command", ""))
                for family in CMD_FAMILIES:
                    if re.search(r"\b(agents\s+)?%s\b" % family, command):
                        counts["cmd:" + family] = counts.get("cmd:" + family, 0) + 1
            elif kind == "tool_result" and names.get(block.get("tool_use_id", "")) not in BOOKKEEPING:
                evidence = True
    return request, counts, " ".join(opening)


def _run_json(argv: list[str]):
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=CATALOG_TIMEOUT_S,
                             stdin=subprocess.DEVNULL, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except ValueError:
        return None


def capabilities() -> dict:
    """Bundle names, the `auth` bundle's backend, and browser profile names. Names
    only, never values; cached for MANIFEST_TTL_S; empty when the CLIs fail."""
    path = cache_dir() / "manifest.json"
    try:
        cached = json.loads(path.read_text())
        if time.time() - float(cached.get("at", 0)) < MANIFEST_TTL_S:
            return cached
    except (OSError, ValueError, AttributeError):
        pass
    bundles = _run_json(["secrets", "list", "--json"])
    profiles = _run_json(["browser", "profiles", "list", "--json"])
    rows = [b for b in bundles if isinstance(b, dict)] if isinstance(bundles, list) else []
    manifest = {
        "at": time.time(),
        "bundles": sorted({str(b.get("name")) for b in rows
                           if b.get("name") and not str(b.get("name")).startswith("__")}),
        "auth_backend": next((str(b.get("backend") or "") for b in rows if b.get("name") == "auth"), ""),
        "profiles": sorted({str(p.get("name")) for p in profiles if isinstance(p, dict) and p.get("name")})
        if isinstance(profiles, list) else [],
    }
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".manifest.")
    with os.fdopen(fd, "w") as handle:
        json.dump(manifest, handle)
    os.replace(tmp, path)
    return manifest


def manifest_text(caps: dict) -> str:
    parts = []
    if caps["bundles"]:
        parts.append("secrets bundles (names only): " + ", ".join(caps["bundles"]))
    if caps["profiles"]:
        parts.append("browser profiles: " + ", ".join(caps["profiles"]))
    return "; ".join(parts)


# --- model call -------------------------------------------------------------


def account_key() -> str:
    """The setup-token key name for the session's account: CLAUDE_CODE_OAUTH_TOKEN_<SLUG>."""
    config = os.environ.get("CLAUDE_CONFIG_DIR")
    path = Path(config) / ".claude.json" if config else _home() / ".claude.json"
    try:
        email = (json.loads(path.read_text()).get("oauthAccount") or {}).get("emailAddress") or ""
    except (OSError, ValueError, AttributeError):
        return ""
    if not email:
        return ""
    slug = email.upper().replace("@", "_AT_").replace(".", "_DOT_")
    return "CLAUDE_CODE_OAUTH_TOKEN_" + re.sub(r"[^A-Z0-9_]", "_", slug)


def model_timeout() -> float:
    try:
        return min(MODEL_TIMEOUT_S, float(os.environ.get("STOP_JUDGE_TIMEOUT_S", MODEL_TIMEOUT_S)))
    except ValueError:
        return MODEL_TIMEOUT_S


def judge(snapshot: dict, caps: dict) -> dict:
    """One extraction call. Returns {outcome, detail, items, latency_ms, in_tok, out_tok}."""
    result = {"outcome": "error", "detail": "", "items": [], "latency_ms": None,
              "in_tok": None, "out_tok": None}
    claude = os.environ.get("CLAUDE_CODE_EXECPATH") or shutil.which("claude")
    if not claude:
        result["detail"] = "no-claude"
        return result
    rubric_path = Path(__file__).resolve().with_suffix(".txt")
    try:
        rubric = rubric_path.read_text()
    except OSError:
        result["detail"] = "no-rubric"
        return result
    argv = [claude, "-p", "--setting-sources", "project", "--model", MODEL, "--tools", "",
            "--no-session-persistence", "--system-prompt", rubric, "--output-format", "json",
            "SNAPSHOT:\n" + json.dumps(snapshot, ensure_ascii=False)]
    env = dict(os.environ, MAX_THINKING_TOKENS="0")
    if not env.get("CLAUDE_CODE_OAUTH_TOKEN"):
        # Only a file-backed bundle reads without a Touch ID or passphrase prompt.
        if caps.get("auth_backend") != "file" or not shutil.which("secrets"):
            result["outcome"] = "no-auth"
            return result
        argv = ["secrets", "exec", "auth", "--", "sh", "-c", AUTH_SHIM, "sh", account_key()] + argv
    cwd = cache_dir() / "cwd"
    cwd.mkdir(exist_ok=True, mode=0o700)
    started = time.monotonic()
    try:
        proc = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, start_new_session=True)
    except OSError:
        result["detail"] = "spawn"
        return result
    try:
        stdout, _ = proc.communicate(timeout=model_timeout())
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        result["outcome"] = "timeout"
        result["latency_ms"] = int((time.monotonic() - started) * 1000)
        return result
    result["latency_ms"] = int((time.monotonic() - started) * 1000)
    if proc.returncode == NO_AUTH_EXIT:
        result["outcome"] = "no-auth"
        return result
    try:
        reply = json.loads(stdout)
    except ValueError:
        result["detail"] = f"exit-{proc.returncode}"
        return result
    if not isinstance(reply, dict):
        result["detail"] = "reply-shape"
        return result
    usage = reply.get("usage") or {}
    result["in_tok"] = sum(int(usage.get(k) or 0) for k in
                           ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    result["out_tok"] = int(usage.get("output_tokens") or 0)
    if reply.get("is_error"):
        result["detail"] = "is_error"
        return result
    items = parse_items(str(reply.get("result") or ""))
    if items is None:
        result["outcome"] = "parse-fail"
        return result
    result["outcome"] = "ok"
    result["items"] = items
    return result


def parse_items(text: str):
    """The `items` list of the first JSON object in the model's reply, or None."""
    start = text.find("{")
    if start < 0:
        return None
    try:
        obj, _ = json.JSONDecoder().raw_decode(text[start:])
    except ValueError:
        return None
    items = obj.get("items") if isinstance(obj, dict) else None
    if not isinstance(items, list):
        return None
    return [it for it in items if isinstance(it, dict)]


# --- decision (code) --------------------------------------------------------


def bundle_for(text: str, bundles: list[str]):
    words = set(re.findall(r"[a-z0-9]+", text.lower()))
    for bundle in bundles:
        stem = re.split(r"[.\-]", bundle.lower())[0]
        if len(stem) >= 3 and (stem in words or any(w.startswith(stem) for w in words)):
            return bundle
    return None


def decide(counts: dict[str, int], items: list[dict], background_live: bool,
           bundles: list[str]) -> tuple[bool, str]:
    calls = sum(v for k, v in counts.items() if not k.startswith("cmd:") and k not in BOOKKEEPING)
    if calls == 0:
        return True, "zero-tools"
    for item in items:
        kind = item.get("kind")
        blob = " ".join(str(item.get(x, "")) for x in ("quote", "object", "credential", "host"))
        if kind in OWNER_KINDS:
            continue
        if kind == "announced_not_taken":
            # A live background task or session cron will re-invoke the agent.
            if background_live or item.get("actor") not in (None, "agent"):
                continue
            return True, kind
        if kind == "provide_credential":
            if bundle_for(blob, bundles):
                return True, kind
            continue
        if kind == "blocker_claim":
            if EXCUSED_BLOCKER.search(blob):
                continue
            return True, kind
        if kind in HINT:
            return True, kind
    return False, "pass"


# --- record -----------------------------------------------------------------


def record(row: dict) -> None:
    path = db_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    db = sqlite3.connect(str(path), timeout=BUSY_TIMEOUT_MS / 1000)
    try:
        db.execute(f"PRAGMA busy_timeout={BUSY_TIMEOUT_MS}")
        db.execute("PRAGMA journal_mode=WAL")
        db.executescript(
            """
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS judgments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_key TEXT NOT NULL,
              ts_ms INTEGER NOT NULL,
              would_block INTEGER NOT NULL,
              reason TEXT NOT NULL,
              hint TEXT NOT NULL,
              item_kinds TEXT NOT NULL,
              background_live INTEGER NOT NULL,
              latency_ms INTEGER,
              input_tokens INTEGER,
              output_tokens INTEGER,
              outcome TEXT NOT NULL,
              detail TEXT NOT NULL,
              final_sha256 TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_judgments_ts ON judgments(ts_ms);
            """
        )
        db.execute("INSERT OR IGNORE INTO meta(key, value) VALUES('schema_version', ?)", (str(SCHEMA_VERSION),))
        db.execute("DELETE FROM judgments WHERE ts_ms < ?", (row["ts_ms"] - RETENTION_DAYS * 86_400_000,))
        db.execute(
            "INSERT INTO judgments(session_key, ts_ms, would_block, reason, hint, item_kinds,"
            " background_live, latency_ms, input_tokens, output_tokens, outcome, detail, final_sha256)"
            " VALUES(:session_key, :ts_ms, :would_block, :reason, :hint, :item_kinds,"
            " :background_live, :latency_ms, :input_tokens, :output_tokens, :outcome, :detail, :final_sha256)",
            row,
        )
        db.commit()
    finally:
        db.close()
    os.chmod(path, 0o600)


def judge_stop(payload: dict) -> None:
    """The detached child's work: snapshot, catalog, model call, decision, row."""
    final = payload["last_assistant_message"]
    request, counts, opening = turn_facts(read_records(payload["transcript_path"]))
    caps = capabilities()
    snapshot = {
        "latest_request": request[:1200],
        "tool_counts_this_turn": counts,
        "text_before_first_evidence": opening[:500],
        "final_message": final[-2500:],
        "capability_manifest": manifest_text(caps),
    }
    background_live = bool(payload.get("background_tasks") or payload.get("session_crons"))
    verdict = judge(snapshot, caps)
    kinds = [str(it.get("kind")) if it.get("kind") in KINDS else "other" for it in verdict["items"]]
    if verdict["outcome"] == "ok":
        would_block, reason = decide(counts, verdict["items"], background_live, caps["bundles"])
    else:
        # Without items only the tool-count fact can be judged.
        would_block, reason = decide(counts, [], background_live, caps["bundles"])
        reason = reason if would_block else "unjudged"
    record({
        "session_key": f"claude:{payload['session_id']}",
        "ts_ms": int(time.time() * 1000),
        "would_block": int(would_block),
        "reason": reason,
        "hint": HINT.get(reason, ""),
        "item_kinds": ",".join(kinds),
        "background_live": int(background_live),
        "latency_ms": verdict["latency_ms"],
        "input_tokens": verdict["in_tok"],
        "output_tokens": verdict["out_tok"],
        "outcome": verdict["outcome"],
        "detail": verdict["detail"],
        "final_sha256": hashlib.sha256(final.encode("utf-8", "replace")).hexdigest(),
    })


def pending_dir() -> Path:
    path = cache_dir() / "pending"
    path.mkdir(exist_ok=True, mode=0o700)
    return path


def child(handoff: str) -> None:
    """Read and delete the handoff file, then judge. Only files in pending/ are accepted."""
    path = Path(handoff).resolve()
    if path.parent != pending_dir().resolve():
        return
    try:
        payload = json.loads(path.read_text())
    finally:
        path.unlink()
    judge_stop(payload)


def main() -> None:
    """Foreground: scope checks only, then hand off to a detached child and return."""
    if os.environ.get("CLAUDE_CODE_ENTRYPOINT") != "cli":
        return
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict) or payload.get("stop_hook_active"):
        return
    final = payload.get("last_assistant_message")
    if (not isinstance(final, str) or not final.strip() or not payload.get("session_id")
            or not payload.get("transcript_path")):
        return
    fd, handoff = tempfile.mkstemp(dir=pending_dir(), prefix="stop-", suffix=".json")
    with os.fdopen(fd, "w") as handle:
        json.dump(payload, handle)
    try:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "--judge", handoff],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True, close_fds=True,
        )
    except OSError:
        os.unlink(handoff)


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--judge":
            child(sys.argv[2])
        else:
            main()
    except BaseException:  # noqa: BLE001 — log-only: no path may block or wedge a stop
        pass
    sys.exit(0)
