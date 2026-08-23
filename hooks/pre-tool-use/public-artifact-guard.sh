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
# Exits 0 (allow) or 2 (deny, message on stderr).

set -eu

input=$(cat)
# Fast path: must plausibly be a staging command.
case "$input" in
  *git*add*|*git*commit*|*git*stage*) ;;
  *) exit 0 ;;
esac

# Portable JSON field (jq -> node -> python). Claude/Codex: tool_input.command;
# Grok: toolInput.command.
_json_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r "(.$2) // empty" 2>/dev/null; return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{let o=JSON.parse(s);for(const k of process.argv[1].split("."))o=(o==null?null:o[k]);process.stdout.write(o==null?"":String(o))}catch(e){}})' "$2" 2>/dev/null; return 0
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$1" | "$_py" -c 'import json,sys
try: o=json.load(sys.stdin)
except Exception: o=None
for k in sys.argv[1].split("."):
    o=o.get(k) if isinstance(o,dict) else None
sys.stdout.write("" if o is None else str(o))' "$2" 2>/dev/null
    return 0
  done
  return 1
}

if ! cmd=$(_json_field "$input" tool_input.command); then
  printf 'public-artifact-guard: no JSON parser (jq/node/python) — refusing the staging command unchecked (fail-closed).\n' >&2
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
      if (q != "") {
        if (c == q) { q = "" } else { tok = tok c; have = 1 }
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
is_strategy_name() {
  _b=${1##*/}
  _b=$(printf '%s' "$_b" | tr '[:upper:]' '[:lower:]')
  _b=${_b%.md}; _b=${_b%.markdown}; _b=${_b%.mdx}; _b=${_b%.html}; _b=${_b%.yaml}; _b=${_b%.yml}
  # Drop a leading date or "plan-"/"draft-" style prefix before anchoring.
  _b=$(printf '%s' "$_b" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
  case "$_b" in
    # The RUSH-3033 document set, by whole name.
    gtm|gtm-strategy|go-to-market|go-to-market-strategy) return 0 ;;
    monetize|monetize-*|monetization-strategy|pricing-models) return 0 ;;
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
# Capture a `cd <dir>` anywhere in the command so later segments resolve against
# it (blocker: `cd repo && git add <relative>` bypassed an existence-gated check).
_cd_target=$(printf '%s' "$cmd" | sed -n 's/.*\(^\|[;&|] *\)cd  *\([^ ;&|]*\).*/\2/p' | head -1)
if [ -n "$_cd_target" ]; then
  _cd_target=$(strip_quotes "$_cd_target")
  [ -d "$_cd_target" ] && SEG_CWD=$_cd_target
fi

# Read segments from a FILE, not a pipe: a `cmd | while` loop runs in a subshell,
# where emit_deny's `exit 2` would kill only that subshell and the guard would
# return 0 — allowing exactly what it just detected.
_SEG_FILE="${_HIT_FILE}.segs"
trap 'rm -f "$_HIT_FILE" "$_SEG_FILE"' EXIT INT TERM
check_command_string "$cmd" > "$_SEG_FILE"

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

  first=$(strip_quotes "${1:-}")
  case "$first" in git|*/git) ;; *) continue ;; esac
  shift

  # Peel git's global flags (mirrors large-file-add-guard).
  while [ $# -gt 0 ]; do
    case "$1" in
      -C)            shift; [ $# -gt 0 ] && shift ;;
      --git-dir=*|--work-tree=*|--namespace=*) shift ;;
      --git-dir|--work-tree|--namespace)      shift; [ $# -gt 0 ] && shift ;;
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

  _sweeps=0
  for a in "$@"; do
    case "$(strip_quotes "$a")" in
      -A|--all|.|-a) _sweeps=1 ;;
    esac
  done
  [ "$_sweeps" = 1 ] && sweep_pending

  for a in "$@"; do
    case "$a" in -*) continue ;; esac
    inspect_path "$a"
  done
done < "$_SEG_FILE"

exit 0
