#!/usr/bin/env bash
# SessionStart hook: fast-forward the session's working directory git repo
# when the tree is clean. Brings origin/<upstream> into the current branch
# without force, without rebasing local commits, and without autostash.
#
# Safety contract (never override local work):
#   1. Dirty working tree / index  → skip (exit 0).
#   2. Detached HEAD               → skip.
#   3. No upstream configured      → skip.
#   4. Local commits not on remote → skip (would require a non-ff merge/rebase).
#   5. Only `git merge --ff-only` after a successful fetch. Never --force,
#      never rebase, never reset, never clean, never autostash.
#
# Stdout is kept empty: SessionStart stdout is injected into the model context.
# Opt out per-machine: export AGENTS_NO_GIT_PULL_FORWARD=1
set -euo pipefail

# Drain SessionStart stdin (payload). We re-parse a copy for cwd only.
input=$(cat 2>/dev/null || true)

[ -n "${AGENTS_NO_GIT_PULL_FORWARD:-}" ] && exit 0
command -v git >/dev/null 2>&1 || exit 0

# --- portable JSON field extractor (jq → node → python) -----------------------
_json_field() {  # $1=json  $2=dotted.path
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r "(.$2) // empty" 2>/dev/null; return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{let o=JSON.parse(s);for(const k of process.argv[1].split("."))o=(o==null?null:o[k]);process.stdout.write(o==null?"":String(o))}catch(e){}})' "$2" 2>/dev/null; return 0
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$1" | "$_py" -c 'import json,sys
try: o=json.load(sys.stdin)
except Exception: o=None
for k in sys.argv[1].split("."):
    o=o.get(k) if isinstance(o,dict) else None
sys.stdout.write("" if o is None else str(o))' "$2" 2>/dev/null
    return 0
  done
  return 1
}

cwd=""
if [ -n "$input" ]; then
  cwd=$(_json_field "$input" cwd 2>/dev/null || true)
  # Claude / Grok alternate shapes
  if [ -z "$cwd" ]; then
    cwd=$(_json_field "$input" working_directory 2>/dev/null || true)
  fi
  if [ -z "$cwd" ]; then
    cwd=$(_json_field "$input" cwdPath 2>/dev/null || true)
  fi
fi
# Fall back to the process cwd when the payload has no path.
if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
  cwd=$(pwd -P 2>/dev/null || pwd)
fi

cd "$cwd" 2>/dev/null || exit 0

# Must be inside a work tree (not just a bare repo).
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
case "$(git rev-parse --is-inside-work-tree 2>/dev/null || echo false)" in
  true) ;;
  *) exit 0 ;;
esac

# Dirty tree → never touch it.
if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
  exit 0
fi

# Detached HEAD → skip.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
  exit 0
fi

# Need an upstream. Don't invent origin/main if the branch has none configured.
upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)
if [ -z "$upstream" ]; then
  exit 0
fi

# Fetch quietly; network / auth failure → skip (never block session start).
if ! git fetch --quiet --no-tags 2>/dev/null; then
  exit 0
fi

# Re-check clean after fetch (rare, but a concurrent writer could dirty us).
if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
  exit 0
fi

# Only fast-forward: requires HEAD to be an ancestor of upstream (we are
# behind or equal). If we have local commits not on upstream, skip.
if ! git merge-base --is-ancestor HEAD "$upstream" 2>/dev/null; then
  exit 0
fi

# Already up to date?
if [ "$(git rev-parse HEAD 2>/dev/null)" = "$(git rev-parse "$upstream" 2>/dev/null)" ]; then
  exit 0
fi

# Fast-forward only. Never force, never rebase, never autostash.
git merge --ff-only --quiet "$upstream" >/dev/null 2>&1 || true

exit 0
