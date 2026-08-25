#!/bin/sh
# public-artifact-guard — PreToolUse hook on Bash.
#
# Blocks staging confidential material into a repo's `.agents/artifacts/`
# directory, which is COMMITTED by design and therefore PUBLIC on an OSS repo.
#
# Why this exists (RUSH-3033): the agi-cli GTM/monetization strategy -- real
# revenue figures, a "~no users" assessment, competitor intel, pricing model,
# launch plan -- was committed to `.agents/artifacts/` on the public agents-cli
# repo and stayed world-readable for about two days. The tip was cleaned by
# PR #2895; git history still carries it, and strategy intel is not a rotatable
# secret.
#
# The failure is structural, not careless. Two documented rules compose into it:
# `.agents/artifacts/<date>/` is "durable output, committed" while
# `.agents/scratch/` is gitignored, so an agent writing a durable strategy doc
# puts it on the public path BY FOLLOWING INSTRUCTIONS -- and the session-recap
# workflow tells agents to commit any uncommitted work they find, including
# other sessions'. A 2026-08-22 sweep found exactly that pending in the public
# tree: an internal monetization doc and a 1147-line compile of the operator's
# private global ruleset, both untracked.
#
# --- What it keys on, and what it deliberately does NOT --------------------
#
# PRIMARY signal: a `confidential: true` frontmatter key. Explicit, robust, and
# author-controlled — no guessing from a filename.
#
# BACKSTOP signal: a small set of document names, deliberately anchored rather
# than substring-matched. An earlier revision used loose substrings
# (`*pricing-model*`, `*monetiz*`, `*fundrais*`) and a reviewer showed it blocked
# ordinary engineering work: `plan-pricing-model-api.md`,
# `monetization-service-refactor.md`, `fundraising-page-redesign.md`,
# `plan-revenue-model-migration.md`. That is the worst failure mode available to
# this hook — it runs on every `git add` fleet-wide, so a guard that blocks real
# work gets switched off, and then it protects nothing. The patterns below match
# whole-name documents, not any file whose name mentions money.
#
# NOT `surface: internal` frontmatter. That field names the PRODUCT surface a
# plan touches (internal / cli / web / native / api / workflow), not its
# confidentiality; ordinary architecture plans carry it.
#
# No network call: repo visibility would need `gh repo view` on a path that runs
# on every `git add`. Confidential material does not belong in a tracked
# artifacts dir of ANY repo -- private repos get forked and flipped public.
#
# --- Known limits, stated rather than implied -------------------------------
#
# TWO different classes, kept separate on purpose — an earlier version of this
# note ran them together, which implied more completeness than the code has.
#
# 1. UNREACHABLE by string inspection. The real path does not exist in the
#    command text at all, so no amount of parsing finds it:
#      - `xargs git add < list`  — paths arrive on stdin
#      - backticks and $(...)    — the path is another command's output
#      - a path built from variables expanded at run time
#    Closing these needs a different mechanism entirely: a repo pre-commit hook,
#    or server-side push protection.
#
# 2. NOT ENUMERATED YET. `git add` IS textually present, but behind a prefix
#    wrapper this list does not name. The peel list below covers the common
#    ones; an exotic or newly-invented wrapper is simply a gap, and the fix is
#    to add it here. This class is finite and open to extension — unlike (1).
#
# So the honest scope: a cheap early catch for the realistic case — an agent
# staging a file it should not — NOT a defense against deliberate evasion.
# Anyone determined to commit the file can rename it and walk straight past
# every check here.
#
# Exits 0 (allow) or 2 (deny, message on stderr).

set -eu

input=$(cat)
# Fast path: must plausibly be a staging command.
case "$input" in
  *git*add*|*git*commit*|*git*stage*) ;;
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
  printf 'public-artifact-guard: shared json-field lib not found — refusing to run a git add unchecked (fail-closed). Ensure ~/.agents/.system/hooks/lib/json-field.sh is present.\n' >&2
  exit 2
fi

if ! cmd=$(_json_field "$input" tool_input.command); then
  printf 'public-artifact-guard: no JSON parser succeeded (malformed payload or jq/node/python unavailable) — refusing the staging command unchecked (fail-closed).\n' >&2
  exit 2
fi
[ -z "$cmd" ] && cmd=$(_json_field "$input" toolInput.command) || true
[ -z "$cmd" ] && exit 0

report_friction() {  # $1=failureId  $2=error-message
  [ -z "${AGENTS_DISABLE_FRICTION_LOG:-}" ] || return 0
  _fc=$cmd
  (agents _internal friction --surface guard --id "$1" \
    --error "$2" --command "$_fc" || true) </dev/null >/dev/null 2>&1 &
}

emit_deny() {  # $1=path  $2=why
  report_friction "artifacts.confidential-publish" "$2"
  printf 'blocked_op: %s\nreason: %s\ndo_this_instead: %s\n' \
    "artifacts.confidential-publish" \
    "$1 — $2. .agents/artifacts/ is COMMITTED by design, so on an OSS repo this publishes to the world (RUSH-3033: exactly this leaked the GTM strategy for ~2 days, and git history still carries it)." \
    "Confidential material does not belong on a tracked path. Move it to .agents/scratch/ (gitignored) or a PRIVATE repo, then stage the rest. If it is genuinely publishable, drop 'confidential: true' from its frontmatter or give it a name that is not a whole-document strategy title — do not work around the guard." >&2
  exit 2
}

# Tokenize a segment the way a shell would, honoring quotes, one token per line.
# Plain `set -- $seg` splits `git add "notes gtm-strategy.md"` into `"notes` and
# `gtm-strategy.md"` — the first carries the artifacts path but an innocuous
# basename, the second carries the strategy name but no path, so a check needing
# BOTH matches neither and the file sails through. Reported as a bypass.
tokenize() {
  printf '%s' "$1" | awk '
  {
    n = length($0); tok = ""; q = ""; have = 0
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (q == "\047") {
        # Single quotes: no escape processing, per shell semantics.
        if (c == q) { q = "" } else { tok = tok c; have = 1 }
      } else if (c == "\\") {
        # Backslash escapes the next character, so `gtm-strategy\ x.md` is ONE
        # token. Without this the escaped space split it in two and both halves
        # failed the path+name test — a reported bypass.
        i++
        if (i <= n) { tok = tok substr($0, i, 1); have = 1 }
      } else if (q != "") {
        if (c == q) { q = "" } else { tok = tok c; have = 1 }
      } else if (c == "$" && i < n && (substr($0, i+1, 1) == "\047" || substr($0, i+1, 1) == "\"")) {
        # ANSI-C / locale quoting: $'...' and $"...". Drop the leading $ so the
        # token is a plain path — leaving it made resolve() treat an absolute
        # path as relative and the frontmatter check missed.
        have = 1
      } else if (c == "\"" || c == "\047") {
        q = c; have = 1
      } else if (c == " " || c == "\t") {
        if (have) { print tok; tok = ""; have = 0 }
      } else {
        tok = tok c; have = 1
      }
    }
    if (have) print tok
  }'
}

strip_quotes() {
  case "$1" in
    \"*\") printf '%s' "$1" | sed 's/^"\(.*\)"$/\1/' ;;
    \'*\') printf '%s' "$1" | sed "s/^'\(.*\)'\$/\1/" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Whole-document strategy names. ANCHORED on purpose: each alternative must be
# the entire basename (modulo an extension and an optional date/dir prefix), so
# `plan-pricing-model-api.md` and `monetization-service-refactor.md` — real
# engineering work — do not match, while the actual leaked documents do.
# Does a SHORT-option cluster consume the following token as its value?
# Matching exact tokens (-m, -F, …) missed `git commit -am "<msg>"`, which is the
# most common way that idiom is written: git clusters short options, so -am is
# -a plus -m and the token equals no listed flag. The sweep logic in this file
# already reads clusters (`-*[aA]*`); this applies the same idea.
#
# Left to right, the FIRST value-taking option takes the remainder of the
# cluster when there is one, otherwise the next argument. So -am consumes the
# next token, while -ma takes "a" as its inline value and consumes nothing —
# meaning a path following -ma is a REAL path and must still be inspected.
cluster_consumes_next() {
  _c=${1#-}
  while [ -n "$_c" ]; do
    _ch=${_c%"${_c#?}"}
    _rest=${_c#?}
    case "$_ch" in
      m|F|t|C|c) [ -z "$_rest" ] && return 0; return 1 ;;
    esac
    _c=$_rest
  done
  return 1
}

is_strategy_name() {
  _b=${1##*/}
  _b=$(printf '%s' "$_b" | tr '[:upper:]' '[:lower:]')
  _b=${_b%.md}; _b=${_b%.markdown}; _b=${_b%.mdx}; _b=${_b%.html}; _b=${_b%.yaml}; _b=${_b%.yml}
  # Normalize separators so "gtm-strategy copy" and "gtm_strategy" reduce to the
  # same shape, then drop a leading date prefix.
  # Both expressions need -e: with a bare first expression plus a later -e, sed
  # treats the bare one as a FILENAME and the whole normalization silently
  # no-ops, which made every name allow.
  _b=$(printf '%s' "$_b" | tr ' _' '--' \
    | sed -E -e 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//' -e 's/-+/-/g')

  # WHOLE-NAME match only. An earlier revision also trimmed trailing "-segment"
  # suffixes so "gtm-strategy-v2" would be caught, gated on the trimmed
  # candidate still being multi-word. Review showed that gate stops the round-1
  # failure mode but not this one: launch-venues-map-component,
  # supply-vs-demand-chart-lib, how-winners-charge-back-taxes,
  # stars-playbook-for-kids and byo-subscription-pivot-table-ui all trim to a
  # real pattern that is still multi-word, so 5 of 18 ordinary filenames blocked.
  #
  # The trim bought one marginal catch and cost a whole new false-positive class.
  # For a hook on every stage fleet-wide that is the wrong trade — a guard that
  # blocks real work gets switched off, and then it protects nothing. So the name
  # list stays a narrow backstop for the exact documents that leaked, and
  # `confidential: true` frontmatter remains the signal that scales.
  _match_strategy "$_b"
}

_match_strategy() {
  case "$1" in
    # The RUSH-3033 document set, by whole name.
    gtm|gtm-strategy|go-to-market|go-to-market-strategy) return 0 ;;
    # `monetize-*` used to sit here — the ONLY glob in an otherwise all-literal
    # list, directly under a comment promising whole-basename matching. It
    # blocked monetize-api-endpoint, monetize-webhook-integration and
    # monetize-tier-flag-component: ordinary engineering files. It survived
    # seven review rounds because the suite only ever exercised `monetize` via
    # the monetize-agents-cli fixture and never through the ALLOWS block that
    # pins this exact failure mode for every sibling pattern. Literals only.
    monetize|monetize-agents-cli|monetization-strategy|pricing-models) return 0 ;;
    how-winners-charge|launch-venues|launch-venues-and-posts) return 0 ;;
    github-stars-playbook|stars-playbook|supply-vs-demand) return 0 ;;
    byo-subscription-pivot|developer-pain-reddit|vibe-kanban-postmortem) return 0 ;;
    # Not business strategy, but the same leak class: the 2026-08-22 sweep found
    # a compile of the operator's PRIVATE global ruleset in the public tree. It
    # carries no frontmatter to declare itself, and no engineering document is
    # ever called this.
    compiled-ruleset|ruleset-compiled) return 0 ;;
  esac
  return 1
}

# `exit` in awk still runs END, so END must not hard-code the status or it
# overrides the match — carry the result in a flag.
has_confidential_frontmatter() {
  [ -f "$1" ] || return 1
  case "$1" in *.md|*.markdown|*.mdx|*.html|*.yaml|*.yml) ;; *) return 1 ;; esac
  head -20 "$1" 2>/dev/null | awk '
    NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR>1 && /^---[[:space:]]*$/ { exit }
    tolower($0) ~ /^confidential:[[:space:]]*(true|yes)[[:space:]]*$/ { found=1; exit }
    END { exit (found ? 0 : 1) }
  ' && return 0
  return 1
}

# Resolve a possibly-relative path against the segment's `cd` target, so
# `cd repo && git add .agents/artifacts/gtm-strategy.md` is still inspectable.
# SEG_CWD is set by the segment walker below.
resolve() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) [ -n "${SEG_CWD:-}" ] && printf '%s/%s' "${SEG_CWD%/}" "$1" || printf '%s' "$1" ;;
  esac
}

# The NAME test runs on the string alone — no filesystem access — so a relative
# path under a `cd` the hook never performed is still caught. Only the
# frontmatter test needs to open the file, and that is best-effort.
inspect_path() {
  _p=$(strip_quotes "$1")
  case "$_p" in *\**|*\?*|*\[*) return 0 ;; esac
  case "$_p" in
    */.agents/artifacts|*/.agents/artifacts/*|.agents/artifacts|.agents/artifacts/*) ;;
    *) return 0 ;;
  esac

  is_strategy_name "$_p" && emit_deny "$_p" "reads as a confidential business-strategy document"

  _full=$(resolve "$_p")
  if [ -d "$_full" ]; then
    # `git add <day-dir>/` stages a whole day at once — the realistic vector.
    # Bounded so a large tree cannot stall a hot path.
    find "$_full" -type f \( -name '*.md' -o -name '*.markdown' -o -name '*.mdx' \
      -o -name '*.html' -o -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | head -400 \
      | while IFS= read -r _f; do
          if is_strategy_name "$_f" || has_confidential_frontmatter "$_f"; then
            printf '%s\n' "$_f" > "$_HIT_FILE"; break
          fi
        done
    if [ -s "$_HIT_FILE" ]; then
      emit_deny "$(cat "$_HIT_FILE")" "is confidential and would be staged by adding the directory $_p"
    fi
    return 0
  fi
  if [ -f "$_full" ] && has_confidential_frontmatter "$_full"; then
    emit_deny "$_p" "declares 'confidential: true' in its frontmatter"
  fi
  return 0
}

_HIT_FILE=$(mktemp 2>/dev/null || echo "/tmp/paguard.$$")
trap 'rm -f "$_HIT_FILE"' EXIT INT TERM

# `git add -A` / `.` / `git commit -a`: the MOST likely vector, because the
# recap workflow tells agents to commit any stray work they find. Read exactly
# what git is about to stage. -uall is load-bearing: plain --porcelain COLLAPSES
# an untracked dir into one "?? .agents/" entry, so an artifacts filter never
# matches (this silently passed until a fresh-repo test caught it).
sweep_pending() {
  _root=$(cd "${SEG_CWD:-.}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$_root" ] || return 0
  git -C "$_root" status --porcelain -uall 2>/dev/null | while IFS= read -r _line; do
    _p=$(printf '%s' "$_line" | cut -c4-)
    case "$_p" in *" -> "*) _p=${_p##* -> } ;; esac
    _p=$(printf '%s' "$_p" | sed -e 's/^"//' -e 's/"$//')
    case "$_p" in .agents/artifacts/*|*/.agents/artifacts/*) ;; *) continue ;; esac
    _f="$_root/$_p"
    if [ -f "$_f" ] && { is_strategy_name "$_f" || has_confidential_frontmatter "$_f"; }; then
      printf '%s\n' "$_f" > "$_HIT_FILE"; break
    fi
  done
  if [ -s "$_HIT_FILE" ]; then
    emit_deny "$(cat "$_HIT_FILE")" "is pending and would be swept in by this stage-everything command"
  fi
}

# --- command walk ----------------------------------------------------------
# Split on segment separators, track `cd` per segment, scope to the git
# subcommand. Modelled on large-file-add-guard.sh's parser, which already
# solved this; an earlier revision here walked every whitespace-separated word
# regardless of subcommand and so fired on read-only `git log <path>`.
# `sh -c '<inner>'` / `bash -c "<inner>"` hides the real command one level down.
# large-file-add-guard.sh carries this unwrapping and I failed to port it, so
# wrapping defeated the name check, the frontmatter check AND the -A sweep at
# once — the worst of the reported bypasses. Returns the inner string.
unwrap_dash_c() {
  _raw=$(printf '%s' "$1" | sed 's/^[[:space:]]*//')
  while :; do
    _pre=$_raw
    _raw=$(printf '%s' "$_raw" | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]][[:space:]]*//')
    [ "$_raw" = "$_pre" ] && break
  done
  # `eval "<cmd>"` takes its command directly, with no -c. Handle it first —
  # enumerating `sh`/`bash`/`zsh` one at a time is what let `eval` through, so
  # the interpreter set is an explicit allowlist and eval is part of it.
  case "$_raw" in
    eval\ *)
      _inner=${_raw#eval }
      _inner=$(printf '%s' "$_inner" | sed 's/^[[:space:]]*//')
      case "$_inner" in
        \"*\") _inner=${_inner#\"}; _inner=${_inner%\"} ;;
        \'*\') _inner=${_inner#\'}; _inner=${_inner%\'} ;;
      esac
      printf '%s' "$_inner"
      return 0
      ;;
  esac
  # flock has BOTH forms: `flock <file> <cmd> [args]` (peeled as a wrapper
  # below) and `flock <file> -c '<cmd>'` (a shell string, structurally identical
  # to sh -c / su -c). Closing only the bare form left the -c form bypassing —
  # an incomplete close, not an un-enumerated wrapper. The `${_raw#* -c }` split
  # below already handles -c appearing after positional args, so listing flock
  # here is the whole fix.
  _interp=${_raw%% *}
  case "${_interp##*/}" in
    sh|bash|zsh|dash|ksh|env|su|flock) ;;
    *) return 1 ;;
  esac
  case "$_raw" in *" -c "*) ;; *) return 1 ;; esac
  _inner=${_raw#* -c }
  _inner=$(printf '%s' "$_inner" | sed 's/^[[:space:]]*//')
  case "$_inner" in
    \"*\") _inner=${_inner#\"}; _inner=${_inner%\"} ;;
    \'*\') _inner=${_inner#\'}; _inner=${_inner%\'} ;;
  esac
  printf '%s' "$_inner"
  return 0
}

# Strip leading peel-list wrappers from a command STRING, so the interpreter
# unwrapper can see an interpreter that sits behind one. Without this the two
# mechanisms compose in only one direction: `sh -c 'sudo git add X'` worked
# because unwrapping ran first, but `sudo sh -c 'git add X'` did not, because
# unwrap_dash_c only ever inspects the FIRST word and nothing re-invoked it
# after the peel loop stripped the wrapper. That asymmetry — not a missing name
# — is what let every wrapper+interpreter pair through.
strip_leading_wrappers() {
  _s=$(printf '%s' "$1" | sed 's/^[[:space:]]*//')
  _guard=0
  while [ "$_guard" -lt 8 ]; do
    _guard=$((_guard + 1))
    _w=${_s%% *}
    case "${_w##*/}" in
      command|exec|nohup|setsid|caffeinate|time|unbuffer)
        _s=${_s#* } ;;
      sudo|doas)
        _s=${_s#* }
        while :; do
          case "${_s%% *}" in
            -u|-g|-U|-p|-C) _s=${_s#* }; _s=${_s#* } ;;
            -*|*=*) _s=${_s#* } ;;
            *) break ;;
          esac
        done ;;
      nice|ionice|stdbuf)
        _s=${_s#* }
        while :; do
          case "${_s%% *}" in
            -[a-zA-Z]) _s=${_s#* }; _s=${_s#* } ;;
            -*) _s=${_s#* } ;;
            *) break ;;
          esac
        done ;;
      timeout|gtimeout)
        _s=${_s#* }
        while :; do
          case "${_s%% *}" in
            -*) _s=${_s#* } ;;
            *) _s=${_s#* }; break ;;
          esac
        done ;;
      *) break ;;
    esac
    _s=$(printf '%s' "$_s" | sed 's/^[[:space:]]*//')
  done
  printf '%s' "$_s"
}

check_command_string() {
  _cs=$1
  # Split into segments on && || ; | and newlines.
  printf '%s\n' "$_cs" | tr ';\n' '\n\n' | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/|/\n/g' \
  | while IFS= read -r _seg; do
      [ -n "$_seg" ] || continue
      printf '%s\n' "$_seg"
    done
}

SEG_CWD=""

# Read segments from a FILE, not a pipe: a `cmd | while` loop runs in a subshell,
# where emit_deny's `exit 2` would kill only that subshell and the guard would
# return 0 — allowing exactly what it just detected.
_SEG_FILE="${_HIT_FILE}.segs"
trap 'rm -f "$_HIT_FILE" "$_SEG_FILE" "${_SEG_FILE}.new" "${_SEG_FILE}.new.u"' EXIT INT TERM

# Segment, then expand: every segment is stripped of leading wrappers and, if an
# interpreter is behind them, unwrapped and re-segmented. Iterating over SEGMENTS
# rather than only the whole command matters because the pair can sit inside a
# chain — `cd x && sudo sh -c 'git add y'`. Bounded on both axes so pathological
# nesting cannot loop.
: > "$_SEG_FILE"
check_command_string "$cmd" > "$_SEG_FILE"
_pass=0
while [ "$_pass" -lt 4 ]; do
  _pass=$((_pass + 1))
  _new="${_SEG_FILE}.new"
  : > "$_new"
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    _stripped=$(strip_leading_wrappers "$_s")
    if _inner_cmd=$(unwrap_dash_c "$_stripped") && [ -n "$_inner_cmd" ] && [ "$_inner_cmd" != "$_s" ]; then
      check_command_string "$_inner_cmd" >> "$_new"
    fi
  done < "$_SEG_FILE"
  [ -s "$_new" ] || { rm -f "$_new"; break; }
  # Keep only genuinely new lines, so a self-referential unwrap cannot spin.
  sort -u "$_new" > "${_new}.u"
  _grew=0
  while IFS= read -r _l; do
    grep -Fxq "$_l" "$_SEG_FILE" 2>/dev/null || { printf '%s\n' "$_l" >> "$_SEG_FILE"; _grew=1; }
  done < "${_new}.u"
  rm -f "$_new" "${_new}.u"
  [ "$_grew" = 1 ] || break
done

# Capture `cd <dir>` from the SEGMENTS, not the raw command, so a cd inside an
# `sh -c` wrapper is seen too. Later segments resolve relative paths against it
# (`cd repo && git add <relative>` was a reported bypass).
# tail -1, not head -1: with several `cd` hops the effective directory is the
# LAST one. Switching this to head during the segment-file rewrite silently
# regressed multi-hop resolution.
_cd_target=$(sed -n 's/^[[:space:]]*cd[[:space:]][[:space:]]*\([^[:space:];&|]*\).*/\1/p' "$_SEG_FILE" | tail -1)
if [ -n "$_cd_target" ]; then
  _cd_target=$(strip_quotes "$_cd_target")
  [ -d "$_cd_target" ] && SEG_CWD=$_cd_target
fi

while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  _oldifs=${IFS:-}
  IFS='
'
  # shellcheck disable=SC2046,SC2086
  set -- $(tokenize "$seg")
  IFS=$_oldifs
  # Drop leading VAR=value assignments.
  while [ $# -gt 0 ]; do
    case "$1" in *=*) shift ;; *) break ;; esac
  done
  [ $# -eq 0 ] && continue

  # Peel prefix wrappers. `command git add X`, `exec git add X`, `nohup …`,
  # `timeout 5 …`, `env …` are ordinary shell idioms, and requiring the first
  # token to be exactly `git` made the whole segment skip silently — six
  # bypasses from one root cause. Kept as an explicit list for the same reason
  # the interpreter set is: enumerating inline is what let them through.
  _peeled=1
  while [ "$_peeled" = 1 ] && [ $# -gt 0 ]; do
    _peeled=0
    case "$(strip_quotes "${1:-}")" in
      command|exec|nohup|setsid|caffeinate|time|unbuffer)
        shift; _peeled=1 ;;
      sudo|doas)
        shift; _peeled=1
        while [ $# -gt 0 ]; do
          case "$(strip_quotes "$1")" in
            -u|-g|-U|-p|-C) shift; [ $# -gt 0 ] && shift ;;
            --*=*|-[a-zA-Z]) shift ;;
            -[a-zA-Z]*) shift ;;
            *=*) shift ;;
            *) break ;;
          esac
        done ;;
      flock)
        shift; _peeled=1
        # flock <file|fd> <cmd>, with optional flags first.
        while [ $# -gt 0 ]; do
          case "$(strip_quotes "$1")" in
            -w|--timeout|-E|--conflict-exit-code) shift; [ $# -gt 0 ] && shift ;;
            -*) shift ;;
            *) shift; break ;;
          esac
        done ;;
      nice|ionice|stdbuf)
        shift; _peeled=1
        # These take flags that carry a value (`nice -n 5`, `ionice -c2 -n0`,
        # `stdbuf -oL`), so peel flag[+value] pairs before the real command.
        while [ $# -gt 0 ]; do
          case "$(strip_quotes "$1")" in
            -[a-zA-Z])   shift; [ $# -gt 0 ] && shift ;;
            -[a-zA-Z]*)  shift ;;
            --*=*)       shift ;;
            --[a-zA-Z]*) shift; [ $# -gt 0 ] && shift ;;
            *) break ;;
          esac
        done ;;
      env)
        shift; _peeled=1
        # env's own flags, then VAR=value pairs.
        while [ $# -gt 0 ]; do
          case "$(strip_quotes "$1")" in
            -i|--ignore-environment|-0|--null) shift ;;
            -u|--unset) shift; [ $# -gt 0 ] && shift ;;
            *=*) shift ;;
            *) break ;;
          esac
        done ;;
      timeout|gtimeout)
        shift; _peeled=1
        # Flags, then the duration argument.
        while [ $# -gt 0 ]; do
          case "$(strip_quotes "$1")" in
            -*) shift ;;
            *) shift; break ;;
          esac
        done ;;
    esac
    # A wrapper may be followed by more VAR=value assignments.
    while [ $# -gt 0 ]; do
      case "$1" in *=*) shift; _peeled=1 ;; *) break ;; esac
    done
  done
  [ $# -eq 0 ] && continue

  first=$(strip_quotes "${1:-}")
  case "$first" in git|*/git) ;; *) continue ;; esac
  shift

  # Peel git's global flags (mirrors large-file-add-guard). -C's VALUE is kept,
  # not discarded: `git -C <dir> add <relative>` resolves against that dir, and
  # throwing it away made the frontmatter check — the primary signal — miss.
  while [ $# -gt 0 ]; do
    case "$1" in
      -C)            shift
                     if [ $# -gt 0 ]; then
                       _cdir=$(strip_quotes "$1")
                       [ -d "$_cdir" ] && SEG_CWD=$_cdir
                       shift
                     fi ;;
      -C*)           _cdir=$(strip_quotes "${1#-C}")
                     [ -d "$_cdir" ] && SEG_CWD=$_cdir
                     shift ;;
      # --work-tree names the tree paths resolve against, exactly like -C, so it
      # must feed SEG_CWD too — same bug as -C, sibling flag, two lines away.
      --work-tree=*) _wt=$(strip_quotes "${1#--work-tree=}")
                     [ -d "$_wt" ] && SEG_CWD=$_wt
                     shift ;;
      --work-tree)   shift
                     if [ $# -gt 0 ]; then
                       _wt=$(strip_quotes "$1")
                       [ -d "$_wt" ] && SEG_CWD=$_wt
                       shift
                     fi ;;
      --git-dir=*|--namespace=*) shift ;;
      --git-dir|--namespace)     shift; [ $# -gt 0 ] && shift ;;
      -c)            shift; [ $# -gt 0 ] && shift ;;
      --no-pager|--paginate|--bare|--literal-pathspecs|--no-optional-locks) shift ;;
      -*)            shift ;;
      *)             break ;;
    esac
  done
  [ $# -eq 0 ] && continue

  sub=$1; shift
  # ONLY staging subcommands. `git log`/`git diff`/`git show` may legitimately
  # name a strategy path and must not be blocked.
  case "$sub" in add|stage|commit) ;; *) continue ;; esac

  # Combined short flags count: `git commit -am "wip"` is `-a -m`, and matching
  # only the exact token `-a` let it through. Any single-dash cluster carrying
  # a/A means stage-everything; `--` long options are excluded so `--amend`
  # does not read as `-a`.
  _sweeps=0
  for a in "$@"; do
    _a=$(strip_quotes "$a")
    case "$_a" in
      --all) _sweeps=1 ;;
      --*) ;;
      .) _sweeps=1 ;;
      -*[aA]*) _sweeps=1 ;;
    esac
  done
  [ "$_sweeps" = 1 ] && sweep_pending

  # Walk the remaining args as PATHS — but flags that consume a value must have
  # that value skipped, or the value gets inspected as if it were a path. The
  # reported case: `git commit -m 'remove leaked .../pricing-models.md'` was
  # denied while staging nothing, which is precisely the shape of the
  # remediation commit this hook exists to support.
  _skip=0
  for a in "$@"; do
    if [ "$_skip" = 1 ]; then _skip=0; continue; fi
    _t=$(strip_quotes "$a")
    case "$_t" in
      # `--flag=value` carries its value inline; nothing to skip.
      --*=*) continue ;;
      --message|--file|--template|--author|--date|--cleanup|--fixup|--squash|--reuse-message|--reedit-message|--trailer|--pathspec-from-file)
        _skip=1; continue ;;
      --*) continue ;;
      -*) cluster_consumes_next "$_t" && _skip=1; continue ;;
    esac
    inspect_path "$_t"
  done
done < "$_SEG_FILE"

exit 0
