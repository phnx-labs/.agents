# Permissions

Canonical tool approval rules translated by `agents-cli` into each agent's native format —
Claude `settings.json`, OpenCode `opencode.jsonc`, Codex `config.toml`.

Both presets allow `Bash`, `Read`, `Write`, and `Edit` without ordinary harness approval
prompts. Command-substitution/simple-expansion and cd-before-git prechecks run before allow
rules and can still prompt. Credential denies reduce accidental `Read`/`Edit`/`Write` access;
they do not constrain allowed Bash commands. Hooks remain cooperative guardrails for normal
agent behavior, not an adversarial sandbox or operating-system security boundary.

Layered with `~/.agents/permissions/`: a same-named file in your user repo wins.

## How it fits together

```
presets/default.yaml + groups/*.yaml ──build.sh──► default.yaml ──agents permissions add──► agent config
          (you edit)                         (generated)
```

`default.yaml` is **generated** from `presets/default.yaml` in manifest order. Edit the
preset or a listed group, then run `./build.sh`. Never edit `default.yaml` by hand.

## The groups

Preset manifests define which groups are active and their concatenation order.

| Group | Covers |
|---|---|
| [`00-header.yaml`](./groups/00-header.yaml) | The YAML header — name, description, the `allow:` key |
| `00-local.yaml` | Your machine only: absolute paths, locally-installed tools. **Gitignored**, never synced |
| [`01-core.yaml`](./groups/01-core.yaml) | Core shell and file tools |
| [`02-dotdirs.yaml`](./groups/02-dotdirs.yaml) | Writes into the agent dotdirs |
| [`02-node.yaml`](./groups/02-node.yaml) · [`03-python.yaml`](./groups/03-python.yaml) · [`04-go.yaml`](./groups/04-go.yaml) · [`05-rust.yaml`](./groups/05-rust.yaml) | Per-language toolchains |
| [`06-docker.yaml`](./groups/06-docker.yaml) · [`07-k8s.yaml`](./groups/07-k8s.yaml) · [`08-cloud.yaml`](./groups/08-cloud.yaml) | Containers, clusters, cloud CLIs |
| [`09-git.yaml`](./groups/09-git.yaml) | Git plumbing |
| [`10-security.yaml`](./groups/10-security.yaml) · [`11-ci.yaml`](./groups/11-ci.yaml) | Security tooling, CI |
| [`12-self.yaml`](./groups/12-self.yaml) | Agent self-operations — the one exact `kill -TERM $PPID` the `self` plugin (`/self:close`) uses to SIGTERM its own harness |
| [`15-misc-bash.yaml`](./groups/15-misc-bash.yaml) | Everything else shell |
| [`20-webfetch-dev.yaml`](./groups/20-webfetch-dev.yaml) · [`21-webfetch-cloud.yaml`](./groups/21-webfetch-cloud.yaml) · [`22-webfetch-social.yaml`](./groups/22-webfetch-social.yaml) · [`25-webfetch-misc.yaml`](./groups/25-webfetch-misc.yaml) | WebFetch domain allowlists |
| [`30-paths.yaml`](./groups/30-paths.yaml) | Blanket Bash, Read, Write, and Edit allows |
| [`99-deny.yaml`](./groups/99-deny.yaml) | Canonical credential file-tool accidental-access matrix shared by both presets |

## Presets

A preset is a named bundle listing which groups to include.

| Preset | For |
|---|---|
| [`default.yaml`](./presets/default.yaml) | Blanket shell/file-tool allows plus credential file-tool denies |
| [`sandbox.yaml`](./presets/sandbox.yaml) | The same permission matrix for ephemeral cloud pods |

Select one at sync time with `AGENTS_PERMISSION_PRESET=sandbox`.

## Changing what an agent may do

```bash
vim permissions/groups/30-paths.yaml   # edit the right group
bash permissions/build.sh              # regenerate default.yaml
bash permissions/build.sh permissions/presets/sandbox.yaml .agents/scratch/sandbox-permissions.yaml
bash permissions/permissions_test.sh   # verify both presets and protected hook scope
agents permissions add permissions/default.yaml -a claude --all -y
```

`build.sh` accepts either no arguments for the canonical `default.yaml`, or both a preset and an
explicit non-default output path. A lone preset argument is rejected so a custom build cannot
silently overwrite the canonical output.

For a machine-specific allow — an absolute path, a CLI only you have installed — put it in
`groups/00-local.yaml`. It is gitignored and stays on that machine.

---

Rule syntax, the cross-agent translation table, and the authoring rules are in
[`AGENTS.md`](./AGENTS.md).
