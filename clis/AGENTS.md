# cli/ — maintenance contract

Humans start at [README.md](./README.md).

One `.yaml` per host CLI. The filename is the tool id: `mq.yaml` is `agents cli install mq`.

## Manifest shape

```yaml
name: mq
description: |
  What it is, and what it is NOT if the name collides with another tool.
homepage: https://github.com/owner/repo

check: mq --version          # must exit 0 when the tool works

install:
  - binary:
      darwin-arm64:
        url: https://.../mq_darwin_arm64.tar.gz
        extract: mq
      linux-x64:
        url: https://.../mq_linux_amd64.tar.gz
        extract: mq

post_install: |
  A few lines the user sees once, showing the tool's most useful invocations.
```

## Platform keys are `<platform>-<arch>` as Node computes them

The arch is **`x64`, never `amd64`**. GoReleaser names its release files `..._amd64.tar.gz`,
so the URL says `amd64` while the manifest **key** must say `x64`. Get this wrong and the
install method silently never matches on an Intel or x86_64 host — the tool just stays
missing with no error.

Supported keys here: `darwin-arm64`, `darwin-x64`, `linux-arm64`, `linux-x64`.

## `check` tests the exit code only

It cannot tell two same-named binaries apart. `mq` is the live example: the unrelated
Homebrew `mq` (mqlang.org) also exits 0 on `--version`, so `agents doctor` reports the tool
present while the wrong binary is on `PATH`. The manifest schema cannot express a
stdout-identity match, so a known collision must be called out in `description` and in the
README. Do not invent a `check` that pretends to disambiguate.

## Adding a tool

1. `cli/<tool>.yaml` with `name`, `description`, `check`, `install`, and `post_install`.
2. Add its row to the table in [`README.md`](./README.md).
3. Add a `CHANGELOG.md` entry under the next version.
4. Verify on both architectures if the tool ships per-arch builds — a manifest that only
   works on Apple Silicon is a half-shipped tool.

## Pin the version, and bump it deliberately

The `url` carries an explicit release tag. It is not `latest` on purpose: an unpinned URL
makes every machine's install non-reproducible. Cutting a new upstream release means editing
the tag in every platform block, plus a CHANGELOG entry.
