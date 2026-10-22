#!/usr/bin/env bash
# rules-check.sh — audit (and with --apply, repair) the instruction file every installed
# agent version on THIS machine loads, without `agents sync`.
#
# It composes the ruleset exactly as agents-cli's composeRules does (cli/src/lib/rules/compose.ts):
# the preset comes from the first layer whose rules.yaml defines it (user before system),
# each named subrule resolves user-first, then every non-system subrule not yet named unions in;
# fragments are right-trimmed and joined by one blank line.
#
#   rules-check.sh            report: sources, composed hash, each version's file, stray files
#   rules-check.sh --apply    also: set aside an untracked ~/.agents/rules/rules.yaml,
#                             fast-forward ~/.agents and ~/.agents/.system when clean,
#                             and rewrite each version's instruction file that differs
# Fleet-wide: see "Checking what each machine loads" in rules/README.md.
set -euo pipefail
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
A="$HOME/.agents"
HOST=$(hostname -s 2>/dev/null || hostname)

if [ "$APPLY" = 1 ]; then
  y="$A/rules/rules.yaml"
  if [ -f "$y" ] && ! git -C "$A" ls-files --error-unmatch rules/rules.yaml >/dev/null 2>&1; then
    mkdir -p "$A/backups"
    mv "$y" "$A/backups/rules.yaml.$(date +%Y%m%d%H%M%S)"
    echo "$HOST: set aside untracked rules/rules.yaml (it replaced the system preset)"
  fi
  for repo in "$A/.system" "$A"; do
    br=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    if [ "$br" != main ]; then echo "$HOST: $repo on '$br', not pulled"; continue; fi
    if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
      echo "$HOST: $repo has tracked changes, not pulled"; continue; fi
    git -C "$repo" fetch -q origin main
    if git -C "$repo" merge -q --ff-only origin/main 2>/dev/null; then
      echo "$HOST: $repo at $(git -C "$repo" log -1 --format='%h %cs')"
    else
      echo "$HOST: $repo diverged from origin/main ($(git -C "$repo" rev-list --count origin/main..HEAD) local, $(git -C "$repo" rev-list --count HEAD..origin/main) remote), not pulled"
    fi
  done
fi

APPLY=$APPLY HOST=$HOST A=$A python3 - <<'PY'
import hashlib, os, re, glob
A, HOST, APPLY = os.environ["A"], os.environ["HOST"], os.environ["APPLY"] == "1"
layers = [("user", f"{A}/rules"), ("system", f"{A}/.system/rules")]
layers = [(s, d) for s, d in layers if os.path.isdir(d)]

def preset(d):
    p = f"{d}/rules.yaml"
    if not os.path.exists(p): return None
    names, inside, inlist = [], False, False
    for line in open(p):
        if re.match(r"^\s{2}default:\s*$", line): inside = True; continue
        if inside and re.match(r"^\s{2}\S", line): break
        if inside and re.match(r"^\s+subrules:\s*\[\s*\]\s*$", line): return []
        if inside and re.match(r"^\s+subrules:\s*$", line): inlist = True; continue
        m = re.match(r"^\s+-\s+(\S+)", line)
        if inside and inlist and m: names.append(m.group(1))
    return names if inside else None

def resolve(d, name):
    for p in (f"{d}/subrules/{name}/rule.md", f"{d}/subrules/{name}.md"):
        if os.path.exists(p): return p

def layer_names(d):
    out = set()
    sd = f"{d}/subrules"
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
        if name in seen: continue
        p = resolve(d, name)
        if p: composed.append((name, s, p)); seen.add(name)
parts = [open(p).read().rstrip() for _, _, p in composed]
content = ("\n\n".join(parts) + "\n") if parts else ""
h = lambda b: hashlib.md5(b).hexdigest()[:8]
want = h(content.encode())
print(f"{HOST}: preset from {pre[0] if pre else 'NONE'} layer; composed {want} {len(content)}B = "
      + " ".join(f"{n}({s[0]})" for n, s, _ in composed))
if pre and pre[0] != "system":
    print(f"{HOST}: WARNING {A}/rules/rules.yaml defines the default preset, so the system preset is ignored")

for f in sorted(glob.glob(f"{A}/.history/versions/*/*/home/.*/CLAUDE.md") + glob.glob(f"{A}/.history/versions/*/*/home/.*/AGENTS.md")):
    rel = f[len(A) + 1:]
    if os.path.islink(f): continue
    got = h(open(f, "rb").read())
    if got == want: print(f"  ok     {rel}"); continue
    if APPLY:
        tmp = f + ".rules-check.tmp"
        open(tmp, "w").write(content); os.replace(tmp, f)
        print(f"  fixed  {rel} ({got} -> {want})")
    else:
        print(f"  STALE  {rel} ({got})")
for f in sorted(glob.glob(f"{A}/.history/accounts/*/*/.*/CLAUDE.md") + glob.glob(f"{A}/.history/accounts/*/*/.*/AGENTS.md")):
    if not os.path.islink(f):
        print(f"  frozen {f[len(A) + 1:]} ({h(open(f, 'rb').read())}; a copy, not a link to a version)")
PY
