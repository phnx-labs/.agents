#!/usr/bin/env bash
# rules-check.sh — audit (and with --apply, repair) the rules file each installed agent
# version on THIS machine loads, without `agents sync`.
#
# `agents sync status` fingerprints rule sources, not the installed file, so a version file
# that drifted still reads synced. This check composes each version's ruleset with the
# installed agents-cli's own code (composeRules, readMeta, the agent specs: same layers,
# extra repos, YAML parser and per-version preset) and compares bytes. Metadata is read with
# readMeta({migrate: false}), so the check itself never migrates or rewrites configuration.
# A preset that does not compose leaves that version's file as is.
#
#   rules-check.sh            report: composed hash per preset, each version's file, frozen
#                             account copies
#   rules-check.sh --apply    also: set aside an untracked ~/.agents/rules/rules.yaml,
#                             fast-forward ~/.agents and ~/.agents/.system when clean,
#                             and write each version's rules file that differs or is missing
# Fleet-wide: see "Checking what each machine loads" in rules/README.md.
set -uo pipefail
case "${1:-}" in
  "") APPLY=0 ;;
  --apply) APPLY=1 ;;
  *) echo "usage: rules-check.sh [--apply]" >&2; exit 2 ;;
esac
A="$HOME/.agents"
HOST=$(hostname -s 2>/dev/null || hostname)

bin=$(command -v agents) || { echo "$HOST: agents-cli is not installed" >&2; exit 2; }
# The entrypoint is dist/index.js or, on macOS, the native dist/bin/agents; the modules sit
# under the package root's dist/ either way.
DIST=$(node -e '
const fs = require("fs"), path = require("path");
let d = path.dirname(fs.realpathSync(process.argv[1]));
while (d !== path.dirname(d)) {
  const p = path.join(d, "package.json");
  if (fs.existsSync(p) && JSON.parse(fs.readFileSync(p, "utf-8")).name === "@phnx-labs/agents-cli") break;
  d = path.dirname(d);
}
console.log(path.join(d, "dist"));' "$bin")
[ -f "$DIST/lib/rules/compose.js" ] || { echo "$HOST: no rules composer under $DIST" >&2; exit 2; }

if [ "$APPLY" = 1 ]; then
  y="$A/rules/rules.yaml"
  if [ -f "$y" ] && git -C "$A" rev-parse --is-inside-work-tree >/dev/null 2>&1 </dev/null \
     && ! git -C "$A" ls-files --error-unmatch rules/rules.yaml >/dev/null 2>&1 </dev/null; then
    if mkdir -p "$A/backups" && mv "$y" "$A/backups/rules.yaml.$(date +%Y%m%d%H%M%S)"; then
      echo "$HOST: set aside untracked rules/rules.yaml (it replaced the system preset)"
    else
      echo "$HOST: could not set aside untracked rules/rules.yaml"
    fi
  fi
  for repo in "$A/.system" "$A"; do
    br=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null </dev/null || echo "?")
    if [ "$br" != main ]; then echo "$HOST: $repo on '$br', not pulled"; continue; fi
    if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no </dev/null)" ]; then
      echo "$HOST: $repo has tracked changes, not pulled"; continue; fi
    if ! git -C "$repo" fetch -q origin main </dev/null; then
      echo "$HOST: $repo fetch failed, not pulled"; continue; fi
    if git -C "$repo" merge -q --ff-only origin/main </dev/null 2>/dev/null; then
      echo "$HOST: $repo at $(git -C "$repo" log -1 --format='%h %cs' </dev/null)"
    else
      echo "$HOST: $repo did not fast-forward to origin/main ($(git -C "$repo" rev-list --count origin/main..HEAD </dev/null) local, $(git -C "$repo" rev-list --count HEAD..origin/main </dev/null) remote commits), not pulled"
    fi
  done
fi

read -r -d '' COMPOSE <<'JS' || true  # not $(cat <<...): bash 3.2 misparses quotes in it
import fs from "fs"; import path from "path"; import crypto from "crypto";
const { DIST, A, HOST } = process.env, APPLY = process.env.APPLY === "1";
const { composeRules } = await import(`${DIST}/lib/rules/compose.js`);
const { readMeta, getUserRulesDir, getResolvedRulesDir, resolveExtraRepoDir } = await import(`${DIST}/lib/state.js`);
// discoverRulesLayers and getActiveRulesPreset, over readMeta({migrate: false}): the CLI's
// getters call readMeta() with migration on, which can write agents.yaml and chmod ~/.agents.
const meta = readMeta({ migrate: false });
const layers = [];
if (fs.existsSync(getUserRulesDir())) layers.push({ scope: "user", rulesDir: getUserRulesDir() });
for (const [alias, cfg] of Object.entries(meta.extraRepos || {})) {
  const rulesDir = path.join(resolveExtraRepoDir(alias, cfg), "rules");
  if (cfg?.enabled && fs.existsSync(rulesDir)) layers.push({ scope: "extra", rulesDir, alias });
}
if (fs.existsSync(getResolvedRulesDir())) layers.push({ scope: "system", rulesDir: getResolvedRulesDir() });
const getActiveRulesPreset = (agent, version) => meta.versions?.[agent]?.[version]?.rulesPreset || "default";
const { AGENTS, agentConfigDirName } = await import(`${DIST}/lib/agents.js`);
const h = (b) => crypto.createHash("md5").update(b).digest("hex").slice(0, 8);
const VERSIONS = path.join(A, ".history", "versions");
const rulesFile = (agent) => {
  const cap = AGENTS[agent]?.capabilities?.rules;
  return cap ? path.join(agentConfigDirName(agent), cap.file) : null;
};
const ls = (d) => { try { return fs.readdirSync(d).sort(); } catch { return []; } };

const composed = new Map();
function compose(preset) {
  if (composed.has(preset)) return composed.get(preset);
  let out = null;
  try {
    const r = composeRules({ preset, layers });
    out = Buffer.from(r.content, "utf-8");
    console.log(`${HOST}: preset '${preset}' from ${r.presetLayer} layer; composed ${h(out)} ${out.length} bytes = `
      + r.subrules.map((s) => `${s.name}(${s.layerScope[0]})`).join(" "));
    if (r.presetLayer !== "system")
      console.log(`${HOST}: WARNING the ${r.presetLayer} layer defines preset '${preset}', so the system one is ignored`);
  } catch (e) {
    console.log(`${HOST}: preset '${preset}' does not compose (${e.message}); versions selecting it are left as is`);
  }
  composed.set(preset, out);
  return out;
}

// Write f atomically. The versions dir and every path component below it down to f's directory must
// be a real directory (no symlink can redirect the write), and the temp file is created
// exclusively, so a planted file or link is never written through.
function write(f, content) {
  let cur = VERSIONS;
  for (const part of ["", ...path.relative(VERSIONS, path.dirname(f)).split(path.sep)]) {
    cur = path.join(cur, part);
    let st = null;
    try { st = fs.lstatSync(cur); } catch {}
    if (st && !st.isDirectory()) throw new Error(`${cur} is a symlink or not a directory`);
    if (!st) fs.mkdirSync(cur);
  }
  const tmp = path.join(path.dirname(f), `.rules-check.${crypto.randomBytes(6).toString("hex")}`);
  const fd = fs.openSync(tmp, "wx", 0o644);
  try {
    fs.writeSync(fd, content); fs.fsyncSync(fd); fs.closeSync(fd);
    fs.renameSync(tmp, f);  // replaces a symlink at f itself, as the CLI's writer does
  } catch (e) {
    try { fs.unlinkSync(tmp); } catch {}
    throw e;
  }
}

let failed = 0;
for (const agent of ls(VERSIONS)) for (const version of ls(path.join(VERSIONS, agent))) {
  const home = path.join(VERSIONS, agent, version, "home");
  if (!fs.existsSync(home)) continue;
  const relFile = rulesFile(agent);
  if (!relFile) { console.log(`  skip   ${path.relative(A, home)} (${agent} has no rules file)`); continue; }
  const f = path.join(home, relFile), rel = path.relative(A, f);
  const preset = getActiveRulesPreset(agent, version);
  const want = compose(preset);
  if (!want) { console.log(`  NOPRESET ${rel} (selects '${preset}')`); continue; }
  let st = null;
  try { st = fs.lstatSync(f); } catch {}
  const link = !!st?.isSymbolicLink();
  const got = !st ? "absent" : fs.existsSync(f) ? h(fs.readFileSync(f)) : "dangling";
  if (got === h(want) && !link) { console.log(`  ok     ${rel}`); continue; }
  const what = link ? `link -> ${fs.readlinkSync(f)} (${got})` : got;
  if (!APPLY) { console.log(`  ${link ? "LINK  " : got === "absent" ? "ABSENT" : "STALE "} ${rel} (${what})`); continue; }
  try { write(f, want); console.log(`  fixed  ${rel} (${what} -> ${h(want)})`); }
  catch (e) { failed++; console.log(`  FAILED ${rel} (${e.message})`); }
}
const ACCOUNTS = path.join(A, ".history", "accounts");
for (const agent of ls(ACCOUNTS)) for (const id of ls(path.join(ACCOUNTS, agent))) {
  const relFile = rulesFile(agent);
  if (!relFile) continue;
  const f = path.join(ACCOUNTS, agent, id, relFile);
  let st = null;
  try { st = fs.lstatSync(f); } catch {}
  if (st?.isFile()) console.log(`  frozen ${path.relative(A, f)} (${h(fs.readFileSync(f))}; a copy, not a link to a version)`);
}
process.exit(failed ? 1 : 0);
JS
cd "$A" && DIST=$DIST A=$A HOST=$HOST APPLY=$APPLY node --input-type=module -e "$COMPOSE"
