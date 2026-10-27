# Arc

An Arc profile is driven natively through Apple Events, not CDP. The task's tab is an ordinary tab in the user's own Arc Space, and the user keeps working in Arc while you drive it.

## What Arc cannot do

These fail with `Native Arc does not support <capability>`:

- `screenshot` (it would have to bring the tab to the front)
- asynchronous JavaScript: `evaluate` runs synchronous expressions only
- `console` and `errors` capture, `requests` and `responsebody`
- `record`, `pdf`, `upload`, `download`, `set viewport`
- coordinate clicks (`click --at X,Y`)
- `show` (the viewer cannot open a task-less Arc tab)

Read the page with `evaluate` instead of a screenshot, for example `browser evaluate "document.body.innerText.slice(0, 4000)" --task <task>`. If the task needs a picture, ask the user, or tell them the task needs a CDP browser.

Do not pass an async function to `evaluate`. Arc starts running it before the CLI rejects it, so side effects such as clicks still happen and a retry repeats them. Write the step as one synchronous expression.

## Sharing the user's window

- The user can click in your tab. Before any step that writes data (a note, a message, a form submit), check the page is still yours: `browser evaluate "location.href" --task <task>`. If the URL changed, stop and tell the user. Do not write into whatever page is showing.
- Do not run `browser tab focus`. It switches the user's window to your tab.
- Creating a tab selects it for up to 2 seconds while Arc loads it, then returns the user to their tab.

## Errors

- `Creation marker did not resolve exactly one tab`: Arc created the tab late. Run your next command with the same `--task`; the task adopts the tab once it appears.
- `Arc Apple Event timed out`: Arc was busy. Retry once.
- `Owned Arc tab … is missing from its original window/Space`: the tab was closed or moved. Start a new task.
