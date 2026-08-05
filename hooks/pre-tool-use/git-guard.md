# git-guard

A PreToolUse hook on the `Bash` tool that deterministically blocks destructive
git operations before they reach the shell. Closes gaps that Claude Code's
literal-prefix permission patterns leave open, and that git itself doesn't
guard against.

## Why this hook exists

### Gap 1 — Claude Code permission patterns are literal prefix

`Bash(git reset:*)` in `settings.json` matches commands beginning with the
exact tokens `git reset`. It does **not** match `git -C <path> reset`,
`FOO=bar git reset`, `/usr/bin/git reset`, `sh -c "git reset"`, or
`ls; git reset`. This bypassed the deny list in a real session:

> 2026-06-07: agent ran `git -C $REPO reset --hard origin/main`. The literal
> prefix did not match; the LLM-based classifier missed it; the reset went
> through against an explicit `CLAUDE.md` prohibition.

### Gap 2 — git itself only protects *some* destructive ops

People assume git refuses dangerous operations. It doesn't, consistently.

| Operation | Does git itself refuse? | Why the hook still matters |
|---|---|---|
| `git reset --hard <ref>` | **No** | Silently rewrites HEAD + discards working tree |
| `git push --force` | **No** | Overwrites remote unconditionally |
| `git push --force-with-lease` | (safer; refuses if remote advanced) | Hook allows this |
| `git stash drop` / `clear` | No | |
| `git clean -fd` | No | `-f` already opts out of the prompt |
| `git rebase`, `cherry-pick`, `revert` | No | |
| `git reflog expire / delete` | No | |
| `git filter-branch`, `gc --prune=now` | No | Rare, catastrophic |
| `git branch -d <unmerged>` | **Yes** — refuses unless merged | Hook overlaps |
| `git branch -D <unmerged>` | **No** — `-D` bypasses the merge check | Big gap |
| `git checkout -- <file>` | **No** | Silently overwrites uncommitted work |
| `git config user.name x` | No | Hook allows `--get`/`--list` reads |
| `git merge --abort` | No | Loses conflict-resolution work |
| `git worktree remove <dirty>` | **Yes** — refuses unless `--force` | Hook overlaps |
| `git worktree remove --force <dirty>` | **No** — `--force` bypasses git's check | Gap |
| `git worktree remove <clean-but-unpushed>` | **No** — git doesn't look at the commit graph | **Silent loss** |

The hook is most valuable where the table says git refuses **No**.

## Architecture

```
        ┌───────────────────┐
        │   Claude (LLM)    │
        │  emits Bash call  │
        └─────────┬─────────┘
                  │
                  ▼  tool_input.command = "git -C /tmp reset --hard HEAD"
        ┌───────────────────┐
        │  Claude Code      │
        │    runtime        │───── stdin JSON ──┐
        └─────────┬─────────┘                    │
                  │                              ▼
                  │              ┌─────────────────────────────┐
                  │              │      git-guard.sh           │
                  │              │   (/bin/sh + jq)            │
                  │              │                             │
                  │              │  1. jq → unescape command   │
                  │              │  2. split on && || ; |      │
                  │              │       and real newlines     │
                  │              │  3. per-segment:            │
                  │              │       strip VAR=val         │
                  │              │       strip quote on token0 │
                  │              │       recurse for sh -c …   │
                  │              │       require token0 ≈ git  │
                  │              │       peel -C/-c/--git-dir  │
                  │              │       match subcommand      │
                  │              │  4. exit 0 (allow) or 2     │
                  │              └──────────────┬──────────────┘
                  │                             │
        exit 0 ◄──┘            exit 2 + stderr ─┘
                  │                             │
                  ▼                             ▼
        ┌───────────────────┐         ┌───────────────────┐
        │    /bin/bash      │         │  Bash call denied │
        │  runs the command │         │   reason → LLM    │
        └───────────────────┘         └───────────────────┘
```

### Parse pipeline, by example

```
input:  "FOO=bar git -C /tmp reset --hard HEAD~1"

      │ jq unescape JSON (\n, \t, \", \\ → real chars)
      ▼
"FOO=bar git -C /tmp reset --hard HEAD~1"

      │ chain split: && || ; | newline → 1 segment
      ▼
"FOO=bar git -C /tmp reset --hard HEAD~1"

      │ strip leading KEY=val assignments
      ▼
"git -C /tmp reset --hard HEAD~1"

      │ strip enclosing quotes around token0 ('git' / "git" → git)
      │ recurse if token0 ∈ {sh, bash, /bin/sh, /bin/bash, …} with -c <str>
      │ accept token0 if it matches  git  or  */git
      ▼
"-C /tmp reset --hard HEAD~1"

      │ peel global flags: -C <path>, --git-dir=, --work-tree=, -c, --no-pager …
      ▼
"reset --hard HEAD~1"

      │ subcommand → reset
      ▼
DENY  ─→  stderr: "git reset is denied (rewrites history or destroys work). …"
          exit 2
```

## Detection guarantees

### Caught (verified by tests)

For every form below, the hook catches a destructive subcommand regardless of
where the dressing sits:

| Dressing | Example | Caught? |
|---|---|---|
| Plain | `git reset --hard HEAD` | yes |
| `-C <path>` | `git -C /tmp reset --hard HEAD` | yes |
| `--git-dir=<path>`, `--work-tree=<path>` | `git --git-dir=/tmp/.git reset …` | yes |
| Env-var prefix | `FOO=bar git reset --hard` | yes |
| Chain `&&` `||` `;` `|` | `ls && git reset --hard` | yes |
| Real newlines (multi-line scripts) | `cd /tmp` `\n` `git reset --hard` | **yes** |
| Absolute path | `/usr/bin/git reset --hard` | yes |
| Relative path | `./git reset --hard` | yes |
| Quoted first token | `'git' reset --hard`, `"git" reset` | yes |
| `sh -c "<inner>"` wrapper | `sh -c "git reset --hard"` | yes (single-level recursion) |
| `bash -c "<inner>"` | `bash -c "git reset --hard"` | yes |
| `/bin/sh -c "<inner>"`, `/usr/bin/bash -c …` | absolute-path -c | yes |

### Not caught (out of scope)

These require runtime context the hook doesn't have. They're documented as
known limitations, not pretended-to-handle:

| Form | Why uncaught | What stops it instead |
|---|---|---|
| `eval "$DESTRUCTIVE_STRING"` | The string isn't statically inspectable | LLM classifier; agent self-discipline |
| `echo reset --hard \| xargs git` | git invoked via xargs; first token is `xargs` | classifier; restricted shell |
| `$(...)` / `` `...` `` subshells | Recursion into subshells not implemented | classifier |
| Base64-decoded command | Need runtime eval | sandbox |
| Shell aliases defined in a sourced rc | Hook doesn't read rc | rely on no rc on non-login shells |
| Shell functions defined inline | `f() { git reset; }; f` — token0 is `f` | classifier; future work |

If any of these become real bypasses in practice, harden case-by-case. Don't
over-engineer for theoretical adversaries; the threat model is *autonomous
agent drift*, not a malicious actor.

## Behavior matrix

| Subcommand | Verdict | Notes |
|---|---|---|
| `reset`, `checkout`, `stash`, `rebase`, `cherry-pick`, `revert`, `clean`, `reflog`, `filter-branch`, `gc`, `prune`, `fsck` | DENY | Blanket |
| `branch` with `-D`, `-d`, `-m`, `-M`, `--delete`, `--move` | DENY | Destructive ref ops only — `git branch` (list) and `git branch <newname>` allowed |
| `config` with `--get*` / `--list` / `-l` / `--show-*` / `-h` | allow | Read-only |
| `config` otherwise | DENY | Writes |
| `push` with `--force` / `-f` | DENY | `--force-with-lease` allowed |
| `merge --abort` | DENY | |
| `worktree remove <path>` | conditional | Allowed iff `<path>` is clean AND has no commits ahead of upstream. `--force` always denied |
| Other git subcommands | allow | `status`, `diff`, `log`, `add`, `commit`, `push`, `pull`, `fetch`, `worktree add`, `worktree list`, … |
| Non-`git` commands | allow | Returns 0 immediately after the segment check |

## Overhead

Measured: 100 invocations against this hook on this Mac, payload sent via
stdin.

```
Non-git command  (ls -la /tmp)        p50 =  7.10 ms  p95 =  8.24 ms
Non-git command  (npm install …)      p50 =  6.73 ms  p95 =  7.46 ms
Git allow        (git status)         p50 = 19.33 ms  p95 = 26.29 ms
Git deny         (git reset --hard)   p50 = 19.83 ms  p95 = 25.29 ms
Multi-line + git reset                p50 = 21.14 ms  p95 = 25.12 ms
worktree remove (adds git status …)   add ~17 ms for the porcelain check
```

Weighted average (assuming a typical agent session is ~80% non-git,
~20% git): **~9.6 ms per Bash call.**

### Fast path for non-git commands

Most `Bash` calls in a session (`ls`, `npm`, `cat`, `mkdir`, …) have nothing
to do with git. The first thing the hook does after buffering stdin is a
substring check on the raw JSON:

```sh
case "$input" in *git*) ;; *) exit 0 ;; esac
```

If the raw input doesn't even contain the literal substring `git`, the hook
exits without spawning `jq` or running any parse logic. This cuts ~6 ms off
every non-git call.

### Breakdown of the git path (~14–20 ms)

- `/bin/sh` cold start: ~3.5 ms
- buffer stdin (`input=$(cat)`) + substring case: ~0.5 ms
- `jq -r .tool_input.command`: ~8 ms (dominant cost on the git path)
- sed pipeline (chain split, segment trim): ~2 ms
- shell logic (cases, peeling): ~0.5 ms

Trade-off vs an earlier sed-only version (~4 ms across the board): the jq path
adds ~8 ms on the git path but gains correct JSON unescape — without which
`\n`-escaped multi-line commands silently bypass the hook. Multi-line is the
realistic case for agent-authored scripts, so correctness wins.

### Matcher specificity

Hook is registered with `matcher: "Bash"`. Per Claude Code spec, an
alphanumeric matcher is exact-match:

> Only letters, digits, `_`, and `|` → exact string, or `|`-separated list of
> exact strings. `Bash` matches only the Bash tool.

So the hook fires on `Bash` tool calls only. Zero overhead on `Read`,
`Edit`, `Write`, `Grep`, `Glob`, `BashOutput`, `KillBash`, MCP tools, or
`Agent` subagents.

## Verification

23 test cases, all pass on the current script (see `~/.agents/hooks/` for the
test harness). Highlights:

| # | Input | Expected | Result |
|---|---|---|---|
| 1 | `ls -la /tmp` | allow | allow |
| 2 | `git reset --hard origin/main` | deny | deny |
| 3 | `git -C /tmp reset --hard HEAD` *(the original bypass)* | deny | **deny** |
| 4 | `git -C $REPO branch -D foo` | deny | deny |
| 5 | `git -C /tmp status --porcelain` | allow | allow |
| 6 | `git push --force origin main` | deny | deny |
| 7 | `git push --force-with-lease origin main` | allow | allow |
| 8 | `ls -la && git -C /tmp reset --hard` *(chain)* | deny | deny |
| 9 | `FOO=bar git -C /tmp rebase origin/main` *(env prefix)* | deny | deny |
| 10 | `git config --get user.name` | allow | allow |
| 11 | `git config user.name newname` *(write)* | deny | deny |
| 12 | `worktree remove` on clean+pushed | allow | allow |
| 13 | `worktree remove` on dirty | deny | deny (lists files) |
| 14 | `worktree remove` on unpushed | deny | deny (lists ahead count) |
| 15 | `worktree remove --force` | deny | deny |
| 16 | `cd /tmp` `\n` `git reset --hard` *(real newline)* | deny | **deny** |
| 17 | `sh -c "git reset --hard HEAD"` | deny | **deny** |
| 18 | `bash -c "git reset --hard HEAD"` | deny | **deny** |
| 19 | `/bin/sh -c "git reset --hard"` | deny | **deny** |
| 20 | `/usr/bin/git reset --hard HEAD` *(absolute path)* | deny | **deny** |
| 21 | `"git" reset --hard HEAD` *(double-quoted)* | deny | **deny** |
| 22 | `'git' reset --hard HEAD` *(single-quoted)* | deny | **deny** |
| 23 | `eval "git reset --hard"` *(out of scope)* | allow | allow (documented) |

Cases 16–22 are the hardening that lifted the hook from "trivially evadable
with multi-line or wrapper syntax" to "deterministic detection on every form
an agent realistically produces."

In-session live verification: with a diagnostic line writing to
`/tmp/git-guard.log` on every fire, each Bash tool invocation produced one
entry. The hook is on the actual PreToolUse path for this Claude version
(2.1.142).

## Where the pieces live

| Path | Role |
|---|---|
| `~/.agents/hooks/git-guard.sh` | Canonical source |
| `~/.agents/hooks/git-guard.md` | This document |
| `~/.agents/agents.yaml` → `hooks.git-guard` | Manifest: PreToolUse, matcher `Bash`, agents claude+codex+gemini, timeout 5s |
| `~/.agents/.history/versions/<agent>/<ver>/home/.claude/hooks/git-guard.sh` | Per-version synced copy |
| `~/.claude/settings.json` `.hooks.PreToolUse[]` | Active registration |

Activate after source edits: `agents sync --agent claude --agent-version <ver>`.

## Maintenance notes

- **Adding a new banned subcommand**: append to the `case "$sub"` block in
  `check_segment`. Add a row to the Behavior matrix.
- **Allowing a previously-banned form**: narrow with arg inspection (like
  `config` split into read/write, or `push` split into normal/force). Don't
  remove from the blanket case unless you've confirmed it's never destructive.
- **Closing a documented out-of-scope gap**: see "Not caught" table. The fix
  pattern is to extend `check_segment` to recognize the wrapper (e.g.,
  `eval`) and either deny it outright or recurse into the inner string.
- **Dependency**: requires `jq` on `$PATH`. Apple ships `/usr/bin/jq` since
  macOS 14.x; Linux distros bundle it via `apt install jq` / `dnf install jq`.
  If you ship this as part of agents-cli system defaults, add `jq` to
  `~/.agents/cli/`.
- **POSIX sh only**: no bash features (`[[`, `<<<`, arrays). Runs on
  `/bin/sh` (dash on Linux, bash-in-sh-mode on macOS).
- **Limitation reminder**: this is a guardrail against accidents and LLM
  bypass drift, not a sandbox. Determined runtime obfuscation (`eval` of a
  computed string, `xargs git`, base64-decoded payloads) is out of scope.
