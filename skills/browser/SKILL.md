---
name: browser
description: Drive a browser to automate websites — fill forms, click buttons, take screenshots, scrape pages. Uses the built-in `browser` command (or `agents browser`).
argument-hint: "[url]"
allowed-tools: Bash(browser*), Bash(agents browser*), Bash(sleep*)
user-invocable: true
---

# Browser Automation

Routes to specialized subskills based on the target.

## Routing Table

| Target | Subskill | When to Use |
|---|---|---|
| Websites, web apps | `browser-use.md` | Any HTTP/HTTPS URL in a regular browser |

## Configured browser and viewer

Use `agents browser start` for automation. The CLI resolves `browser.device`
when a fleet hub is configured, otherwise this machine, then that machine's
`browser.profile`. `agents browser use` reports the default; `agents browser
profiles list` lists discovered profiles and their devices. Follow the live
session configuration, never a hardcoded browser or host.

Use `agents browser show <url|file>` on the user's interactive host for pages
they should read. It resolves `browser.viewer`, then `browser.profile`; `os`
selects the OS default browser. Viewer tabs are not owned by an automation task. The CLI may report a fallback
to the OS browser when the configured profile cannot open viewer tabs; do not
claim it opened the selected profile without checking the result (`--json`).
Deliver local files to that host before opening them.

To drive another device explicitly, use `agents browser start --device <host>`
and omit `--profile` so the target resolves its own configuration. Later commands
use the task bound at start. Check the installed command help for supported options. Remote driving requires the owner's remote-control
consent on the target; do not bypass a refusal through SSH.

Profiles reflect the installed browser's capabilities. Inspect the selected
profile before choosing capture or interaction commands. A missing capability
is not a reason to silently switch the user's configured browser or create a
fresh profile without their logins.

## Decision Tree

```
What are you automating?
└── Web page / web app → browser-use.md
    └── Specific site with known quirks? → domain-skills/<site>/
```

## Adding a new domain-skill

When you need to drive a site that doesn't have a `domain-skills/<site>/` entry yet:

1. **Check upstream first.** [browser-use/awesome-prompts](https://github.com/browser-use/awesome-prompts) is a community library of agent prompts for popular sites — often a faster starting point than writing selectors from scratch. Adapt their snippets into our `SKILL.md` format (frontmatter `description:` + body); credit upstream in the body.
2. **Scaffold the directory:** `domain-skills/<site>/SKILL.md` plus any helper scripts under `scripts/`.
3. **Match by directory name** (e.g. `slack` resolves both `slack.com` and `app.slack.com`), or set an explicit `domains:` array in the frontmatter for cross-host coverage:
   ```yaml
   ---
   description: Drive <site>...
   domains: [mail.google.com, gmail.com]
   ---
   ```
4. **Auto-discovery:** `agents browser start --url <url>` now auto-loads the matching `SKILL.md` and surfaces its contents on stderr so an agent driving the task has site-specific guidance before clicking anything. Pass `--no-skills` to opt out.
