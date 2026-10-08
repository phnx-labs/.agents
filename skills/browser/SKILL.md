---
name: browser
description: Drive the user's real browser from the command line with the `browser` CLI — open sites they are signed into, navigate, click, type, read pages, take screenshots, capture console and network traffic, and show pages to the user. Use for any task that needs a website or web app, including logged-in sites, form filling, scraping, testing a web app, and opening a report or page for the user to look at.
allowed-tools: Bash(browser:*)
---

# browser

`browser` drives real browsers (Chrome-family over CDP, Firefox over BiDi, Arc natively) with the user's own profiles, cookies and logins.

## Use the user's browser

Start without `--profile` or `--device`:

```bash
browser start --url https://example.com
```

A bare start opens the browser the user configured as their default. When the machine is set to drive another device's browser, the start runs there. `browser use` prints the default. Pass `--profile` or `--device` only when the user asks for a different browser.

Do not create profiles, launch a headless browser, or switch to another machine's browser to work around an error. Sites block remote and cloud browsers, and those browsers do not have the user's logins. Report the error instead.

## Workflow

```bash
browser start --url https://example.com    # stdout is the task name
browser refs --task <task>                 # interactive elements, numbered
browser click 3 --task <task>              # act on a ref
browser done --task <task>                 # close the task's tabs
```

Everything else (typing, waiting, evaluating JavaScript, screenshots, console and network capture) is in `browser --help`.

- Pass `--task <task>` on every call. Each shell is new, so an exported variable is gone by the next call.
- Refs are numbers from the latest `refs` output. They change when the page changes, so run `refs` again after each action.
- `browser start --url` prints the site guide for that site when one exists (`--- site guide: … ---`). Read it before you click.

## Flags: read the help, never guess

```bash
browser <command> --help      # options for one command
browser help --json           # every command, argument and option
```

An `unknown option` error means the flag does not exist. Read that command's `--help`.

## Show the user a page

```bash
browser show https://example.com
browser show ./report.html
```

`show` opens it in the user's configured viewer and binds no task. Add `--json` to see which browser actually opened it.

## Arc

When the task's profile is an Arc profile, read `references/arc.md` first. Arc has no screenshots and runs only synchronous JavaScript, and the agent's tab sits in the user's own Arc window.

## When something fails

- `browser status` lists the service and running tasks.
- Service unresponsive, or IPC requests time out: `browser stop --service`, then retry the command.
- `nothing is speaking CDP on port …`: that profile's browser is not running. Tell the user; do not switch browsers.
- `Task "…" not found`: the task ended. Start a new one.

## Reference documents

```bash
browser skills list            # this skill's documents
browser skills get arc         # references/arc.md
browser skills get slack       # a site guide, references/sites/slack.md
```

- `references/arc.md`: Arc limits and how to share the user's window safely.
- `references/sites/<site>.md`: per-site selectors and gotchas (higgsfield, linkedin, perplexity, slack).
- `scripts/slack/*.js`: page scripts for `browser evaluate --file`, used by the Slack guide.
