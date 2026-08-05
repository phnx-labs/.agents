#!/usr/bin/env bash
# SessionStart hook: make this machine current (config repos + secrets + sessions
# -> reconcile) so nobody has to type `agents sync`. Part of epic #363.
#
# Two properties keep this safe to run on EVERY session start for every agent:
#   1. THROTTLED  — runs at most once per AGENTS_AUTOSYNC_INTERVAL (default 4h),
#                   gated by a timestamp file. The stamp is written before the
#                   sync runs, so a failed/slow sync never thrashes.
#   2. NON-BLOCKING — the actual `agents sync` is fully detached (setsid + &),
#                   so a slow git pull / reconcile never delays session start.
#
# Stdout is kept empty: SessionStart stdout is injected into the model context
# on Claude/Codex, and this hook has nothing to say to the model.
#
# Opt out per-machine with: export AGENTS_NO_AUTOSYNC=1
set -euo pipefail

# Drain stdin (the SessionStart payload) so the agent isn't left writing to a
# closed pipe; we don't need its contents.
cat >/dev/null 2>&1 || true

[ -n "${AGENTS_NO_AUTOSYNC:-}" ] && exit 0
command -v agents >/dev/null 2>&1 || exit 0

interval="${AGENTS_AUTOSYNC_INTERVAL:-14400}"   # seconds; default 4h
stamp="${HOME}/.agents/.cache/state/last-autosync"
now="$(date +%s)"

if [ -f "$stamp" ]; then
  last="$(cat "$stamp" 2>/dev/null || echo 0)"
  case "$last" in (''|*[!0-9]*) last=0 ;; esac
  if [ $(( now - last )) -lt "$interval" ]; then
    exit 0
  fi
fi

mkdir -p "$(dirname "$stamp")"
printf '%s' "$now" > "$stamp"

# Detach completely: new session + background, stdio fully closed, so this can
# never block or leak output into the agent's session.
( setsid agents sync --yes --quiet >/dev/null 2>&1 & ) </dev/null >/dev/null 2>&1 || true

exit 0
