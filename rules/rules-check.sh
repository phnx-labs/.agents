#!/usr/bin/env bash
# rules-check.sh — audit (and with --apply, repair) the rules file each installed agent
# version on THIS machine loads, without `agents sync`.
#
# It composes the ruleset as agents-cli's version-home writer does (staleness/writers/rules.ts
# -> composeRulesFromState, cli/src/lib/rules/compose.ts) for the user and system layers:
# the preset comes from the first layer whose rules.yaml defines it (user before system),
# each named subrule resolves user-first, then every user subrule not yet named unions in;
# fragments are right-trimmed and joined by one blank line. Each version composes the preset
# it selected (`rulesPreset` in .history/version-resources.json or agents.yaml, else
# `default`). Enabled extra repos (`extraRepos`) are not modelled: when one is set it says so
# and --apply changes nothing. A preset no layer defines leaves that version's file as is,
# as the CLI's writer does. Needs PyYAML (or uv to fetch it), like the CLI's YAML parser.
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

# The CLI parses YAML fully; a partial parser would compose a different ruleset.
if python3 -c 'import yaml' 2>/dev/null; then PY=(python3)
elif command -v uv >/dev/null 2>&1; then PY=(uv run -q --no-project --with pyyaml python)
else echo "$HOST: rules-check.sh needs PyYAML (python3 -m pip install --user pyyaml) or uv" >&2; exit 2
fi
COMPOSE=$(cat <<'PY'
import glob as globmod, hashlib, json, os, sys, tempfile
import yaml
A, HOST, MODE = os.environ["A"], os.environ["HOST"], os.environ["MODE"]
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

def load(path, parse):
    if not os.path.exists(path): return {}
    try:
        with open(path, encoding="utf-8") as fh: doc = parse(fh)
    except (OSError, ValueError, yaml.YAMLError): return None
    return doc if isinstance(doc, dict) else {}

meta = load(f"{A}/agents.yaml", yaml.safe_load)
resources = load(f"{A}/.history/version-resources.json", json.load)
if meta is None or resources is None:
    print(f"{HOST}: WARNING agents.yaml or .history/version-resources.json does not parse; --apply changes nothing")
    if MODE != "report": sys.exit(1)
    meta, resources = meta or {}, resources or {}
extras = sorted(a for a, c in (meta.get("extraRepos") or {}).items() if isinstance(c, dict) and c.get("enabled"))
if extras:
    print(f"{HOST}: WARNING extra repos {', '.join(extras)} add rules layers this check does not model; "
          "STALE may be wrong and --apply changes nothing")
    if MODE != "report": sys.exit(1)
if MODE == "preflight": sys.exit(0)
APPLY = MODE == "apply"

layers = [(s, d) for s, d in (("user", f"{A}/rules"), ("system", f"{A}/.system/rules")) if os.path.isdir(d)]

def preset_def(d, name):
    """The subrules preset `name` lists in d/rules.yaml, or None when that file does not define it."""
    doc = load(f"{d}/rules.yaml", yaml.safe_load)
    presets = (doc or {}).get("presets")
    if not isinstance(presets, dict) or presets.get(name) is None: return None
    return list((presets[name] or {}).get("subrules") or [])

def resolve(d, name):
    for p in (f"{d}/subrules/{name}/rule.md", f"{d}/subrules/{name}.md"):
        if os.path.exists(p): return p

def layer_names(d):
    sd, out = f"{d}/subrules", set()
    if not os.path.isdir(sd): return []
    for e in os.scandir(sd):  # a symlinked directory is not a subrule, as with Dirent.isDirectory()
        if e.is_dir(follow_symlinks=False):
            if os.path.exists(f"{sd}/{e.name}/rule.md"): out.add(e.name)
        elif e.name.endswith(".md") and e.name != "README.md": out.add(e.name[:-3])
    return sorted(out)

h = lambda b: hashlib.md5(b).hexdigest()[:8]
cache = {}
def compose(name):
    if name in cache: return cache[name]
    pre = next(((s, n) for s, d in layers for n in [preset_def(d, name)] if n is not None), None)
    if pre is None:
        cache[name] = None
        print(f"{HOST}: preset {name!r} is not defined in any rules.yaml; versions selecting it are left as is")
        return None
    composed, seen = [], set()
    for sub in pre[1]:
        if sub in seen: continue
        for s, d in layers:
            p = resolve(d, sub)
            if p: composed.append((sub, s, p)); seen.add(sub); break
    for s, d in layers:
        if s == "system": continue
        for sub in layer_names(d):
            if sub not in seen and resolve(d, sub):
                composed.append((sub, s, resolve(d, sub))); seen.add(sub)
    parts = [open(p, "rb").read().decode("utf-8").rstrip() for _, _, p in composed]
    content = (("\n\n".join(parts) + "\n") if parts else "").encode("utf-8")
    print(f"{HOST}: preset {name!r} from {pre[0]} layer; composed {h(content)} {len(content)} bytes = "
          + " ".join(f"{n}({s[0]})" for n, s, _ in composed))
    if pre[0] != "system":
        print(f"{HOST}: WARNING {A}/rules/rules.yaml defines preset {name!r}, so the system one is ignored")
    cache[name] = content
    return content

def selected(agent, version):
    for src in (resources, meta.get("versions") or {}):
        v = ((src.get(agent) or {}).get(version) or {}) if isinstance(src, dict) else {}
        if isinstance(v, dict) and v.get("rulesPreset"): return v["rulesPreset"]
    return "default"

def write(home, f, content):
    """Write f atomically, never through a symlinked directory below home or a planted temp file."""
    cur = home
    for part in os.path.relpath(os.path.dirname(f), home).split(os.sep):
        cur = os.path.join(cur, part)
        if os.path.islink(cur) or (os.path.lexists(cur) and not os.path.isdir(cur)):
            raise OSError(f"{cur} is a symlink or not a directory")
    os.makedirs(os.path.dirname(f), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(f), prefix=".rules-check.")
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(content); out.flush(); os.fsync(out.fileno())
        os.replace(tmp, f)  # replaces a symlink at f itself, as the CLI's writer does
    except BaseException:
        if os.path.lexists(tmp): os.unlink(tmp)
        raise

failed = 0
for home in sorted(globmod.glob(f"{A}/.history/versions/*/*/home")):
    agent, version = home.split("/")[-3], home.split("/")[-2]
    if agent not in RULES_FILE:
        print(f"  skip   {home[len(A) + 1:]} (no rules file known for {agent})"); continue
    f = os.path.join(home, RULES_FILE[agent])
    rel = f[len(A) + 1:]
    want = compose(selected(agent, version))
    if want is None:
        print(f"  NOPRESET {rel} (selects {selected(agent, version)!r})"); continue
    link = os.path.islink(f)
    if not os.path.lexists(f): got = "absent"
    elif os.path.exists(f): got = h(open(f, "rb").read())
    else: got = "dangling"
    if got == h(want) and not link:
        print(f"  ok     {rel}"); continue
    what = f"link -> {os.readlink(f)} ({got})" if link else got
    if not APPLY:
        print(f"  {'LINK ' if link else 'ABSENT' if got == 'absent' else 'STALE'}  {rel} ({what})"); continue
    try:
        write(home, f, want)
        print(f"  fixed  {rel} ({what} -> {h(want)})")
    except OSError as e:
        failed += 1
        print(f"  FAILED {rel} ({e})")
for acct in sorted(globmod.glob(f"{A}/.history/accounts/*/*")):
    agent = acct.split("/")[-2]
    f = os.path.join(acct, RULES_FILE.get(agent, "\0"))
    if agent in RULES_FILE and os.path.isfile(f) and not os.path.islink(f):
        print(f"  frozen {f[len(A) + 1:]} ({h(open(f, 'rb').read())}; a copy, not a link to a version)")
sys.exit(1 if failed else 0)
PY
)
run() { MODE=$1 HOST=$HOST A=$A "${PY[@]}" -c "$COMPOSE"; }

if [ "$APPLY" = 1 ] && ! run preflight; then
  echo "$HOST: --apply changed nothing"; exit 1
fi

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

if [ "$APPLY" = 1 ]; then run apply; else run report; fi
