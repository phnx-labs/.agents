# Permissions

Which tool calls an agent may make without stopping to ask you. Written once as YAML here,
translated by `agents-cli` into each agent's native format — Claude `settings.json`, OpenCode
`opencode.jsonc`, Codex `config.toml`.

Layered with `~/.agents/permissions/`: a same-named file in your user repo wins.

## How it fits together

```
groups/*.yaml   ──build.sh──►  default.yaml  ──agents permissions add──►  each agent's config
  (you edit)                   (generated)
```

`default.yaml` is **generated**. Edit a file in `groups/`, then run `./build.sh`. Never edit
`default.yaml` by hand.

## The groups

Files concatenate in alphabetical order, so the number prefix controls order.

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
| [`30-paths.yaml`](./groups/30-paths.yaml) | Blanket allows plus Write and Edit path rules |
| [`99-deny.yaml`](./groups/99-deny.yaml) · [`99-deny-sandbox.yaml`](./groups/99-deny-sandbox.yaml) | Deny lists. Deny always beats allow |

## Presets

A preset is a named bundle listing which groups to include.

| Preset | For |
|---|---|
| [`default.yaml`](./presets/default.yaml) | The laptop-strict bundle |
| [`sandbox.yaml`](./presets/sandbox.yaml) | Sandboxed execution |

Select one at sync time with `AGENTS_PERMISSION_PRESET=sandbox`.

## Changing what an agent may do

```bash
vim permissions/groups/30-paths.yaml   # edit the right group
bash permissions/build.sh              # regenerate default.yaml
agents permissions add permissions/default.yaml -a claude --all -y
```

For a machine-specific allow — an absolute path, a CLI only you have installed — put it in
`groups/00-local.yaml`. It is gitignored and stays on that machine.

---

Rule syntax, the cross-agent translation table, and the authoring rules are in
[`AGENTS.md`](./AGENTS.md).
