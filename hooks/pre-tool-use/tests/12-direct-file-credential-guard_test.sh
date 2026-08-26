#!/usr/bin/env bash

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../12-direct-file-credential-guard.sh"
SOURCE="$HERE/../../../permissions/groups/99-deny.yaml"
AGENTS_YAML="$HERE/../../../agents.yaml"
SH_BIN="$(command -v sh)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0
fail=0
RC=0
OUT=""
ERR=""

json_payload() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {sys.argv[2]: sys.argv[3]}}))
PY
}

run_payload() {
  local payload="$1" source_mode="${2:-$SOURCE}" hook_path="${3:-$HOOK}"
  local home_override="${4:-$HOME}" path_override="${5:-$PATH}"
  local infile="$SANDBOX/in.$$.$RANDOM" outfile="$SANDBOX/out.$$.$RANDOM" errfile="$SANDBOX/err.$$.$RANDOM"
  printf '%s' "$payload" >"$infile"
  RC=0
  if [[ "$source_mode" == discover ]]; then
    (unset AGENTS_CREDENTIAL_DENY_SOURCE; HOME="$home_override" PATH="$path_override" AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$hook_path" <"$infile" >"$outfile" 2>"$errfile") || RC=$?
  else
    HOME="$home_override" PATH="$path_override" AGENTS_CREDENTIAL_DENY_SOURCE="$source_mode" AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$hook_path" <"$infile" >"$outfile" 2>"$errfile" || RC=$?
  fi
  OUT="$(cat "$outfile" 2>/dev/null)"
  ERR="$(cat "$errfile" 2>/dev/null)"
  rm -f "$infile" "$outfile" "$errfile"
}

record_pass() {
  printf 'ok   - %s\n' "$1"
  pass=$((pass + 1))
}

record_fail() {
  printf 'FAIL - %s: rc=%s stdout=%s stderr=%s\n' "$1" "$RC" "$OUT" "$ERR"
  fail=$((fail + 1))
}

check_deny() {
  local label="$1"
  if [[ "$RC" -ne 0 ]] && printf '%s' "$OUT" | python3 -c 'import json,sys; value=json.load(sys.stdin); assert value.get("decision")=="deny"; assert value.get("hookSpecificOutput",{}).get("permissionDecision")=="deny"' 2>/dev/null; then
    record_pass "$label"
  else
    record_fail "$label"
  fi
}

check_dual_deny() {
  local label="$1" protected_value="$2"
  if [[ "$RC" -eq 2 && -n "$ERR" && "${#ERR}" -lt 200 && "$ERR" != *"$protected_value"* ]] && printf '%s' "$OUT" | python3 -c 'import json,sys; value=json.load(sys.stdin); assert value.get("decision")=="deny"; assert value.get("hookSpecificOutput",{}).get("permissionDecision")=="deny"' 2>/dev/null; then
    record_pass "$label"
  else
    record_fail "$label"
  fi
}

check_allow() {
  local label="$1"
  if [[ "$RC" -eq 0 && -z "$OUT" ]]; then
    record_pass "$label"
  else
    record_fail "$label"
  fi
}

check_fail_closed() {
  local label="$1"
  if [[ "$RC" -ne 0 ]]; then
    record_pass "$label"
  else
    record_fail "$label"
  fi
}

check_identity_fail_closed() {
  local label="$1"
  if [[ "$RC" -eq 2 && -z "$OUT" && -n "$ERR" && "${#ERR}" -lt 200 ]]; then
    record_pass "$label"
  else
    record_fail "$label"
  fi
}

materialize() {
  local pattern="$1" home_root="${2:-$HOME}"
  local relative="${pattern#\~/}"
  case "$pattern" in
    */\*\*) printf '%s/%s/probe' "$home_root" "${relative%/\*\*}" ;;
    */\*.json) printf '%s/%s' "$home_root" "${relative/\*/probe}" ;;
    *) printf '%s/%s' "$home_root" "$relative" ;;
  esac
}

protected_patterns=()
while IFS= read -r pattern; do
  protected_patterns+=("$pattern")
done < <(awk '
  /^[[:space:]]*- "Read\(/ {
    line=$0
    sub(/^[[:space:]]*- "Read\(/, "", line)
    sub(/\)"[[:space:]]*$/, "", line)
    print line
  }
' "$SOURCE")

printf 'direct-file-credential-guard\n'

if [[ "${#protected_patterns[@]}" -eq 12 ]]; then
  record_pass "canonical YAML defines 12 source-derived credential patterns"
else
  record_fail "canonical YAML defines 12 source-derived credential patterns"
  exit 1
fi

recursive_pattern=""
json_pattern=""
exact_pattern=""
for pattern in "${protected_patterns[@]}"; do
  case "$pattern" in
    */\*\*) [[ -n "$recursive_pattern" ]] || recursive_pattern="$pattern" ;;
    */\*.json) [[ -n "$json_pattern" ]] || json_pattern="$pattern" ;;
    *) [[ -n "$exact_pattern" ]] || exact_pattern="$pattern" ;;
  esac
  target="$(materialize "$pattern")"
  for tool in Read Edit Write; do
    run_payload "$(json_payload "$tool" file_path "$target")"
    check_deny "$tool denies source-derived pattern $pattern"
  done
done

alias_index=0
for alias_spec in 'Read:path' 'read_file:file_path' 'Edit:filePath' 'edit_file:path' 'search_replace:file_path' 'MultiEdit:filePath' 'Write:path' 'write_file:filePath'; do
  alias_name="${alias_spec%%:*}"
  field_name="${alias_spec#*:}"
  pattern="${protected_patterns[$alias_index]}"
  target="$(materialize "$pattern")"
  run_payload "$(json_payload "$alias_name" "$field_name" "$target")"
  check_deny "$alias_name alias denies via $field_name"
  alias_index=$((alias_index + 1))
done

camel_target="$(materialize "${protected_patterns[8]}")"
run_payload "$(python3 - "$camel_target" <<'PY'
import json, sys
print(json.dumps({"toolName":"read_file", "toolInput":{"filePath":sys.argv[1]}}))
PY
)"
check_deny "camelCase tool and input envelopes are denied"

recursive_base="$(materialize "$recursive_pattern")"
recursive_base="${recursive_base%/probe}"
run_payload "$(json_payload Read path "$recursive_base")"
check_deny "recursive pattern denies the directory itself"
run_payload "$(json_payload Read path "${recursive_base}-sibling/probe")"
check_allow "recursive pattern does not deny a sibling prefix"

json_target="$(materialize "$json_pattern")"
json_base="${json_target%/probe.json}"
run_payload "$(json_payload Read path "$json_base/nested/probe.json")"
check_allow "single-level JSON pattern allows nested JSON"
run_payload "$(json_payload Read path "$json_base/probe.txt")"
check_allow "single-level JSON pattern allows immediate non-JSON"
run_payload "$(json_payload Read path "$json_base")"
check_allow "single-level JSON pattern allows its directory"

exact_target="$(materialize "$exact_pattern")"
run_payload "$(json_payload Read path "${exact_target}.backup")"
check_allow "exact pattern allows a suffixed file"
run_payload "$(json_payload Read path "$exact_target/child")"
check_allow "exact pattern allows descendants"

relative_recursive="${recursive_pattern#\~/}"
relative_recursive="${relative_recursive%/\*\*}"
mkdir -p "$SANDBOX/repo"
run_payload "$(python3 - "$relative_recursive/probe" "$SANDBOX/repo" <<'PY'
import json, sys
print(json.dumps({"tool_name":"Read", "cwd":sys.argv[2], "tool_input":{"path":sys.argv[1]}}))
PY
)"
check_allow "repo-local relative credential-shaped directory is allowed"
run_payload "$(json_payload Read path "$SANDBOX/repo/$relative_recursive/probe")"
check_allow "repo-local absolute credential-shaped directory is allowed"

home_relative="$(materialize "$recursive_pattern")"
home_relative="${home_relative#"$HOME"/}"
for path_form in "~/$home_relative" '$HOME/'"$home_relative" '${HOME}/'"$home_relative" "$HOME/safe/../$home_relative"; do
  run_payload "$(json_payload Read path "$path_form")"
  check_deny "home form $path_form is normalized and denied"
done

home_user="${HOME##*/}"
for path_form in "C:/Users/$home_user/$home_relative" "C:\\Users\\$home_user\\${home_relative//\//\\}" "/c/Users/$home_user/$home_relative"; do
  run_payload "$(json_payload Read path "$path_form")"
  check_deny "Windows/MSYS form $path_form is normalized and denied"
done

allowed_path="$SANDBOX/allowed.txt"
protected_path="$(materialize "$exact_pattern")"
multi_payload="$(python3 - "$allowed_path" "$protected_path" <<'PY'
import json, sys
print(json.dumps({"tool_name":"MultiEdit", "tool_input":{"edits":[{"path":sys.argv[1]},{"filePath":sys.argv[2]}]}}))
PY
)"
run_payload "$multi_payload"
check_deny "MultiEdit inspects every extracted path"

for non_file_tool in Bash run_terminal_command; do
  run_payload "$(json_payload "$non_file_tool" path "$protected_path")" "$SANDBOX/missing.yaml"
  check_allow "$non_file_tool remains outside the direct-file guard"
done
run_payload "$(json_payload Read path "$allowed_path")"
check_allow "allowed direct-file operation emits empty stdout"

run_payload "$(json_payload Read path "$protected_path")"
check_dual_deny "credential denial emits concise path-free stderr and Grok JSON" "$protected_path"

for invalid_identity_payload in \
  '{"tool_input":{"path":"safe.txt"}}' \
  '{"tool_name":"","tool_input":{"path":"safe.txt"}}' \
  '{"tool_name":42,"tool_input":{"path":"safe.txt"}}' \
  '{"tool_name":"UnknownFileTool","tool_input":{"path":"safe.txt"}}'; do
  run_payload "$invalid_identity_payload"
  check_identity_fail_closed "invalid or unknown matched tool identity fails closed"
done

SYMLINK_HOME="$SANDBOX/symlink-home"
LINK_DIR="$SANDBOX/links"
mkdir -p "$SYMLINK_HOME" "$LINK_DIR" "$SANDBOX/safe-targets"
recursive_target="$(materialize "$recursive_pattern" "$SYMLINK_HOME")"
recursive_target_dir="${recursive_target%/probe}"
exact_symlink_target="$(materialize "$exact_pattern" "$SYMLINK_HOME")"
json_symlink_target="$(materialize "$json_pattern" "$SYMLINK_HOME")"
mkdir -p "$recursive_target_dir" "${exact_symlink_target%/*}" "${json_symlink_target%/*}"
touch "$recursive_target" "$exact_symlink_target" "$json_symlink_target" "$SANDBOX/safe-targets/plain.txt"
ln -s "$SANDBOX/safe-targets/plain.txt" "$LINK_DIR/safe-link"
ln -s "$recursive_target" "$LINK_DIR/recursive-link"
ln -s "$exact_symlink_target" "$LINK_DIR/exact-link"
ln -s "$json_symlink_target" "$LINK_DIR/json-link"
ln -s "$recursive_target_dir" "$LINK_DIR/protected-dir-link"
ln -s "$SANDBOX/missing-target" "$LINK_DIR/broken-link"

run_payload "$(json_payload Read path "$LINK_DIR/safe-link")" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
check_allow "existing safe symlink to safe target remains allowed"
for protected_link in "$LINK_DIR/recursive-link" "$LINK_DIR/exact-link" "$LINK_DIR/json-link"; do
  run_payload "$(json_payload Read path "$protected_link")" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
  check_deny "existing symlink to protected target is denied"
done
run_payload "$(json_payload Write path "$LINK_DIR/protected-dir-link/new-child")" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
check_deny "non-existing child under protected directory symlink is denied"

relative_symlink_payload="$(python3 - "$LINK_DIR" exact-link <<'PY'
import json, sys
print(json.dumps({"tool_name":"Read", "cwd":sys.argv[1], "tool_input":{"path":sys.argv[2]}}))
PY
)"
run_payload "$relative_symlink_payload" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
check_deny "relative cwd symlink projection is denied"

symlink_multi_payload="$(python3 - "$LINK_DIR/safe-link" "$LINK_DIR/json-link" <<'PY'
import json, sys
print(json.dumps({"tool_name":"MultiEdit", "tool_input":{"edits":[{"path":sys.argv[1]},{"filePath":sys.argv[2]}]}}))
PY
)"
run_payload "$symlink_multi_payload" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
check_deny "MultiEdit denies when any physical projection is protected"

run_payload "$(json_payload Read path "$LINK_DIR/broken-link")" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
check_identity_fail_closed "broken symlink fails closed"

NORESOLVER="$SANDBOX/noresolver-bin"
mkdir -p "$NORESOLVER"
for required_command in cat awk sed; do
  ln -s "$(command -v "$required_command")" "$NORESOLVER/$required_command"
done
if command -v jq >/dev/null 2>&1; then
  ln -s "$(command -v jq)" "$NORESOLVER/jq"
elif command -v node >/dev/null 2>&1; then
  ln -s "$(command -v node)" "$NORESOLVER/node"
else
  ln -s "$(command -v python3)" "$NORESOLVER/python3"
fi
run_payload "$(json_payload Read path "$LINK_DIR/safe-link")" "$SOURCE" "$HOOK" "$SYMLINK_HOME" "$NORESOLVER"
check_identity_fail_closed "unavailable physical resolver fails closed"

run_payload '{not-json'
check_fail_closed "malformed payload fails closed"
run_payload '{"tool_name":"Read","tool_input":{}}'
check_fail_closed "direct-file payload without a path fails closed"
run_payload "$(json_payload Read path "$protected_path")" "$SANDBOX/missing.yaml"
check_fail_closed "missing canonical source fails closed"

first_pattern="${protected_patterns[0]}"
missing_triplet="$SANDBOX/missing-triplet.yaml"
printf 'deny:\n  - "Read(%s)"\n  - "Edit(%s)"\n' "$first_pattern" "$first_pattern" >"$missing_triplet"
run_payload "$(json_payload Read path "$protected_path")" "$missing_triplet"
check_fail_closed "missing Write member fails closed"

complete_triplet_removed="$SANDBOX/complete-triplet-removed.yaml"
awk '
  /^[[:space:]]*- "Read\(/ && !removed { skip = 3; removed = 1 }
  skip > 0 { skip--; next }
  { print }
  END { if (!removed) exit 2 }
' "$SOURCE" >"$complete_triplet_removed"
run_payload "$(json_payload Read path "$protected_path")" "$complete_triplet_removed"
check_fail_closed "structurally valid source with one complete triplet removed fails closed"

wrong_order="$SANDBOX/wrong-order.yaml"
printf 'deny:\n  - "Read(%s)"\n  - "Write(%s)"\n  - "Edit(%s)"\n' "$first_pattern" "$first_pattern" "$first_pattern" >"$wrong_order"
run_payload "$(json_payload Read path "$protected_path")" "$wrong_order"
check_fail_closed "malformed triplet ordering fails closed"

duplicate_source="$SANDBOX/duplicate.yaml"
printf 'deny:\n' >"$duplicate_source"
for duplicate_round in 1 2; do
  printf '  - "Read(%s)"\n  - "Edit(%s)"\n  - "Write(%s)"\n' "$first_pattern" "$first_pattern" "$first_pattern" >>"$duplicate_source"
done
run_payload "$(json_payload Read path "$protected_path")" "$duplicate_source"
check_fail_closed "duplicate canonical pattern fails closed"

NOPARSER="$SANDBOX/noparser-bin"
mkdir -p "$NOPARSER"
ln -s "$(command -v cat)" "$NOPARSER/cat"
run_payload "$(json_payload Read path "$protected_path")" "$SOURCE" "$HOOK" "$HOME" "$NOPARSER"
check_fail_closed "missing JSON parser fails closed"

run_payload "$(json_payload Read path "$protected_path")" discover
check_deny "source checkout discovers its relative canonical YAML"

FAKE_HOME="$SANDBOX/home"
FLAT_DIR="$SANDBOX/flat/hooks/pre-tool-use"
mkdir -p "$FAKE_HOME/.agents/.system/hooks/lib" "$FAKE_HOME/.agents/.system/permissions/groups" "$FLAT_DIR"
cp "$HERE/../../lib/json-field.sh" "$FAKE_HOME/.agents/.system/hooks/lib/json-field.sh"
cp "$SOURCE" "$FAKE_HOME/.agents/.system/permissions/groups/99-deny.yaml"
cp "$HOOK" "$FLAT_DIR/12-direct-file-credential-guard.sh"
installed_target="$(materialize "$exact_pattern" "$FAKE_HOME")"
run_payload "$(json_payload Read path "$installed_target")" discover "$FLAT_DIR/12-direct-file-credential-guard.sh" "$FAKE_HOME"
check_deny "installed hook falls back to the installed canonical YAML"

if grep -q '^  direct-file-credential-guard:$' "$AGENTS_YAML" && grep -A4 '^  direct-file-credential-guard:$' "$AGENTS_YAML" | grep -Fq 'matcher: ^(Read|read_file|Edit|edit_file|search_replace|MultiEdit|Write|write_file)$'; then
  record_pass "agents.yaml registers the direct-file matcher"
else
  record_fail "agents.yaml registers the direct-file matcher"
fi

printf '\n'
if [[ "$fail" -eq 0 ]]; then
  printf 'ALL DIRECT-FILE CREDENTIAL GUARD TESTS PASSED (%d checks)\n' "$pass"
else
  printf 'DIRECT-FILE CREDENTIAL GUARD TESTS FAILED (%d passed, %d failed)\n' "$pass" "$fail"
fi
exit "$fail"
