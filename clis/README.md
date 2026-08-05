# CLI manifests

Host CLIs that agents rely on. Each `.yaml` here tells `agents-cli` how to install a tool and
how to check whether it is already working, so `agents doctor` can report a missing one and
`agents cli install <name>` can fix it.

These are **host tools**, not agents. They are the binaries a skill shells out to.

## What ships here

| Tool | What it's for |
|---|---|
| [`mq`](./mq.yaml) | Structure-aware query for large files — extract one section instead of reading the whole file into context |
| [`jq`](./jq.yaml) | JSON processing. Several hooks depend on it and **fail closed** without it |
| [`linear-cli`](./linear-cli.yaml) | Linear issue tracker CLI, behind `/tickets` |

## Using them

```bash
agents doctor              # Host CLIs section — what's missing
agents cli install mq      # install one
```

> **`mq` name collision.** This is `github.com/muqsitnawaz/mq`, not the unrelated Homebrew
> `mq` markdown processor from mqlang.org. Do not `brew install mq` — the manifest's `check`
> inspects the exit code only and cannot tell the two apart, so `agents doctor` will report
> `mq` present while the wrong binary is on `PATH`.

---

Changing something here? Read [`AGENTS.md`](./AGENTS.md).
