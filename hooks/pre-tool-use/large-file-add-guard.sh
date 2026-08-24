#!/bin/sh
# large-file-add-guard — PreToolUse hook on Bash.
#
# Blocks `git add` when a target file is large (>5 MiB) or has binary magic
# bytes (Mach-O, ELF, PE, common archive formats). Catches the "build artifact
# escaped into a commit" failure mode at the tool boundary.
#
# Threshold: 5 MiB. Override per-repo by exporting LARGE_FILE_GUARD_MAX_KB
# (in KiB) before invoking the agent. Set to 0 to disable size check.
#
# Magic-byte detection covers: Mach-O (cf fa ed fe / fe ed fa cf), ELF
# (7f 45 4c 46), Windows PE (4d 5a), zip/jar/docx (50 4b 03 04), gzip
# (1f 8b), bzip2 (42 5a 68), 7z (37 7a bc af 27 1c), xz (fd 37 7a 58 5a),
# DMG (78 da / koly trailer is at EOF — out of scope).
#
# Exits 0 (allow) or 2 (deny, message on stderr).
#
# Out of scope:
#   - `git add -A` / `git add .` — too broad to introspect per-file at hook
#     time without scanning the whole tree; let `git` itself surface those.
#   - Globs (`git add 'dist/*.so'`) — they're expanded by the shell BEFORE
#     the hook fires, so already-expanded paths are checked. Quoted globs
#     reach git unexpanded and we skip them.

set -eu

THRESHOLD_KB=${LARGE_FILE_GUARD_MAX_KB:-5120}

input=$(cat)
# Fast path: must mention both "git" and "add" (or "stage") in the JSON.
case "$input" in
  *git*add*|*git*stage*) ;;
  *) exit 0 ;;
esac

# --- shared JSON field extractor -------------------------------------------
# _json_field lives in hooks/lib/json-field.sh (one definition; formerly copied
# into 12 hook scripts). Source it relative to this script, fall back to the
# absolute system-install path, then verify it is defined — a guard that cannot
# parse its input must refuse, not wave a `git add` through, so a missing lib
# fails CLOSED (exit 2). ${0%/*} (POSIX, no subprocess) locates the lib even
# when PATH carries no coreutils.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../lib/json-field.sh" "${HOME}/.agents/.system/hooks/lib/json-field.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../lib/json-field.sh
    . "$_cand"
    if command -v _json_field >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
if ! command -v _json_field >/dev/null 2>&1; then
  printf 'large-file-add-guard: shared json-field lib not found — refusing to run a git add unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/json-field.sh is present.\n' >&2
  exit 2
fi

_hook_skip_plan_mode "$input" && exit 0

if ! cmd=$(_json_field "$input" tool_input.command); then
  # No parser: fail closed only when the payload clearly looks like git add —
  # we already matched *git*add* above.
  printf 'large-file-add-guard: no JSON parser (jq/node/python) — refusing git add unchecked (fail-closed).\n' >&2
  exit 2
fi
[ -z "$cmd" ] && cmd=$(_json_field "$input" toolInput.command) || true
[ -z "$cmd" ] && exit 0

is_binary_magic() {
  _f=$1
  [ -r "$_f" ] || return 1
  # Read first 8 bytes as hex.
  _hex=$(od -An -N8 -tx1 "$_f" 2>/dev/null | tr -d ' \n')
  case "$_hex" in
    cffaedfe*|cefaedfe*|feedfacf*|feedface*|cafebabe*) return 0 ;; # Mach-O / fat
    7f454c46*) return 0 ;; # ELF
    4d5a*)     return 0 ;; # PE / DOS exe
    504b0304*|504b0506*|504b0708*) return 0 ;; # zip family
    1f8b*)     return 0 ;; # gzip
    425a68*)   return 0 ;; # bzip2
    fd377a58*) return 0 ;; # xz
    377abcaf*) return 0 ;; # 7z
    7573746172*) return 0 ;; # ustar/tar
  esac
  return 1
}

size_kb() {
  _f=$1
  [ -f "$_f" ] || { echo 0; return; }
  # GNU stat: -c %s; BSD/macOS stat: -f %z. Validate each result is numeric:
  # `stat -f` on GNU means --file-system and prints a multi-line blurb with
  # exit 0 (not a failure), so a naive `stat -f ... || stat -c ...` chain keeps
  # the garbage and breaks the arithmetic below. Try GNU first, then BSD, then
  # the portable `wc -c`, validating numeric at each step.
  _bytes=$(stat -c %s "$_f" 2>/dev/null) || _bytes=""
  case "$_bytes" in ''|*[!0-9]*) _bytes=$(stat -f %z "$_f" 2>/dev/null) ;; esac
  case "$_bytes" in ''|*[!0-9]*) _bytes=$(wc -c < "$_f" 2>/dev/null | tr -d ' ') ;; esac
  case "$_bytes" in ''|*[!0-9]*) _bytes=0 ;; esac
  echo $(( _bytes / 1024 ))
}

# --- friction self-report ---------------------------------------------------
# Guard hooks exit 2 before any `agents` process exists, so they cannot emit
# in-process. This helper fires the hidden recorder in the background, fully
# fail-open, so a missing/slow CLI never breaks the guard's hot path.
report_friction() {  # $1=failureId  $2=error-message
  [ -z "${AGENTS_DISABLE_FRICTION_LOG:-}" ] || return 0
  _friction_cmd=$cmd
  _friction_id=$1
  _friction_msg=$2
  (agents _internal friction --surface guard --id "$_friction_id" \
    --error "$_friction_msg" --command "$_friction_cmd" || true) </dev/null >/dev/null 2>&1 &
}

# Structured denial (RUSH-2295) — same shape as git-guard / rm-guard.
deny_op=""
deny_reason=""
deny_next=""
set_deny() {  # $1=blocked_op  $2=reason  $3=do_this_instead
  deny_op=$1
  deny_reason=$2
  deny_next=$3
  report_friction "$1" "$2"
}
emit_deny() {
  printf 'blocked_op: %s\nreason: %s\ndo_this_instead: %s\n' \
    "$deny_op" "$deny_reason" "$deny_next" >&2
}

check_path() {
  _p=$1
  # Skip quoted globs (caller-quoted *).
  case "$_p" in
    *\**|*\?*|*\[*) return 0 ;;
  esac

  # Resolve relative paths against the working dir of the tool call.
  if [ ! -e "$_p" ]; then
    return 0
  fi

  # Directory: skip (let `git add` itself walk it; we'd need a tree scan).
  if [ -d "$_p" ]; then
    return 0
  fi

  if [ "$THRESHOLD_KB" -gt 0 ]; then
    _kb=$(size_kb "$_p")
    if [ "$_kb" -gt "$THRESHOLD_KB" ]; then
      set_deny "git.add-large-file" \
        "git add denied — $_p is $(( _kb / 1024 )) MiB (limit ${THRESHOLD_KB} KiB)." \
        "add to \`.gitignore\` or use \`git lfs\`; do not commit the blob. Set LARGE_FILE_GUARD_MAX_KB=0 only when the user explicitly wants a large intentional asset."
      return 1
    fi
  fi

  if is_binary_magic "$_p"; then
    set_deny "git.add-binary-magic" \
      "git add denied — $_p has binary magic bytes (build artifact / compiled output)." \
      "add the path to \`.gitignore\` (build output) or confirm with the user and use \`git lfs\` / an intentional asset path — do not force-add binaries by default."
    return 1
  fi

  return 0
}

# Detect `sh|bash -c <inner>` at raw string level (see git-guard.sh).
extract_sh_c_inner() {
  _raw=$1
  _raw=$(printf '%s' "$_raw" | sed 's/^[[:space:]]*//')
  while :; do
    _pre=$_raw
    _raw=$(printf '%s' "$_raw" | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]][[:space:]]*//')
    [ "$_raw" = "$_pre" ] && break
  done
  case "$_raw" in
    sh\ *|bash\ *|/bin/sh\ *|/bin/bash\ *|/usr/bin/sh\ *|/usr/bin/bash\ *) ;;
    *) return 1 ;;
  esac
  case "$_raw" in
    *" -c "*) ;;
    *) return 1 ;;
  esac
  _inner=${_raw#* -c }
  _inner=$(printf '%s' "$_inner" | sed 's/^[[:space:]]*//')
  case "$_inner" in
    \"*\") _inner=${_inner#\"}; _inner=${_inner%\"} ;;
    \'*\') _inner=${_inner#\'}; _inner=${_inner%\'} ;;
  esac
  _dash_c_inner=$_inner
  return 0
}

check_segment() {
  _seg=$1

  if extract_sh_c_inner "$_seg"; then
    if ! check_command_string "$_dash_c_inner"; then return 1; fi
    return 0
  fi

  unset IFS
  # shellcheck disable=SC2086
  set -- $_seg

  while [ $# -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && return 0

  first=$1
  case "$first" in
    \"*\") first=$(printf '%s' "$first" | sed 's/^"\(.*\)"$/\1/') ;;
    \'*\') first=$(printf '%s' "$first" | sed "s/^'\(.*\)'$/\1/") ;;
  esac

  case "$first" in
    sh|bash|/bin/sh|/bin/bash|/usr/bin/sh|/usr/bin/bash)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          -c)
            shift
            [ $# -eq 0 ] && return 0
            if ! check_command_string "$1"; then return 1; fi
            return 0
            ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      return 0
      ;;
  esac

  case "$first" in
    git|*/git) ;;
    *) return 0 ;;
  esac
  shift

  # Peel git's global flags.
  while [ $# -gt 0 ]; do
    case "$1" in
      -C)            shift; [ $# -gt 0 ] && shift ;;
      --git-dir=*|--work-tree=*|--namespace=*) shift ;;
      --git-dir|--work-tree|--namespace)      shift; [ $# -gt 0 ] && shift ;;
      -c)            shift; [ $# -gt 0 ] && shift ;;
      --no-pager|--paginate|--no-replace-objects|--bare|--exec-path=*|--literal-pathspecs|--no-optional-locks)
                     shift ;;
      -*)            shift ;;
      *)             break ;;
    esac
  done
  [ $# -eq 0 ] && return 0

  sub=$1
  shift
  case "$sub" in
    add|stage) ;;
    *) return 0 ;;
  esac

  # Walk remaining args. -A / --all / -u / --update / . => out of scope.
  # -f / --force => explicit override (the bypass this hook's own deny message
  # tells the user to use); honor it instead of denying anyway.
  while [ $# -gt 0 ]; do
    case "$1" in
      -A|--all|-u|--update) return 0 ;;
      -f|--force) return 0 ;;
      .) return 0 ;;
      --) shift; while [ $# -gt 0 ]; do
            if ! check_path "$1"; then return 1; fi
            shift
          done; return 0 ;;
      -*) shift ;;
      *)
        if ! check_path "$1"; then return 1; fi
        shift
        ;;
    esac
  done
  return 0
}

check_command_string() {
  _input=$1
  # Restore POSIX-default IFS before reading it — check_segment may have
  # unset IFS, and `OLDIFS=$IFS` under `set -u` would error on unset.
  IFS=$(printf ' \t\n.'); IFS=${IFS%.}
  _chains=$(printf '%s' "$_input" | sed 's/&&/\
/g; s/||/\
/g; s/;/\
/g; s/|/\
/g')

  OLDIFS=$IFS
  IFS='
'
  for seg in $_chains; do
    seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$seg" ] && continue
    if ! check_segment "$seg"; then
      IFS=$OLDIFS
      return 1
    fi
  done
  IFS=$OLDIFS
  return 0
}

if ! check_command_string "$cmd"; then
  emit_deny
  exit 2
fi
exit 0
