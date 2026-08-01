#!/usr/bin/env bash
# env.sh — shared paths + helpers for a clify build. Source this first:
#   source "$(dirname "$0")/lib/env.sh"   (or the absolute path to this file)
#
# Establishes a per-build workspace under the system scratch dir so nothing
# clify writes can ever land on a git branch, and exposes small helpers the
# stage subprompts reference.

# Workspace root — gitignored scratch, never the repo tree.
: "${CLIFY_HOME:=${TMPDIR:-/tmp}/clify}"

# clify_workspace <slug> — echo (creating if needed) the build dir for a target.
clify_workspace() {
  local slug="$1"
  [ -n "$slug" ] || { echo "clify_workspace: slug required" >&2; return 2; }
  local ws="$CLIFY_HOME/$slug"
  mkdir -p "$ws"
  printf '%s\n' "$ws"
}

# clify_slug <target> — normalize a target ("Stripe.com", "https://api.x.co/") to
# a kebab slug ("stripe", "api-x-co") usable as a package/bin suffix.
clify_slug() {
  printf '%s' "$1" \
    | sed -E 's#^https?://##; s#/.*$##; s#^www\.##; s#\.(com|io|dev|ai|co|net|org|app)$##' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#[^a-z0-9]+#-#g; s#^-+|-+$##g'
}

# clify_bundle <slug> — the agents-secrets bundle name for a target's credentials.
clify_bundle() { printf 'clify.%s\n' "$1"; }
