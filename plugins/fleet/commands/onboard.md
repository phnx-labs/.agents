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
  touch (`setup`, `add`, `import`, `repos`, `repo`, `devices`, `secrets`, `profiles`,
  `doctor`, `inspect`, `view`).
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

- **Agent auth** → `agents secrets` bundles (keychain/file), `agents profiles login
  <provider>` (for API-key providers), the agent's **own native login flow** (e.g. run
  the `claude` CLI's login → `~/.claude/.credentials.json`), or `agents setup`. Two valid
  models exist on this fleet — OAuth credentials *or* an `agents secrets` API-key bundle
  (`anthropic.com`/`claude`); pick whichever the reference node uses. (Confirm the current
  verb via `--help` — there is no bare `agents login`.)
- **Fleet SSH key** (the one shared Ed25519 that unlocks git + node-to-node mesh) →
  installed from its `agents secrets` bundle, **with explicit authorization** each time.
  It is a private key; treat distributing it as the sensitive act it is.

If you can't provision a credential the sanctioned way, **stop and hand that one step
to the user** — don't improvise a copy.

## Process

### 1. Learn the target state (introspect a healthy reference)

Run on the machine you're on (a known-good node): `agents view`, `agents inspect user`
and `agents inspect system`, `agents repos list`, `agents devices list`, `agents secrets
list`. Note: which agent CLIs are installed, which repos are registered (system + user +
extras), which auth model is in use, and that the shared fleet SSH key + the
non-interactive PATH shim are present. That's the parity target.

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
8. **Agent auth** — provision via the sanctioned path from step 1's hard line, matching
   the reference node's auth model. Verify the agent can actually run (not just that a
   file exists).

### 4. Verify — end to end

- `agents doctor` on the target reports healthy (CLI available, repos synced, no
  missing auth).
- `agents ssh <target> 'agents --version'` works **non-interactively** (PATH shim).
- **Node-to-node reachability both ways:** the target can `agents ssh` a peer *and* a
  peer can `agents ssh` the target (proves the fleet SSH key took — the exact thing that
  was broken before the mesh fix).
- Optionally run `/fleet:sync` scoped to the target to confirm its repos pull.

### 5. Report

What was already present, what you installed/registered, what you provisioned, what
(if anything) you handed to the user (a credential you couldn't provision the sanctioned
way), and the final `agents doctor` verdict.

## Safety rules (non-negotiable)

- **Never copy a credential file host-to-host.** Sanctioned provisioning only; hand off
  what you can't do that way.
- **Additive + idempotent.** Never overwrite or tear down existing setup on a device
  that's partially/already onboarded — install only what `agents doctor` shows missing.
- **Discover before you run.** If a command in this doc doesn't match `--help` on the
  target, use the current command; don't force a stale invocation.
- The fleet SSH key is a private key — install it only with explicit authorization,
  per device.
- Platform-aware: install method, the PATH shim, and shell profile differ on
  Linux / macOS / Windows — confirm per target, don't assume POSIX.
