---
name: secrets
description: "Manage named bundles of environment variables backed by macOS Keychain. Create bundles, add secrets, and inject them into agent runs. Use this skill when working with credentials, API keys, or sensitive configuration."
argument-hint: "[list|view|create|add|remove|import|export]"
allowed-tools: Bash(agents secrets*)
user-invocable: true
---

# Secrets Skill

Manage named bundles of environment variables backed by macOS Keychain. This skill teaches you how to use the `agents secrets` CLI.

## Concepts

- **Bundle** — A named container for secrets (e.g., "production", "staging", "stripe")
- **Secret** — A key-value pair inside a bundle
- **Keychain** — Secrets are stored in macOS Keychain by default (never touch disk in plaintext)

## Quick Start

```bash
# List bundles
agents secrets list

# Create a bundle
agents secrets create production

# Add a secret
agents secrets add production STRIPE_API_KEY
# Enter value when prompted (stored in Keychain)

# Use in an agent run
agents run --secrets production
```

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `list` | List bundles | `agents secrets list` |
| `view` | Show a bundle | `agents secrets view production` |
| `create` | Create empty bundle | `agents secrets create staging` |
| `delete` | Delete a bundle | `agents secrets delete staging` |
| `add` | Add a secret | `agents secrets add staging API_KEY` |
| `remove` | Remove a secret | `agents secrets remove staging API_KEY` |
| `import` | Import from .env or 1Password | `agents secrets import .env production` |
| `export` | Export to file or 1Password | `agents secrets export production .env` |

## Adding Secrets

```bash
# Keychain-backed (default)
agents secrets add production STRIPE_API_KEY
# Prompts for value, stores in Keychain

# Literal value
agents secrets add production DEBUG true --value

# From environment variable
agents secrets add production PATH --env

# From file
agents secrets add production CERT --file /path/to/cert.pem

# From command output
agents secrets add production TOKEN --exec "cat /tmp/token"
```

## Viewing Secrets

```bash
# Masked (default)
agents secrets view production

# Revealed (be careful)
agents secrets view production --reveal
```

## Remote secrets (other hosts)

Browse and *use* the bundles that live on another machine, over SSH. Hosts
resolve through the `agents devices` registry, an ssh-config alias, or `user@host`.
Use `--device` for one host and `--devices` for a comma-separated list.

```bash
# Browse bundles on one host, or several at once (grouped by host)
agents secrets list  --device yosemite-s1
agents secrets list  --devices yosemite-s0,yosemite-s1
agents secrets view  --device yosemite-s1 r2.backups --reveal --plaintext

# Use a remote bundle ephemerally — values are injected, never stored locally
agents secrets exec  --device yosemite-s1 r2.backups -- ./deploy.sh
agents run claude "ship it" --secrets r2.backups@yosemite-s1   # bundle@host
```

- **`bundle@host`** is the reference form for `agents run --secrets`; local and
  remote bundles mix freely in one run.
- **Ephemeral.** Remote values cross over SSH and are injected into the
  run/command env in memory — never written to this machine's keychain or disk.
- **The remote unlocks with its own credentials.** A file-backed remote bundle
  reads headlessly via the remote's own `AGENTS_SECRETS_PASSPHRASE`; a keychain
  bundle on a macOS remote blocks on Touch ID under non-interactive SSH — use a
  remote `file` bundle, an unlocked remote secrets-agent, or run `view --reveal`
  from an interactive terminal (it forces an SSH TTY so the prompt can surface).

### Push a bundle to another machine (`export --device`) — incl. Windows

```bash
# Push a bundle over SSH; it lands in the remote's native store. Works to
# macOS, Linux AND Windows targets (Windows lands in Credential Manager, or the
# headless file store when there's no logon session).
agents secrets export linear.app --device win-mini --force
agents secrets export r2.backups --device yosemite-s0 --device yosemite-s1
```

You don't do anything different for a Windows host — the push detects the
remote's platform and drives its `agents secrets import` under PowerShell instead
of `bash`. (Over a relayed link the push can take ~30-40s; that's the link, not a
hang.) `--remote-backend file` is POSIX-only and is refused cleanly on Windows.

### Unlock a remote Mac's bundle from the road (`unlock --device`)

```bash
# Away from the Mac Mini: unlock its FILE-backed bundle by typing the passphrase
# into YOUR terminal — the prompt surfaces over the ssh -tt session.
agents secrets unlock linear.app --device mac-mini
```

`unlock --device <machine> <bundle>` runs the unlock on the remote over `ssh -tt`,
so the remote's passphrase prompt appears on your terminal. Only **file-backed**
bundles work this way (their passphrase is a CLI prompt held in the remote's
secrets-agent, default 7d); a keychain/biometry bundle would pop a **local**
Touch-ID/passcode sheet on the remote's screen, which can't cross SSH. `--device`
here is single-valued, so put the bundle name first: `unlock <bundle> --device <machine>`.
Type the password interactively — it can't be piped.

## Multiple Accounts on One Website

Name the bundle after the domain (`x.com`, `linkedin.com`) — one bundle per site, any number of accounts inside. Group keys by account handle and give every account a `--note` saying when to use it:

```bash
agents secrets create x.com --description "X/Twitter accounts. Read key notes to pick the right one."

agents secrets add x.com THEMUQSIT_USERNAME --value themuqsit \
  --note "Personal account. Casual engagement, research."
agents secrets add x.com THEMUQSIT_PASSWORD --type password \
  --note "Password for @themuqsit"
agents secrets add x.com GETONRUSH_USERNAME --value GetOnRush \
  --note "Product account for promoting Rush. Marketing, announcements."
agents secrets add x.com GETONRUSH_PASSWORD --type password \
  --note "Password for @GetOnRush"
```

Key naming: uppercase the handle, replace non-alphanumerics with `_`, suffix `_USERNAME` / `_PASSWORD` (plus `_EMAIL` for the login email and `_TOTP_SECRET` for 2FA accounts).

To pick an account, run `agents secrets view x.com` — notes print in the clear while values stay masked. Reveal only the pair you need:

```bash
agents secrets export x.com --plaintext | grep '^GETONRUSH_'
```

For browser logins, bind the bundle to a profile so it injects at browser start: `agents browser profiles create x --browser chrome --secrets x.com`.

## 1Password Integration

```bash
# Import from 1Password vault
agents secrets import 1password:MyVault production

# Export to 1Password vault
agents secrets export production 1password:MyVault
```

Requires the `op` CLI signed in.

## Security

- Keychain-backed values never touch disk in plaintext
- Use `--reveal` sparingly and only when necessary
- Delete bundles when no longer needed
- Use separate bundles for different environments (dev, staging, production)
