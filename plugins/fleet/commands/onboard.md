---
description: Bring a bare new device up to fleet parity — install agents-cli, clone/register the repos, install the shared fleet SSH key, fix PATH, register the device, and provision agent auth via sanctioned paths. Discovers the current agents-cli commands at run time rather than hardcoding them.
---

Onboard a new machine to the fleet. Argument (required): $ARGUMENTS = the target device (a name in `agents devices list`, or `user@host` you can reach over SSH).

## Goal

Take a device that has **little or none** of the fleet setup — agents-cli not
installed, the DotAgent repos not cloned, no fleet SSH key, agent auth missing — and
bring it to the same state as a healthy fleet node, so it can run agents and be
reached/orchestrated like the others.

## DISCOVER, don't hardcode — the CLI surface moves

**The agents-cli command surface changes over time. Do not trust exact flags written
in this doc over the live tool.** Your job is to hit the *goal* below using *whatever
the current CLI offers* — so at run time:

- Read the map first: `agents --help`, then `agents <area> --help` for each area you
  touch (`setup`, `add`, `import`, `repos`, `repo`, `devices`, `accounts`, `secrets`,
  `profiles`, `doctor`, `inspect`, `view`).
- **`agents doctor` on the target is your ground truth** for what's present vs missing,
  before and after. **`agents setup`** is the interactive first-time bootstrap — prefer
  it when the box is truly bare; fall back to the individual primitives when you need
  precision or it's partially set up.
- If a step here names a command that no longer exists, find its replacement in
  `--help` and use that. Treat this file as the checklist + the map, not the exact
  keystrokes.

## HARD LINE — credentials never travel as files

Onboarding touches agent auth and the fleet SSH key. **Never `scp`/copy a credential
file (`~/.claude/.credentials.json`, keychain exports, tokens) host-to-host.** Provision
only through the sanctioned paths, and only with the user's explicit OK:

- **Agent auth** → **mint it yourself first** — see [**Minting agent auth yourself**](#minting-agent-auth-yourself--the-token-flow) below.
  Prefer the harness's native device/OAuth flow inside a distinct account slot on the
  target, driven through `agents pty` plus a browser signed into the intended account.
  Verify the resulting email on the target and repeat independently per device. For a
  deliberately shared headless credential, mint a long-lived `setup-token` / API key
  and store it as a named provider account with `agents accounts add <name> --provider
  <provider> --auth <type>` — account bundles use `policy: never`, so reads are
  headless and Touch-ID-free on any OS. "The account isn't logged in" is a false
  blocker, not a reason to hand off. Other sanctioned paths: `agents
  accounts add` (provider accounts), `agents profiles login <provider>` (API-key
  providers), the agent's own native login flow, or `agents setup`. Two auth models
  exist on this fleet — native OAuth (preferred when available; per-machine and never
  copied) *or* a long-lived setup-token/API-key bundle stored via `agents accounts add`
  (safe to hold and sync with `agents accounts sync`). (Confirm the current verb via
  `--help` — there is no bare `agents login`.)
- **Fleet SSH key** (the one shared Ed25519 that unlocks git + node-to-node mesh) →
  installed from its `agents secrets` bundle, **with explicit authorization** each time.
  It is a private key; treat distributing it as the sensitive act it is.

Only after you have genuinely tried to mint it yourself (see **Minting agent auth
yourself** below) and that
failed for a concrete, quoted reason should you hand that one step to the user — and
even then, never improvise a credential-file copy.

## Process

### 1. Learn the target state (introspect a healthy reference)

Run on the machine you're on (a known-good node): `agents view`, `agents inspect user`
and `agents inspect system`, `agents repos list`, `agents devices list`, `agents
accounts list`, `agents secrets list`. Note: which agent CLIs are installed, which
repos are registered (system + user + extras), which accounts and auth model are in
use, and that the shared fleet SSH key + the non-interactive PATH shim are present.
That's the parity target.

### 2. Assess the target — idempotent

`agents doctor` on `$ARGUMENTS` (and `agents devices list` to see if it's registered).
Onboard is **additive and idempotent**: only install/register what's missing; never
tear down or overwrite an existing, working setup. If the box is already at parity, say
so and stop.

### 3. Bring it to parity — in dependency order (confirm each via `--help`)

1. **agents-cli itself** — install it on the target if absent (global install per its
   platform; on a bare box that may be a one-line installer or `npm i -g`). Everything
   below needs it.
2. **Bootstrap** — prefer `agents setup` on a bare box (it walks agent install + config
   sync). Otherwise proceed with the primitives:
3. **Agent CLIs** — `agents add <agent>` (or `agents import` to adopt an existing global
   install) for each agent the fleet runs (claude, codex, …).
4. **Repos** — register + clone the DotAgent repos: `agents repos add` for each (and/or
   `agents repo pull system` for the system repo). Match the reference's repo set.
5. **Fleet SSH key** — install the shared Ed25519 from its `agents secrets` bundle so
   git and node-to-node SSH work (explicit auth — see the hard line).
6. **Non-interactive PATH** — ensure agents-cli resolves in a *non-login* shell (fleet
   tooling like `agents sessions`/`fleet:sync` uses `bash -lc` but a bare box may lack
   the shim). If `agents ssh <target> 'agents --version'` fails while a login shell
   works, add the fleet-path block to the shell env (`~/.zshenv` on zsh) — the same shim
   the working nodes carry. (No sudo; only affects new shells.)
7. **Register the device + sync the registry** — `agents devices add`/`sync` so the
   target appears in the fleet, and re-sync on the orchestrator so it sees the target.
8. **Agent auth** — follow **Minting agent auth yourself** below. For native OAuth, create/select the target's
   stable account slot, run the device flow on that target, and verify the resulting
   email plus a real invocation. For a setup-token/API-key account, store it with
   `agents accounts add`, sync it with `agents accounts sync <name> <target>`, and verify
   `agents run ... --account <name>` succeeds. Never translate one model into the other
   by copying a native credential file.

### 4. Verify — end to end

- `agents doctor` on the target reports healthy (CLI available, repos synced, no
  missing auth).
- `agents ssh <target> 'agents --version'` works **non-interactively** (PATH shim).
- **Node-to-node reachability both ways:** the target can `agents ssh` a peer *and* a
  peer can `agents ssh` the target (proves the fleet SSH key took — the exact thing that
  was broken before the mesh fix).
- `agents accounts list` on the target shows the expected accounts.
- Optionally run `/fleet:sync` scoped to the target to confirm its repos pull.

### 5. Report

What was already present, what you installed/registered, what you provisioned
(including account names and verified `--account` run output), what (if anything) you
handed to the user (a credential you couldn't provision the sanctioned way), and the
final `agents doctor` verdict.

## Minting agent auth yourself — the token flow

Step 3.8 and the hard line above both send you here. Provisioning a harness credential for
the target is **your** job, not a user hand-off: "the account isn't logged in, so I need
you to log in" is almost always a **false blocker** (F2). Any harness with a
device/setup-token flow (Claude `setup-token`, Codex / Grok API keys, Droid/Kimi
device-code) can be authorized by an agent driving the flow itself — the OAuth handshake
only needs *a* browser signed in to the provider, and the fleet already has one (the online
macOS box). Do NOT stop and ask the user to log in until you have actually attempted this
and it failed for a concrete, quoted reason. Proven end-to-end 2026-08-01.

### HARD LINE — authorize natively, never copy native OAuth

Two supported credential classes; do not blur them:

- **Native OAuth/device login:** mint it independently inside every target device's
  version-home/account slot. Never copy its credential file or keychain entry. Refresh
  tokens may rotate, so two machines sharing one copied login can invalidate each other.
- **Setup token/API key:** store it as a named provider account. This long-lived,
  non-rotating credential class may be distributed with `agents accounts sync`.

Prefer native device OAuth when the harness exposes it and the user wants the harness's
full native account identity, subscription, and usage behavior. Use setup tokens/API keys
when native OAuth is unavailable or a deliberately shared headless account is the product
requirement. Copying native OAuth material is not a fallback.

### DISCOVER first — the CLI surface moves

Confirm the current verbs before running: `claude setup-token --help`, `agents pty
--help`, `agents computer --help` / `agents browser --help`, `agents accounts --help`.
Treat the keystrokes below as the map, not gospel.

### Recipe — native device OAuth in a target account slot

The preferred fleet recipe for Grok, Kimi, Droid, and any harness that exposes a
device-code flow. Run it once per account per device. A version label is the stable
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

### Recipe — Claude setup-token (syncable alternative)

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

### Other harnesses

- **API-key harnesses** (Codex `OPENAI_API_KEY`, Grok `XAI_API_KEY`): no browser dance —
  provision the key with the provider name the account registry owns:
  `agents accounts add codex-work --provider openai --auth api-key` or
  `agents accounts add grok-work --provider xai --auth api-key`.
- **Device-code harnesses** (Grok, Droid, Kimi): use the native target-slot recipe above.
  Mint/log in independently on every target and verify the resulting email; do not copy
  the native credential file.

For native OAuth report the device, stable slot label, verified email, and a redacted
`agents view --json` result; for named setup-token/API-key accounts report the account
name, provider, headless `agents run --account` verification, and devices that received
the bundle. **Never** paste a token, device credential, or credential file into a message,
PR, or commit.

## Safety rules (non-negotiable)

- **Never copy a credential file host-to-host.** Sanctioned provisioning only; hand off
  what you can't do that way. Provider account bundles are safe to sync via `agents
  accounts sync`; native auth material (keychain entries, OAuth sessions) is never
  copied.
- **Additive + idempotent.** Never overwrite or tear down existing setup on a device
  that's partially/already onboarded — install only what `agents doctor` shows missing.
- **Discover before you run.** If a command in this doc doesn't match `--help` on the
  target, use the current command; don't force a stale invocation.
- The fleet SSH key is a private key — install it only with explicit authorization,
  per device.
- Platform-aware: install method, the PATH shim, and shell profile differ on
  Linux / macOS / Windows — confirm per target, don't assume POSIX.
