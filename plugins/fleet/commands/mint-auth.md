---
description: Mint a harness auth credential YOURSELF by driving the login/OAuth flow (no user hand-off). Default: a long-lived Claude `setup-token` via the device flow, driven with a pty + a logged-in browser (computer-use or CDP), then stored file-backed so reads are headless and Touch-ID-free. Use when an account shows "not logged in" on a device.
---

Provision a harness credential for a device **without handing the login off to the
user**. Argument (optional): $ARGUMENTS = the account email (or the device/agent) you
need signed in; default to the account that is showing "not logged in".

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
--help`, `agents computer --help` / `agents browser --help`, `agents secrets --help`.
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

4. **Store it in the reserved FILE-backed `auth` bundle** — the exact bundle the usage
   reader consults (`AUTH_BUNDLE = 'auth'` in `apps/cli/src/lib/usage.ts`, which requires
   `bundleBackend('auth') === 'file'`; a keychain- or vault-backed bundle is ignored and
   the reader falls back to the keychain → Touch ID). So it MUST be **`--backend file`**:
   ```
   agents secrets create auth --backend file          # once. Do NOT pass --synced:
                                                       # --synced forces a VAULT bundle
                                                       # (needs `agents login`), which the
                                                       # file-only usage reader rejects.
   printf '%s' "$TOKEN" | agents secrets add auth <KEY> --value-stdin --type token
   ```
   Per-account key convention (`accountTokenKey`): upper-case, `@`→`_AT_`, `.`→`_DOT_` —
   e.g. `muqsit@trp.so` → `CLAUDE_CODE_OAUTH_TOKEN_MUQSIT_AT_TRP_DOT_SO`.

   **macOS provisioning (required):** a file-backed bundle is not auto-provisioned on
   macOS, and headless reads (the daemon's usage/auth probe reads with `agentOnly`) can't
   pop a biometric prompt — so the file-store passphrase must be available via
   `AGENTS_SECRETS_PASSPHRASE` (export it for the daemon's environment, or run the
   create/add in a TTY that has it set). Without it, the `auth` read throws and the code
   falls back to the keychain (Touch ID). On Linux the machine-local passphrase is
   auto-provisioned, so this is macOS-only.

5. **Verify (zero keychain):** in a shell where `AGENTS_SECRETS_PASSPHRASE` is set (macOS),
   `agents secrets get auth <KEY> </dev/null | wc -c` → ~108 chars, no prompt. Then
   `agents view` draws that account's bars from the `auth` token with no keychain read.

## Other harnesses

- **API-key harnesses** (Codex `OPENAI_API_KEY`, Grok `XAI_API_KEY`): no browser dance —
  provision the key into the auth bundle via `agents secrets`/`agents profiles login`.
- **Device-code harnesses** (Droid, Kimi): drive their device-code flow the same way
  (`agents pty` to start it, read the URL+code, authorize in the logged-in browser).
  These are login-only per-machine — mint/log in on the target, do not copy the file.

## Report

Which account you minted, where it is stored (bundle + key, value **redacted**), and the
headless-read verification. **Never** paste the token itself into a message, PR, or
commit — it is a live credential; the bundle holds it.
