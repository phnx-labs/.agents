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
| Electron desktop apps | `electron-use.md` | Attach to a running Electron process via CDP port |

## Which machine? (`--device`)

The routing table above picks the *kind* of target. This picks the *box*.

Every `agents browser` command takes `--device <host>`, which runs the CLI over
there — so the target machine resolves its own profile. **Never pass `--profile`
on a `--device` run**; you would be naming a profile that means something
different on that box.

The reason this matters is not display, it is credentials. A fleet usually has
one browser carrying the real logins, and it lives on one machine. An agent on a
worker that needs to act as the user (post, read a dashboard, use a signed-in
API) has to reach that browser rather than launch a logged-out one locally.

```bash
agents browser profiles logins                    # what is signed in here
agents browser profiles logins --device <host>    # ...and over there
agents browser navigate --device <host> --url https://example.com
```

`agents browser profiles logins` is the discovery step: one row per detected
session, with the profile name, the service, the signed-in account, and whether
login credentials sit in that profile's secrets bundle. Read it to find which box
holds the session you need before you drive anything.

**Do not use `agents ssh <host> 'agents browser ...'`.** It reaches the same
machine but skips the fleet dispatch path, so the remote-control consent marker
is never set — the target cannot tell it is being driven remotely. `--device` is
the supported form.

A machine only accepts remote drives when its owner has run
`agents browser remote-control on` there; a refusal names that command.

## Decision Tree

```
What are you automating?
├── Web page / web app → browser-use.md
│   └── Specific site with known quirks? → domain-skills/<site>/
└── Electron desktop app (VS Code, Slack, …) → electron-use.md
    └── App in app-skills/? → read that first, then follow electron-use.md
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
