# skills/ — maintenance contract

Humans start at [README.md](./README.md).

One directory per skill, containing `SKILL.md`. The directory name is the skill name and the
invocation name: `skills/browser/` is `/browser`. No manifest, no registration step.

## SKILL.md frontmatter

```yaml
---
name: my-skill
description: What it does. Triggers on: <the phrases that should load it>
allowed-tools: Bash(pattern*)   # optional; narrows what the skill may call
---
```

- `name` must equal the directory name. A mismatch makes the skill unfindable.
- `description` is the **only** thing an agent sees before loading the skill, so it decides
  whether the skill is ever used. Write what it does plus the trigger phrases. A vague
  description is a skill nobody loads.

## Adding or renaming a skill

1. Create `skills/<name>/SKILL.md` with `name` and `description`.
2. Add a row to the right section of [`README.md`](./README.md), linked to `SKILL.md`. A
   skill missing from the README is invisible to humans.
3. Add a `CHANGELOG.md` entry under the next version.

On a rename, `grep -rn "<oldname>"` from the repo root — rules, commands, and other skills
reference skills by name, and a stale reference routes to nothing.

## One capability per skill

A skill that does everything is loaded for everything and helps with nothing. Split it. If
the thing is a single one-shot prompt with no scripts or reference files, it belongs in
[`commands/`](../commands/AGENTS.md) instead.

## Never hardcode machine-specific values

No `/Users/<name>/` paths, no hostnames, no credentials in `SKILL.md`. Read them at load time
from `~/.agents/.environment` via the skill's own `env.sh`:

```markdown
!`${CLAUDE_SKILL_DIR}/env.sh block`
```

`.environment` is gitignored and per-machine. This is what makes a skill publishable.
Credentials go through `agents secrets`, never into a file here.

## Known drift — `user-invocable`

15 of the 18 `SKILL.md` files carry `user-invocable: true`; `agents-cli`, `mq`, and
`tickets` omit it. **agents-cli does not read this field** — `grep -rn "user-invocable"` over
`apps/cli/src` returns nothing, so it is inert here and consumed only by the harness that
reads the skill. Do not build behavior on it. Either set it consistently across all 18 or
drop it; leaving it unevenly applied invites a false assumption.
