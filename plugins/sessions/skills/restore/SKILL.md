---
name: restore
description: "Re-open agent sessions killed by a crash or reboot as Ghostty (or terminal) windows, each resuming its real transcript. Not /continue (finish work here) and not recover mode (finish many headlessly). Triggers on: /restore, /sessions:restore, 'bring the windows back', 'reopen crashed sessions', 'restore after reboot'."
argument-hint: "[repo path or keyword to scope | 'all' | empty = auto-detect last crash]"
allowed-tools: Bash(agents sessions*), Bash(open *), Bash(sysctl *), Bash(uptime *), Bash(who *), Bash(date *), Bash(ls *), Bash(rg *), Bash(jq *), Bash(sleep *), Bash(pbcopy *), Bash(xclip *), Bash(wl-copy *), Read(*), Task(*), AskUserQuestion(*), computer(*)
user-invocable: true
---

# sessions:restore

Re-open agent work that was lost when the machine crashed, rebooted, or the terminal was
killed — each chosen session in its **own terminal window**, resuming its real transcript.

Scope: `$ARGUMENTS` (empty = auto-detect the most recent crash).

| This skill | Not this skill |
|---|---|
| Relaunch *other* sessions as windows | `sessions:continue` — finish work **in this** session |
| Window / tab surface back | `sessions:continue` recover mode (`/continue recover`) — finish many **headlessly** |

## 1. Find the crash boundary

**Boot / crash time** (pick what works on this OS):

- macOS: `sysctl -n kern.boottime`
- Linux: `uptime -s` if available, else
  `date -d @$(awk '/btime/ {print $2}' /proc/stat)` (GNU date) or the equivalent epoch
  format on this host

An unexpected reboot ≈ the crash moment. Sessions active just before it are the
casualties.

**Source of truth:** raw transcripts, not only the search index. Claude writes one JSONL
per session under **each** installed version home:

```text
~/.agents/.history/versions/claude/*/home/.claude/projects/<encoded-cwd>/<id>.jsonl
```

(`encoded-cwd` replaces `/` with `-`.) Terminals may pin different versions — sweep **all**
version homes, not only whatever `~/.claude` points at. Prefer
`agents sessions --crashed` / recent index rows when they exist, then confirm against the
JSONL tail.

Scope by `$ARGUMENTS` when given (repo path → encoded project dir(s); keyword → first user
prompts). Empty → all projects in scope.

## 2. Triage each candidate (don't restore blindly)

For every session whose mtime sits shortly before the crash boundary, read the **tail** of
its JSONL (or `agents sessions <id>` summary) and classify:

- **Interrupted mid-task** — last entry is an assistant `tool_use` with no matching
  `tool_result`, or a user/tool message with no assistant reply, or the file is truncated.
  **These** are worth restoring.
- **Completed & idle** — last assistant turn finished cleanly (answered, "Done", PR
  opened). List them; do not default to restoring them.
- Note each session's `cwd`, version home, first real user prompt (topic), and one-line
  state.

Nothing is lost either way — the JSONL is intact; `--resume` / `agents sessions resume`
replays it.

## 3. Present the triage, then restore the chosen ones

Show a short table: id · version · cwd · topic · interrupted?

Recommend the interrupted set. **Ask which to open and how many** unless `$ARGUMENTS`
already said `all` — opening many live agents at once is exactly the load that causes the
crash you are recovering from.

### Preferred launch path

Prefer the CLI lifecycle when it can open interactive terminals:

```bash
agents sessions resume <SESSION_ID>
# multi: agents sessions resume   # picker / multi-select into tabs when supported
```

When you must place **Ghostty windows** yourself (macOS; no direct Ghostty CLI — go through
`open`), resume with the **version-pinned** binary in the session's own cwd, staggered:

```bash
open -na Ghostty.app --args -e zsh -lc \
  "cd <CWD> && exec claude@<VERSION> --resume <SESSION_ID>"
sleep 1   # stagger between launches
```

- **Tabs instead of windows** (one window, many tabs): Ghostty has no CLI for that — drive
  it via the `computer` skill (focus Ghostty → ⌘T → type the resume command → Enter),
  repeating per session.
- **VS Code / Codium:** `code <cwd>` / `codium <cwd>` opens the folder; a CLI cannot spawn
  an integrated-terminal tab running a command without the agent-terminals extension. Offer
  folder-open; do not claim tab automation.
- **Linux without Ghostty:** use the terminal emulator that is actually installed
  (`ghostty`, `kitty`, `alacritty`, `gnome-terminal`, …) with an equivalent `-e` /
  `--command` form, or fall back to printing version-pinned resume commands and putting the
  first on the clipboard.

Harness resume flags differ — Codex: `codex@<ver> resume <id>`; Gemini / OpenCode have
their own. When unsure, let `agents sessions` / `agents sessions resume` build the correct
per-agent resume command.

## Guardrails

- Never auto-open more than a couple of live sessions without confirming the count (unless
  `$ARGUMENTS` is `all` and the user already accepted the blast radius).
- Verify each launch returned exit 0; a window should appear.
- Do not use this skill to "continue the work myself" — hand that to `sessions:continue`.
- Do not hand-walk only one version home and declare the fleet empty.
