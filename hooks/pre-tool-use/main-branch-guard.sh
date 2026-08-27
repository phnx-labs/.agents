#!/bin/sh
# Registered entrypoint for the canonical rule-bundled guard. Hook discovery
# only installs scripts below hooks/, while the implementation intentionally
# lives with its rule. Keep this file logic-free: one definition, one fix site.
set -eu

_ENTRY_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _ENTRY_DIR=""
_REAL_HOME=${AGENTS_REAL_HOME:-$HOME}
for _guard in \
  "$_ENTRY_DIR/../../rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh" \
  "$_REAL_HOME/.agents/.system/rules/subrules/truly-agentic-git-workflow/main-branch-guard.sh"
do
  if [ -f "$_guard" ]; then
    exec sh "$_guard"
  fi
done

printf 'main-branch-guard: canonical rule guard not found — refusing the tool call unchecked (fail-closed).\n' >&2
exit 2
