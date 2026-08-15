#!/usr/bin/env python3
"""Hook-owned, session-keyed SQLite state for verify-work-complete.

This is deliberately not an agents-cli state service. The hook owns its schema,
migrations, retention, and interpretation. The shared convention is only:

  durable: ~/.agents/.history/hooks/<stable-hook-id>/state.db
  cache:   ~/.agents/.cache/state/hooks/<stable-hook-id>/

UserPromptSubmit records a privacy-preserving goal boundary and transcript offset.
Stop folds positive evidence from that goal's transcript suffix, maintains a
session-owned entity ledger, and records the decision and gate outcome. No raw
prompts, transcript text, commands, or tool output are stored.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path
from typing import Any, Iterable

from visual_readback import inspect_transcript


HOOK_ID = "system.verify-work-complete"
SCHEMA_VERSION = 2
RETENTION_DAYS = 30
BUSY_TIMEOUT_MS = 100
PR_URL = re.compile(r"https://github\.com/[\w.-]+/[\w.-]+/pull/\d+")
TICKET_ID = re.compile(r"\bRUSH-\d+\b", re.IGNORECASE)
REPO_WRITE_TOOLS = {
    "write", "edit", "multiedit", "notebookedit", "apply_patch", "applypatch",
}
READ_TOOLS = {
    "read", "grep", "glob", "websearch", "webfetch", "search", "find", "ls",
}


def _now_ms() -> int:
    return int(time.time() * 1000)


def _home() -> Path:
    return Path(os.path.expanduser("~"))


def default_db_path() -> Path:
    override = os.environ.get("VERIFY_WORK_STATE_DB")
    if override:  # Hermetic tests only; production never sets this.
        return Path(override)
    return _home() / ".agents" / ".history" / "hooks" / HOOK_ID / "state.db"


def _connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.parent.chmod(0o700)
    except OSError:
        pass
    db = sqlite3.connect(str(path), timeout=BUSY_TIMEOUT_MS / 1000)
    db.execute(f"PRAGMA busy_timeout={BUSY_TIMEOUT_MS}")
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS session_aliases (
          alias_kind TEXT NOT NULL,
          alias_value TEXT NOT NULL,
          session_key TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          PRIMARY KEY(alias_kind, alias_value)
        );
        CREATE TABLE IF NOT EXISTS goal_boundaries (
          session_key TEXT NOT NULL,
          ordinal INTEGER NOT NULL,
          prompt_sha256 TEXT NOT NULL,
          transcript_offset INTEGER NOT NULL DEFAULT 0,
          created_at_ms INTEGER NOT NULL,
          PRIMARY KEY(session_key, ordinal)
        );
        CREATE TABLE IF NOT EXISTS session_state (
          session_key TEXT PRIMARY KEY,
          harness TEXT NOT NULL,
          native_session_id TEXT,
          launch_id TEXT,
          goal_ordinal INTEGER NOT NULL DEFAULT 0,
          context_kind TEXT NOT NULL,
          evidence_json TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS decisions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_key TEXT NOT NULL,
          goal_ordinal INTEGER NOT NULL,
          decision TEXT NOT NULL,
          reason TEXT NOT NULL,
          evidence_sha256 TEXT NOT NULL,
          created_at_ms INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_decisions_session
          ON decisions(session_key, created_at_ms);
        CREATE TABLE IF NOT EXISTS owned_entities (
          session_key TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          acquired_goal_ordinal INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          PRIMARY KEY(session_key, entity_type, entity_id)
        );
        CREATE TABLE IF NOT EXISTS gate_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_key TEXT NOT NULL,
          goal_ordinal INTEGER NOT NULL,
          gate_name TEXT NOT NULL,
          outcome TEXT NOT NULL,
          reason_code TEXT NOT NULL,
          created_at_ms INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_gate_events_session
          ON gate_events(session_key, created_at_ms);
        """
    )
    row = db.execute("SELECT value FROM meta WHERE key='schema_version'").fetchone()
    if row is None:
        db.execute("INSERT INTO meta(key,value) VALUES('schema_version',?)", (str(SCHEMA_VERSION),))
    elif int(row[0]) == 1:
        columns = {str(value[1]) for value in db.execute("PRAGMA table_info(goal_boundaries)")}
        if "transcript_offset" not in columns:
            db.execute("ALTER TABLE goal_boundaries ADD COLUMN transcript_offset INTEGER NOT NULL DEFAULT 0")
        db.execute("UPDATE meta SET value=? WHERE key='schema_version'", (str(SCHEMA_VERSION),))
    elif int(row[0]) != SCHEMA_VERSION:
        raise RuntimeError(f"unsupported schema version {row[0]}")
    db.commit()
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return db


def _connect_recovering(path: Path) -> sqlite3.Connection:
    try:
        return _connect(path)
    except sqlite3.DatabaseError:
        if not path.exists():
            raise
        suffix = f".corrupt-{time.time_ns()}"
        for candidate in (path, Path(f"{path}-wal"), Path(f"{path}-shm")):
            if candidate.exists():
                candidate.replace(candidate.with_name(candidate.name + suffix))
        return _connect(path)


def _harness(payload: dict[str, Any]) -> str:
    explicit = payload.get("agent") or payload.get("agent_name") or payload.get("agentName")
    if isinstance(explicit, str) and explicit.strip():
        return explicit.strip().lower()
    if os.environ.get("CLAUDECODE"):
        return "claude"
    if os.environ.get("CODEX_HOME"):
        return "codex"
    if os.environ.get("GROK_SESSION_ID"):
        return "grok"
    return "unknown"


def _identity(payload: dict[str, Any]) -> tuple[str, str, str, str]:
    harness = _harness(payload)
    native = str(payload.get("session_id") or payload.get("sessionId") or "").strip()
    launch = str(payload.get("launch_id") or payload.get("launchId") or os.environ.get("AGENT_LAUNCH_ID") or "").strip()
    if native:
        return f"{harness}:{native}", harness, native, launch
    if launch:
        return f"launch:{launch}", harness, "", launch
    return "", harness, "", ""


def _blocks(record: dict[str, Any]) -> Iterable[dict[str, Any]]:
    item = record.get("item")
    if isinstance(item, dict) and item.get("type") == "command_execution":
        yield {
            "type": "tool_use",
            "name": "Bash",
            "input": {"command": item.get("command") or ""},
        }
    payload = record
    if record.get("type") in {"response_item", "event_msg"} and isinstance(record.get("payload"), dict):
        payload = record["payload"]
    message = payload.get("message") if isinstance(payload.get("message"), dict) else payload
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict):
                yield block
    tool_name = payload.get("name") if payload.get("type") in {"function_call", "custom_tool_call"} else None
    if tool_name:
        yield {"type": "tool_use", "name": tool_name, "input": payload.get("arguments") or payload.get("input") or {}}


def _tool_input(block: dict[str, Any]) -> dict[str, Any]:
    value = block.get("input") or block.get("arguments") or {}
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except Exception:
            return {"command": value}
    return value if isinstance(value, dict) else {}


def _command_is_repo_write(command: str) -> bool:
    patterns = (
        r"(?:^|[;&\n]\s*)git\s+(?:-C\s+\S+\s+)?(?:add|commit|push|merge)\b",
        r"(?:^|[;&\n]\s*)gh\s+pr\s+(?:create|merge|ready|rebase|close|reopen|edit)\b",
    )
    return any(re.search(pattern, command) for pattern in patterns)


def extract_evidence(transcript_path: str, start_offset: int = 0) -> dict[str, Any]:
    evidence: dict[str, Any] = {
        "repo_mutated": False,
        "browser_acted": False,
        "ticket_created": False,
        "review_submitted": False,
        "deployment_started": False,
        "verification_observed": False,
        "read_only_activity": False,
        "prs_authored": [],
        "prs_operated": [],
        "prs_observed": [],
        "tickets_created": [],
        "tickets_observed": [],
    }
    create_ids: dict[str, str] = {}
    path = Path(transcript_path)
    if not transcript_path or not path.is_file():
        return evidence
    try:
        lines = path.open("rb")
    except OSError:
        return evidence
    with lines:
        size = path.stat().st_size
        if start_offset < 0 or start_offset > size:
            return evidence
        lines.seek(start_offset)
        for raw in lines:
            try:
                record = json.loads(raw.decode("utf-8", "replace"))
            except Exception:
                continue
            for block in _blocks(record):
                block_type = str(block.get("type") or "").lower()
                if block_type in {"tool_result", "function_call_output", "custom_tool_call_output"}:
                    call_id = str(block.get("tool_use_id") or block.get("call_id") or "")
                    if call_id in create_ids:
                        text = json.dumps(block.get("content") or block.get("output") or "")
                        if create_ids[call_id] == "pr":
                            for match in PR_URL.findall(text):
                                if match not in evidence["prs_authored"]:
                                    evidence["prs_authored"].append(match)
                        elif create_ids[call_id] == "ticket":
                            for match in TICKET_ID.findall(text):
                                ticket_id = match.upper()
                                if ticket_id not in evidence["tickets_created"]:
                                    evidence["tickets_created"].append(ticket_id)
                    continue
                if block_type not in {"tool_use", "function_call", "custom_tool_call"}:
                    continue
                name = str(block.get("name") or block.get("tool") or "").lower()
                inputs = _tool_input(block)
                command = str(inputs.get("command") or inputs.get("cmd") or "")
                call_id = str(block.get("id") or block.get("call_id") or "")
                if name in REPO_WRITE_TOOLS:
                    target = str(inputs.get("file_path") or inputs.get("path") or "")
                    if target and not target.startswith(("/tmp/", "/private/tmp/")):
                        evidence["repo_mutated"] = True
                if name in READ_TOOLS:
                    evidence["read_only_activity"] = True
                lowered = f"{name} {command}".lower()
                if "gh pr create" in lowered:
                    if call_id:
                        create_ids[call_id] = "pr"
                    evidence["repo_mutated"] = True
                if re.search(r"\bgh\s+pr\s+(?:merge|ready|rebase|close|reopen|edit)\b", command):
                    evidence["repo_mutated"] = True
                    for match in PR_URL.findall(command):
                        if match not in evidence["prs_operated"]:
                            evidence["prs_operated"].append(match)
                if re.search(r"\bgh\s+pr\s+(?:view|checks|review|comment)\b", command):
                    for match in PR_URL.findall(command):
                        if match not in evidence["prs_observed"]:
                            evidence["prs_observed"].append(match)
                if re.search(r"\bgh\s+pr\s+review\b", command):
                    evidence["review_submitted"] = True
                if re.search(r"\b(?:linear\s+create|gh\s+issue\s+create)\b", command):
                    evidence["ticket_created"] = True
                    if call_id:
                        create_ids[call_id] = "ticket"
                if re.search(r"\blinear\s+tasks\s+RUSH-\d+\b", command, re.IGNORECASE):
                    for match in TICKET_ID.findall(command):
                        ticket_id = match.upper()
                        if ticket_id not in evidence["tickets_observed"]:
                            evidence["tickets_observed"].append(ticket_id)
                if re.search(r"\b(?:deploy|release|publish)\b", command) and not re.search(r"\b(?:grep|rg|cat|read)\b", command):
                    evidence["deployment_started"] = True
                if "browser" in name or re.search(r"\bagents\s+browser\s+(?:open|click|type|screenshot|snapshot|done)\b", command):
                    evidence["browser_acted"] = True
                if re.search(r"\b(?:screenshot|curl|health|test|vitest|pytest|bun test|go test)\b", lowered):
                    evidence["verification_observed"] = True
                if _command_is_repo_write(command):
                    evidence["repo_mutated"] = True
                elif command:
                    evidence["read_only_activity"] = True
    evidence["prs_authored"].sort()
    evidence["prs_operated"].sort()
    evidence["prs_observed"].sort()
    evidence["tickets_created"].sort()
    evidence["tickets_observed"].sort()
    visual = inspect_transcript(transcript_path, start_offset)
    evidence["visual_artifact_authored"] = visual["visual_authored"]
    evidence["visual_artifact_delivered"] = visual["visual_delivered"]
    evidence["visual_artifact_read_back"] = visual["visual_read_back"]
    evidence["latest_visual_artifact"] = visual["latest_visual"]
    return evidence


def classify(evidence: dict[str, Any]) -> tuple[str, bool, str]:
    delivery = bool(
        evidence["repo_mutated"]
        or evidence["prs_authored"]
        or evidence["prs_operated"]
        or evidence["deployment_started"]
        or evidence.get("visual_artifact_delivered")
    )
    if delivery:
        return "code-delivery", True, "positive delivery evidence"
    if evidence["browser_acted"]:
        return "browser-external", False, "browser activity without repository delivery evidence"
    if evidence["ticket_created"]:
        return "ticket-creation", False, "ticket creation without repository delivery evidence"
    if evidence["review_submitted"] or evidence["prs_observed"]:
        return "review-only", False, "PR observation/review without ownership evidence"
    if evidence["read_only_activity"]:
        return "research-diagnostic", False, "read-only activity without repository delivery evidence"
    return "unknown", False, "no positive delivery evidence"


def _reconcile_aliases(db: sqlite3.Connection, session_key: str, native: str, launch: str) -> str:
    now = _now_ms()
    if native:
        previous = db.execute(
            "SELECT session_key FROM session_aliases WHERE alias_kind='native' AND alias_value=?",
            (native,),
        ).fetchone()
        if previous:
            session_key = str(previous[0])
    if launch:
        previous = db.execute(
            "SELECT session_key FROM session_aliases WHERE alias_kind='launch' AND alias_value=?",
            (launch,),
        ).fetchone()
        if previous and native and str(previous[0]) != session_key:
            provisional = str(previous[0])
            db.execute("UPDATE OR IGNORE goal_boundaries SET session_key=? WHERE session_key=?", (session_key, provisional))
            db.execute("UPDATE OR IGNORE decisions SET session_key=? WHERE session_key=?", (session_key, provisional))
            db.execute(
                """INSERT OR IGNORE INTO owned_entities
                   SELECT ?, entity_type, entity_id, acquired_goal_ordinal, updated_at_ms
                   FROM owned_entities WHERE session_key=?""",
                (session_key, provisional),
            )
            db.execute("DELETE FROM owned_entities WHERE session_key=?", (provisional,))
            db.execute("UPDATE gate_events SET session_key=? WHERE session_key=?", (session_key, provisional))
            db.execute("DELETE FROM session_state WHERE session_key=?", (provisional,))
            db.execute("UPDATE session_aliases SET session_key=? WHERE session_key=?", (session_key, provisional))
        elif previous and not native:
            session_key = str(previous[0])
    if native:
        db.execute(
            "INSERT INTO session_aliases VALUES('native',?,?,?) ON CONFLICT(alias_kind,alias_value) DO UPDATE SET session_key=excluded.session_key,updated_at_ms=excluded.updated_at_ms",
            (native, session_key, now),
        )
    if launch:
        db.execute(
            "INSERT INTO session_aliases VALUES('launch',?,?,?) ON CONFLICT(alias_kind,alias_value) DO UPDATE SET session_key=excluded.session_key,updated_at_ms=excluded.updated_at_ms",
            (launch, session_key, now),
        )
    return session_key


def _prune(db: sqlite3.Connection) -> None:
    cutoff = _now_ms() - RETENTION_DAYS * 86_400_000
    last = db.execute("SELECT value FROM meta WHERE key='last_pruned_ms'").fetchone()
    if last and _now_ms() - int(last[0]) < 86_400_000:
        return
    db.execute("DELETE FROM decisions WHERE created_at_ms < ?", (cutoff,))
    db.execute("DELETE FROM goal_boundaries WHERE created_at_ms < ?", (cutoff,))
    db.execute("DELETE FROM session_state WHERE updated_at_ms < ?", (cutoff,))
    db.execute("DELETE FROM session_aliases WHERE updated_at_ms < ?", (cutoff,))
    db.execute("DELETE FROM owned_entities WHERE updated_at_ms < ?", (cutoff,))
    db.execute("DELETE FROM gate_events WHERE created_at_ms < ?", (cutoff,))
    db.execute(
        "INSERT INTO meta(key,value) VALUES('last_pruned_ms',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (str(_now_ms()),),
    )


def record_prompt(payload: dict[str, Any], db_path: Path) -> dict[str, Any]:
    if not payload:
        return {"recorded": False, "reason": "malformed or empty payload"}
    session_key, harness, native, launch = _identity(payload)
    if not session_key:
        return {"recorded": False, "reason": "missing session identity"}
    prompt = str(payload.get("prompt") or payload.get("user_prompt") or payload.get("userPrompt") or "")
    digest = hashlib.sha256(prompt.encode("utf-8", "replace")).hexdigest()
    transcript = str(payload.get("transcript_path") or payload.get("transcriptPath") or "")
    try:
        transcript_offset = Path(transcript).stat().st_size if transcript else 0
    except OSError:
        transcript_offset = 0
    with _connect_recovering(db_path) as db:
        session_key = _reconcile_aliases(db, session_key, native, launch)
        ordinal = int(db.execute("SELECT COALESCE(MAX(ordinal),0)+1 FROM goal_boundaries WHERE session_key=?", (session_key,)).fetchone()[0])
        db.execute(
            "INSERT INTO goal_boundaries(session_key,ordinal,prompt_sha256,transcript_offset,created_at_ms) VALUES(?,?,?,?,?)",
            (session_key, ordinal, digest, transcript_offset, _now_ms()),
        )
        _prune(db)
    return {
        "recorded": True,
        "session_key": session_key,
        "goal_ordinal": ordinal,
        "transcript_offset": transcript_offset,
    }


def evaluate(payload: dict[str, Any], db_path: Path) -> dict[str, Any]:
    session_key, harness, native, launch = _identity(payload)
    transcript = str(payload.get("transcript_path") or payload.get("transcriptPath") or "")
    if not session_key:
        evidence = extract_evidence(transcript)
        context, delivery, reason = classify(evidence)
        return {
            "recorded": False,
            "context_kind": context,
            "delivery_evidence": delivery,
            "reason": reason,
            "evidence": evidence,
        }
    with _connect_recovering(db_path) as db:
        session_key = _reconcile_aliases(db, session_key, native, launch)
        goal_row = db.execute(
            "SELECT ordinal,transcript_offset FROM goal_boundaries WHERE session_key=? ORDER BY ordinal DESC LIMIT 1",
            (session_key,),
        ).fetchone()
        goal_ordinal = int(goal_row[0]) if goal_row else 0
        transcript_offset = int(goal_row[1]) if goal_row else 0
        evidence = extract_evidence(transcript, transcript_offset)
        context, delivery, reason = classify(evidence)
        evidence_json = json.dumps(evidence, sort_keys=True, separators=(",", ":"))
        evidence_hash = hashlib.sha256(evidence_json.encode()).hexdigest()
        decision = "run-delivery-gate" if delivery else "skip-delivery-gate"
        now = _now_ms()
        for entity_type, values in (
            ("pr", evidence["prs_authored"] + evidence["prs_operated"]),
            ("ticket", evidence["tickets_created"]),
        ):
            for entity_id in values:
                db.execute(
                    """INSERT INTO owned_entities VALUES(?,?,?,?,?)
                       ON CONFLICT(session_key,entity_type,entity_id) DO UPDATE SET
                         updated_at_ms=excluded.updated_at_ms""",
                    (session_key, entity_type, entity_id, goal_ordinal, now),
                )
        owned_prs = [
            str(row[0]) for row in db.execute(
                "SELECT entity_id FROM owned_entities WHERE session_key=? AND entity_type='pr' ORDER BY updated_at_ms,entity_id",
                (session_key,),
            )
        ]
        owned_tickets = [
            str(row[0]) for row in db.execute(
                "SELECT entity_id FROM owned_entities WHERE session_key=? AND entity_type='ticket' ORDER BY updated_at_ms,entity_id",
                (session_key,),
            )
        ]
        db.execute(
            """INSERT INTO session_state VALUES(?,?,?,?,?,?,?,?)
               ON CONFLICT(session_key) DO UPDATE SET
                 harness=excluded.harness,native_session_id=excluded.native_session_id,
                 launch_id=excluded.launch_id,goal_ordinal=excluded.goal_ordinal,
                 context_kind=excluded.context_kind,evidence_json=excluded.evidence_json,
                 updated_at_ms=excluded.updated_at_ms""",
            (session_key, harness, native or None, launch or None, goal_ordinal, context, evidence_json, _now_ms()),
        )
        db.execute(
            "INSERT INTO decisions(session_key,goal_ordinal,decision,reason,evidence_sha256,created_at_ms) VALUES(?,?,?,?,?,?)",
            (session_key, goal_ordinal, decision, reason, evidence_hash, _now_ms()),
        )
        _prune(db)
    return {
        "recorded": True,
        "session_key": session_key,
        "goal_ordinal": goal_ordinal,
        "transcript_offset": transcript_offset,
        "context_kind": context,
        "delivery_evidence": delivery,
        "reason": reason,
        "evidence": evidence,
        "owned_prs": owned_prs,
        "owned_tickets": owned_tickets,
    }


def record_gate(payload: dict[str, Any], db_path: Path, gate_name: str, outcome: str, reason_code: str) -> dict[str, Any]:
    session_key, _harness_name, native, launch = _identity(payload)
    if not session_key:
        return {"recorded": False, "reason": "missing session identity"}
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,39}", gate_name):
        raise ValueError("invalid gate name")
    if outcome not in {"blocked", "passed", "skipped"}:
        raise ValueError("invalid gate outcome")
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,63}", reason_code):
        raise ValueError("invalid reason code")
    with _connect_recovering(db_path) as db:
        session_key = _reconcile_aliases(db, session_key, native, launch)
        row = db.execute(
            "SELECT COALESCE(MAX(ordinal),0) FROM goal_boundaries WHERE session_key=?",
            (session_key,),
        ).fetchone()
        goal_ordinal = int(row[0])
        db.execute(
            "INSERT INTO gate_events(session_key,goal_ordinal,gate_name,outcome,reason_code,created_at_ms) VALUES(?,?,?,?,?,?)",
            (session_key, goal_ordinal, gate_name, outcome, reason_code, _now_ms()),
        )
        _prune(db)
    return {"recorded": True, "gate_name": gate_name, "outcome": outcome}


def _load_payload() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "evaluate"
    payload = _load_payload()
    try:
        if action == "record-prompt":
            result = record_prompt(payload, default_db_path())
        elif action == "evaluate":
            result = evaluate(payload, default_db_path())
        elif action == "record-gate":
            if len(sys.argv) != 5:
                raise ValueError("record-gate requires gate, outcome, and reason")
            result = record_gate(payload, default_db_path(), sys.argv[2], sys.argv[3], sys.argv[4])
        else:
            raise ValueError(f"unknown action: {action}")
    except (OSError, sqlite3.Error, RuntimeError, ValueError) as exc:
        # Hook state is guidance, never a reason to corrupt or wedge a session.
        result = {"recorded": False, "state_error": type(exc).__name__}
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
