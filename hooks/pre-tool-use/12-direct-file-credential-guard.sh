#!/bin/sh

set -eu

input=$(cat)

_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../lib/json-field.sh" "${HOME:-}/.agents/.system/hooks/lib/json-field.sh"; do
  if [ -f "$_cand" ]; then
    . "$_cand"
    if command -v _json_field >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v _json_field >/dev/null 2>&1; then
  printf 'direct-file-credential-guard: shared json-field lib not found; refusing an unparsed tool call (fail-closed).\n' >&2
  exit 2
fi

json_tool() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '
      (.tool_name // .toolName // null) as $tool |
      if ($tool | type) != "string" or ($tool | length) == 0 then error("invalid tool identity")
      else $tool
      end
    ' 2>/dev/null
    return $?
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$input" | node -e '
      let text = "";
      process.stdin.on("data", chunk => text += chunk).on("end", () => {
        try {
          const payload = JSON.parse(text);
          const tool = payload.tool_name ?? payload.toolName;
          if (typeof tool !== "string" || tool.length === 0) process.exit(2);
          process.stdout.write(tool);
        } catch (_) {
          process.exit(1);
        }
      });
    ' 2>/dev/null
    return $?
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$input" | "$_py" -c 'import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(1)
tool = payload.get("tool_name", payload.get("toolName"))
if not isinstance(tool, str) or not tool:
    sys.exit(2)
sys.stdout.write(tool)' 2>/dev/null
    return $?
  done
  return 1
}

if ! tool=$(json_tool); then
  printf 'direct-file-credential-guard: invalid or unparsed tool identity (fail-closed).\n' >&2
  exit 2
fi

case "$tool" in
  Bash|run_terminal_command) exit 0 ;;
  Read|read_file) canonical_tool=Read ;;
  Edit|edit_file|search_replace|MultiEdit) canonical_tool=Edit ;;
  Write|write_file) canonical_tool=Write ;;
  *)
    printf 'direct-file-credential-guard: unknown tool identity (fail-closed).\n' >&2
    exit 2
    ;;
esac

json_paths() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '
      [(.tool_input // .toolInput // {}) | .. | objects | to_entries[] |
        select(.key == "path" or .key == "file_path" or .key == "filePath") | .value] as $paths |
      if any($paths[]; type != "string" or length == 0) then error("invalid path")
      else $paths[]
      end
    ' 2>/dev/null
    return $?
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$input" | node -e '
      let text = "";
      process.stdin.on("data", chunk => text += chunk).on("end", () => {
        try {
          const payload = JSON.parse(text);
          const root = payload.tool_input ?? payload.toolInput ?? {};
          const paths = [];
          const visit = value => {
            if (Array.isArray(value)) return value.forEach(visit);
            if (value === null || typeof value !== "object") return;
            for (const [key, child] of Object.entries(value)) {
              if (key === "path" || key === "file_path" || key === "filePath") {
                if (typeof child !== "string" || child.length === 0) process.exit(2);
                paths.push(child);
              }
              visit(child);
            }
          };
          visit(root);
          process.stdout.write(paths.join("\n"));
        } catch (_) {
          process.exit(1);
        }
      });
    ' 2>/dev/null
    return $?
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$input" | "$_py" -c 'import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(1)
root = payload.get("tool_input", payload.get("toolInput", {}))
paths = []
def visit(value):
    if isinstance(value, list):
        for child in value:
            visit(child)
    elif isinstance(value, dict):
        for key, child in value.items():
            if key in ("path", "file_path", "filePath"):
                if not isinstance(child, str) or not child:
                    sys.exit(2)
                paths.append(child)
            visit(child)
visit(root)
sys.stdout.write("\n".join(paths))' 2>/dev/null
    return $?
  done
  return 1
}

if ! targets=$(json_paths); then
  printf 'direct-file-credential-guard: could not parse direct-file paths (fail-closed).\n' >&2
  exit 2
fi
if [ -z "$targets" ]; then
  printf 'direct-file-credential-guard: direct-file tool supplied no recognized path (fail-closed).\n' >&2
  exit 2
fi

source_override=${AGENTS_CREDENTIAL_DENY_SOURCE:-}
source_candidate=${0%/*}/../../permissions/groups/99-deny.yaml
installed_candidate=${HOME:-}/.agents/.system/permissions/groups/99-deny.yaml
if [ -n "$source_override" ]; then
  source_file=$source_override
elif [ -e "$source_candidate" ]; then
  source_file=$source_candidate
elif [ -n "${HOME:-}" ] && [ -e "$installed_candidate" ]; then
  source_file=$installed_candidate
else
  printf 'direct-file-credential-guard: canonical deny source was not found (fail-closed).\n' >&2
  exit 2
fi
if [ ! -r "$source_file" ]; then
  printf 'direct-file-credential-guard: canonical deny source is unreadable (fail-closed).\n' >&2
  exit 2
fi

if ! patterns=$(awk '
  BEGIN { in_deny = 0; expected = "Read"; current = ""; count = 0 }
  /^[[:space:]]*deny:[[:space:]]*$/ {
    if (in_deny) exit 2
    in_deny = 1
    next
  }
  /^[[:space:]]*(#.*)?$/ { next }
  {
    if (!in_deny || $0 !~ /^[[:space:]]*- "(Read|Edit|Write)\(.+\)"[[:space:]]*$/) exit 2
    line = $0
    sub(/^[[:space:]]*- "/, "", line)
    sub(/"[[:space:]]*$/, "", line)
    tool = line
    sub(/\(.*/, "", tool)
    path = line
    sub(/^[^(]*\(/, "", path)
    sub(/\)$/, "", path)
    if (tool != expected) exit 2
    if (tool == "Read") {
      if (path !~ /^~\// || seen[path]++) exit 2
      current = path
      print path
      expected = "Edit"
      count++
    } else if (path != current) {
      exit 2
    } else if (tool == "Edit") {
      expected = "Write"
    } else {
      expected = "Read"
    }
  }
  END { if (!in_deny || count != 12 || expected != "Read") exit 2 }
' "$source_file"); then
  printf 'direct-file-credential-guard: canonical deny source is malformed (fail-closed).\n' >&2
  exit 2
fi

normalize_path() {
  _raw=$(printf '%s\n' "$1" | sed 's#\\#/#g') || return 1
  _home=${HOME:-}
  [ -n "$_home" ] || return 1
  _user=${_home##*/}
  case "$_raw" in
    '~') _raw=$_home ;;
    '~/'*) _raw=$_home/${_raw#\~/} ;;
    '$HOME') _raw=$_home ;;
    '$HOME/'*) _raw=$_home/${_raw#\$HOME/} ;;
    '${HOME}') _raw=$_home ;;
    '${HOME}/'*) _raw=$_home/${_raw#\$\{HOME\}/} ;;
    [A-Za-z]:/Users/"$_user") _raw=$_home ;;
    [A-Za-z]:/Users/"$_user"/*) _raw=$_home/${_raw#?:/Users/$_user/} ;;
    /[A-Za-z]/Users/"$_user") _raw=$_home ;;
    /[A-Za-z]/Users/"$_user"/*) _raw=$_home/${_raw#/?/Users/$_user/} ;;
  esac
  case "$_raw" in
    /*) ;;
    *)
      _cwd=$(printf '%s\n' "$2" | sed 's#\\#/#g') || return 1
      case "$_cwd" in
        '~') _cwd=$_home ;;
        '~/'*) _cwd=$_home/${_cwd#\~/} ;;
        '$HOME') _cwd=$_home ;;
        '$HOME/'*) _cwd=$_home/${_cwd#\$HOME/} ;;
        '${HOME}') _cwd=$_home ;;
        '${HOME}/'*) _cwd=$_home/${_cwd#\$\{HOME\}/} ;;
        [A-Za-z]:/Users/"$_user") _cwd=$_home ;;
        [A-Za-z]:/Users/"$_user"/*) _cwd=$_home/${_cwd#?:/Users/$_user/} ;;
        /[A-Za-z]/Users/"$_user") _cwd=$_home ;;
        /[A-Za-z]/Users/"$_user"/*) _cwd=$_home/${_cwd#/?/Users/$_user/} ;;
      esac
      case "$_cwd" in /*) ;; *) return 1 ;; esac
      _raw=$_cwd/$_raw
      ;;
  esac
  printf '%s\n' "$_raw" | awk -F/ '
    {
      depth = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "" || $i == ".") continue
        if ($i == "..") {
          if (depth > 0) depth--
          continue
        }
        stack[++depth] = $i
      }
      out = ""
      for (i = 1; i <= depth; i++) out = out "/" stack[i]
      print (out == "" ? "/" : out)
    }
  '
}

cwd=$(_json_field "$input" cwd) || {
  printf 'direct-file-credential-guard: could not parse cwd (fail-closed).\n' >&2
  exit 2
}
[ -n "$cwd" ] || cwd=$(pwd)

is_protected() {
  _target=$1
  _root=$2
  while IFS= read -r _pattern; do
    _resolved=${_root}/${_pattern#\~/}
    case "$_pattern" in
      */\*\*)
        _base=${_resolved%/\*\*}
        case "$_target" in "$_base"|"$_base"/*) return 0 ;; esac
        ;;
      */\*.json)
        _base=${_resolved%/\*.json}
        case "$_target" in
          "$_base"/*)
            _child=${_target#"$_base"/}
            case "$_child" in */*) ;; *.json) return 0 ;; esac
            ;;
        esac
        ;;
      *) [ "$_target" = "$_resolved" ] && return 0 ;;
    esac
  done <<EOF
$patterns
EOF
  return 1
}

physical_path() {
  command -v realpath >/dev/null 2>&1 || return 1
  _probe=$1
  _suffix=""
  while [ ! -e "$_probe" ]; do
    [ ! -L "$_probe" ] || return 1
    [ "$_probe" != "/" ] || return 1
    _name=${_probe##*/}
    _parent=${_probe%/*}
    [ -n "$_parent" ] || _parent=/
    _suffix=/$_name$_suffix
    _probe=$_parent
  done
  _physical=$(realpath "$_probe" 2>/dev/null) || return 1
  [ -n "$_physical" ] || return 1
  printf '%s%s\n' "$_physical" "$_suffix"
}

deny_access() {
  printf 'direct-file-credential-guard: direct-file access denied by credential policy.\n' >&2
  printf '{"decision":"deny","reason":"%s direct-file access matches canonical credential policy","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Direct-file access matches canonical credential policy"}}\n' "$canonical_tool"
  exit 2
}

if ! physical_home=$(physical_path "${HOME:-}"); then
  printf 'direct-file-credential-guard: physical path resolution unavailable (fail-closed).\n' >&2
  exit 2
fi

while IFS= read -r target; do
  if ! normalized=$(normalize_path "$target" "$cwd"); then
    printf 'direct-file-credential-guard: path normalization failed (fail-closed).\n' >&2
    exit 2
  fi
  if is_protected "$normalized" "${HOME}"; then
    deny_access
  fi
  if ! physical=$(physical_path "$normalized"); then
    printf 'direct-file-credential-guard: physical path resolution failed (fail-closed).\n' >&2
    exit 2
  fi
  if is_protected "$physical" "$physical_home"; then
    deny_access
  fi
done <<EOF
$targets
EOF

exit 0
