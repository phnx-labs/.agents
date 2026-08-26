#!/usr/bin/env bash

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../12-direct-file-credential-guard.sh"
SOURCE="$HERE/../../../permissions/groups/99-deny.yaml"
AGENTS_YAML="$HERE/../../../agents.yaml"
SH_BIN="$(command -v sh)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
RUNTIME_TMP="$SANDBOX/runtime-tmp"
mkdir -p "$RUNTIME_TMP"

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

patch_payload() {
  python3 - "$1" <<'PY'
import json, sys
print(json.dumps({"tool_name": "apply_patch", "tool_input": {"command": sys.argv[1]}}))
PY
}

direct_value_payload() {
  python3 - "$1" "$2" <<'PY'
import json, sys
print('{"tool_name":"Read","tool_input":{"path":%s,"marker":%s}}' % (json.dumps(sys.argv[1]), sys.argv[2]))
PY
}

patch_value_payload() {
  python3 - "$1" "$2" <<'PY'
import json, sys
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"marker":%s}}' % (json.dumps(sys.argv[1]), sys.argv[2]))
PY
}

parser_path() {
  local parser_name="$1" parser_bin="$2" bin_dir="$SANDBOX/${parser_name}-only-bin"
  mkdir -p "$bin_dir"
  for required_command in cat awk sed realpath mktemp od rm; do
    ln -s "$(command -v "$required_command")" "$bin_dir/$required_command"
  done
  ln -s "$parser_bin" "$bin_dir/$parser_name"
  printf '%s\n' "$bin_dir"
}

run_input_file() {
  local infile="$1" source_mode="${2:-$SOURCE}" hook_path="${3:-$HOOK}"
  local home_override="${4:-$HOME}" path_override="${5:-$PATH}"
  local outfile="$SANDBOX/out.$$.$RANDOM" errfile="$SANDBOX/err.$$.$RANDOM"
  RC=0
  if [[ "$source_mode" == discover ]]; then
    (unset AGENTS_CREDENTIAL_DENY_SOURCE; HOME="$home_override" PATH="$path_override" TMPDIR="$RUNTIME_TMP" AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$hook_path" <"$infile" >"$outfile" 2>"$errfile") || RC=$?
  else
    HOME="$home_override" PATH="$path_override" TMPDIR="$RUNTIME_TMP" AGENTS_CREDENTIAL_DENY_SOURCE="$source_mode" AGENTS_DISABLE_FRICTION_LOG=1 "$SH_BIN" "$hook_path" <"$infile" >"$outfile" 2>"$errfile" || RC=$?
  fi
  OUT="$(cat "$outfile" 2>/dev/null)"
  ERR="$(cat "$errfile" 2>/dev/null)"
  rm -f "$outfile" "$errfile"
}

run_payload() {
  local payload="$1" source_mode="${2:-$SOURCE}" hook_path="${3:-$HOOK}"
  local home_override="${4:-$HOME}" path_override="${5:-$PATH}"
  local infile="$SANDBOX/in.$$.$RANDOM"
  printf '%s' "$payload" >"$infile"
  run_input_file "$infile" "$source_mode" "$hook_path" "$home_override" "$path_override"
  rm -f "$infile"
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

check_runtime_cleanup() {
  local label="$1" entries=("$RUNTIME_TMP"/*)
  if [[ "${#entries[@]}" -eq 1 && "${entries[0]}" == "$RUNTIME_TMP/*" ]]; then
    record_pass "$label"
  else
    record_fail "$label"
  fi
}

check_stderr_omits() {
  local label="$1" forbidden="$2"
  if [[ "$ERR" != *"$forbidden"* ]]; then
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
  run_payload "$(json_payload ReadFile file_path "$target")"
  check_deny "ReadFile denies source-derived pattern $pattern"
done

alias_index=0
for alias_spec in 'Read:path' 'read:file_path' 'ReadFile:filePath' 'read_file:path' 'Edit:file_path' 'edit:filePath' 'edit_file:path' 'search_replace:file_path' 'MultiEdit:filePath' 'Write:path' 'write:file_path' 'write_file:filePath'; do
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

POSIX_HOME="$SANDBOX/posix-home"
literal_backslash_absolute="$POSIX_HOME/safe\\../.ssh/id_literal"
literal_backslash_relative='safe\../.ssh/id_literal'
mkdir -p "${literal_backslash_absolute%/*}"
touch "$literal_backslash_absolute"
run_payload "$(json_payload Read path "$literal_backslash_absolute")" "$SOURCE" "$HOOK" "$POSIX_HOME"
check_allow "POSIX absolute path preserves a literal backslash"
run_payload "$(python3 - "$literal_backslash_relative" "$POSIX_HOME" <<'PY'
import json, sys
print(json.dumps({"tool_name":"Read", "cwd":sys.argv[2], "tool_input":{"path":sys.argv[1]}}))
PY
)" "$SOURCE" "$HOOK" "$POSIX_HOME"
check_allow "POSIX relative path preserves a literal backslash"

allowed_path="$SANDBOX/allowed.txt"
protected_path="$(materialize "$exact_pattern")"
run_payload "$(python3 - "$protected_path" <<'PY'
import json, sys
print(json.dumps({"tool_name":"Bash", "toolName":"Read", "tool_input":{"path":sys.argv[1]}}))
PY
)"
check_identity_fail_closed "conflicting tool_name and toolName aliases fail closed"

run_payload "$(python3 - "$allowed_path" "$protected_path" <<'PY'
import json, sys
print(json.dumps({"tool_name":"Read", "tool_input":{"path":sys.argv[1]}, "toolInput":{"path":sys.argv[2]}}))
PY
)"
check_identity_fail_closed "conflicting tool_input and toolInput aliases fail closed"

run_payload "$(python3 - "$SANDBOX/first-safe.txt" "$SANDBOX/second-safe.txt" <<'PY'
import json, sys
print(json.dumps({"tool_name":"Read", "tool_input":{"path":sys.argv[1], "file_path":sys.argv[2]}}))
PY
)"
check_identity_fail_closed "conflicting path aliases in one input object fail closed"

run_payload "$(python3 - "$allowed_path" <<'PY'
import json, sys
tool_input = {"path": sys.argv[1], "file_path": sys.argv[1]}
print(json.dumps({"tool_name":"Read", "toolName":"Read", "tool_input":tool_input, "toolInput":tool_input}))
PY
)"
check_allow "equal envelope and path aliases remain accepted"

type_conflict_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "Read",
    "tool_input": {"path": sys.argv[1], "marker": [{"value": 1}]},
    "toolInput": {"path": sys.argv[1], "marker": [{"value": True}]},
}))
PY
)"

safe_patch_path="$SANDBOX/safe-patch.txt"
safe_patch="*** Begin Patch
*** Add File: $safe_patch_path
+safe
*** End Patch"
type_conflict_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "apply_patch",
    "tool_input": {"command": sys.argv[1], "marker": [{"value": 1}]},
    "toolInput": {"command": sys.argv[1], "marker": [{"value": True}]},
}))
PY
)"

signed_zero_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "Read",
    "tool_input": {"path": sys.argv[1], "marker": [{"value": -0.0}]},
    "toolInput": {"path": sys.argv[1], "marker": [{"value": 0.0}]},
}))
PY
)"

signed_zero_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "apply_patch",
    "tool_input": {"command": sys.argv[1], "marker": [{"value": -0.0}]},
    "toolInput": {"command": sys.argv[1], "marker": [{"value": 0.0}]},
}))
PY
)"

safe_integer_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
tool_input = {"path": sys.argv[1], "marker": [{"value": 9007199254740991}]}
print(json.dumps({"tool_name": "Read", "tool_input": tool_input, "toolInput": tool_input}))
PY
)"

safe_integer_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
tool_input = {"command": sys.argv[1], "marker": [{"value": -9007199254740991}]}
print(json.dumps({"tool_name": "apply_patch", "tool_input": tool_input, "toolInput": tool_input}))
PY
)"

unsafe_integer_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "Read",
    "tool_input": {"path": sys.argv[1], "marker": [{"value": 9007199254740992}]},
    "toolInput": {"path": sys.argv[1], "marker": [{"value": 9007199254740993}]},
}))
PY
)"

unsafe_integer_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "apply_patch",
    "tool_input": {"command": sys.argv[1], "marker": [{"value": 9007199254740992}]},
    "toolInput": {"command": sys.argv[1], "marker": [{"value": 9007199254740993}]},
}))
PY
)"

fraction_collision_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
path = json.dumps(sys.argv[1])
print('{"tool_name":"Read","tool_input":{"path":%s,"marker":[{"value":1.0}]},"toolInput":{"path":%s,"marker":[{"value":1.0000000000000001}]}}' % (path, path))
PY
)"

fraction_collision_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
command = json.dumps(sys.argv[1])
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"marker":[{"value":1.0}]},"toolInput":{"command":%s,"marker":[{"value":1.0000000000000001}]}}' % (command, command))
PY
)"

standalone_fraction_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
path = json.dumps(sys.argv[1])
print('{"tool_name":"Read","tool_input":{"path":%s,"marker":1.0000000000000001}}' % path)
PY
)"

standalone_fraction_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
command = json.dumps(sys.argv[1])
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"marker":1.0000000000000001}}' % command)
PY
)"

duplicate_nested_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
path = json.dumps(sys.argv[1])
print('{"tool_name":"Read","tool_input":{"path":%s,"nested":{"fraction":1.5,"fraction":1,"unsafe":9007199254740993,"unsafe":1}}}' % path)
PY
)"

duplicate_nested_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
command = json.dumps(sys.argv[1])
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"nested":{"fraction":1.5,"fraction":1,"unsafe":9007199254740993,"unsafe":1}}}' % command)
PY
)"

duplicate_escaped_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
path = json.dumps(sys.argv[1])
print('{"tool_name":"Read","tool_input":{"path":%s,"nested":{"marker":1,"\\u006darker":1}}}' % path)
PY
)"

duplicate_escaped_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
command = json.dumps(sys.argv[1])
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"nested":{"marker":1,"\\u006darker":1}}}' % command)
PY
)"

numeric_text_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "Read",
    "tool_input": {"path": sys.argv[1], "marker": "9007199254740993 1.5 NaN {\"same\":1,\"same\":2}"},
}))
PY
)"

numeric_text_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({
    "tool_name": "apply_patch",
    "tool_input": {"command": sys.argv[1], "marker": "9007199254740993 1.5 Infinity {\"same\":1,\"same\":2}"},
}))
PY
)"

nan_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Read", "tool_input": {"path": sys.argv[1], "marker": float("nan")}}))
PY
)"

nan_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({"tool_name": "apply_patch", "tool_input": {"command": sys.argv[1], "marker": float("nan")}}))
PY
)"

infinity_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Read", "tool_input": {"path": sys.argv[1], "marker": float("inf")}}))
PY
)"

infinity_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({"tool_name": "apply_patch", "tool_input": {"command": sys.argv[1], "marker": -float("inf")}}))
PY
)"

integral_exponent_path_payload="$(direct_value_payload "$allowed_path" '100e-2')"
integral_exponent_patch_payload="$(patch_value_payload "$safe_patch" '0.5e1')"
boundary_decimal_path_payload="$(direct_value_payload "$allowed_path" '9007199254740991.0')"
boundary_exponent_patch_payload="$(patch_value_payload "$safe_patch" '-90071992547409910e-1')"
zero_exponent_path_payload="$(direct_value_payload "$allowed_path" '-0e9999999')"
zero_exponent_patch_payload="$(patch_value_payload "$safe_patch" '0.0e-9999999')"
normalized_fraction_path_payload="$(direct_value_payload "$allowed_path" '1e-1')"
normalized_fraction_patch_payload="$(patch_value_payload "$safe_patch" '10e-2')"
normalized_range_path_payload="$(direct_value_payload "$allowed_path" '9007199254740992.0')"
normalized_range_patch_payload="$(patch_value_payload "$safe_patch" '-90071992547409920e-1')"

raw_utf8_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Read", "tool_input": {"path": sys.argv[1], "café": "snowman ☃"}}, ensure_ascii=False))
PY
)"

raw_utf8_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({"tool_name": "apply_patch", "tool_input": {"command": sys.argv[1], "音": "𝄞"}}, ensure_ascii=False))
PY
)"

surrogate_pair_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
path = json.dumps(sys.argv[1])
print('{"tool_name":"Read","tool_input":{"path":%s,"\\uD83D\\uDE00":"ok"}}' % path)
PY
)"

surrogate_pair_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
command = json.dumps(sys.argv[1])
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"\\uD834\\uDD1E":"ok"}}' % command)
PY
)"

lone_surrogate_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
path = json.dumps(sys.argv[1])
print('{"tool_name":"Read","tool_input":{"path":%s,"marker":"\\uD800"}}' % path)
PY
)"

invalid_surrogate_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
command = json.dumps(sys.argv[1])
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"marker":"\\uD800\\u0041"}}' % command)
PY
)"

escaped_text_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Read", "tool_input": {"path": sys.argv[1], "marker": "quote \" backslash \\ 9007199254740993 1.5"}}))
PY
)"

escaped_text_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({"tool_name": "apply_patch", "tool_input": {"command": sys.argv[1], "marker": "{\"same\":1,\"same\":2} \\uD800"}}))
PY
)"

unicode_duplicate_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
path = json.dumps(sys.argv[1])
print('{"tool_name":"Read","tool_input":{"path":%s,"nested":{"é":1,"\\u00e9":1}}}' % path)
PY
)"

unicode_duplicate_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
command = json.dumps(sys.argv[1])
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"nested":{"😀":1,"\\uD83D\\uDE00":1}}}' % command)
PY
)"

sibling_keys_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Read", "tool_input": {"path": sys.argv[1], "left": {"same": 1}, "right": {"same": 1}}}))
PY
)"

array_sibling_keys_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
print(json.dumps({"tool_name": "apply_patch", "tool_input": {"command": sys.argv[1], "items": [{"same": 1}, {"same": 1}]}}))
PY
)"

array_duplicate_path_payload="$(python3 - "$allowed_path" <<'PY'
import json, sys
path = json.dumps(sys.argv[1])
print('{"tool_name":"Read","tool_input":{"path":%s,"items":[{"same":1,"same":1}]}}' % path)
PY
)"

array_duplicate_patch_payload="$(python3 - "$safe_patch" <<'PY'
import json, sys
command = json.dumps(sys.argv[1])
print('{"tool_name":"apply_patch","tool_input":{"command":%s,"items":[{"same":1,"same":1}]}}' % command)
PY
)"

trailing_path_payload="$(direct_value_payload "$allowed_path" '1') true"
trailing_patch_payload="$(patch_value_payload "$safe_patch" '1') []"

nul_path_file="$SANDBOX/nul-path.json"
python3 - "$nul_path_file" "$allowed_path" <<'PY'
import json, sys
payload = ('{"tool_\x00name":"Read","tool_input":{"path":%s}}' % json.dumps(sys.argv[2])).encode()
with open(sys.argv[1], "wb") as handle:
    handle.write(payload)
PY

nul_patch_file="$SANDBOX/nul-patch.json"
python3 - "$nul_patch_file" "$safe_patch" <<'PY'
import json, sys
payload = json.dumps({"tool_name": "apply_patch", "tool_input": {"command": sys.argv[2], "mar\x00ker": 1}}).encode()
with open(sys.argv[1], "wb") as handle:
    handle.write(payload.replace(b"mar\\u0000ker", b"mar\x00ker"))
PY

malformed_utf8_path_file="$SANDBOX/malformed-utf8-path.json"
python3 - "$malformed_utf8_path_file" "$allowed_path" <<'PY'
import json, sys
payload = json.dumps({"tool_name": "Read", "tool_input": {"path": sys.argv[2], "marker": "TOKEN"}}).encode()
with open(sys.argv[1], "wb") as handle:
    handle.write(payload.replace(b"TOKEN", b"\xc0\xaf"))
PY

malformed_utf8_patch_file="$SANDBOX/malformed-utf8-patch.json"
python3 - "$malformed_utf8_patch_file" "$safe_patch" <<'PY'
import json, sys
payload = json.dumps({"tool_name": "apply_patch", "tool_input": {"command": sys.argv[2], "marker": "TOKEN"}}).encode()
with open(sys.argv[1], "wb") as handle:
    handle.write(payload.replace(b"TOKEN", b"\xf4\x90\x80\x80"))
PY

run_input_file "$nul_path_file"
check_identity_fail_closed "raw NUL in direct-input member name fails closed before shell capture"
check_stderr_omits "raw-NUL denial omits the direct-input path" "$allowed_path"
check_runtime_cleanup "deny path removes the private raw-input temp file"
run_input_file "$nul_patch_file"
check_identity_fail_closed "raw NUL in patch-input member name fails closed before shell capture"
check_stderr_omits "raw-NUL denial omits the patch target path" "$safe_patch_path"

for parser_spec in "jq:$(command -v jq)" "node:$(command -v node)" "python3:$(command -v python3)"; do
  parser_name="${parser_spec%%:*}"
  parser_bin="${parser_spec#*:}"
  forced_path="$(parser_path "$parser_name" "$parser_bin")"
  run_payload "$type_conflict_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects number-versus-boolean direct-input aliases"
  run_payload "$type_conflict_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects number-versus-boolean patch-input aliases"
  run_payload "$signed_zero_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts negative-zero-versus-zero direct-input aliases"
  run_payload "$signed_zero_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts negative-zero-versus-zero patch-input aliases"
  run_payload "$safe_integer_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts maximum-safe-integer direct-input aliases"
  run_payload "$safe_integer_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts minimum-safe-integer patch-input aliases"
  run_payload "$unsafe_integer_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects precision-colliding integer direct-input aliases"
  run_payload "$unsafe_integer_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects precision-colliding integer patch-input aliases"
  run_payload "$fraction_collision_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects precision-colliding fractional direct-input aliases"
  run_payload "$fraction_collision_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects precision-colliding fractional patch-input aliases"
  run_payload "$standalone_fraction_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects standalone rounded fractional direct input"
  run_payload "$standalone_fraction_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects standalone rounded fractional patch input"
  run_payload "$duplicate_nested_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects nested duplicate-member direct input before overwrite"
  run_payload "$duplicate_nested_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects nested duplicate-member patch input before overwrite"
  run_payload "$duplicate_escaped_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects escaped-equivalent duplicate direct-input keys"
  run_payload "$duplicate_escaped_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects escaped-equivalent duplicate patch-input keys"
  run_payload "$numeric_text_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name ignores number and duplicate-key text inside direct-input strings"
  run_payload "$numeric_text_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name ignores number and duplicate-key text inside patch-input strings"
  run_payload "$integral_exponent_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts 100e-2 direct input"
  run_payload "$integral_exponent_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts 0.5e1 patch input"
  run_payload "$boundary_decimal_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts safe-boundary decimal direct input"
  run_payload "$boundary_exponent_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts safe-boundary exponent patch input"
  run_payload "$zero_exponent_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts signed-zero exponent direct input"
  run_payload "$zero_exponent_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts signed-zero exponent patch input"
  run_payload "$normalized_fraction_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects exponent-normalized fractional direct input"
  run_payload "$normalized_fraction_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects exponent-normalized fractional patch input"
  run_payload "$normalized_range_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects out-of-range decimal direct input"
  run_payload "$normalized_range_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects out-of-range exponent patch input"
  run_payload "$raw_utf8_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts raw UTF-8 direct input"
  run_payload "$raw_utf8_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts raw UTF-8 patch input"
  run_payload "$surrogate_pair_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts valid surrogate-pair direct input"
  run_payload "$surrogate_pair_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts valid surrogate-pair patch input"
  run_input_file "$malformed_utf8_path_file" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects malformed UTF-8 direct input"
  run_input_file "$malformed_utf8_patch_file" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects malformed UTF-8 patch input"
  run_payload "$lone_surrogate_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects lone-surrogate direct input"
  run_payload "$invalid_surrogate_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects invalid-surrogate patch input"
  run_payload "$escaped_text_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts escaped quote, backslash, and numeric-looking direct-input text"
  run_payload "$escaped_text_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name accepts escaped quote, backslash, and numeric-looking patch-input text"
  run_payload "$unicode_duplicate_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects escaped and raw Unicode-equivalent direct-input keys"
  run_payload "$unicode_duplicate_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects escaped and raw Unicode-equivalent patch-input keys"
  run_payload "$sibling_keys_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name allows identical direct-input keys in sibling objects"
  run_payload "$array_sibling_keys_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_allow "$parser_name allows identical patch-input keys in separate array objects"
  run_payload "$array_duplicate_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects duplicate direct-input keys inside one array object"
  run_payload "$array_duplicate_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects duplicate patch-input keys inside one array object"
  run_payload "$trailing_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects trailing input after direct-input JSON"
  run_payload "$trailing_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects trailing input after patch-input JSON"
  run_payload "$nan_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects non-standard NaN direct input"
  run_payload "$nan_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects non-standard NaN patch input"
  run_payload "$infinity_path_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects non-standard infinity direct input"
  run_payload "$infinity_patch_payload" "$SOURCE" "$HOOK" "$HOME" "$forced_path"
  check_identity_fail_closed "$parser_name rejects non-standard infinity patch input"
done

multi_payload="$(python3 - "$allowed_path" "$protected_path" <<'PY'
import json, sys
print(json.dumps({"tool_name":"MultiEdit", "tool_input":{"edits":[{"path":sys.argv[1]},{"filePath":sys.argv[2]}]}}))
PY
)"
run_payload "$multi_payload"
check_deny "MultiEdit inspects every extracted path"

run_payload "$(patch_payload "$safe_patch")"
check_allow "apply_patch allows a well-formed safe patch"

for patch_operation in Add Update Delete; do
  protected_patch="*** Begin Patch
*** $patch_operation File: $protected_path
@@
+blocked
*** End Patch"
  run_payload "$(patch_payload "$protected_patch")"
  check_deny "apply_patch denies protected $patch_operation File target"
done

mixed_patch="*** Begin Patch
*** Add File: $safe_patch_path
+safe
*** Update File: $protected_path
@@
-old
+new
*** End Patch"
run_payload "$(patch_payload "$mixed_patch")"
check_deny "apply_patch inspects every target in a mixed safe and protected patch"

move_patch="*** Begin Patch
*** Update File: $safe_patch_path
*** Move to: $protected_path
@@
-old
+new
*** End Patch"
run_payload "$(patch_payload "$move_patch")"
check_deny "apply_patch denies a protected Move to target"

run_payload "$(patch_payload '*** Begin Patch
*** Update File safe.txt
*** End Patch')"
check_identity_fail_closed "malformed apply_patch command fails closed"
run_payload "$(patch_payload '*** Begin Patch
*** End Patch')"
check_identity_fail_closed "pathless apply_patch command fails closed"

for non_file_tool in Bash run_terminal_command; do
  run_payload "$(json_payload "$non_file_tool" path "$protected_path")" "$SANDBOX/missing.yaml"
  check_allow "$non_file_tool remains outside the direct-file guard"
done
run_payload "$(json_payload Read path "$allowed_path")"
check_allow "allowed direct-file operation emits empty stdout"
check_runtime_cleanup "allow path removes the private raw-input temp file"

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
mkdir -p "$recursive_target_dir" "${exact_symlink_target%/*}" "${json_symlink_target%/*}" "$SYMLINK_HOME/safe/subdir"
touch "$recursive_target" "$exact_symlink_target" "$json_symlink_target" "$SANDBOX/safe-targets/plain.txt" "$SYMLINK_HOME/.ssh/id_probe"
ln -s "$SANDBOX/safe-targets/plain.txt" "$LINK_DIR/safe-link"
ln -s "$recursive_target" "$LINK_DIR/recursive-link"
ln -s "$exact_symlink_target" "$LINK_DIR/exact-link"
ln -s "$json_symlink_target" "$LINK_DIR/json-link"
ln -s "$recursive_target_dir" "$LINK_DIR/protected-dir-link"
ln -s "$SYMLINK_HOME/safe/subdir" "$LINK_DIR/hop"
ln -s "$SANDBOX/missing-target" "$LINK_DIR/broken-link"

run_payload "$(json_payload Read path "$LINK_DIR/safe-link")" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
check_allow "existing safe symlink to safe target remains allowed"
for protected_link in "$LINK_DIR/recursive-link" "$LINK_DIR/exact-link" "$LINK_DIR/json-link"; do
  run_payload "$(json_payload Read path "$protected_link")" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
  check_deny "existing symlink to protected target is denied"
done
run_payload "$(json_payload Write path "$LINK_DIR/protected-dir-link/new-child")" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
check_deny "non-existing child under protected directory symlink is denied"

symlink_dotdot_target="$LINK_DIR/hop/../../.ssh/id_probe"
if [[ "$(realpath "$symlink_dotdot_target")" == "$(realpath "$SYMLINK_HOME/.ssh/id_probe")" ]]; then
  record_pass "filesystem resolves symlink-plus-dotdot target under protected home"
else
  record_fail "filesystem resolves symlink-plus-dotdot target under protected home"
fi
run_payload "$(json_payload Read path "$symlink_dotdot_target")" "$SOURCE" "$HOOK" "$SYMLINK_HOME"
check_deny "symlink-plus-dotdot path resolving under protected home is denied"

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

if grep -q '^  direct-file-credential-guard:$' "$AGENTS_YAML" && grep -A4 '^  direct-file-credential-guard:$' "$AGENTS_YAML" | grep -Fq 'matcher: ^(Read|read|ReadFile|read_file|Edit|edit|edit_file|search_replace|MultiEdit|Write|write|write_file|apply_patch)$'; then
  record_pass "agents.yaml registers the direct-file matcher"
else
  record_fail "agents.yaml registers the direct-file matcher"
fi

registered_matcher="$(awk '/^  direct-file-credential-guard:$/ { found=1; next } found && /matcher:/ { sub(/^[[:space:]]*matcher:[[:space:]]*/, ""); print; exit }' "$AGENTS_YAML")"
for native_tool in read edit write; do
  if [[ "$native_tool" =~ $registered_matcher ]]; then
    record_pass "registered matcher accepts OpenCode native $native_tool"
  else
    record_fail "registered matcher accepts OpenCode native $native_tool"
  fi
done

printf '\n'
if [[ "$fail" -eq 0 ]]; then
  printf 'ALL DIRECT-FILE CREDENTIAL GUARD TESTS PASSED (%d checks)\n' "$pass"
else
  printf 'DIRECT-FILE CREDENTIAL GUARD TESTS FAILED (%d passed, %d failed)\n' "$pass" "$fail"
fi
exit "$fail"
