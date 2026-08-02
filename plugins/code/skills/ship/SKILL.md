---
name: ship
description: "Ship gate for distributables. The verb after merge — take a merged change and get it into users' hands, then prove it. Publish (marketplace / npm / cargo / deploy), confirm it's live on the public channel, install/activate it where it runs, verify the real surface renders. For VS Code extensions, CLIs, and web apps, merge is the middle — this is the end. Triggers on: 'ship it', 'did it reach users', 'publish the extension', 'is it live', 'release to the marketplace', 'cut the release'."
argument-hint: "[version | PR# | empty for current] — artifact auto-detected (extension / npm / cargo / web)"
allowed-tools: Bash(agents *), Bash(gh *), Bash(git *), Bash(vsce*), Bash(ovsx*), Bash(npm*), Bash(cargo*), Bash(bun*), Bash(curl *), Bash(jq *), Bash(osascript*), Bash(pgrep*), Bash(defaults*), Bash(ls*), Bash(grep*), Read(*), Write(*), Edit(*), WebFetch(*)
user-invocable: true
---

# code:ship

> A change is merged and CI is green. For a library that's the end. For a **distributable** — a VS Code extension, a published CLI, a deployed web app — it's the middle. Users don't run your default branch. This skill takes the merged artifact the rest of the way: publish it, confirm the public channel actually serves it, get it active where it runs, and verify the real surface with quoted evidence.

This is the closing gate for "done means end-to-end" when the thing you built is something other people install or visit. `code:verify` proves the code works; `code:ship` proves users can get the working code and that it's live for them.

## The one rule

**"Published" is not "shipped." "Installed" is not "active."** A `publish` command exiting 0 means the upload was accepted, not that the registry serves it. `--install-extension` exiting 0 means bytes are on disk, not that the running app loaded them. Each gap hides a class of "it worked on my machine" failures. Close every gap with a query, not an assumption.

## What "shipped" means per artifact

Detect the artifact from the repo, then hold it to the matching bar. Every "live check" and "active check" is a command whose output you quote — never an inference.

| Artifact | Publish channel | Live check (users can get it) | Active check (it runs the new code) |
|---|---|---|---|
| VS Code extension | VS Code Marketplace + Open VSX | both registry APIs report the new version (below) | running editor window reloaded → `exthost.log` shows the new activation; real surface renders |
| npm CLI / lib | npm registry | `npm view <pkg> version` == target | `npx <pkg>@latest --version` in a clean dir prints target |
| cargo crate | crates.io | `cargo search <crate>` / index API shows target | `cargo install <crate> --version <t>` then `<bin> --version` |
| web app / API | host (Vercel / CF / Hetzner) | deploy reports success | `curl` the prod health/version endpoint returns 200 with the new build (per F3) |

## The ship loop

1. **Resolve the target.** `$ARGUMENTS` is a version (`0.9.251`), a PR number, or empty (current repo / latest tag). Confirm the merge is on the default branch and CI is green before publishing — re-run `code:verify` if unproven.
2. **Prefer the repo's own release script.** Most repos already have one (`scripts/release.sh`, `npm publish` wrapper, a deploy script). Read it, run it, don't reinvent it. A good release script already does the collision pre-flight, token resolution, and publish.
3. **Confirm live on the public channel** — the registry/host's own API, not the publish command's exit code.
4. **Activate where it runs** — install/reload/redeploy so the new version is actually executing, not just available.
5. **Verify the real surface** — the marketplace listing, the CLI's `--version`, the rendered UI. Quote it.
6. **Report** with the artifact, the version, and the quoted live + active evidence. Post the public URL.

## VS Code / editor extensions (the detailed path)

This is the artifact with the most gaps, so it gets the most words.

**Publish.** Use the repo's `scripts/release.sh <version> --confirm` if present (it handles `vsce publish` + `ovsx publish`, tokens from the keychain bundle, and collision pre-flight). Otherwise: `vsce publish --packagePath <vsix>` and `ovsx publish <vsix>`.

**Confirm live on BOTH registries** — publish exit 0 is not propagation:

```bash
# Open VSX
curl -s "https://open-vsx.org/api/<publisher>/<name>" | jq -r '.version'
# VS Code Marketplace (extensionquery)
curl -s -X POST "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json;api-version=3.0-preview.1" \
  -d '{"filters":[{"criteria":[{"filterType":7,"value":"<publisher>.<name>"}]}],"flags":914}' \
  | jq -r '.results[0].extensions[0].versions[0].version'
```

Both must return your target version. Marketplace propagation can lag a minute or two after publish — poll, don't assume.

**Install ≠ active — the gap that bites.** `<cli> --install-extension <vsix> --force` writes the new version to `~/.vscode/extensions` (or `.vscode-oss` for VSCodium), but **a running editor loaded its extension host once, at window open, and keeps the old code until the window reloads.** Every open window has its own host. So after install:

- Reload each running window: command palette → **"Developer: Reload Window"**. Drive it via the `computer` skill's "Electron editors" section (System Events palette keystroke; `type-text`, not `type`; reload each window by raising it via `AXRaise` by title).
- An editor running with **zero windows** needs a fresh one first: `code -n <folder>` / `codium -n <folder>`.
- Purge stale version dirs: if `~/.vscode/extensions/<ext>-<oldver>` lingers beside the new one, remove it so there's a single resolved version.

**Verify activation via `exthost.log` — authoritative, file-based, no GUI needed:**

```bash
# Newest logs session dir per editor: Code | VSCodium | Cursor
BASE="$HOME/Library/Application Support/Code/logs"
LOGDIR="$(ls -dt "$BASE"/*/ | head -1)"
for EH in "$LOGDIR"window*/exthost/exthost.log; do
  echo "== $EH =="
  grep "_doActivateExtension <publisher>.<name>" "$EH" | tail -1   # activation timestamp
  grep "\[error\]" "$EH" | grep -i "<name>" | tail -3              # post-activation errors
done
```

A fresh `_doActivateExtension` timestamp (after your reload) with no trailing `[error]` for the extension = the window is live on the new code. A timestamp from hours ago = that window is still stale; reload it. An error like `command '<x>' not found` after install usually means the running host predates the new `package.json` — a reload clears it.

**Verify the real surface.** Screenshots need ScreenCaptureKit (Screen Recording permission); **AX `get-text`/`describe` do not** — they read the webview's accessibility tree even when screen recording is denied. Open the extension's view and `agents computer get-text --bundle <id>`, then grep for the strings your change should render. Quote them.

## CLIs (npm / cargo)

Publish via the repo's release path. Then prove a **clean-room** install pulls the new version — the publisher's own machine has a cached build, so test where users start:

```bash
# npm
npm view <pkg> version                       # registry serves target?
( cd "$(mktemp -d)" && npx -y <pkg>@latest --version )   # clean install runs target?
# cargo
cargo install <crate> --version <target> --force && <bin> --version
```

If the user installs globally (`npm i -g` / `cargo install`) per their convention, run that and quote `<bin> --version`.

## Web apps / services

Deploying is not shipping — the deploy command finishing is not proof (per F3). Hit the prod surface:

```bash
curl -sS https://<prod-host>/health          # 200 + the new build/version field
```

Quote the status and body. If the app exposes a version/build endpoint, confirm it matches what you shipped. A 200 with the old build means the deploy didn't propagate — investigate, don't claim done.

## Evidence

Every ship claim needs a quotable source: the registry API version, the `exthost.log` activation line, the `--version` output, the health-endpoint body. "It published" / "it's live" / "users have it" without quoted output is exactly the unverified-claim failure this skill exists to prevent. Post the public URL so the user can see the listing themselves.

When you brief a sub-agent for any part of this, end with: `Return file:line quotes (or quoted command output) for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.`
