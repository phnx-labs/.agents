#!/usr/bin/env python3
"""stop-judge — Stop hook. Interactive Claude sessions only.

Pushes an agent back once per owner request when it stopped on a step it should
do itself, and publishes whose move it is (the turn verdict) into the session
record, where agents-cli reads it for the card.

One model call (lib/model_call.py; MODEL, snapshot on stdin, never argv; run as a machine prompt with
CLAUDE_CODE_ENTRYPOINT=sdk-cli and STOP_JUDGE_CHILD=1 so it never re-enters this
hook) returns both the items in the final message (handoffs, offers, waits, blocker
and done claims) and a verdict: `continue` with the in-scope step, or `stop_ok`.
On `continue`, with nothing armed to wake the agent (background tasks, session
crons, Monitor/ScheduleWakeup/CronCreate this turn), not a `!` prompt, and no push
yet for this owner request, the hook exits 2 with the step on stderr. Every other
path, an error or timeout included, exits 0. At most MAX_JUDGES calls run at once
per machine (flock slots); a third stop passes unjudged.

The verdict replaced kind-based blocking: on 55 stops labelled blind (2026-11-07),
item kinds alone would have pushed 32 of 44 legitimate stops; the verdict pushed 7
and caught 4 of 7 labelled ones (tests/replay_stop_judge.py). `decide()` still records the kind-based would-block code.

State (see hooks/AGENTS.md "Hook-owned session state"):
  durable:    ~/.agents/.history/hooks/system.stop-judge/state.db
  disposable: ~/.agents/.cache/state/hooks/system.stop-judge/
  turn verdict: `turnVerdict` in ~/.agents/.cache/state/sessions/<pid>.json
No message text, prompt, quote, or credential is stored in the database: a row
holds codes, counts, latency, and a sha256 of the final message for later
joining. The turn verdict carries the ask's own sentence and choices, because
the card shows them; it lives in the disposable session record beside the
done-check verdict and is replaced at the next stop.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import credential_catalog  # noqa: E402
import model_call  # noqa: E402

HOOK_ID = "system.stop-judge"
MODEL = "claude-sonnet-5-5"
MODEL_TIMEOUT_S = 12.0
CATALOG_TIMEOUT_S = 2.0
MANIFEST_TTL_S = 600
RETENTION_DAYS = 30
BUSY_TIMEOUT_MS = 100
SCHEMA_VERSION = 1
MAX_JUDGES = 2           # concurrent judge children per machine
CHILD_SENTINEL = "STOP_JUDGE_CHILD"

# Tool calls that record or schedule work but gather no evidence.
BOOKKEEPING = {
    "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "ToolSearch",
    "ScheduleWakeup", "AskUserQuestion", "ExitPlanMode", "EnterPlanMode",
}
CMD_FAMILIES = ("secrets", "browser", "devices", "sessions")

# User records the owner did not type.
SYNTHETIC = re.compile(
    r"^\s*(?:<(?:system-reminder|task-notification|local-command-stdout|local-command-stderr"
    r"|local-command-caveat|bash-input|bash-stdout|bash-stderr)>|Base directory for this skill:"
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
# Whose move it is after the turn (turnVerdict.kind): an ask hands something to the
# owner; a wait claim with nothing live behind it is not done, since nothing will
# wake the agent. offer_extra_work means the asked work is finished.
ASK_KINDS = {
    "merge_or_approve_pr", "publish_or_release", "run_command", "provide_credential",
    "provide_fact", "decide_scope", "decide_taste", "signoff_destructive",
    "permission_next_step", "offer_investigate", "what_next", "blocker_claim",
}
WAIT_KINDS = {"wait_claim", "announced_not_taken"}
EXCUSED_BLOCKER = re.compile(r"touch ?id|biometric|2fa|one-time code|interactive login", re.I)

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


def earlier_requests(records: list[dict], n: int = 3) -> list[str]:
    """The owner's requests before the latest one, newest last: a "done?" carries no scope
    of its own, so the work it asks about is in these."""
    texts = [request_text(r) for r in records if owner_typed(r)]
    return [t[:600] for t in texts[-(n + 1):-1]]


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
    rows = model_call.list_bundles(CATALOG_TIMEOUT_S)
    profiles = _run_json(["browser", "profiles", "list", "--json"])
    manifest = {
        "at": time.time(),
        "bundles": sorted({str(b.get("name")) for b in rows
                           if b.get("name") and not str(b.get("name")).startswith("__")}),
        "auth_backend": model_call.auth_backend(rows),
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


HOOK_BUDGET_S = 17.0     # under the 20 s hook timeout in agents.yaml, with room to record
DEADLINE = [time.monotonic() + HOOK_BUDGET_S]   # main() and replays restart it per stop


def model_timeout() -> float:
    """The per-call cap, never past the hook's own deadline (two key tries share it)."""
    try:
        cap = min(MODEL_TIMEOUT_S, float(os.environ.get("STOP_JUDGE_TIMEOUT_S", MODEL_TIMEOUT_S)))
    except ValueError:
        cap = MODEL_TIMEOUT_S
    return max(0.0, min(cap, DEADLINE[0] - time.monotonic() - 1.0))


# The extraction rubric lives in the script: agents-cli installs hooks into version homes
# and does not reliably copy data files beside them, so a sidecar went missing in place.
RUBRIC = """First decide, then extract. Read the owner's latest_request and the FINAL message an AI coding agent sent before stopping its turn.

1. verdict: was the agent right to stop? The owner's standing policy: agents carry authorized work through doing, verifying, installing what they need (on a fleet worker box, never the owner's laptop), reviewing with a subagent, merging and releasing. Credentials are in secrets bundles and signed-in browser profiles with password managers; fleet machines are reachable. The owner is involved only for genuinely unclear intent, a choice that is truly theirs (a design or taste pick, scope beyond the request, a destructive or irreversible action, spend the request does not imply), or a blocker that is truly exhausted (Touch ID, 2FA, another person). Proving the work is part of the work: running the owner's own product (a real agent run billed to the owner's own org, an API call against production, a test deploy) to verify a fix, or installing a missing tool on a worker box, is not spend the owner must approve, and waiting hours or days for organic traffic or a scheduled recount is not a reason to stop when a faster proof is in reach. The owner has rejected exactly these stops: "I can create a Project session myself, billed to the org, so I'll only do it if you want it"; "Firefox is not installed"; "I don't have the password" while a signed-in browser with a password manager was available. Each is continue. The owner hates "I haven't done X, want me to?" when X is within the request.
The work in scope is what latest_request asks for; when latest_request is only a status question ("done?", "what's left?"), it is the work of earlier_requests. Remaining work the final message itself names toward that goal ("what's still open is…", "not done:") is in scope.
continue = it stopped on something it could and should do itself within that scope; put that step in step. stop_ok = the work is done (an optional extra offer is fine), it is waiting on CI, a reviewer or a process it is watching, or it is a genuine owner decision or exhausted blocker.

2. Extract, do not judge: Read the FINAL message an AI coding agent sent before stopping its turn and list every place where it hands something to the owner, offers something, waits, claims a blocker, or claims completion. Quote the exact sentence for each.

Output ONLY compact JSON, no prose, no fence:
{"why":"<one sentence: what the owner asked for, what the agent left, and whose decision that is>","verdict":"continue|stop_ok","step":"<the in-scope step to do now, in a few words, or empty>","items":[{"kind":"...","actor":"agent|owner|other","quote":"...","object":"<PR number, command, service or thing>","host":"<host named, or empty>","credential":"<token/key/login named, or empty>","choices":["<option>"]}]}

choices = the options the message offers the owner for this item, each a short label in the message's own words (for example ["Keep A","Build B"]); [] when it offers none.

actor = who would perform the step ("let me…", "I'll…", "next I'll…" are always actor=agent): "agent" (the agent itself), "owner" (the human it is talking to), or "other" (CI, a release train, another session or person, an automatic process).

kind is one of:
merge_or_approve_pr      owner is asked to merge, approve, admin-merge, or click to land a PR
publish_or_release       owner is asked to publish/release/deploy something
run_command              owner is asked to run a command or script
provide_credential       owner is asked for a token, key, password, login, or to set a secret
provide_fact             owner is asked for information the agent lacks
decide_scope             owner is asked to choose between approaches, features, or whether to do a piece of work
decide_taste             owner is asked to pick a design, wording, look, or feel
signoff_destructive      owner is asked to OK deleting, killing, force-pushing, closing work, or loosening a safety rule
permission_next_step     agent asks permission for the next step of the work it was asked to do
offer_investigate        agent offers to check/test/verify something that the requested work still depends on, instead of doing it
offer_extra_work         agent offers optional new work beyond what was asked (a share link, tickets, a tidy-up); the requested work itself is finished. A closing "anything else?", "let me know if you need more" or similar after finished work is offer_extra_work, not what_next. If the agent itself calls the offered work "the next step" or "natural next step", use permission_next_step instead
what_next                agent asks what to do next with no specific proposal
announced_not_taken      the AGENT says it will do a step now ("let me…", "next I'll…", "next step is…") and the message ends without doing it; set actor=other when the step belongs to CI, a release, or someone else
wait_claim               agent says it is waiting for something (CI, a poller, a subagent, a publish)
blocker_claim            agent says it CANNOT do something itself ("I can't…", "unable to…", "only you can…", "needs your…"); a status like "CI is red" or "tests fail" is not a blocker_claim
done_claim               agent says the work is complete
agreement_first          agent agrees or concedes with the owner before showing evidence

Return an empty list only if none apply."""


def judge(snapshot: dict, caps: dict) -> dict:
    """One model call. Returns {outcome, detail, items, verdict, step, latency_ms, in_tok, out_tok}."""
    # The snapshot carries message text, so it goes on stdin, never in argv.
    prompt = "SNAPSHOT:\n" + json.dumps(snapshot, ensure_ascii=False)
    cwd = cache_dir() / "cwd"
    cwd.mkdir(exist_ok=True, mode=0o700)
    reply = model_call.ask(RUBRIC, prompt, model=MODEL, cwd=cwd, auth=caps.get("auth_backend", ""),
                           remaining=model_timeout, env={CHILD_SENTINEL: "1"})
    result = {"outcome": reply["outcome"], "detail": reply["detail"], "items": [], "verdict": "",
              "step": "", "latency_ms": reply["latency_ms"], "in_tok": reply["in_tok"],
              "out_tok": reply["out_tok"]}
    if reply["outcome"] != "ok":
        return result
    obj = parse_reply(reply["text"])
    if obj is None:
        result["outcome"] = "parse-fail"
        return result
    result["items"] = obj["items"]
    result["verdict"] = str(obj.get("verdict") or "")
    result["step"] = str(obj.get("step") or "")
    return result


def parse_reply(text: str):
    """The first JSON object in the model's reply, with its `items` list kept to dicts, or None."""
    obj = model_call.first_json_object(text)
    if obj is None or not isinstance(obj.get("items"), list):
        return None
    obj["items"] = [it for it in obj["items"] if isinstance(it, dict)]
    return obj


# --- decision (code) --------------------------------------------------------


def bundle_for(item: dict, bundles: list[str]):
    """The bundle whose service the item's credential/object names. Both sides go
    through credential_catalog.aliases(), which drops generic labels (prod, share,
    auth, personal, key, token, ...); a prefix either way matches (NPM_TOKEN ->
    npmjs.com). The quote is prose and never matched."""
    words = credential_catalog.aliases(f"{item.get('credential', '')} {item.get('object', '')}")
    for bundle in bundles:
        for alias in credential_catalog.aliases(bundle):
            if any(alias.startswith(w) or w.startswith(alias) for w in words):
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
            if bundle_for(item, bundles):
                return True, kind
            continue
        if kind == "blocker_claim":
            if EXCUSED_BLOCKER.search(blob):
                continue
            return True, kind
        if kind in HINT:
            return True, kind
    return False, "pass"


def block_message(step: str, caps: dict) -> str:
    """The one push an agent gets per owner request: name the step and this machine's access."""
    lines = [f"Not done: this step is inside what the owner asked for, so do it now instead of handing it back: {step[:300]}",
             "Then report the result with evidence. A missing tool: install it on a fleet worker box "
             "(agents ssh <box>), never the owner's laptop. A login: use a signed-in browser profile and its "
             "password manager, or a secrets bundle. Stop only for a decision that is genuinely the owner's: "
             "a design pick, scope beyond the request, a destructive step, or spend the request does not imply."]
    manifest = manifest_text(caps)
    if manifest:
        lines.append("This machine has: " + manifest)
    return "\n".join(lines)


# --- turn verdict -------------------------------------------------------------


def turn_verdict(items: list[dict], background_live: bool) -> dict:
    """{kind, quote, choices}: asks beats waiting; a wait with nothing live is not_done.
    A step announced for someone else is waiting; a wait on the owner is an ask; a
    what_next beside a done claim is a sign-off."""
    done = any(it.get("kind") == "done_claim" for it in items)
    asks = [it for it in items if it.get("kind") in ASK_KINDS
            and not (it.get("kind") == "what_next" and done)]
    if not asks:
        asks = [it for it in items if it.get("kind") in WAIT_KINDS and it.get("actor") == "owner"]
    if asks:
        # A message that asks two things asks both; the owner answers them in one reply.
        quotes = [q for q in (str(it.get("quote", "")).strip() for it in asks) if q]
        choices = list(dict.fromkeys(str(c)[:80] for it in asks for c in (it.get("choices") or [])
                                     if isinstance(c, str) and c.strip()))
        return {"kind": "asks", "quote": "\n\n".join(quotes)[:1200], "choices": choices[:6]}
    wait = next((it for it in items if it.get("kind") in WAIT_KINDS), None)
    if wait:
        # A step announced for CI or someone else is theirs; a wait is not_done unless something live will wake the agent.
        theirs = wait.get("kind") == "announced_not_taken" and wait.get("actor") == "other"
        kind = "waiting" if background_live or theirs else "not_done"
        return {"kind": kind, "quote": str(wait.get("quote", ""))[:600], "choices": []}
    return {"kind": "done", "quote": "", "choices": []}


def publish_turn_verdict(agent_pid: int, session_id: str, verdict: dict) -> None:
    """Merge into the agent's record; merge_fields refuses one naming another session."""
    import session_record  # beside this script in a version home, ../lib in the repo

    session_record.merge_fields(agent_pid, session_id, {"turnVerdict": verdict})


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


def push_marker(session_id: str, request: str) -> tuple[Path, str]:
    """This session's marker file and the owner request's hash. One push per request:
    a repeat block in the same goal changed the agent's next move 0 of 29 times."""
    path = cache_dir() / "pushed"
    path.mkdir(exist_ok=True, mode=0o700)
    return (path / hashlib.sha256(session_id.encode()).hexdigest()[:32],
            hashlib.sha256(request.encode("utf-8", "replace")).hexdigest())


def already_pushed(session_id: str, request: str) -> bool:
    marker, request_sha = push_marker(session_id, request)
    try:
        return marker.read_text() == request_sha
    except OSError:
        return False


def judge_stop(payload: dict) -> str | None:
    """Snapshot, catalog, one model call, row; the push message when this stop is blocked."""
    final = payload["last_assistant_message"]
    records = read_records(payload["transcript_path"])
    request, counts, opening = turn_facts(records)
    # The owner request's position, so "continue" sent twice is two requests, each with its push.
    request_key = f"{sum(1 for r in records if owner_typed(r))}:{request}"
    caps = capabilities()
    background_live = bool(payload.get("background_tasks") or payload.get("session_crons")
                           or any(counts.get(tool) for tool in ("Monitor", "ScheduleWakeup", "CronCreate")))
    snapshot = {
        "latest_request": request[:1200],
        "earlier_requests": earlier_requests(records),
        "tool_counts_this_turn": counts,
        "watcher_or_background_task_armed": background_live,
        "text_before_first_evidence": opening[:500],
        "final_message": final[-2500:],
        "capability_manifest": manifest_text(caps),
    }
    slot = claim_slot()  # the flock is held until this process exits
    if slot is None:
        verdict = {"outcome": "skipped-busy", "detail": "", "items": [], "verdict": "", "step": "",
                   "latency_ms": None, "in_tok": None, "out_tok": None}
    else:
        verdict = judge(snapshot, caps)
    kinds = [str(it.get("kind")) if it.get("kind") in KINDS else "other" for it in verdict["items"]]
    final_sha = hashlib.sha256(final.encode("utf-8", "replace")).hexdigest()
    turn = (turn_verdict(verdict["items"], background_live) if verdict["outcome"] == "ok"
            else {"kind": "unjudged", "quote": "", "choices": []})
    push = (verdict["outcome"] == "ok" and verdict["verdict"] == "continue" and not background_live
            and request.strip()
            and not already_pushed(payload["session_id"], request_key))
    if push:
        turn = {"kind": "not_done", "quote": verdict["step"][:600], "choices": []}
    try:  # before the row, so a reader that waits for the row sees the verdict too
        publish_turn_verdict(int(payload["_agent_pid"]), payload["session_id"],
                             {**turn, "at": int(time.time() * 1000), "sha256": final_sha})
    except Exception:  # noqa: BLE001 — a home without session_record still records the row
        pass
    if verdict["outcome"] == "ok":
        would_block, reason = decide(counts, verdict["items"], background_live, caps["bundles"])
    else:
        # Without items only the tool-count fact can be judged.
        would_block, reason = decide(counts, [], background_live, caps["bundles"])
        reason = reason if would_block else "unjudged"
    try:  # a locked or failing database never costs the agent its push
        record({
            "session_key": f"claude:{payload['session_id']}",
            "ts_ms": int(time.time() * 1000),
            "would_block": int(would_block),
            "reason": "pushed" if push else ("continue" if verdict["verdict"] == "continue" else reason),
            "hint": HINT.get(reason, ""),
            "item_kinds": ",".join(kinds),
            "background_live": int(background_live),
            "latency_ms": verdict["latency_ms"],
            "input_tokens": verdict["in_tok"],
            "output_tokens": verdict["out_tok"],
            "outcome": verdict["outcome"],
            "detail": verdict["detail"],
            "final_sha256": final_sha,
        })
    except Exception:  # noqa: BLE001
        pass
    if not push:
        return None
    marker, request_sha = push_marker(payload["session_id"], request_key)
    marker.write_text(request_sha)
    return block_message(verdict["step"] or "the step you offered or handed back", caps)


def claim_slot():
    """An flock on one of MAX_JUDGES slot files, held for this process's life; None
    when every slot is taken."""
    slots = cache_dir() / "slots"
    slots.mkdir(exist_ok=True, mode=0o700)
    for n in range(MAX_JUDGES):
        handle = open(slots / f"slot-{n}.lock", "a")
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            handle.close()
            continue
        return handle
    return None


def main() -> int:
    """Interactive Claude only. Exit 2 with the push on stderr blocks the stop once per owner
    request; every other path, error included, exits 0 and lets the stop through."""
    DEADLINE[0] = time.monotonic() + HOOK_BUDGET_S
    if os.environ.get("CLAUDE_CODE_ENTRYPOINT") != "cli" or os.environ.get(CHILD_SENTINEL):
        return 0
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict) or payload.get("stop_hook_active"):
        return 0
    final = payload.get("last_assistant_message")
    if (not isinstance(final, str) or not final.strip() or not payload.get("session_id")
            or not payload.get("transcript_path")):
        return 0
    try:  # a home without session_record still judges and records its row
        import session_record  # beside this script in a version home, ../lib in the repo
        payload["_agent_pid"] = session_record.unwrap_hook_shell(os.getppid())
    except ImportError:
        pass
    message = judge_stop(payload)
    if message:
        sys.stderr.write(message + "\n")
        return 2
    return 0


if __name__ == "__main__":
    code = 0
    try:
        code = main()
    except BaseException:  # noqa: BLE001 — fail open: an error never blocks or wedges a stop
        code = 0
    sys.exit(code)
