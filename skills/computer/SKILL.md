---
name: computer
description: Drive native macOS apps — screenshot windows, click, type, drag, read text. Uses the built-in `agents computer` command (Accessibility + ScreenCaptureKit daemon). Triggers on automating desktop apps (Photoshop, Parallels VMs, Finder, any non-browser GUI), "computer use", clicking/typing in a Mac app, or capturing an app window.
argument-hint: "[bundle-id]"
allowed-tools: Bash(agents computer*), Bash(sleep*)
user-invocable: true
---

# Computer Use — macOS App Automation

Drives native macOS apps through the Computer Helper daemon (Accessibility + ScreenCaptureKit + HID-tap event synthesis). macOS only. For websites use the `browser` skill; for Electron apps prefer `browser`'s `electron-use.md` (CDP beats pixel automation when available).

When you need exact flags, run `agents computer <verb> --help`.

## Focus safety — do not steal the user's screen (read first)

The user is usually working on the same Mac. **Element mode does not take over their screen; coordinate mode and `--raise` do.** Default to element mode, and reach for the focus-stealing paths only when you truly need them.

- **Element mode (focus-safe, default):** `describe` → `click --id @eN` / `type --id` / `focus --id` / `ax-action`. These fire Accessibility actions (AXPress / set-AXValue) that **do not activate the app and do not move the cursor** — the user keeps typing in their own window while you act. `--raise` is *ignored* in element mode (element actions don't need the app frontmost), so it can't hijack focus.
- **Capture is always focus-safe:** `screenshot --window-id <n>` grabs any window across Spaces **without raising it**.
- **`--raise` and coordinate mode (`--x/--y`) STEAL the screen:** `--raise` brings the app forward and takes keyboard focus; coordinate clicks warp the physical cursor and need the app frontmost. Reserve them for AX-opaque surfaces (VM guests, Chromium/canvas/games) or when the user is away — never to drive an ordinary AppKit app the user can see. The CLI prints a `note:` whenever a verb will cost the user their focus or cursor.
- **To only *view* a webview (VS Code / Electron), use a browser or the repo's preview harness — not this skill.** Reach for `agents computer` on Electron only for what a browser can't do (window reload, AX text extraction when Screen Recording is denied).

## Preflight

```bash
agents computer status     # installed? daemon running? trust granted? policy?
agents computer setup      # one-time install to /Applications (then: start)
agents computer start      # boot the daemon (writes policy + peers, launchctl)
```

The daemon only drives **allow-listed** apps. `permission_denied` or `bundle not in allow list` means the target is missing from policy:

```bash
# Add to a permissions group, then reload
echo '  - "Computer(com.example.app)"' >> ~/.agents/permissions/groups/02-computer-apps.yaml
agents computer reload
```

Find a bundle id: `osascript -e 'id of app "AppName"'`.

## The Core Loop

Every interaction follows **observe → act → verify**. Never chain actions blind. The default loop is **focus-safe — no `raise`**, so the user keeps their screen:

```bash
agents computer apps                                   # 1. what's running (allow-listed)
agents computer screenshot --bundle <id> --list --json # 2. enumerate windows (focus-free)
agents computer screenshot --bundle <id> --window-id <n> --out /tmp/s.jpg
agents computer describe --bundle <id>                 # 3. AX tree (element ids @eN)
agents computer click --bundle <id> --id @e7           # 4. act (AXPress — no focus steal)
agents computer screenshot ... --out /tmp/s2.jpg       # 5. VERIFY — re-capture, compare
```

Add `raise` **only** when the target genuinely must be frontmost — an AX-opaque surface (VM guest) or key-window-gated keystrokes (see Focus safety). Raising takes the user's foreground; don't do it to drive an app you can already reach by element id.

A **byte-identical screenshot after an action means the action did not land**. Treat `ok:true` as "the event was posted", not "the app reacted" — only a visible state change is proof.

## Two Targeting Modes

**AX mode** (preferred, focus-safe): `describe` dumps the accessibility tree; element ids (`@eN`) feed `click --id`, `type --id`, `focus --id`, `ax-action`. Works for native AppKit apps and does not activate the app or move the cursor.

**Coordinate mode** (fallback, steals focus): for AX-opaque surfaces — **VM guests (Parallels), Chromium/UXP/canvas editors, games** — `describe` shows nothing useful inside them. Coordinate clicks warp the physical cursor and need the app frontmost, so only use this mode when AX can't reach the surface. Work from screenshots:

```
global_x = origin_x + pixel_x / scale
global_y = origin_y + pixel_y / scale
```

`origin` and `scale` are in every screenshot result (`--json` or the `saved:` line). Re-capture **after every raise or window move** — a window on an inactive fullscreen Space reports shifted global coords, so coordinates from a stale capture land in the wrong place.

## Focus Discipline (read this before typing)

Mouse clicks are HID-tap synthesized and need the target **visible on the active Space**. Keyboard (`type-text`, `key`) is posted to the pid and is **silently dropped by key-window-gated apps** (Parallels VMs and similar) when the app isn't frontmost.

- `raise` first. `--title` matches a window substring; bare raise activates the app.
- Add `--require-frontmost` to `type-text`/`key` whenever the target gates on key-window (VMs, anything that previously ate your keystrokes) — turns silent drops into a hard `not_frontmost` error.
- Every `type-text`/`key` result includes `"frontmost"`. A stderr warning or `frontmost:false` means the keystrokes probably landed nowhere — raise and retry, do not continue the chain.
- One-shot form: `type-text --raise --require-frontmost --text "..."`.
- Focus can be stolen **between** CLI calls (Space switches, user activity). If a mid-sequence step fails with `not_frontmost`, raise again; don't assume the earlier raise still holds.

## Verb Reference

| Verb | What | Key flags |
|---|---|---|
| `apps` | List drivable apps | `--json` |
| `launch` | Start an app | `--bundle` / `--path` / `--name` |
| `raise` | Bring app/window frontmost (switches Spaces) | `--window-id`, `--title` |
| `screenshot` | Capture window/display, or `--list` windows | `--window-id`, `--display`, `--out`, `--json` |
| `describe` | AX tree with element ids | `--depth` |
| `get-text` | Extract text without OCR | `--id`, `--max-chars` |
| `click` / `right-click` | Element or coordinate | `--id` \| `--x --y`; `--count 2` = double; `--raise` |
| `type` | Set an AX field value | `--id`, `--text`, `--commit` |
| `type-text` | Stream unicode keystrokes to the focused field | `--text`, `--commit`, `--raise`, `--require-frontmost` |
| `key` | Key chord (`enter`, `esc`, `cmd+shift+s`) | `--keys`, `--require-frontmost` |
| `drag` | Coordinate drag | `--from "x,y" --to "x,y"` |
| `scroll` | Scroll at element/coordinate | `--dy`/`--dx`, `--id` \| `--x --y` |
| `ax-action` | Any advertised AX action | `--id`, `--action AXConfirm` |
| `focus` | AX keyboard focus to an element | `--id` |
| `wait` | Sleep or poll for an element | `--duration` \| `--id --until` \| `--role/--label` |

## Failure-Mode Playbook

| Error / symptom | Meaning | Fix |
|---|---|---|
| `not_frontmost` | Keystrokes would be dropped | `raise` (with `--title` for the right window), retry |
| `window_offscreen` | Window on an inactive fullscreen Space; SCK can't capture | `raise --window-id <n>`, then re-screenshot |
| `element_not_found` (raise) | No AX window matched | `screenshot --list`, use the exact title substring |
| `element_stale` / dead `@eN` | UI changed since `describe` | Re-run `describe`, use fresh ids |
| `bundle not in allow list` | Policy gate | Add `Computer(<id>)` to a permissions group, `reload` |
| `rpc_timeout` | Daemon hung or stopped | `agents computer status`; `stop` + `start` |
| `ok:true` but screenshot unchanged | Event posted, app ignored it | Wrong coords (re-derive from a fresh capture) or window not key — raise, re-capture, retry |
| Typed text partially landed (VM guests) | Mid-stream focus blip | `key esc` to clear, retype with `--require-frontmost` |

## Worked Example: Drive a Windows VM (fully AX-opaque)

```bash
agents computer raise --bundle com.parallels.desktop.console --title "Windows 11" --json
agents computer screenshot --bundle com.parallels.desktop.console --list --json   # find window_id
agents computer screenshot --bundle com.parallels.desktop.console --window-id <n> --out /tmp/vm.jpg
# read /tmp/vm.jpg, pick a pixel target, map: global = origin + pixel/scale
agents computer click --bundle com.parallels.desktop.console --x 507 --y 960
agents computer type-text --bundle com.parallels.desktop.console --raise --require-frontmost --text "powershell"
agents computer key --bundle com.parallels.desktop.console --keys enter --require-frontmost
agents computer screenshot --bundle com.parallels.desktop.console --window-id <n> --out /tmp/vm2.jpg  # verify
```

## Electron Editors (VS Code / VSCodium / Cursor)

**First: if you only need to SEE a webview, open it in a browser — do not drive the Electron host at all.** Most VS Code/Electron webviews (dashboards, panels) can be rendered standalone via a dev/preview harness (Vite `bun run dev`, a `/preview` route) and screenshotted from a browser, which never touches the user's focus. Driving the app below to *view* a webview installs the extension and steals the screen for nothing.

**To actually OPERATE a webview** (click a real control, type into a React input): AX won't do it — `agents computer` accepts the action but the web app ignores it, so a reported `clicked`/`typed` is a no-op (the CLI now prints a `note:` steering you here). Drive it over **CDP**, which fires real DOM events and does not need the app frontmost:

```bash
codium --remote-debugging-port=9222 <folder>     # relaunch WITH the debug port (VS Code: `code`, Cursor: `cursor`)
agents browser profiles create vscodium --browser custom --electron -e cdp://localhost:9222
agents browser --electron navigate --url "…"      # then click/type via `agents browser` — focus-safe
```

The debug port opens **only at launch** — you cannot attach to an app already running without it (`electron-use.md:24,122`). An already-open editor must be relaunched (state loss); warn the user first.

The default advice is "prefer `browser`'s `electron-use.md` (CDP)." But you often must drive these via AX instead — to reload a window after installing an extension, or when Screen Recording is denied and screenshots are dead. These techniques take the user's focus, so use them only when a browser can't do the job. The webview UI sits in an iframe the AX tree only partially reaches; the rules below are the ones that bite. Bundle ids: `com.microsoft.VSCode`, `com.vscodium`, Cursor varies (`defaults read /Applications/Cursor.app/Contents/Info CFBundleIdentifier`).

- **AX survives a denied Screen Recording grant.** `get-text` and `describe` read the accessibility tree (incl. webview text) with no ScreenCaptureKit. Only `screenshot` needs Screen Recording. When captures time out with "denied Screen Recording permission," **verify with `get-text`**, not screenshots — grep its output for the strings the UI should render.
- **Reload a window to activate a freshly-installed extension.** Installing writes to disk; the running window keeps its old extension host until reloaded. Command palette → **"Developer: Reload Window"**. Every open window has its own host — reload each. An editor running with **zero windows** needs one first: `code -n <folder>`.
- **Use System Events keystrokes for the palette, not `agents computer key`, after a cross-window raise.** `osascript` System Events posts to the frontmost process coherently; `agents computer key` can race the raise and land in the wrong window. Pattern that works:
  ```bash
  osascript <<'EOF'
  tell application "VSCodium" to activate
  delay 0.5
  tell application "System Events" to tell process "VSCodium"
    perform action "AXRaise" of window "Factory — myrepo"   -- target a specific window by title
    delay 0.8
    keystroke "p" using {command down, shift down}           -- command palette
    delay 0.8
    keystroke "Developer: Reload Window"
    delay 0.8
    key code 36                                              -- Return
  end tell
  EOF
  ```
  List windows to pick a title: `osascript -e 'tell application "System Events" to tell process "Code" to get name of windows'`. The `cmd+\`` "next window" chord is **not** a valid `agents computer key` chord — raise by title instead.
- **`type-text`, not `type`, into the palette.** The palette field rejects `type --id` with `AXValue not settable`. `type-text` synthesizes keystrokes into the focused field and works.
- **Webview buttons (the Floor/Bench/Panel tabs, etc.) ignore both AXPress and coordinate clicks.** `click --id` does an AXPress that doesn't fire the React onClick; coordinate clicks miss because the iframe coordinate space and Retina scale don't line up with AX `bounds`. Drive webview state through the command palette or a keybinding, not by clicking webview chrome.
- **`@eN` ids are per-`describe` snapshots.** They go stale as the UI changes — re-`describe` immediately before you act, never reuse ids across calls.
- **Verify activation from `exthost.log`, not the GUI.** Authoritative and file-based:
  ```bash
  BASE="$HOME/Library/Application Support/Code/logs"   # or VSCodium / Cursor
  EH="$(ls -dt "$BASE"/*/ | head -1)"window1/exthost/exthost.log
  grep "_doActivateExtension <publisher>.<name>" "$EH" | tail -1   # fresh timestamp = live
  grep "\[error\]" "$EH" | grep -i "<name>" | tail -3              # post-activation errors
  ```
  A `_doActivateExtension` timestamp newer than your reload = that window runs the new code. (For the full publish→activate→verify flow, see the `code:release` skill.)

## Safety Rails

- Password/secure fields are refused unless `type --allow-secure-field` is passed explicitly. Don't pass it unless the user asked you to fill a credential.
- System surfaces (`tccd`, SecurityAgent, System Settings) are hard-denied by the daemon — don't try to automate permission prompts.
- Destructive in-app actions (delete, send, purchase) follow the same rule as everywhere: verify state via screenshot before and after, and confirm with the user when irreversible.
