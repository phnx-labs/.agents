#!/bin/sh

set -eu

umask 077
input_file=""
cleanup_input() {
  if [ -n "$input_file" ]; then rm -f "$input_file"; fi
}
trap cleanup_input 0
trap 'exit 2' HUP INT TERM

if ! input_file=$(mktemp "${TMPDIR:-/tmp}/direct-file-credential-guard.XXXXXX" 2>/dev/null); then
  printf 'direct-file-credential-guard: private input capture failed (fail-closed).\n' >&2
  exit 2
fi
if ! cat >"$input_file"; then
  printf 'direct-file-credential-guard: input capture failed (fail-closed).\n' >&2
  exit 2
fi
if ! od -An -v -t u1 "$input_file" >/dev/null 2>&1; then
  printf 'direct-file-credential-guard: raw input inspection failed (fail-closed).\n' >&2
  exit 2
fi
if ! od -An -v -t u1 "$input_file" 2>/dev/null | awk '{ for (index_ = 1; index_ <= NF; index_++) if ($index_ == 0) exit 1 }'; then
  printf 'direct-file-credential-guard: raw input contains a forbidden byte (fail-closed).\n' >&2
  exit 2
fi

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

json_preflight() {
  LC_ALL=C awk '
    function reject() {
      invalid = 1
      return 0
    }
    function skip_space(    byte) {
      while (position <= text_length) {
        byte = substr(text, position, 1)
        if (byte != " " && byte != "\t" && byte != "\r" && byte != "\n") break
        position++
      }
    }
    function hex_digit(byte) {
      if (byte >= "0" && byte <= "9") return byte + 0
      byte = tolower(byte)
      return index("abcdef", byte) + 9
    }
    function hex_code(hex,    index_, value) {
      value = 0
      for (index_ = 1; index_ <= 4; index_++) value = value * 16 + hex_digit(substr(hex, index_, 1))
      return value
    }
    function append_codepoint(value) {
      decoded_string = decoded_string sprintf("%08X;", value)
    }
    function parse_string(    byte, escape, hex, low_hex, codepoint, low, first, second, third, fourth) {
      if (substr(text, position, 1) != "\x22") return reject()
      position++
      decoded_string = ""
      while (position <= text_length) {
        byte = substr(text, position, 1)
        position++
        if (byte == "\x22") return 1
        if (byte == "\\") {
          if (position > text_length) return reject()
          escape = substr(text, position, 1)
          position++
          if (escape == "\x22") codepoint = 34
          else if (escape == "\\") codepoint = 92
          else if (escape == "/") codepoint = 47
          else if (escape == "b") codepoint = 8
          else if (escape == "f") codepoint = 12
          else if (escape == "n") codepoint = 10
          else if (escape == "r") codepoint = 13
          else if (escape == "t") codepoint = 9
          else if (escape == "u") {
            hex = substr(text, position, 4)
            if (length(hex) != 4 || hex !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) return reject()
            position += 4
            codepoint = hex_code(hex)
            if (codepoint >= 55296 && codepoint <= 56319) {
              if (substr(text, position, 2) != "\\u") return reject()
              position += 2
              low_hex = substr(text, position, 4)
              if (length(low_hex) != 4 || low_hex !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) return reject()
              position += 4
              low = hex_code(low_hex)
              if (low < 56320 || low > 57343) return reject()
              codepoint = 65536 + (codepoint - 55296) * 1024 + low - 56320
            } else if (codepoint >= 56320 && codepoint <= 57343) return reject()
          } else return reject()
          append_codepoint(codepoint)
          continue
        }
        first = byte_value[byte]
        if (first < 32) return reject()
        if (first < 128) codepoint = first
        else if (first >= 194 && first <= 223) {
          second = byte_value[substr(text, position, 1)]
          if (second < 128 || second > 191) return reject()
          position++
          codepoint = (first - 192) * 64 + second - 128
        } else if (first >= 224 && first <= 239) {
          second = byte_value[substr(text, position, 1)]
          third = byte_value[substr(text, position + 1, 1)]
          if (second < 128 || second > 191 || third < 128 || third > 191) return reject()
          if ((first == 224 && second < 160) || (first == 237 && second > 159)) return reject()
          position += 2
          codepoint = (first - 224) * 4096 + (second - 128) * 64 + third - 128
        } else if (first >= 240 && first <= 244) {
          second = byte_value[substr(text, position, 1)]
          third = byte_value[substr(text, position + 1, 1)]
          fourth = byte_value[substr(text, position + 2, 1)]
          if (second < 128 || second > 191 || third < 128 || third > 191 || fourth < 128 || fourth > 191) return reject()
          if ((first == 240 && second < 144) || (first == 244 && second > 143)) return reject()
          position += 3
          codepoint = (first - 240) * 262144 + (second - 128) * 4096 + (third - 128) * 64 + fourth - 128
        } else return reject()
        append_codepoint(codepoint)
      }
      return reject()
    }
    function within_limit(digits,    index_, current, maximum) {
      sub(/^0+/, "", digits)
      if (digits == "") return 1
      if (length(digits) < 16) return 1
      if (length(digits) > 16) return 0
      maximum = "9007199254740991"
      for (index_ = 1; index_ <= 16; index_++) {
        current = substr(digits, index_, 1) + 0
        if (current < substr(maximum, index_, 1) + 0) return 1
        if (current > substr(maximum, index_, 1) + 0) return 0
      }
      return 1
    }
    function parse_number(    integer_start, integer, fraction, exponent_digits, exponent_sign, exponent, combined, scale, end, trailing, integral, significant, index_, byte) {
      if (substr(text, position, 1) == "-") position++
      byte = substr(text, position, 1)
      integer_start = position
      if (byte == "0") {
        position++
        if (substr(text, position, 1) ~ /^[0-9]$/) return reject()
      } else if (byte ~ /^[1-9]$/) {
        while (substr(text, position, 1) ~ /^[0-9]$/) position++
      } else return reject()
      integer = substr(text, integer_start, position - integer_start)
      fraction = ""
      if (substr(text, position, 1) == ".") {
        position++
        integer_start = position
        if (substr(text, position, 1) !~ /^[0-9]$/) return reject()
        while (substr(text, position, 1) ~ /^[0-9]$/) position++
        fraction = substr(text, integer_start, position - integer_start)
      }
      exponent_sign = 1
      exponent_digits = ""
      byte = substr(text, position, 1)
      if (byte == "e" || byte == "E") {
        position++
        byte = substr(text, position, 1)
        if (byte == "+" || byte == "-") {
          if (byte == "-") exponent_sign = -1
          position++
        }
        integer_start = position
        if (substr(text, position, 1) !~ /^[0-9]$/) return reject()
        while (substr(text, position, 1) ~ /^[0-9]$/) position++
        exponent_digits = substr(text, integer_start, position - integer_start)
      }
      combined = integer fraction
      if (combined !~ /[1-9]/) return 1
      sub(/^0+/, "", exponent_digits)
      if (length(exponent_digits) > 6) return reject()
      exponent = exponent_digits == "" ? 0 : exponent_sign * (exponent_digits + 0)
      scale = exponent - length(fraction)
      if (scale < 0) {
        end = length(combined) + scale
        if (end <= 0) return reject()
        trailing = substr(combined, end + 1)
        if (trailing ~ /[1-9]/) return reject()
        integral = substr(combined, 1, end)
      } else {
        significant = combined
        sub(/^0+/, "", significant)
        if (length(significant) + scale > 16) return reject()
        integral = significant
        for (index_ = 1; index_ <= scale; index_++) integral = integral "0"
      }
      return within_limit(integral) ? 1 : reject()
    }
    function parse_array(    byte) {
      position++
      skip_space()
      if (substr(text, position, 1) == "]") {
        position++
        return 1
      }
      while (!invalid) {
        if (!parse_value()) return 0
        skip_space()
        byte = substr(text, position, 1)
        if (byte == "]") {
          position++
          return 1
        }
        if (byte != ",") return reject()
        position++
        skip_space()
      }
      return 0
    }
    function parse_object(    object_id, key, slot, byte) {
      position++
      object_id = ++object_count
      skip_space()
      if (substr(text, position, 1) == "}") {
        position++
        return 1
      }
      while (!invalid) {
        if (!parse_string()) return 0
        key = decoded_string
        slot = object_id SUBSEP key
        if (slot in object_keys) return reject()
        object_keys[slot] = 1
        skip_space()
        if (substr(text, position, 1) != ":") return reject()
        position++
        skip_space()
        if (!parse_value()) return 0
        skip_space()
        byte = substr(text, position, 1)
        if (byte == "}") {
          position++
          return 1
        }
        if (byte != ",") return reject()
        position++
        skip_space()
      }
      return 0
    }
    function parse_value(    byte) {
      skip_space()
      byte = substr(text, position, 1)
      if (byte == "{") return parse_object()
      if (byte == "[") return parse_array()
      if (byte == "\x22") return parse_string()
      if (byte == "-" || byte ~ /^[0-9]$/) return parse_number()
      if (substr(text, position, 4) == "true") {
        position += 4
        return 1
      }
      if (substr(text, position, 5) == "false") {
        position += 5
        return 1
      }
      if (substr(text, position, 4) == "null") {
        position += 4
        return 1
      }
      return reject()
    }
    BEGIN {
      for (index_ = 1; index_ < 256; index_++) byte_value[sprintf("%c", index_)] = index_
      raw = ""
    }
    {
      raw = raw (NR == 1 ? "" : "\n") $0
    }
    END {
      text = raw
      text_length = length(text)
      position = 1
      if (!parse_value()) exit 1
      skip_space()
      if (invalid || position <= text_length) exit 1
    }
  '
}

if ! json_preflight <"$input_file"; then
  printf 'direct-file-credential-guard: raw JSON validation failed (fail-closed).\n' >&2
  exit 2
fi
if ! input=$(cat "$input_file"); then
  printf 'direct-file-credential-guard: validated input load failed (fail-closed).\n' >&2
  exit 2
fi
rm -f "$input_file"
input_file=""

json_tool() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '
      if has("tool_name") and has("toolName") and .tool_name != .toolName then
        error("conflicting tool identity aliases")
      else .
      end |
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
          const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
          const jsonEqual = (left, right) => {
            if (typeof left !== typeof right) return false;
            if (left === null || right === null) return left === right;
            if (Array.isArray(left) || Array.isArray(right)) {
              return Array.isArray(left) && Array.isArray(right) && left.length === right.length && left.every((value, index) => jsonEqual(value, right[index]));
            }
            if (typeof left === "object") {
              const keys = Object.keys(left);
              return keys.length === Object.keys(right).length && keys.every(key => hasOwn(right, key) && jsonEqual(left[key], right[key]));
            }
            return left === right;
          };
          if (hasOwn(payload, "tool_name") && hasOwn(payload, "toolName") && !jsonEqual(payload.tool_name, payload.toolName)) process.exit(2);
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
def json_equal(left, right):
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(json_equal(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(json_equal(a, b) for a, b in zip(left, right))
    return left == right
tool = payload.get("tool_name", payload.get("toolName"))
if "tool_name" in payload and "toolName" in payload and not json_equal(payload["tool_name"], payload["toolName"]):
    sys.exit(2)
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
  Read|read|ReadFile|read_file) canonical_tool=Read ;;
  Edit|edit|edit_file|search_replace|MultiEdit|apply_patch) canonical_tool=Edit ;;
  Write|write|write_file) canonical_tool=Write ;;
  *)
    printf 'direct-file-credential-guard: unknown tool identity (fail-closed).\n' >&2
    exit 2
    ;;
esac

json_paths() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '
      if has("tool_input") and has("toolInput") and .tool_input != .toolInput then
        error("conflicting tool input aliases")
      else .
      end |
      [(.tool_input // .toolInput // {}) | .. | objects |
        [to_entries[] |
          select(.key == "path" or .key == "file_path" or .key == "filePath") |
          .value] as $aliases |
        if ($aliases | length) > 1 and any($aliases[]; . != $aliases[0]) then error("conflicting path aliases")
        elif ($aliases | length) == 0 then empty
        else $aliases[0]
        end] as $paths |
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
          const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
          const jsonEqual = (left, right) => {
            if (typeof left !== typeof right) return false;
            if (left === null || right === null) return left === right;
            if (Array.isArray(left) || Array.isArray(right)) {
              return Array.isArray(left) && Array.isArray(right) && left.length === right.length && left.every((value, index) => jsonEqual(value, right[index]));
            }
            if (typeof left === "object") {
              const keys = Object.keys(left);
              return keys.length === Object.keys(right).length && keys.every(key => hasOwn(right, key) && jsonEqual(left[key], right[key]));
            }
            return left === right;
          };
          if (hasOwn(payload, "tool_input") && hasOwn(payload, "toolInput") && !jsonEqual(payload.tool_input, payload.toolInput)) process.exit(2);
          const root = payload.tool_input ?? payload.toolInput ?? {};
          const paths = [];
          const visit = value => {
            if (Array.isArray(value)) return value.forEach(visit);
            if (value === null || typeof value !== "object") return;
            const aliases = ["path", "file_path", "filePath"].filter(key => hasOwn(value, key));
            if (aliases.length > 0) {
              const path = value[aliases[0]];
              if (typeof path !== "string" || path.length === 0) process.exit(2);
              if (aliases.some(key => !jsonEqual(value[key], path))) process.exit(2);
              paths.push(path);
            }
            for (const [key, child] of Object.entries(value)) {
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
def json_equal(left, right):
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(json_equal(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(json_equal(a, b) for a, b in zip(left, right))
    return left == right
root = payload.get("tool_input", payload.get("toolInput", {}))
if "tool_input" in payload and "toolInput" in payload and not json_equal(payload["tool_input"], payload["toolInput"]):
    sys.exit(2)
paths = []
def visit(value):
    if isinstance(value, list):
        for child in value:
            visit(child)
    elif isinstance(value, dict):
        aliases = [key for key in ("path", "file_path", "filePath") if key in value]
        if aliases:
            path = value[aliases[0]]
            if not isinstance(path, str) or not path or any(not json_equal(value[key], path) for key in aliases):
                sys.exit(2)
            paths.append(path)
        for key, child in value.items():
            visit(child)
visit(root)
sys.stdout.write("\n".join(paths))' 2>/dev/null
    return $?
  done
  return 1
}

json_patch_command() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '
      if has("tool_input") and has("toolInput") and .tool_input != .toolInput then
        error("conflicting tool input aliases")
      else (.tool_input // .toolInput // {})
      end |
      if type != "object" or (.command | type) != "string" or (.command | length) == 0 then
        error("invalid patch command")
      else .command
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
          const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
          const jsonEqual = (left, right) => {
            if (typeof left !== typeof right) return false;
            if (left === null || right === null) return left === right;
            if (Array.isArray(left) || Array.isArray(right)) {
              return Array.isArray(left) && Array.isArray(right) && left.length === right.length && left.every((value, index) => jsonEqual(value, right[index]));
            }
            if (typeof left === "object") {
              const keys = Object.keys(left);
              return keys.length === Object.keys(right).length && keys.every(key => hasOwn(right, key) && jsonEqual(left[key], right[key]));
            }
            return left === right;
          };
          if (hasOwn(payload, "tool_input") && hasOwn(payload, "toolInput") && !jsonEqual(payload.tool_input, payload.toolInput)) process.exit(2);
          const root = payload.tool_input ?? payload.toolInput ?? {};
          if (root === null || typeof root !== "object" || Array.isArray(root) || typeof root.command !== "string" || root.command.length === 0) process.exit(2);
          process.stdout.write(root.command);
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
def json_equal(left, right):
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(json_equal(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(json_equal(a, b) for a, b in zip(left, right))
    return left == right
if "tool_input" in payload and "toolInput" in payload and not json_equal(payload["tool_input"], payload["toolInput"]):
    sys.exit(2)
root = payload.get("tool_input", payload.get("toolInput", {}))
command = root.get("command") if isinstance(root, dict) else None
if not isinstance(command, str) or not command:
    sys.exit(2)
sys.stdout.write(command)' 2>/dev/null
    return $?
  done
  return 1
}

patch_paths() {
  awk '
    NR == 1 {
      if ($0 != "*** Begin Patch") exit 2
      next
    }
    ended { exit 2 }
    $0 == "*** End Patch" {
      ended = 1
      next
    }
    /^\*\*\* (Add|Update|Delete) File: / {
      path = $0
      sub(/^\*\*\* (Add|Update|Delete) File: /, "", path)
      if (path == "") exit 2
      print path
      count++
      update_line = ($0 ~ /^\*\*\* Update File: /) ? NR : 0
      next
    }
    /^\*\*\* Move to: / {
      if (update_line != NR - 1) exit 2
      path = $0
      sub(/^\*\*\* Move to: /, "", path)
      if (path == "") exit 2
      print path
      count++
      update_line = 0
      next
    }
    /^\*\*\* / { exit 2 }
    { update_line = 0 }
    END { if (!ended || count == 0) exit 2 }
  '
}

if [ "$tool" = apply_patch ]; then
  if ! patch_command=$(json_patch_command); then
    printf 'direct-file-credential-guard: could not parse patch command (fail-closed).\n' >&2
    exit 2
  fi
  if ! targets=$(printf '%s\n' "$patch_command" | patch_paths); then
    printf 'direct-file-credential-guard: malformed or pathless patch command (fail-closed).\n' >&2
    exit 2
  fi
else
  if ! targets=$(json_paths); then
    printf 'direct-file-credential-guard: could not parse direct-file paths (fail-closed).\n' >&2
    exit 2
  fi
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

absolute_path() {
  _raw=$1
  _home=${HOME:-}
  [ -n "$_home" ] || return 1
  _user=${_home##*/}
  case "$_raw" in
    [A-Za-z]:\\Users\\"$_user"|[A-Za-z]:\\Users\\"$_user"\\*)
      _raw=$(printf '%s\n' "$_raw" | sed 's#\\#/#g') || return 1
      ;;
  esac
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
      _cwd=$2
      case "$_cwd" in
        [A-Za-z]:\\Users\\"$_user"|[A-Za-z]:\\Users\\"$_user"\\*)
          _cwd=$(printf '%s\n' "$_cwd" | sed 's#\\#/#g') || return 1
          ;;
      esac
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
  printf '%s\n' "$_raw"
}

normalize_path() {
  printf '%s\n' "$1" | awk -F/ '
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
  if ! absolute=$(absolute_path "$target" "$cwd"); then
    printf 'direct-file-credential-guard: absolute path expansion failed (fail-closed).\n' >&2
    exit 2
  fi
  if ! normalized=$(normalize_path "$absolute"); then
    printf 'direct-file-credential-guard: path normalization failed (fail-closed).\n' >&2
    exit 2
  fi
  if is_protected "$normalized" "${HOME}"; then
    deny_access
  fi
  if ! physical=$(physical_path "$absolute"); then
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
