# Electron Use — Desktop App Automation

Attach to a running Electron app via its CDP debug port and automate it using the same `agents browser` commands.

## Key Differences from Web Automation

| Behavior | Web | Electron |
|---|---|---|
| Opening new tabs | `tab add --url <url>` | Not supported — reuses the existing window |
| Browser type flag | `chrome`, `comet`, etc. | `custom` (skips identity check) |
| Extra profile flag | — | `--electron` required |
| Target selection | Any new tab | Picks the visible window; skips internal Electron pages |
| Launching | browser spawned automatically | Attach only — app must already be running |

## Setup: Create a Profile (One-Time)

```bash
agents browser profiles create <name> \
  --browser custom \
  --electron \
  -e cdp://localhost:<debug-port>
```

The app must already be running with `--remote-debugging-port=<port>` in its launch args. Verify:

```bash
curl -s http://localhost:<port>/json | head -20
```

## Start a Task (Attach)

```bash
agents browser start --profile <name>    # prints the task handle; later calls take --task <handle>
```

Attaches to the running process — does **not** launch a new instance. Confirm:

```bash
agents browser status    # shows "attached" (not a pid) next to the task
```

## Navigate

```bash
agents browser navigate --url https://app.local/#/settings
```

Navigates the existing window in place. Hash-based routing works normally. There is no `tab add` in Electron mode.

## Interact

```bash
agents browser refs
agents browser refs -t <tabId>
agents browser click <ref>
agents browser type  <ref> --text "text"
agents browser press Enter
agents browser screenshot
agents browser screenshot -o /tmp/out.png
```

## Evaluate — Probe Window Objects and IPC

`agents browser evaluate` runs arbitrary JS with `awaitPromise: true`. Use it to inspect preload-exposed APIs and call IPC bridges:

```bash
# Discover what the app exposes
agents browser evaluate --expression 'Object.keys(window)'
agents browser evaluate --expression 'Object.keys(window.myApp || {})'

# Call an async IPC method
agents browser evaluate --expression '(async () => await window.myApp.someMethod())()'

# For longer scripts, load from a file (no shell-quoting hell)
agents browser evaluate --file ./probe.js

# Inspect current route
agents browser evaluate --expression 'location.pathname + location.hash'
```

## Target Filter — Pick a Specific Window

If the app has multiple renderer windows, pin the right one at profile creation:

```bash
agents browser profiles create my-app \
  --browser custom \
  --electron \
  --target-filter "app.example.com" \
  -e cdp://localhost:<port>
```

Without `--target-filter`, the service skips invisible pages (`about:blank`, `file://`, internal background pages) and picks the first visible window.

## Common Gotchas

### Preload doesn't hot-reload

Preload scripts and main-process IPC handlers load once at app launch — they do not reload when source files change. If a `window.*` method exists in source but is missing at runtime, the process is stale. Restart the app.

Quick check:
```bash
# What does source declare?
grep -rn "contextBridge.exposeInMainWorld" <app>/src/preload.ts

# What does the running renderer expose?
agents browser evaluate --expression 'Object.keys(window.myApp || {})'
```

If source has methods the runtime doesn't, restart the process.

### Multiple hidden windows

Electron apps often have background service windows alongside the main UI. If `start` lands on the wrong window, screenshot to confirm, then add `--target-filter` to the profile or use `-t <tabId>` to pin the right tab.

### No new tabs

`tab add` is not supported in Electron mode — use `navigate` to move the existing window to a different route.

### Debug port not exposed

If `curl http://localhost:<port>/json` returns nothing, the app wasn't launched with `--remote-debugging-port`. You cannot attach to a process that didn't open the port at startup.

## App-Specific Guides

If the app has an entry in `app-skills/`, read it first — it has verified IPC surfaces, route maps, and quirks already discovered. If no entry exists, the general patterns above are enough to get started.

| App | Subskill |
|---|---|
| Rush desktop | `app-skills/rush/` |

## Workflow Pattern

1. **Verify** `curl -s http://localhost:<port>/json` returns pages
2. **Check `app-skills/`** for this app — if found, read it; if not, proceed with general approach
3. **Create profile** (one-time): `agents browser profiles create <name> --browser custom --electron -e cdp://localhost:<port>`
4. **Start**: `agents browser start --profile <name>` — remember the printed handle; pass `--task <handle>` on every call
5. **Screenshot** to confirm which window you landed in
6. **Evaluate** `Object.keys(window)` to discover what the app exposes
7. **Navigate** to the route under test
8. **Refs → click/type** as normal
9. **Done**: `agents browser done` — does not kill the app
