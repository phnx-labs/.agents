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

- **Agent auth** → **mint it yourself first** with [`/fleet:mint-auth`](mint-auth.md): drive
  the harness's device/OAuth flow (a pty + a logged-in browser via `agents computer` /
  `agents browser`) to produce a long-lived `setup-token` / API key. Store it as a
  named provider account with `agents accounts add <name> --provider <provider>
  --auth <type>` — account bundles use `policy: never`, so reads are headless and
  Touch-ID-free on any OS. This is the preferred path — "the account isn't logged in"
  is a false blocker, not a reason to hand off. Other sanctioned paths: `agents
  accounts add` (provider accounts), `agents profiles login <provider>` (API-key
  providers), the agent's own native login flow, or `agents setup`. Two auth models
  exist on this fleet — a long-lived setup-token/API-key bundle stored via `agents
  accounts add` (preferred; safe to hold and sync with `agents accounts sync`) *or*
  interactive OAuth (per-machine, never copied). (Confirm the current verb via
  `--help` — there is no bare `agents login`.)
- **Fleet SSH key** (the one shared Ed25519 that unlocks git + node-to-node mesh) →
  installed from its `agents secrets` bundle, **with explicit authorization** each time.
  It is a private key; treat distributing it as the sensitive act it is.

Only after you have genuinely tried to mint it yourself (`/fleet:mint-auth`) and that
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
8. **Agent auth** — provision a named provider account via `/fleet:mint-auth` (preferred)
   or another sanctioned path from step 1's hard line, matching the reference node's
   auth model. Store the credential with `agents accounts add <name> --provider
   <provider> --auth <type>`, then sync it to the target with `agents accounts sync
   <name> --device <target>`. Verify the agent can actually run (not just that a
   file exists): `agents run claude "Reply: OK" --account <name> --mode plan --timeout 2m`.

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
