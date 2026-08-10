---
description: Mint a harness auth credential YOURSELF by driving the login/OAuth flow (no user hand-off). Default: a long-lived Claude `setup-token` via the device flow, driven with a pty + a logged-in browser (computer-use or CDP), then stored as a named provider account so reads are headless and Touch-ID-free. Use when an account shows "not logged in" on a device.
---

Provision a harness credential for a device **without handing the login off to the
user**. Argument (optional): $ARGUMENTS = the account name to create (defaults to
the email of the account showing "not logged in").

## Why this exists

"The account isn't logged in, so I need you to log in" is almost always a **false
blocker**. Any harness with a device/setup-token flow (Claude `setup-token`, Codex /
Grok API keys, Droid/Kimi device-code) can be authorized by an agent driving the flow
itself — the OAuth handshake only needs *a* browser that is signed in to the provider,
and the fleet already has one (the online macOS box). Proven end-to-end 2026-08-01.

Do NOT stop and ask the user to log in until you have actually attempted this and it
failed for a concrete, quoted reason (see F2 (unblock yourself before you stop)).

## HARD LINE — mint, never copy

This mints a **fresh, per-account** credential on demand. It does **not** copy an
interactive login file host-to-host (that rotates→revokes and logs the fleet out — the
whole reason onboard forbids credential-file copies). The one credential class that is
safe to hold and sync is the long-lived, non-rotating setup-token / API key this
command produces.

## DISCOVER first — the CLI surface moves

Confirm the current verbs before running: `claude setup-token --help`, `agents pty
--help`, `agents computer --help` / `agents browser --help`, `agents accounts --help`.
Treat the keystrokes below as the map, not gospel.

## Recipe — Claude setup-token (the common case)

1. **Start the flow in a pty** (run it anywhere — the token is account-scoped, not
   machine-bound):
   ```
   SID=$(agents pty start)
   agents pty exec "$SID" "claude setup-token"
   sleep 5 && agents pty screen "$SID"
   ```
   It prints an authorize URL and waits for a code. Pull the exact URL from
   `agents pty read "$SID"` (it wraps on screen — join the fragments).

2. **Authorize in a browser signed in to claude.ai.** The online macOS device is
   signed in; open the URL in its *default* browser and read the code off the page:
   ```
   printf '%s' "$URL" | ssh <mac> 'cat > /tmp/oauth_url.txt'
   ssh <mac> 'open "$(cat /tmp/oauth_url.txt)"'
   ssh <mac> 'agents computer get-text'          # find: "Paste this into Claude Code: <code>#<state>"
   ```
   Resolve `<mac>` from `agents devices` (the online macOS node — never hardcode).
   The `#<state>` suffix must match the `state=` in the URL you generated — that is
   how you confirm you grabbed the right code. `agents computer` element mode is
   focus-safe (no `--raise`, no cursor move); or use `agents browser` with a
   logged-in CDP profile.

3. **Complete the mint:**
   ```
   agents pty write "$SID" "<code>#<state>\r"
   sleep 6 && agents pty screen "$SID"           # prints: sk-ant-oat01-...  (valid ~1 year)
   agents pty stop "$SID"
   ```

4. **Store it as a named provider account** — not in any shared bundle. One account
   is one `agents secrets` bundle with `policy: never`, so agent launches read it
   without Touch ID on any OS. Pick a name that identifies the account (e.g. the
   email slug):
   ```
   agents accounts add claude-muqsit \
       --provider anthropic \
       --auth setup-token
   ```
   Enter the setup token at the command's secret prompt. Do not put it in an
   environment variable, command argument, or shell history.
   If you already stored the token in an intermediate bundle with `agents secrets add`,
   import it instead of re-entering:
   ```
   agents accounts add "$ACCOUNT_NAME" \
       --provider anthropic \
       --auth setup-token \
       --from-secrets <bundle>:<key>
   ```
   Account bundles use `policy: never` automatically — no passphrase, no Touch ID
   prompt, no `--backend` flag to juggle.

5. **Verify (headless, zero keychain):**
   ```
   agents run claude "Reply with exactly: AUTH_OK" \
       --account "$ACCOUNT_NAME" \
       --mode plan \
       --timeout 2m
   ```
   A reply of `AUTH_OK` proves the account resolves and the token is readable headless.
   Then confirm the account appears in the list:
   ```
   agents accounts list
   ```

6. **Copy to a worker device** (when provisioning for a remote box):
   ```
   agents accounts sync "$ACCOUNT_NAME" --device <target-device>
   ```
   This copies the bundle explicitly; the target inherits `policy: never` and the full
   account schema. Native auth material (keychain credentials, OAuth sessions) is never
   copied — only the account bundle produced by this recipe is safe to sync.

## Other harnesses

- **API-key harnesses** (Codex `OPENAI_API_KEY`, Grok `XAI_API_KEY`): no browser dance —
  provision the key via `agents accounts add <name> --provider <harness> --auth api-key`.
  (Confirm the current `--auth` values via `agents accounts add --help`.)
- **Device-code harnesses** (Droid, Kimi): drive their device-code flow the same way
  (`agents pty` to start it, read the URL+code, authorize in the logged-in browser).
  These are login-only per-machine — mint/log in on the target, do not copy the file.

## Report

Which account you minted, the account name and provider, the headless
`agents run --account` verification output, and (if synced) which devices received the
bundle. **Never** paste the token itself into a message, PR, or commit — it is a live
credential; the account bundle holds it.
