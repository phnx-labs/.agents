# Browser Use — Web Automation

CDP-based automation for websites and web apps.

## Quick Start

```bash
# Create a profile (one-time)
agents browser profiles create my-profile -b chrome -e cdp://localhost:9222

# Start a task — stdout IS the task handle. Remember it; later calls take --task <handle>.
agents browser start --profile my-profile
# -> quiet-falcon-summit-a743161a

# Navigate and interact — `navigate` reuses the current tab; `tab add` opens a new one
agents browser navigate --url https://example.com --task <handle>
agents browser refs --task <handle>
agents browser click <ref> --task <handle>
agents browser type <ref> --text "hello" --task <handle>
agents browser screenshot --task <handle>
agents browser done --task <handle>
```

Do **not** `export AGENTS_BROWSER_TASK` and rely on it later: every agent tool call runs
in a fresh shell, so the export is gone by your next call. Remember the printed handle
and pass `--task <handle>` explicitly. (Inside one multi-command invocation a plain
shell variable is fine.)

## How do I keep a browser action loop warm?

For repeated observe-and-act work, launch `agents browser stream` once and keep its
standard input open. Send one JSON request per line; it returns one JSON response per
line, in order. The process and its connection to the existing browser daemon stay open
between requests.

```text
{"action":"screenshot","path":"/tmp/current.png"}
{"action":"refs"}
{"action":"click","ref":42}
{"action":"type","ref":15,"text":"hello"}
```

Set the task once when launching the process:

```bash
agents browser stream --task <handle>
```

Use the ordinary commands for a single action or when the calling tool cannot keep a
subprocess open. A successful `start` request changes the stream's default task, so one
stream can also own the full task lifecycle.

## Profiles

Profiles define browser type and connection endpoint. Create once, reuse across tasks.

```bash
agents browser profiles create local    -b chrome -e cdp://localhost:9222
agents browser profiles create mac-mini -b comet  -e ssh://mac-mini?port=9333
agents browser profiles list
agents browser profiles show <name>
agents browser profiles doctor <name>   # diagnose binary / port / user-data-dir
```

Supported browsers: `chrome`, `comet`, `chromium`, `brave`, `edge`

## Session Lifecycle

```bash
# Start — stdout is the task handle; pass it to every later call via --task
agents browser start --profile <profile>

agents browser status        # list running tasks
agents browser done          # complete task, close tabs, save to history
agents browser stop          # stop without saving to history
```

## Tabs

```bash
agents browser navigate --url <url> # PREFER THIS: reuse the current tab in place
agents browser tab add --url <url>  # open URL in a NEW tab (becomes current)
agents browser tabs                 # list open tabs
agents browser tab focus <tabId>    # switch to tab (by ID, prefix, or URL substring)
agents browser tab close [tabId]    # close specific tab, or all if omitted
```

### Showing a document: navigate, never a fresh `open`

To put a plan, report, or review doc in front of the user, use `navigate` — once the
task owns a tab it refreshes that SAME tab in place. A raw `open <file>`, or a
`tab add` per render, spawns a duplicate every single call.

```bash
agents browser start --profile <name>
# -> prints the task handle; pass it explicitly on every later call (see Quick Start)

agents browser navigate --url "file:///abs/path/report.html" --task <handle>
agents browser navigate --url "file:///abs/path/report.html" --task <handle>
# same tab both times — the doc refreshes, no second tab
```

`navigate` reuses `task.currentTabId`, so the FIRST navigate into a task that owns no
tab yet has to obtain one. On Chrome, Comet, Chromium and Brave it simply opens one.
**On Arc it cannot** — Arc crashes on `Target.createTarget` — so that first call
succeeds only against a tab that is already blank or already showing that exact URL,
and otherwise errors rather than taking over a page you are reading.

Note the deliberate `start` WITHOUT `--url` above. On Arc that is the better order:
`start --url` resolves its tab through a narrower path that matches only an exact-URL
tab held by an abandoned task, with no blank-tab fallback, so on a first-ever render it
goes straight to the create call and fails. Bare `start` then `navigate` at least
reaches the blank-tab fallback — provided Arc already has at least one page target.
(Bare `start` only creates a tab when the browser is otherwise EMPTY, and that create
throws on Arc too, so a freshly-launched Arc with no window open fails at `start`.)

If Arc has no blank tab and the doc is not already open, the agent cannot fix this
itself: `tab add` throws on Arc as well, so opening a tab is a HUMAN action in the Arc
window. The agent-executable option is a Comet/Chrome profile — prefer that for
agent-driven work, and keep Arc for what you are reading yourself.

This is not a style preference. Measured on one machine after a day of agent
activity: 58 tabs in a single window, 16 of them agent-opened `file://` docs,
with the same document open three times. Reach for `tab add` only when you
genuinely need two pages side by side.

On a remote interactive host, copy the file over and run the same command there:

```bash
scp report.html <host>:/tmp/report.html
agents ssh <host> "agents browser navigate --url file:///tmp/report.html"
```

Fall back to a one-shot `open` ONLY when the host has no drivable browser profile
(`agents browser profiles list` is empty and `agents browser start` cannot
auto-pick one) — showing something beats showing nothing, but it is the tab-spam
path.

## DOM Interaction

```bash
agents browser refs                       # interactive element refs for current tab
agents browser refs -t <tabId>            # refs for a specific tab
agents browser click <ref>                # click element
agents browser click <ref> -t <tabId>     # click in specific tab
agents browser type  <ref> --text "text"  # type into element
agents browser press Enter                # press key (Enter, Tab, Escape, …)
agents browser hover <ref>                # hover over element
agents browser scroll --dx 0 --dy 1000    # scroll down 1000px (negatives scroll up/left)
```

Refs are ephemeral — re-run `refs` after every action.

## Screenshots & Evaluation

```bash
agents browser screenshot                                      # capture current tab (auto-saves under sessions/<task>/)
agents browser screenshot -t <tabId>                           # specific tab
agents browser screenshot -o /tmp/out.png                      # save to path

agents browser evaluate --expression "document.title"          # run JS in current tab, return result
agents browser evaluate --expression "..." -t <tabId>          # specific tab
agents browser evaluate --file ./script.js                     # load JS from a file (avoids shell-quoting hell)
```

`evaluate` calls `Runtime.evaluate` with `awaitPromise: true` — async IIFEs work. Use `--file` for anything with quotes, backticks, or multi-line content.

## Console & Errors

```bash
agents browser console                    # all console logs
agents browser console --level error      # only errors
agents browser errors                     # uncaught exceptions
```

## Network Requests

```bash
agents browser requests                         # list captured requests
agents browser requests --filter api            # filter by URL substring
agents browser responsebody "api/data"          # wait for and read a response body
```

## Wait Conditions

```bash
agents browser wait --selector ".loaded"        # wait for element
agents browser wait --url "**/dashboard*"       # wait for URL match
agents browser wait --fn "window.APP_READY"     # wait for JS condition
agents browser wait --state networkidle         # wait for network quiet
agents browser wait --time 2000                 # wait N ms
```

## Downloads

```bash
agents browser download --path /tmp/downloads   # set download directory
agents browser waitdownload                      # wait for download to complete
```

## Viewport

```bash
agents browser set viewport 1280 720            # set viewport size
agents browser set device "iPhone 14"           # emulate device
agents browser devices                           # list available presets
```

## Account Credentials

```bash
eval "$(agents secrets export browser-accounts --plaintext)"
```

Always screenshot first — if the session is still alive in the profile, skip login.

## Rich Text Editors

`type` may fail on contenteditable / ProseMirror. Use evaluate:

```bash
agents browser evaluate --expression 'document.execCommand("insertText", false, "your text")'
```

## Remote Browsers (SSH)

```bash
agents browser profiles create remote-mac -b comet -e ssh://user@hostname?port=9222
agents browser start --profile remote-mac      # prints the task handle
agents browser navigate --url https://example.com --task <handle>
```

The SSH driver launches the browser on the remote host and tunnels CDP back.

## Workflow Pattern

1. **Create profile** (one-time): `agents browser profiles create …`
2. **Start**: `agents browser start --profile <name>` — remember the printed handle; pass `--task <handle>` on every call
3. **Show the page**: `agents browser navigate --url <url>` — reuses the current tab. Use `tab add` only when you need a SECOND page open at the same time.
4. **Wait** for page to load (`--state networkidle` or `--selector`)
5. **Refs** to see clickable elements
6. **Click / type / press** using refs
7. **Refs** again after each action — refs are ephemeral
8. **Screenshot** liberally — screenshots are your eyes
9. **Console/errors** if something seems wrong
10. **Done**: `agents browser done`
