# Browser Use — Web Automation

CDP-based automation for websites and web apps.

## Quick Start

```bash
# Create a profile (one-time)
agents browser profiles create my-profile -b chrome -e cdp://localhost:9222

# Start a task — sets AGENTS_BROWSER_TASK for the session
export AGENTS_BROWSER_TASK=$(agents browser start --profile my-profile)

# Navigate and interact
agents browser tab add --url https://example.com
agents browser refs
agents browser click <ref>
agents browser type <ref> --text "hello"
agents browser screenshot
agents browser done
```

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
agents browser stream --task "$AGENTS_BROWSER_TASK"
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
# Start — stdout is the resolved task name; export it so no per-call --task is needed
export AGENTS_BROWSER_TASK=$(agents browser start --profile <profile>)

agents browser status        # list running tasks
agents browser done          # complete task, close tabs, save to history
agents browser stop          # stop without saving to history
```

## Tabs

```bash
agents browser tab add --url <url>  # open URL in new tab (becomes current)
agents browser tabs                 # list open tabs
agents browser tab focus <tabId>    # switch to tab (by ID, prefix, or URL substring)
agents browser tab close [tabId]    # close specific tab, or all if omitted
agents browser navigate --url <url> # navigate current tab in place (no new tab)
```

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
export AGENTS_BROWSER_TASK=$(agents browser start --profile remote-mac)
agents browser tab add --url https://example.com
```

The SSH driver launches the browser on the remote host and tunnels CDP back.

## Workflow Pattern

1. **Create profile** (one-time): `agents browser profiles create …`
2. **Start**: `export AGENTS_BROWSER_TASK=$(agents browser start --profile <name>)`
3. **Open tab**: `agents browser tab add --url <url>`
4. **Wait** for page to load (`--state networkidle` or `--selector`)
5. **Refs** to see clickable elements
6. **Click / type / press** using refs
7. **Refs** again after each action — refs are ephemeral
8. **Screenshot** liberally — screenshots are your eyes
9. **Console/errors** if something seems wrong
10. **Done**: `agents browser done`
