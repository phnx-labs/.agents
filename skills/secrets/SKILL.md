---
name: secrets
description: "Manage named bundles of environment variables backed by macOS Keychain. Create bundles, add secrets, and inject them into agent runs. Use this skill when working with credentials, API keys, or sensitive configuration."
argument-hint: "[list|view|create|add|remove|import|export]"
allowed-tools: Bash(secrets*), Bash(agents secrets*)
user-invocable: true
---

# Secrets Skill

Manage named bundles of environment variables backed by macOS Keychain via the
standalone `secrets` CLI (npm `@phnx-labs/secrets-cli`). It is the same engine
that used to ship inside `agents secrets`, now published on its own — the verbs
are unchanged, only the executable name dropped the `agents` prefix.

- **Bundle** — a named container for secrets (e.g. "production", "x.com")
- **Secret** — a key-value pair inside a bundle
- **Keychain** — the default store; values never touch disk in plaintext

State lives under `SECRETS_HOME`. agents-cli points it at `~/.agents`, so every
bundle you already created is adopted in place — there is nothing to migrate.

## Discover the command surface from the CLI

The subcommands and flags are maintained in the CLI, not here. Run
`secrets --help` and `secrets <command> --help` for the current
surface instead of guessing or trusting a stale table. The everyday flow:

```bash
secrets create production
secrets add production STRIPE_API_KEY   # prompts; stored in Keychain
secrets list
agents run claude "ship it" --secrets production
```

`agents run … --secrets <bundle>` is unchanged — agents-cli still owns that flag
and reads the bundle through the `secrets` engine for you.

What this skill adds beyond `--help` is the behavior you cannot derive from it:

## Remote hosts (bundles on another machine)

Browse and *use* bundles that live on another machine, over SSH. A **host** is an
OpenSSH alias or `user@host` — the standalone CLI has no device registry and does
no fleet alias lookup, so the target must resolve through your `~/.ssh/config`
(add `--port` when it isn't 22). The endpoint flags are `--host` (one target) and
`--hosts` (several).

**Pin the host once before any transfer.** `secrets hosts pin <target>` records
the host's key; any `--host`/`--hosts` credential read or write refuses until the
target is pinned, so a later transfer can't be silently redirected.

- **Use a remote bundle without copying it.** `secrets exec prod --host worker -- ./deploy.sh`
  reads from the pinned host over SSH and runs the child locally. Values ride the
  child env in memory — never written to this machine's keychain or disk.
- **Store a copy on another machine.** `secrets export <bundle> --host <host>`
  pushes into the remote's configured backend after a read-back; `secrets import
  <bundle> --host <host>` pulls into the local backend. Push works to Windows too
  — it detects the remote platform and lands in Credential Manager (or the
  headless file store with no logon session). Over a relayed link the push can
  take ~30-40s; that's the link, not a hang. `--remote-backend file` is POSIX-only
  and is refused cleanly on Windows.
- **Inspect remote metadata.** `secrets list --host <host> --json` returns names
  and status only, never resolved values.
- **The remote unlocks with its own credentials.** A file-backed remote bundle
  reads headlessly via the remote's own `AGENTS_SECRETS_PASSPHRASE`; a keychain
  bundle on a macOS remote blocks on Touch ID under non-interactive SSH — use a
  remote `file` bundle, an unlocked remote secrets-agent, or run
  `secrets unlock <bundle> --host <machine>` from an interactive terminal. That
  surfaces the remote's passphrase prompt on your terminal over `ssh -tt`; only
  **file-backed** bundles work this way. A keychain/biometry bundle pops a local
  Touch-ID sheet on the remote's screen, which can't cross SSH, and the password
  can't be piped.

## Multiple accounts on one website

Name the bundle after the domain (`x.com`, `linkedin.com`) — one bundle per
site, any number of accounts inside. Key naming: uppercase the handle, replace
non-alphanumerics with `_`, suffix `_USERNAME` / `_PASSWORD` (plus `_EMAIL` and
`_TOTP_SECRET` for 2FA). Give every account a `--note` saying when to use it —
`secrets view x.com` prints notes in the clear while values stay masked.

**Never print the values** (RUSH-2774: the plaintext export is removed). Run the
consuming command with just that account's pair injected:

```bash
secrets exec x.com --keys GETONRUSH_USERNAME,GETONRUSH_PASSWORD -- ./login-helper
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
