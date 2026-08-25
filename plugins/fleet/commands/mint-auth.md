---
description: Mint harness auth YOURSELF through the provider's supported flow. Prefer a fresh native device/OAuth login inside each target account slot; use a syncable named account only for long-lived setup tokens or API keys. Never copy native OAuth files host-to-host.
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

## HARD LINE — authorize natively, never copy native OAuth

There are two supported credential classes. Do not blur them:

- **Native OAuth/device login:** mint it independently inside every target device's
  version-home/account slot. Never copy its credential file or keychain entry. Refresh
  tokens may rotate, so two machines sharing one copied login can invalidate each other.
- **Setup token/API key:** store it as a named provider account. This long-lived,
  non-rotating credential class may be distributed with `agents accounts sync`.

Prefer native device OAuth when the harness exposes it and the user wants the harness's
full native account identity, subscription, and usage behavior. Use setup tokens/API
keys when native OAuth is unavailable or a deliberately shared headless account is the
product requirement. Copying native OAuth material is not a fallback.

## DISCOVER first — the CLI surface moves

Confirm the current verbs before running: `claude setup-token --help`, `agents pty
--help`, `agents computer --help` / `agents browser --help`, `agents accounts --help`.
Treat the keystrokes below as the map, not gospel.

## Recipe — native device OAuth in a target account slot

This is the preferred fleet recipe for Grok, Kimi, Droid, and any harness that exposes
a device-code flow. Run it once per account per device. A version label is the stable
account-slot identity; the vendor binary may self-update to a different release without
changing that label.

1. **Create or select a distinct slot on the target.** Discover the current `agents add`
   and `agents view` syntax first. For Grok, a concrete label keeps credentials separate:
   ```
   agents ssh <target> 'agents add grok@<stable-label> -y'
   agents ssh <target> 'agents view grok'
   ```
   Never reuse a slot that already belongs to another email. Do not infer identity from
   the label; the native login result is the source of truth.

2. **Start the native login on the target in a PTY.** Let `agents pty start` choose the
   target's native shell; never hardcode `/bin/bash` fleet-wide. Use the managed
   invocation so `HOME` resolves to that slot.

   From a POSIX orchestrator:
   ```
   SID=$(agents ssh <target> 'agents pty start' | tail -1)
   agents ssh <target> "agents pty write $SID 'agents run grok@<stable-label> -- login --device-auth\r'"
   sleep 3
   agents ssh <target> "agents pty screen $SID"
   ```

   From a PowerShell orchestrator:
   ```powershell
   $SID = (agents ssh <target> "agents pty start" | Select-Object -Last 1)
   agents ssh <target> "agents pty write $SID `"agents run grok@<stable-label> -- login --device-auth\r`""
   Start-Sleep -Seconds 3
   agents ssh <target> "agents pty screen $SID"
   ```
   Read the exact device URL and code from the PTY. Keep the PTY alive while authorizing.

3. **Authorize with a browser already signed into the intended provider account.** Use
   `agents browser` for trusted clicks, or `agents computer` element mode when driving a
   native browser. Confirm the page names the expected email before Allow/Continue. Do
   not authorize when the displayed account is wrong; sign out or choose the correct
   browser identity first.

4. **Verify the terminal and installed identity, then clean up.** The following POSIX
   form uses the same verbs on PowerShell; replace shell quoting and `$SID` assignment
   with the PowerShell form above:
   ```
   agents ssh <target> "agents pty screen $SID"  # must say Signed in as <expected-email>
   agents ssh <target> 'agents view grok --json'
   agents ssh <target> "agents pty stop $SID"
   ```
   Success means the expected slot reports `signedIn: true` with the expected email.
   A browser success page alone is not proof.

5. **Repeat for every target device and account.** Device OAuth is deliberately
   per-machine. Minting on one worker does not authorize the rest, and copying the
   resulting native credential is forbidden.

## Recipe — Claude setup-token (syncable alternative)

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

6. **Sync to a worker device** (when provisioning for a remote box):
   ```
   agents accounts sync "$ACCOUNT_NAME" <target-device>
   ```
   This copies the bundle explicitly; the target inherits `policy: never` and the full
   account schema. Native auth material (keychain credentials, OAuth sessions) is never
   copied — only the account bundle produced by this recipe is safe to sync.

## Other harnesses

- **API-key harnesses** (Codex `OPENAI_API_KEY`, Grok `XAI_API_KEY`): no browser dance —
  provision the key with the provider name the account registry owns:
  `agents accounts add codex-work --provider openai --auth api-key` or
  `agents accounts add grok-work --provider xai --auth api-key`.
- **Device-code harnesses** (Grok, Droid, Kimi): use the native target-slot recipe above.
  Mint/log in independently on every target and verify the resulting email; do not copy
  the native credential file.

## Report

For native OAuth: report the device, stable slot label, verified email, and a redacted
`agents view --json` result. For named setup-token/API-key accounts: report the account
name, provider, headless `agents run --account` verification, and devices that received
the bundle. **Never** paste a token, device credential, or credential file into a
message, PR, or commit.
