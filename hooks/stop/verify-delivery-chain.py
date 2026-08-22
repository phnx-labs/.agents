#!/usr/bin/env python3
"""Evidence-based delivery-chain check for the agent stop hook.

Reads JSON on stdin with keys:
  transcript_path         path to the session transcript (JSONL)
  responsible_prs         list of PR URLs/refs this session created/worked
  last_assistant_message  final assistant message text
  repo_path               optional repo path hint
  cwd                     session working directory as reported by the harness

Outputs a check message to stdout if the agent must close a delivery loop.
Outputs nothing (exit 0) if no issue is found or any probe fails.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from visual_readback import inspect_transcript

LINEAR_BIN = (
    os.environ.get("LINEAR_BIN")
    or shutil.which("linear")
    or os.path.expanduser("~/.agents/skills/linear/scripts/linear")
)
DONE_STATES = {"done", "canceled", "cancelled", "closed"}
SHIP_KEYWORDS = {
    "release", "publish", "ship", "version bump", "bump version",
    "npm publish", "cargo publish", "vsce publish", "gem push",
    "pypi upload", "publish extension",
}
USER_FACING_KEYWORDS = {
    "add ", "new ", "support ", "flag", "command", "option", "argument",
    "api", "endpoint", "config", "configuration", "behavior", "behaviour",
    "cli ", "extension", "plugin", "feature", "user-facing", "breaking change",
}
EXEMPT_KEYWORDS = {
    "fix", "bugfix", "refactor", "internal", "test", "tests", "rename",
    "typo", "lint", "format", "cleanup", "clean up", "nit",
}
DOC_PATHS = {"README.md", "README", "AGENTS.md", "CLAUDE.md", "GEMINI.md"}
CHANGELOG_PATHS = {"CHANGELOG.md", "CHANGELOG", "CHANGES.md", "CHANGES"}


def _run(cmd, cwd=None, timeout=8):
    """Run a command, return stripped stdout. Empty string on any failure."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        if result.returncode != 0:
            return ""
        return result.stdout.strip()
    except Exception:
        return ""


def _records(transcript_path, start_offset=0, end_offset=None):
    try:
        with open(transcript_path, "rb") as handle:
            handle.seek(max(0, int(start_offset)))
            while end_offset is None or handle.tell() < end_offset:
                raw = handle.readline()
                if not raw:
                    break
                try:
                    yield json.loads(raw.decode("utf-8", "replace"))
                except Exception:
                    continue
    except Exception:
        return


def _tool_commands(transcript_path, start_offset=0):
    """Yield shell commands from tool_use blocks."""
    for rec in _records(transcript_path, start_offset):
        msg = rec.get("message") if isinstance(rec.get("message"), dict) else rec
        content = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                yield str((block.get("input") or {}).get("command", ""))


def _find_repo_path(transcript_path, responsible_prs, hint, start_offset=0, session_cwd=""):
    """Best-effort repo path from hint, transcript commands, or the session cwd.

    Only the harness-reported session cwd from the hook input is consulted —
    never this process's own cwd, because a Stop hook can be invoked from any
    directory and must resolve the same repo regardless.
    """
    if hint and Path(hint).is_dir() and Path(hint, ".git").exists():
        return str(Path(hint).resolve())

    # Scan transcript for directory hints in git/gh commands.
    candidates = []
    for cmd in _tool_commands(transcript_path, start_offset):
        # cd /some/path && gh pr create
        for m in re.finditer(r"(?:^|&&|;)\s*cd\s+(\S+)", cmd):
            p = m.group(1).strip("\"'")
            if Path(p, ".git").exists():
                candidates.append(str(Path(p).resolve()))
        # git -C /some/path ...
        for m in re.finditer(r"\bgit\s+-C\s+(\S+)", cmd):
            p = m.group(1).strip("\"'")
            if Path(p, ".git").exists():
                candidates.append(str(Path(p).resolve()))

    if candidates:
        return candidates[-1]

    if session_cwd and Path(session_cwd, ".git").exists():
        return str(Path(session_cwd).resolve())

    return ""


def _extract_text_from_transcript(transcript_path, start_offset=0):
    """Yield strings of text content found in the transcript."""
    for rec in _records(transcript_path, start_offset):
        msg = rec.get("message") if isinstance(rec.get("message"), dict) else rec
        content = msg.get("content") if isinstance(msg, dict) else None
        if isinstance(content, str):
            yield content
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict):
                    if block.get("type") == "text":
                        yield block.get("text", "")
                    elif block.get("type") == "tool_use":
                        yield str((block.get("input") or {}).get("command", ""))
                    elif block.get("type") == "tool_result":
                        yield json.dumps(block.get("content", "") or "")


def _first_user_message(transcript_path, goal_offset=0):
    """Return the current goal's user prose immediately before its boundary."""
    NOISE = re.compile(
        r"^\s*<(/?)(bash-(input|stdout|stderr)|command-(name|message|args|contents)|"
        r"local-command-(stdout|stderr)|system-reminder|task-notification)>"
    )
    CAVEAT = re.compile(r"^\s*Caveat: The messages below were generated by the user while running")
    INTERRUPT = re.compile(r"^\s*\[Request interrupted")
    SKILL = re.compile(r"^\s*Base directory for this skill:")
    HOOKFB = re.compile(r"^\s*[A-Za-z]+ hook feedback:")
    selected = ""
    try:
        records = _records(transcript_path, 0, goal_offset or None)
        for rec in records:
            msg = rec.get("message") if isinstance(rec.get("message"), dict) else rec
            if (rec.get("role") or msg.get("role")) != "user":
                continue
            content = rec.get("content", "") or msg.get("content", "")
            if isinstance(content, list):
                if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
                    continue
                content = " ".join(
                    c.get("text", "") for c in content
                    if isinstance(c, dict) and c.get("type") == "text"
                )
            content = (content or "").strip()
            if len(content) <= 20:
                continue
            if (NOISE.search(content) or CAVEAT.search(content)
                    or INTERRUPT.search(content) or SKILL.search(content)
                    or HOOKFB.search(content)):
                continue
            if not goal_offset:
                return content
            selected = content
    except Exception:
        pass
    return selected


def _ticket_ids(text):
    """Return deduplicated RUSH-XXXX identifiers found in text."""
    if not text:
        return []
    found = re.findall(r"\bRUSH-\d+\b", text, flags=re.IGNORECASE)
    # Preserve order, uppercase.
    seen = set()
    out = []
    for t in found:
        u = t.upper()
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


def _all_ticket_ids(transcript_path, pr_data, branch_name, commits_text, first_user_msg, start_offset=0):
    """Collect ticket IDs from every evidence source."""
    ids = []
    sources = [
        branch_name,
        first_user_msg,
        commits_text,
    ]
    for pr in pr_data:
        sources.append(pr.get("title", ""))
        sources.append(pr.get("body", ""))
        sources.append(pr.get("headRefName", ""))

    for s in sources:
        ids.extend(_ticket_ids(s))

    # Also scan explicit Linear WRITE commands in the transcript — `linear
    # update <id>` is real engagement (a status/comment change), so it counts
    # as "referenced by this delivery". `linear tasks <id>` is a bare READ —
    # checking a ticket's state or triaging is incidental, not a claim of
    # ownership over it, mirroring the same read-vs-worked distinction this
    # file already applies to `gh pr view` above (VIEW is excluded from WORK).
    # Without this, a session that merely looked up an unrelated ticket while
    # researching something else gets permanently blocked from stopping for
    # the rest of its transcript, because this scan is transcript-wide and the
    # ticket's live state may never reach a DONE_STATE.
    for cmd in _tool_commands(transcript_path, start_offset):
        for m in re.finditer(r"\blinear\s+update\s+(RUSH-\d+)\b", cmd, flags=re.IGNORECASE):
            ids.append(m.group(1).upper())

    seen = set()
    out = []
    for t in ids:
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


def _fetch_pr_data(repo_path, pr_refs):
    """Return list of dicts with title/body/headRefName for each PR ref."""
    data = []
    if not pr_refs or not repo_path:
        return data
    for ref in pr_refs:
        if not ref:
            continue
        out = _run(["gh", "pr", "view", ref, "--json", "title,body,headRefName"], cwd=repo_path, timeout=8)
        if not out:
            continue
        try:
            obj = json.loads(out)
            data.append({
                "title": obj.get("title", ""),
                "body": obj.get("body", ""),
                "headRefName": obj.get("headRefName", ""),
            })
        except Exception:
            pass
    return data


def _fetched_pr_data_failed(repo_path, pr_refs, pr_data):
    """If PR refs exist but every gh probe failed, fail open."""
    return bool(repo_path and pr_refs and not pr_data)


def _current_branch(repo_path):
    return _run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_path, timeout=5)


def _default_base(repo_path):
    ref = _run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd=repo_path, timeout=5)
    if ref:
        return ref
    return "origin/main"


def _commits_text(repo_path, pr_data):
    """Collect commit messages from PR branches or the current branch."""
    texts = []
    for pr in pr_data:
        branch = pr.get("headRefName", "")
        if not branch:
            continue
        # Try merge-base against default branch.
        base = _run(["git", "merge-base", "HEAD", branch], cwd=repo_path, timeout=5)
        if base:
            log = _run(
                ["git", "log", f"{base}..{branch}", "--pretty=format:%s%n%b"],
                cwd=repo_path,
                timeout=5,
            )
            if log:
                texts.append(log)
    if not texts:
        base_ref = _default_base(repo_path)
        base = _run(["git", "merge-base", base_ref, "HEAD"], cwd=repo_path, timeout=5)
        rev = f"{base}..HEAD" if base else None
        if rev:
            log = _run(["git", "log", rev, "--pretty=format:%s%n%b"], cwd=repo_path, timeout=5)
            if log:
                texts.append(log)
    return "\n".join(texts)


def _changed_files(repo_path, pr_data):
    """Return set of file paths changed in PR branches or the current branch."""
    files = set()
    for pr in pr_data:
        branch = pr.get("headRefName", "")
        if not branch:
            continue
        base = _run(["git", "merge-base", "HEAD", branch], cwd=repo_path, timeout=5)
        if base:
            out = _run(["git", "diff", "--name-only", f"{base}..{branch}"], cwd=repo_path, timeout=5)
            if out:
                files.update(line.strip() for line in out.splitlines() if line.strip())
    if not files:
        base_ref = _default_base(repo_path)
        base = _run(["git", "merge-base", base_ref, "HEAD"], cwd=repo_path, timeout=5)
        rev = f"{base}..HEAD" if base else None
        if rev:
            out = _run(["git", "diff", "--name-only", rev], cwd=repo_path, timeout=5)
            if out:
                files.update(line.strip() for line in out.splitlines() if line.strip())
    return files


# Path segments that are mechanically incapable of being a user-facing delivery:
# the gitignored scratch/artifact/worktree scratch space and OS temp dirs. A write
# confined to one of these can never ship, so it must not raise a delivery check.
NON_DELIVERABLE_MARKERS = (
    ".agents/artifacts/", ".agents/scratch/", ".agents/worktrees/",
)


def _is_non_deliverable_path(path):
    low = path.replace("\\", "/").lower()
    if low.startswith("./"):
        low = low[2:]
    if any(m in low for m in NON_DELIVERABLE_MARKERS):
        return True
    if low.startswith("tmp/") or "/tmp/" in low or "/var/folders/" in low:
        return True
    return False


def _deliverable_changed_files(repo_path, pr_data):
    """Changed files that could actually ship. `_changed_files` already excludes
    gitignored/untracked paths (it diffs tracked commit ranges); this additionally
    drops scratch/artifact/worktree/tmp paths, so a session whose only changes are
    non-shippable scratch writes counts as producing no delivery."""
    return {f for f in _changed_files(repo_path, pr_data) if not _is_non_deliverable_path(f)}


def _is_shippable_repo(repo_path):
    """Detect whether this repo produces an independently-shippable artifact."""
    if not repo_path:
        return False
    p = Path(repo_path)
    shippable_files = [
        "package.json", "Cargo.toml", "pyproject.toml", "setup.py", "setup.cfg",
        "go.mod", "build.gradle", "pom.xml", "Gemfile",
    ]
    for name in shippable_files:
        if (p / name).exists():
            return True
    if (p / "release.sh").exists():
        return True
    workflow_dir = p / ".github" / "workflows"
    if workflow_dir.exists():
        for wf in workflow_dir.iterdir():
            if wf.is_file() and "release" in wf.name.lower():
                return True
    # VS Code extension manifest.
    if (p / "package.json").exists():
        try:
            pkg = json.loads((p / "package.json").read_text())
            if pkg.get("publisher") or pkg.get("engines", {}).get("vscode"):
                return True
        except Exception:
            pass
    return False


def _release_status(repo_path, pr_data, transcript_path, last_assistant_message, start_offset=0):
    """Return (release_ran, verified_live, unreleased_changelogs) from concrete evidence."""
    release_ran = False
    verified_live = False

    text_chunks = [last_assistant_message or ""]
    text_chunks.extend(_extract_text_from_transcript(transcript_path, start_offset))
    for pr in pr_data:
        text_chunks.append(pr.get("body", ""))

    all_text = "\n".join(text_chunks)

    # A tag ANYWHERE in history used to set release_ran here. That defeated the check
    # permanently in any repo that has ever cut a release: agents-cli has 185 tags, so
    # `git describe --tags --abbrev=0` always answered, release_ran was always True, and
    # "merged is not shipped" could never fire. Measured 2026-08-15: PR #2705 merged, its
    # entry sat under `## [Unreleased]`, and the session stopped clean asking whether to
    # release — the exact banned stop this check exists to catch.
    #
    # Ask the real question instead: is the delivered work still staged rather than
    # shipped? A changelog this PR touched that still carries content under
    # `## [Unreleased]` is the mechanical signature of merged-but-unreleased.
    unreleased_changelogs = _unreleased_changelogs(repo_path, pr_data)

    release_cmds = re.compile(
        r"\b(npm\s+publish|yarn\s+publish|cargo\s+publish|vsce\s+publish|"
        r"gem\s+push|twine\s+upload|python\s+-m\s+twine|publish-extension|"
        r"release\.sh|gh\s+release\s+create|released\s+v?\d+\.\d+\.\d+)\b",
        flags=re.IGNORECASE,
    )
    if release_cmds.search(all_text):
        release_ran = True

    verify_cmds = re.compile(
        r"\b(npm\s+(?:view|info)\b.*\bversion\b|cargo\s+install\b|pip\s+install\b|"
        r"python\s+-m\s+pip\s+install\b|gh\s+release\s+view\b|"
        r"(?:agents|rush|codex|claude|node|python|uv|bun|npm)\s+--version\b|"
        r"curl\b.*(?:/health|/version|/status)|rush\s+http\b|"
        r"installed version|version check|verified live|live verified)\b",
        flags=re.IGNORECASE,
    )
    if verify_cmds.search(all_text):
        verified_live = True

    if re.search(r"https://github\.com/[\w.-]+/[\w.-]+/releases/tag/", all_text):
        release_ran = True
        verified_live = True

    # Staged work outranks any positive signal above: a real `## [Unreleased]` block in a
    # changelog this delivery touched means the change is merged and not published, whatever
    # the transcript claims. The paths ride along so the check can name the actual
    # remediation (fold + finish the release) instead of "run the release" — which would
    # be wrong, and could induce a duplicate publish, when a publish already ran but the
    # changelog was never folded.
    if unreleased_changelogs:
        release_ran = False
        verified_live = False

    return release_ran, verified_live, unreleased_changelogs


def _unreleased_changelogs(repo_path, pr_data):
    """Changelogs this delivery touched that still carry content under `## [Unreleased]`.

    An empty `## [Unreleased]` heading is fine — that is the normal resting state. Only a
    heading with real content beneath it means work is staged and unshipped.
    """
    if not repo_path:
        return []
    found = []
    for path in _changed_files(repo_path, pr_data):
        if "changelog" not in path.lower():
            continue
        body = _run(["git", "show", f"HEAD:{path}"], cwd=repo_path, timeout=5)
        if not body:
            continue
        m = re.search(r"^##\s*\[Unreleased\]\s*$(.*?)(?=^##\s|\Z)", body, re.M | re.S)
        if m and m.group(1).strip():
            found.append(path)
    return found


def _docs_changelog_status(repo_path, pr_data):
    """Check whether docs and CHANGELOG were updated in the same delivery."""
    changed = _changed_files(repo_path, pr_data)
    docs_ok = False
    changelog_ok = False
    for f in changed:
        lower = f.lower()
        name = Path(f).name
        if f in DOC_PATHS or lower.startswith("docs/") or "/docs/" in lower:
            docs_ok = True
        if f in CHANGELOG_PATHS or (lower.endswith(".md") and "changelog" in lower):
            changelog_ok = True
        # A CHANGELOG entry is not a user doc by itself.
        if name in CHANGELOG_PATHS:
            changelog_ok = True
    return docs_ok, changelog_ok


def _linear_state(ticket_id):
    """Return (state_name, title) or (None, None) on failure."""
    if not Path(LINEAR_BIN).exists():
        return None, None
    out = _run([LINEAR_BIN, "tasks", ticket_id, "--json"], timeout=10)
    if not out:
        return None, None
    try:
        data = json.loads(out)
        state = data.get("state", {}) or {}
        return state.get("name", ""), data.get("title", "")
    except Exception:
        return None, None


def _looks_user_facing(pr_data, first_user_msg):
    """Heuristic: does the delivery look user-facing?"""
    text = (first_user_msg or "").lower()
    for pr in pr_data:
        text += " " + (pr.get("title", "") + " " + pr.get("body", "")).lower()

    has_user_facing = any(kw in text for kw in USER_FACING_KEYWORDS)
    has_exempt = any(kw in text for kw in EXEMPT_KEYWORDS)
    # Strong signal: PR title starts with feat/add/ship.
    strong = re.search(r"\b(feat|feature|add|ship|release|publish)\b", text)
    if strong and not has_exempt:
        return True
    if has_user_facing and not has_exempt:
        return True
    return False


def _looks_shippable(pr_data, first_user_msg):
    """Heuristic: does the delivery mention release/publish?"""
    text = (first_user_msg or "").lower()
    for pr in pr_data:
        text += " " + (pr.get("title", "") + " " + pr.get("body", "")).lower()
    return any(kw in text for kw in SHIP_KEYWORDS)


def _has_outcome_evidence(pr_data, transcript_path, last_assistant_message, start_offset=0):
    """Look for screenshot, URL, metric, test, or version evidence."""
    chunks = [last_assistant_message or ""]
    chunks.extend(_extract_text_from_transcript(transcript_path, start_offset))
    for pr in pr_data:
        chunks.append(pr.get("body", ""))
    text = "\n".join(chunks)
    if re.search(r"https?://(?!github\.com/[\w.-]+/[\w.-]+/pull/)\S+", text):
        return True
    evidence = re.compile(
        r"\b(screenshot|recording|artifact|proof|metric|verified live|live verified|"
        r"version check|installed version|tests? (?:pass|passed|green)|"
        r"\d+\s+(?:tests?|checks?|assertions?)\s+(?:pass|passed|green)|"
        r"(?:curl|rush http|npm view|npm info|gh release view)\b)\b",
        flags=re.IGNORECASE,
    )
    return bool(evidence.search(text))


def _related_ticket_ids(pr_data, commits_text):
    """Tickets explicitly linked as related/blocked/closes."""
    ids = []
    text = commits_text
    for pr in pr_data:
        text += "\n" + pr.get("body", "")
    for m in re.finditer(
        r"\b(?:closes|fixes|fixes:|closed|fix|related|relates|relates to|blocked by|unblocks)\s+(RUSH-\d+)\b",
        text,
        flags=re.IGNORECASE,
    ):
        ids.append(m.group(1).upper())
    return list(dict.fromkeys(ids))


def main():
    data = json.load(sys.stdin)
    transcript_path = data.get("transcript_path", "")
    responsible_prs = data.get("responsible_prs", [])
    last_msg = (data.get("last_assistant_message", "") or "").lower()
    goal_offset = max(0, int(data.get("goal_offset", 0) or 0))

    if not transcript_path or not Path(transcript_path).exists():
        return

    repo_path = _find_repo_path(
        transcript_path,
        responsible_prs,
        data.get("repo_path", ""),
        goal_offset,
        session_cwd=data.get("cwd", ""),
    )
    pr_data = _fetch_pr_data(repo_path, responsible_prs) if repo_path else []
    if _fetched_pr_data_failed(repo_path, responsible_prs, pr_data):
        return
    branch_name = _current_branch(repo_path) if repo_path else ""
    commits_text = _commits_text(repo_path, pr_data) if repo_path else ""
    first_user_msg = _first_user_message(transcript_path, goal_offset)

    ticket_ids = _all_ticket_ids(transcript_path, pr_data, branch_name, commits_text, first_user_msg, goal_offset)
    related_ids = _related_ticket_ids(pr_data, commits_text)

    open_tickets = []
    for t in ticket_ids:
        state, title = _linear_state(t)
        if state is None:
            return  # fail open on probe error
        if state.lower() not in DONE_STATES:
            open_tickets.append((t, state, title))

    open_related = []
    for t in related_ids:
        if t in {x[0] for x in open_tickets}:
            continue
        state, title = _linear_state(t)
        if state is None:
            return  # fail open on probe error
        if state.lower() not in DONE_STATES:
            open_related.append((t, state, title))

    # The docs/CHANGELOG demand keys off _looks_user_facing, a keyword match on the
    # conversation ("command", "flag", "feature", ...). A conversation that merely
    # *mentions* a user-facing thing is not a *delivery* of one, so only check it when
    # this session produced a real change to document: a tracked file changed outside
    # scratch/artifact/tmp paths, or a responsible PR. Can't be gamed — a genuine
    # change shows up in `git diff` / a PR.
    #
    # NOTE: this check is deliberately NOT applied to `shippable`. A release cut from
    # already-merged code (tag/publish, no new local commits, no PR this session) is a
    # real delivery with no file diff, and `_release_status` already checks it on
    # independent tag/publish/verify evidence. ANDing is_real_delivery here would
    # silently disable release verification for that ordinary flow.
    visual = inspect_transcript(transcript_path, goal_offset)
    is_real_delivery = (
        bool(pr_data)
        or (bool(repo_path) and bool(_deliverable_changed_files(repo_path, pr_data)))
        or visual["visual_delivered"]
    )

    user_facing = _looks_user_facing(pr_data, first_user_msg) and is_real_delivery
    docs_ok, changelog_ok = _docs_changelog_status(repo_path, pr_data) if repo_path else (True, True)
    shippable = _is_shippable_repo(repo_path) and _looks_shippable(pr_data, first_user_msg)
    release_ran, release_verified, unreleased_changelogs = (
        _release_status(repo_path, pr_data, transcript_path, last_msg, goal_offset)
        if shippable
        else (True, True, [])
    )
    evidence_ok = _has_outcome_evidence(
        pr_data, transcript_path, data.get("last_assistant_message", ""), goal_offset
    )

    issues = []
    if open_tickets:
        issues.append("open Linear ticket(s) referenced by this delivery")
    if open_related:
        issues.append("open related/downstream Linear ticket(s)")
    if user_facing and (not docs_ok or not changelog_ok):
        issues.append("docs and CHANGELOG not updated for a user-facing change")
    if shippable and (not release_ran or not release_verified):
        issues.append("independently-shippable change not released/verified")
    if (ticket_ids or user_facing or shippable) and not evidence_ok:
        issues.append("outcome evidence missing")
    if visual["visual_delivered"] and not visual["visual_read_back"]:
        issues.append("visual artifact delivered without image read-back")

    if not issues:
        return

    lines = ["STOP — close out the delivery, then stop again:"]

    if open_tickets:
        ids = ", ".join(f"{t} [{state}]" for t, state, _ in open_tickets)
        lines.append(f"  - Open Linear ticket(s): {ids} — update state with proof (`linear update <id> --done --proof <url|file|metric>`).")

    if open_related:
        ids = ", ".join(f"{t} [{state}]" for t, state, _ in open_related)
        lines.append(f"  - Related/downstream ticket(s) still open: {ids}.")

    if user_facing and (not docs_ok or not changelog_ok):
        missing = " and ".join(m for m, ok in (("docs", docs_ok), ("CHANGELOG", changelog_ok)) if not ok)
        lines.append(f"  - User-facing change with no {missing} update — commit it in this delivery (exempt: pure bug fix, refactor, test-only, self-evident rename).")

    if shippable and (not release_ran or not release_verified):
        if unreleased_changelogs:
            paths = ", ".join(unreleased_changelogs)
            lines.append(f"  - Merged but not published ({paths} still under [Unreleased]) — finish the release and verify the registry, or probe the live releaser (process/lease/PR, not a claim).")
        else:
            lines.append("  - Release/live verification incomplete — release, then cite the live version/URL/output.")

    if visual["visual_delivered"] and not visual["visual_read_back"]:
        lines.append(f"  - Visual delivered without image read-back ({visual['latest_visual'] or 'visual artifact'}) — screenshot it headlessly and view_image it.")

    if (ticket_ids or user_facing or shippable) and not evidence_ok:
        lines.append("  - No outcome evidence — cite a screenshot, URL, metric, passing test output, or version check.")

    sys.stdout.write("\n".join(lines))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Fail open: never wedge a session because of a hook bug.
        pass
