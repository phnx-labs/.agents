---
name: computer
description: Drive desktop apps with the standalone Computer CLI — screenshot windows, click, type, drag, read text. Triggers on automating native or Electron apps, remote Windows or VNC desktops, "computer use", or capturing an app window.
argument-hint: "[bundle-id]"
allowed-tools: Bash(computer*), Bash(sleep*)
user-invocable: true
---

# Computer Use

The standalone `@phnx-labs/computer-cli` package drives desktops: the local Mac through Accessibility and screen capture, remote Windows over SSH, and any Linux or X desktop over VNC. For websites use the `browser` skill. Run `computer <verb> --help` for exact flags; `computer sessions --json` shows recorded activity.

## Read the guide for your desktop first

- **The local Mac** (no `--host`): [`references/macos.md`](references/macos.md). The user is usually working on that Mac; it says which verbs take their screen and keyboard and which do not. Read it before your first action.
- **Linux or any desktop over VNC** (`--host vnc://…`): [`references/vnc.md`](references/vnc.md). Coordinate-only; everything there is read from screenshots.

Install with `agents clis install computer` if `computer --version` fails.

When your harness takes MCP servers, `computer mcp` (add `--host vnc://…` for a VNC desktop) serves these verbs as tools. Each input tool returns the screen after it in the same result, so one call acts and looks. Over VNC its coordinates are pixels of the latest screenshot it returned.

## The loop

Observe, act, verify. Never chain actions you have not seen the result of.

- Add `--screenshot <path>` to an input verb to capture the screen after it in the same call, then read that file. A separate `screenshot --out <path>` is only needed before the first action.
- A screenshot reports `origin` and `scale` (the `saved:` line, or `--json`). A pixel in the image maps to a desktop coordinate as `x = origin_x + pixel_x / scale`, `y = origin_y + pixel_y / scale`.
- `ok:true` means the event was sent, not that the app reacted. A screenshot identical to the one before means the action did not land: re-derive the coordinates from a fresh capture before retrying.

## Verbs

| Verb | What | Key flags |
|---|---|---|
| `screenshot` | Capture a window or the display | `--out`, `--json`, `--max-dimension` |
| `click` / `right-click` | Click an element or a point | `--id` \| `--x --y`; `--count 2` double-clicks |
| `type-text` | Type into the focused field | `--text`, `--commit` |
| `key` | Key chords, comma-separated | `--keys "ctrl+a,Delete"` |
| `scroll` | Scroll at a point or element | `--dy` / `--dx` |
| `drag` | Press, move, release | `--from x,y --to x,y` |
| `wait` | Sleep or poll for an element | `--duration` \| `--id --until` |
| `apps`, `launch`, `raise`, `describe`, `get-text`, `type`, `focus`, `ax-action` | macOS only; see `references/macos.md` | |

## Safety rails

- Password fields are refused unless `type --allow-secure-field` is passed. Pass it only when the user asked you to fill a credential.
- System surfaces (`tccd`, SecurityAgent, System Settings) are denied by the daemon; do not automate permission prompts.
- Before a destructive in-app action (delete, send, purchase), check the state on a screenshot before and after, and confirm with the user when it cannot be undone.
