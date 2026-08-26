---
name: secrets
description: "Manage named bundles of environment variables backed by macOS Keychain. Create bundles, add secrets, and inject them into agent runs. Use this skill when working with credentials, API keys, or sensitive configuration."
argument-hint: "[list|view|create|add|remove|import|export]"
allowed-tools: Bash(agents secrets*)
user-invocable: true
---

# Secrets Skill

Manage named bundles of environment variables backed by macOS Keychain via the
`agents secrets` CLI.

- **Bundle** — a named container for secrets (e.g. "production", "x.com")
- **Secret** — a key-value pair inside a bundle
- **Keychain** — the default store; values never touch disk in plaintext

## Discover the command surface from the CLI

The subcommands and flags are maintained in the CLI, not here. Run
`agents secrets --help` and `agents secrets <command> --help` for the current
surface instead of guessing or trusting a stale table. The everyday flow:

```bash
agents secrets create production
agents secrets add production STRIPE_API_KEY   # prompts; stored in Keychain
agents secrets list
agents run claude "ship it" --secrets production
```

What this skill adds beyond `--help` is the behavior you cannot derive from it:

## Remote bundles (other hosts)

Browse and *use* bundles that live on another machine, over SSH. Hosts resolve
through the `agents devices` registry, an ssh-config alias, or `user@host`.

- **`bundle@host`** is the reference form for `agents run --secrets`; local and
  remote bundles mix freely in one run.
- **Ephemeral.** Remote values cross over SSH and are injected into the run's
  env in memory — never written to this machine's keychain or disk.
- **The remote unlocks with its own credentials.** A file-backed remote bundle
  reads headlessly via the remote's own `AGENTS_SECRETS_PASSPHRASE`; a keychain
  bundle on a macOS remote blocks on Touch ID under non-interactive SSH — use a
  remote `file` bundle, an unlocked remote secrets-agent, or run `view --reveal`
  from an interactive terminal (it forces an SSH TTY so the prompt can surface).
- **Push works to Windows too.** `agents secrets export <bundle> --device <host>`
  detects the remote platform and lands in Credential Manager (or the headless
  file store with no logon session). Over a relayed link the push can take
  ~30-40s; that's the link, not a hang. `--remote-backend file` is POSIX-only
  and is refused cleanly on Windows.
- **`unlock --device` is single-valued and bundle-first:**
  `agents secrets unlock <bundle> --device <machine>` surfaces the remote's
  passphrase prompt on your terminal over `ssh -tt`. Only **file-backed**
  bundles work this way; a keychain/biometry bundle pops a local Touch-ID sheet
  on the remote's screen, which can't cross SSH. The password can't be piped.

## Multiple accounts on one website

Name the bundle after the domain (`x.com`, `linkedin.com`) — one bundle per
site, any number of accounts inside. Key naming: uppercase the handle, replace
non-alphanumerics with `_`, suffix `_USERNAME` / `_PASSWORD` (plus `_EMAIL` and
`_TOTP_SECRET` for 2FA). Give every account a `--note` saying when to use it —
`agents secrets view x.com` prints notes in the clear while values stay masked.

**Never print the values** (RUSH-2774: the plaintext export is removed). Run the
consuming command with just that account's pair injected:

```bash
agents secrets exec x.com --keys GETONRUSH_USERNAME,GETONRUSH_PASSWORD -- ./login-helper
```

For browser logins, bind the bundle to a profile so it injects at browser start:
`agents browser profiles create x --browser chrome --secrets x.com`.

## 1Password

`import` / `export` accept `1password:<Vault>` as the source/target. Requires
the `op` CLI signed in.

## Security

- Use `--reveal` sparingly and only when necessary.
- Delete bundles when no longer needed.
- Use separate bundles for different environments (dev, staging, production).
