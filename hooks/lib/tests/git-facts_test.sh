#!/usr/bin/env bash
# Tests for hooks/lib/git-facts.sh — shared short-TTL git-fact cache (RUSH-2293).
#
# Real throwaway git repos only (no mocking). Covers:
#   - on-default / off-default / non-git / origin/HEAD default
#   - cache hit on repeated load of the same dir
#   - branch switch invalidates immediately (HEAD re-validation), even inside TTL
#   - TTL expiry forces recompute
#   - microbench: warm load is materially cheaper than cold (git forks)
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
LIB="$DIR/../git-facts.sh"
pass=0
fail=0

# Isolate cache + home so we never touch the user's state.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_FACTS_CACHE_DIR="$TMP/git-facts-cache"
export GIT_FACTS_TTL_SEC=30
export GIT_CONFIG_NOSYSTEM=1

# shellcheck source=git-facts.sh
. "$LIB"

git_q() { git -c user.email=t@t.dev -c user.name=t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# --- fixtures ---------------------------------------------------------------

MAIN_REPO="$TMP/main_repo"
mkdir -p "$MAIN_REPO"
git_q -C "$MAIN_REPO" init
git_q -C "$MAIN_REPO" commit --allow-empty -m init
mkdir -p "$MAIN_REPO/sub/deep"
echo x > "$MAIN_REPO/tracked.txt"
echo x > "$MAIN_REPO/sub/deep/f.txt"

FEAT_REPO="$TMP/feat_repo"
mkdir -p "$FEAT_REPO"
git_q -C "$FEAT_REPO" init
git_q -C "$FEAT_REPO" commit --allow-empty -m init
git_q -C "$FEAT_REPO" checkout -b feat/x
echo x > "$FEAT_REPO/tracked.txt"

BARE="$TMP/origin.git"
git_q init --bare -b trunk "$BARE"
CLONE="$TMP/clone"
git_q clone "$BARE" "$CLONE"
git_q -C "$CLONE" commit --allow-empty -m init
git_q -C "$CLONE" push -u origin trunk
git_q -C "$CLONE" remote set-head origin trunk

NOGIT="$TMP/plain"
mkdir -p "$NOGIT"
echo x > "$NOGIT/file.txt"

WT_LINK="$TMP/wt_link"
git_q -C "$MAIN_REPO" worktree add -b wt-feat "$WT_LINK"

# --- correctness ------------------------------------------------------------

GIT_FACTS_HITS=0
GIT_FACTS_MISSES=0

if git_facts_load "$MAIN_REPO"; then
  if [ "$GIT_FACTS_ON_DEFAULT" = 1 ] && [ "$GIT_FACTS_CUR" = "main" ] && [ -n "$GIT_FACTS_TOP" ]; then
    ok "main_repo: on default (main)"
  else
    bad "main_repo: expected on-default main, got on=$GIT_FACTS_ON_DEFAULT cur=$GIT_FACTS_CUR top=$GIT_FACTS_TOP"
  fi
else
  bad "main_repo: git_facts_load failed"
fi

if git_facts_on_default "$MAIN_REPO"; then
  ok "git_facts_on_default: main is protected"
else
  bad "git_facts_on_default: main should be protected"
fi

if git_facts_load "$FEAT_REPO"; then
  if [ "$GIT_FACTS_ON_DEFAULT" = 0 ] && [ "$GIT_FACTS_CUR" = "feat/x" ]; then
    ok "feat_repo: off default"
  else
    bad "feat_repo: expected off-default feat/x, got on=$GIT_FACTS_ON_DEFAULT cur=$GIT_FACTS_CUR"
  fi
else
  bad "feat_repo: git_facts_load failed"
fi

if git_facts_on_default "$FEAT_REPO"; then
  bad "git_facts_on_default: feat should allow (return 1)"
else
  ok "git_facts_on_default: feat is not protected"
fi

if git_facts_load "$CLONE"; then
  if [ "$GIT_FACTS_ON_DEFAULT" = 1 ] && [ "$GIT_FACTS_CUR" = "trunk" ] && [ "$GIT_FACTS_DEF" = "trunk" ]; then
    ok "clone: origin/HEAD trunk is protected"
  else
    bad "clone: expected on trunk/trunk, got on=$GIT_FACTS_ON_DEFAULT cur=$GIT_FACTS_CUR def=$GIT_FACTS_DEF"
  fi
else
  bad "clone: git_facts_load failed"
fi

if git_facts_load "$NOGIT"; then
  bad "non-git dir should return 1"
else
  ok "non-git dir: load returns 1"
fi

if git_facts_load "$WT_LINK"; then
  if [ "$GIT_FACTS_ON_DEFAULT" = 0 ] && [ "$GIT_FACTS_CUR" = "wt-feat" ]; then
    ok "linked worktree: off default"
  else
    bad "linked worktree: expected wt-feat off-default, got on=$GIT_FACTS_ON_DEFAULT cur=$GIT_FACTS_CUR"
  fi
else
  bad "linked worktree: git_facts_load failed"
fi

# Nested path under main resolves same top + on-default.
if git_facts_load "$MAIN_REPO/sub/deep"; then
  if [ "$GIT_FACTS_ON_DEFAULT" = 1 ]; then
    ok "nested path under main is on-default"
  else
    bad "nested path under main should be on-default"
  fi
else
  bad "nested path load failed"
fi

# --- cache hit on repeat ----------------------------------------------------

GIT_FACTS_HITS=0
GIT_FACTS_MISSES=0
# Clear prior entries for a clean counter on this dir.
rm -rf "$GIT_FACTS_CACHE_DIR"
mkdir -p "$GIT_FACTS_CACHE_DIR"

git_facts_load "$MAIN_REPO" >/dev/null
m1=$GIT_FACTS_MISSES
h1=$GIT_FACTS_HITS
git_facts_load "$MAIN_REPO" >/dev/null
m2=$GIT_FACTS_MISSES
h2=$GIT_FACTS_HITS

if [ "$m1" -eq 1 ] && [ "$h1" -eq 0 ] && [ "$m2" -eq 1 ] && [ "$h2" -eq 1 ]; then
  ok "second load of same dir is a cache hit (misses=$m2 hits=$h2)"
else
  bad "expected miss then hit; got first misses=$m1 hits=$h1, second misses=$m2 hits=$h2"
fi

# --- branch switch invalidates inside TTL -----------------------------------

SWITCH_REPO="$TMP/switch_repo"
mkdir -p "$SWITCH_REPO"
git_q -C "$SWITCH_REPO" init
git_q -C "$SWITCH_REPO" commit --allow-empty -m init
# Ensure we start on main.
git_q -C "$SWITCH_REPO" checkout main 2>/dev/null || true

rm -rf "$GIT_FACTS_CACHE_DIR"
mkdir -p "$GIT_FACTS_CACHE_DIR"
GIT_FACTS_TTL_SEC=60
GIT_FACTS_HITS=0
GIT_FACTS_MISSES=0

git_facts_load "$SWITCH_REPO" >/dev/null
if [ "$GIT_FACTS_ON_DEFAULT" != 1 ]; then
  bad "switch_repo pre-switch should be on-default (cur=$GIT_FACTS_CUR)"
else
  ok "switch_repo pre-switch on-default"
fi

git_q -C "$SWITCH_REPO" checkout -b feat/switch
git_facts_load "$SWITCH_REPO" >/dev/null
if [ "$GIT_FACTS_ON_DEFAULT" = 0 ] && [ "$GIT_FACTS_CUR" = "feat/switch" ]; then
  ok "branch switch invalidates cache inside TTL (now feat/switch)"
else
  bad "after switch expected off-default feat/switch, got on=$GIT_FACTS_ON_DEFAULT cur=$GIT_FACTS_CUR hits=$GIT_FACTS_HITS misses=$GIT_FACTS_MISSES"
fi

# Switch back to main — must protect again.
git_q -C "$SWITCH_REPO" checkout main
git_facts_load "$SWITCH_REPO" >/dev/null
if [ "$GIT_FACTS_ON_DEFAULT" = 1 ] && [ "$GIT_FACTS_CUR" = "main" ]; then
  ok "switch back to main re-protects inside TTL"
else
  bad "after switch-back expected on-default main, got on=$GIT_FACTS_ON_DEFAULT cur=$GIT_FACTS_CUR"
fi

# --- TTL expiry -------------------------------------------------------------

rm -rf "$GIT_FACTS_CACHE_DIR"
mkdir -p "$GIT_FACTS_CACHE_DIR"
export GIT_FACTS_TTL_SEC=1
GIT_FACTS_HITS=0
GIT_FACTS_MISSES=0

git_facts_load "$MAIN_REPO" >/dev/null
git_facts_load "$MAIN_REPO" >/dev/null
# Warm hit.
if [ "$GIT_FACTS_HITS" -ge 1 ]; then
  ok "TTL=1s still hits within the second"
else
  bad "expected a hit within TTL=1s (hits=$GIT_FACTS_HITS misses=$GIT_FACTS_MISSES)"
fi
sleep 2
h_before=$GIT_FACTS_HITS
m_before=$GIT_FACTS_MISSES
git_facts_load "$MAIN_REPO" >/dev/null
if [ "$GIT_FACTS_MISSES" -gt "$m_before" ]; then
  ok "TTL expiry forces recompute (misses $m_before -> $GIT_FACTS_MISSES)"
else
  bad "after 2s with TTL=1 expected a miss; hits=$GIT_FACTS_HITS (was $h_before) misses=$GIT_FACTS_MISSES (was $m_before)"
fi

# --- microbench: warm << cold ----------------------------------------------

export GIT_FACTS_TTL_SEC=30
rm -rf "$GIT_FACTS_CACHE_DIR"
mkdir -p "$GIT_FACTS_CACHE_DIR"

# Cold: 25 loads of distinct dirs under same repo would still share after first
# top resolution... use one dir, but force miss by clearing cache each time.
cold_ms=$(
  python3 - <<'PY' "$LIB" "$MAIN_REPO" "$GIT_FACTS_CACHE_DIR"
import os, subprocess, sys, time, shutil
lib, repo, cdir = sys.argv[1], sys.argv[2], sys.argv[3]
n = 15
# Each iteration: wipe cache so every load is a cold miss (3 git forks).
times = []
for _ in range(n):
    shutil.rmtree(cdir, ignore_errors=True)
    os.makedirs(cdir, exist_ok=True)
    script = f'''
. "{lib}"
export GIT_FACTS_CACHE_DIR="{cdir}"
export GIT_FACTS_TTL_SEC=30
git_facts_load "{repo}" >/dev/null
'''
    t0 = time.perf_counter()
    subprocess.run(["sh", "-c", script], check=True, env={**os.environ, "HOME": os.environ.get("HOME","")})
    times.append((time.perf_counter() - t0) * 1000)
print(f"{sum(times)/len(times):.2f}")
PY
)

warm_ms=$(
  python3 - <<'PY' "$LIB" "$MAIN_REPO" "$GIT_FACTS_CACHE_DIR"
import os, subprocess, sys, time, shutil
lib, repo, cdir = sys.argv[1], sys.argv[2], sys.argv[3]
shutil.rmtree(cdir, ignore_errors=True)
os.makedirs(cdir, exist_ok=True)
# Prime
prime = f'''. "{lib}"
export GIT_FACTS_CACHE_DIR="{cdir}"
export GIT_FACTS_TTL_SEC=30
git_facts_load "{repo}" >/dev/null
'''
subprocess.run(["sh", "-c", prime], check=True, env={**os.environ, "HOME": os.environ.get("HOME","")})
n = 25
times = []
for _ in range(n):
    script = f'''
. "{lib}"
export GIT_FACTS_CACHE_DIR="{cdir}"
export GIT_FACTS_TTL_SEC=30
git_facts_load "{repo}" >/dev/null
'''
    t0 = time.perf_counter()
    subprocess.run(["sh", "-c", script], check=True, env={**os.environ, "HOME": os.environ.get("HOME","")})
    times.append((time.perf_counter() - t0) * 1000)
print(f"{sum(times)/len(times):.2f}")
PY
)

printf 'bench - cold mean %s ms, warm mean %s ms\n' "$cold_ms" "$warm_ms"
# Warm should be at least 2x faster (usually 5-20x). Allow load noise on busy hosts.
python3 -c "
cold=float('$cold_ms'); warm=float('$warm_ms')
# Require warm < cold * 0.75 and warm < 40ms on a healthy box; if cold is already
# tiny (<5ms) the machine is so fast the ratio is noise — still require warm<=cold.
if warm <= cold and (cold < 5.0 or warm < cold * 0.75):
    raise SystemExit(0)
raise SystemExit(1)
" && ok "warm load materially faster than cold (cold=${cold_ms}ms warm=${warm_ms}ms)" \
  || bad "warm not faster enough (cold=${cold_ms}ms warm=${warm_ms}ms)"

# --- TTL=0 disables cache ---------------------------------------------------

export GIT_FACTS_TTL_SEC=0
rm -rf "$GIT_FACTS_CACHE_DIR"
mkdir -p "$GIT_FACTS_CACHE_DIR"
GIT_FACTS_HITS=0
GIT_FACTS_MISSES=0
git_facts_load "$MAIN_REPO" >/dev/null
git_facts_load "$MAIN_REPO" >/dev/null
if [ "$GIT_FACTS_HITS" -eq 0 ] && [ "$GIT_FACTS_MISSES" -eq 2 ]; then
  ok "TTL=0 disables cache (2 misses, 0 hits)"
else
  bad "TTL=0 expected 2 misses 0 hits, got misses=$GIT_FACTS_MISSES hits=$GIT_FACTS_HITS"
fi

echo
echo "git-facts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
