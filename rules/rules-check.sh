#!/usr/bin/env bash
# rules-check.sh — audit (and with --apply, repair) the rules file each installed agent
# version on THIS machine loads, without `agents sync`.
#
# It composes the ruleset as agents-cli's version-home writer does (staleness/writers/rules.ts
# -> composeRulesFromState, cli/src/lib/rules/compose.ts) for the user and system layers:
# the preset comes from the first layer whose rules.yaml defines it (user before system),
# each named subrule resolves user-first, then every user subrule not yet named unions in;
# fragments are right-trimmed and joined by one blank line. Extra repos (`extraRepos`) and a
# per-version `rulesPreset` in agents.yaml are not modelled: when either is set it says so
# and --apply rewrites nothing.
#
#   rules-check.sh            report: composed hash, each version's file, frozen account copies
#   rules-check.sh --apply    also: set aside an untracked ~/.agents/rules/rules.yaml,
#                             fast-forward ~/.agents and ~/.agents/.system when clean,
#                             and rewrite each version's rules file that differs
# Fleet-wide: see "Checking what each machine loads" in rules/README.md.
set -uo pipefail
case "${1:-}" in
  "") APPLY=0 ;;
  --apply) APPLY=1 ;;
  *) echo "usage: rules-check.sh [--apply]" >&2; exit 2 ;;
esac
A="$HOME/.agents"
HOST=$(hostname -s 2>/dev/null || hostname)

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

APPLY=$APPLY HOST=$HOST A=$A python3 - <<'PY'
import hashlib, os, re, glob
A, HOST, APPLY = os.environ["A"], os.environ["HOST"], os.environ["APPLY"] == "1"
# Rules file per agent under its config dir (agents-cli agent-spec `configDir` and
# `capabilities.rules.file`); an agent not listed is not checked.
RULES_FILE = {
    "claude": ".claude/CLAUDE.md", "codex": ".codex/AGENTS.md", "cursor": ".cursor/.cursorrules",
    "opencode": ".opencode/AGENTS.md", "openclaw": ".openclaw/workspace/AGENTS.md",
    "copilot": ".copilot/AGENTS.md", "amp": ".config/amp/AGENTS.md", "goose": ".config/goose/AGENTS.md",
    "antigravity": ".gemini/antigravity-cli/AGENTS.md", "grok": ".grok/AGENTS.md",
    "kimi": ".kimi-code/AGENTS.md", "droid": ".factory/AGENTS.md", "hermes": ".hermes/MEMORY.md",
    "muse": ".config/muse/AGENTS.md", "warp": ".warp/AGENTS.md",
}
layers = [(s, d) for s, d in (("user", f"{A}/rules"), ("system", f"{A}/.system/rules")) if os.path.isdir(d)]

def preset(d):
    """The default preset's subrules in d/rules.yaml, or None when it defines none."""
    p = f"{d}/rules.yaml"
    if not os.path.exists(p): return None
    try:
        import yaml
        try: doc = yaml.safe_load(open(p, encoding="utf-8")) or {}
        except yaml.YAMLError: return None  # composeRules skips a layer whose rules.yaml does not parse
        if not isinstance(doc, dict): return None
        dflt = (doc.get("presets") or {}).get("default")
        return None if not dflt else list(dflt.get("subrules") or [])
    except ImportError:  # block lists only, as this repo writes them
        names, inside, inlist = [], False, False
        for line in open(p, encoding="utf-8"):
            if re.match(r"^\s+default:\s*$", line): inside = True; continue
            if inside and re.match(r"^\s{0,2}\S", line): break
            if inside and re.match(r"^\s+subrules:\s*\[\s*\]\s*$", line): return []
            if inside and re.match(r"^\s+subrules:\s*$", line): inlist = True; continue
            m = re.match(r"^\s+-\s+[\"']?([^\"'\s]+)", line)
            if inside and inlist and m: names.append(m.group(1))
        return names if inside else None

def resolve(d, name):
    for p in (f"{d}/subrules/{name}/rule.md", f"{d}/subrules/{name}.md"):
        if os.path.exists(p): return p

def layer_names(d):
    sd, out = f"{d}/subrules", set()
    if not os.path.isdir(sd): return []
    for e in os.listdir(sd):
        if os.path.isdir(f"{sd}/{e}") and os.path.exists(f"{sd}/{e}/rule.md"): out.add(e)
        elif e.endswith(".md") and e != "README.md": out.add(e[:-3])
    return sorted(out)

pre = next(((s, n) for s, d in layers for n in [preset(d)] if n is not None), None)
composed, seen = [], set()
for name in (pre[1] if pre else []):
    if name in seen: continue
    for s, d in layers:
        p = resolve(d, name)
        if p: composed.append((name, s, p)); seen.add(name); break
for s, d in layers:
    if s == "system": continue
    for name in layer_names(d):
        if name not in seen and resolve(d, name):
            composed.append((name, s, resolve(d, name))); seen.add(name)
parts = [open(p, "rb").read().decode("utf-8").rstrip() for _, _, p in composed]
content = (("\n\n".join(parts) + "\n") if parts else "").encode("utf-8")
h = lambda b: hashlib.md5(b).hexdigest()[:8]
want = h(content)
print(f"{HOST}: preset from {pre[0] if pre else 'NONE'} layer; composed {want} {len(content)} bytes = "
      + " ".join(f"{n}({s[0]})" for n, s, _ in composed))
if pre and pre[0] != "system":
    print(f"{HOST}: WARNING {A}/rules/rules.yaml defines the default preset, so the system preset is ignored")

unmodelled = [k for k in ("extraRepos", "rulesPreset") for f in (f"{A}/agents.yaml", f"{A}/.system/agents.yaml")
              if os.path.exists(f) and re.search(rf"^\s*{k}:", open(f, encoding="utf-8").read(), re.M)]
if unmodelled:
    print(f"{HOST}: WARNING agents.yaml sets {', '.join(sorted(set(unmodelled)))}, which this check does not model; "
          "STALE may be wrong and --apply rewrites nothing")
    APPLY = False

for home in sorted(glob.glob(f"{A}/.history/versions/*/*/home")):
    agent = home.split("/")[-3]
    if agent not in RULES_FILE:
        print(f"  skip   {home[len(A) + 1:]} (no rules file known for {agent})"); continue
    f = os.path.join(home, RULES_FILE[agent])
    rel = f[len(A) + 1:]
    if not os.path.lexists(f):
        print(f"  absent {rel}"); continue
    link = os.path.islink(f)
    got = h(open(f, "rb").read()) if os.path.exists(f) else "dangling"
    if got == want and not link:
        print(f"  ok     {rel}"); continue
    what = f"link -> {os.readlink(f)} ({got})" if link else got
    if APPLY:
        tmp = f + ".rules-check.tmp"
        try:
            with open(tmp, "wb") as out:
                out.write(content); out.flush(); os.fsync(out.fileno())
            if link: os.unlink(f)  # the writer replaces a symlink with a regular file
            os.replace(tmp, f)
        finally:
            if os.path.exists(tmp): os.unlink(tmp)
        print(f"  fixed  {rel} ({what} -> {want})")
    else:
        print(f"  {'LINK ' if link else 'STALE'}  {rel} ({what})")
for f in sorted(glob.glob(f"{A}/.history/accounts/*/*/.*/CLAUDE.md") + glob.glob(f"{A}/.history/accounts/*/*/.*/AGENTS.md")):
    if not os.path.islink(f):
        print(f"  frozen {f[len(A) + 1:]} ({h(open(f, 'rb').read())}; a copy, not a link to a version)")
PY
