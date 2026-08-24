#!/bin/sh
# truly-agentic-git-workflow/pr-description-reminder.sh — PreToolUse(Bash) reminder.
#
# Nudges (a satisfiable block, exit 2) when a `gh pr create` / `gh pr edit` ships a
# body with NO proof the agent ran what it built — no screenshot / recording /
# uploaded asset. The reviewer should see it work, not read code to believe it. The
# reminder clears on a real run result OR an explicit no-run declaration — and a
# CHECKABLE declaration (test-only / docs-only) is verified against the branch's
# changed files: a contradicted declaration BLOCKS instead of clearing (2026-08-15,
# PR #2736: "test-only." on a fifteen-file fix diff). Unverifiable declarations
# (release-shaped phrases / refactor / no-behavior-change) clear as before. A code
# block, a table, and a bare ticket/plan LINK are context, not proof of a run, and
# do NOT clear it.
#
# The body it inspects: an inline --body/-b AND the file behind --body-file/-F
# (read and inspected — agents route nearly every multi-line body through it). A
# --fill / --template / --web / editor body it cannot read, and an unreadable or
# space-containing --body-file path it cannot resolve, FAIL OPEN (allow) — a
# reminder must never block a legit PR.
#
# Multi-harness: reads the tool command from Claude's snake_case
# .tool_input.command OR Grok/Codex camelCase .toolInput.command, via a
# jq -> node -> python fallback chain (same helper as footer-guard). Unlike the
# footer guard this FAILS OPEN — a reminder must never block a legit PR, so any
# parse/extract failure exits 0.
input=$(cat)

# Fast path: ignore anything that isn't a gh pr command.
case "$input" in
  *"gh pr "*) ;;
  *) exit 0 ;;
esac

# --- shared JSON field extractor -------------------------------------------
# _json_field lives in hooks/lib/json-field.sh (one definition; formerly copied
# into 12 hook scripts). Source it relative to this script, fall back to the
# absolute system-install path. This is an advisory reminder that fails OPEN on
# a parse failure, so a missing lib skips quietly (exit 0). ${0%/*} (POSIX, no
# subprocess) locates the lib even when PATH carries no coreutils.
_LIB_DIR=$(CDPATH= cd "${0%/*}" 2>/dev/null && pwd) || _LIB_DIR=""
for _cand in "$_LIB_DIR/../../../hooks/lib/json-field.sh" "${HOME}/.agents/.system/hooks/lib/json-field.sh"; do
  if [ -f "$_cand" ]; then
    # shellcheck source=../../../hooks/lib/json-field.sh
    . "$_cand"
    if command -v _json_field >/dev/null 2>&1; then break; fi
  fi
done
unset _LIB_DIR _cand
command -v _json_field >/dev/null 2>&1 || exit 0

_hook_skip_plan_mode "$input" && exit 0

# No JSON parser -> FAIL OPEN (a reminder must never block a legit PR).
cmd=$(_json_field "$input" tool_input.command toolInput.command) || exit 0
[ -n "$cmd" ] || exit 0

# Only the body-bearing subcommands.
case "$cmd" in
  *"gh pr create"*|*"gh pr edit"*) ;;
  *) exit 0 ;;
esac

# Resolve the inspectable BODY text. Three sources:
#   - inline --body/-b: the body is already inside the command string.
#   - --body-file/-F <path>: read that file and inspect its CONTENT (the common
#     multi-line path — agents route almost every real PR body through it, so it
#     MUST be inspected, not waved through).
#   - --fill/--template/--web/editor: the body lives in commits/template/editor we
#     cannot read here -> fail OPEN (allow), a reminder must never block a legit PR.
# Any extraction or read failure also fails OPEN.
body=""
case "$cmd" in
  *"--body-file"*|*"--body-file="*|*" -F "*|*"-F="*)
    bf=$(printf '%s\n' "$cmd" | sed -n 's/.*--body-file[ =]*//p')
    [ -n "$bf" ] || bf=$(printf '%s\n' "$cmd" | sed -n 's/.*-F[ =]*//p')
    bf=${bf%% *}          # first whitespace-delimited token only
    bf=${bf#\"}; bf=${bf%\"}; bf=${bf#\'}; bf=${bf%\'}   # strip one layer of quotes
    if [ -n "$bf" ] && [ -f "$bf" ] && [ -r "$bf" ]; then
      body=$(cat "$bf" 2>/dev/null) || exit 0
    else
      exit 0            # cannot resolve/read the body file -> fail open
    fi
    ;;
  *"--fill"*|*"--fill-first"*|*"--fill-verbose"*|*"--template"*|*"--web"*)
    exit 0 ;;           # body from commits / template / editor -> not inspectable
  *"--body"*|*" -b "*|*"-b="*)
    body="$cmd" ;;      # inline body is carried in the command string itself
  *)
    exit 0 ;;           # no body flag -> editor (create) or a non-body edit -> allow
esac

# Everything we can see about the body: the command flags PLUS the resolved content.
hay="$cmd
$body"

# RAN-IT-OR-EXEMPT. An agentic developer runs the feature it builds, looks at the
# real result, and attaches THAT — a screenshot/recording of the thing running, or
# the run's output as an uploaded artifact. Source code, hand-authored tables, and a
# bare ticket/plan LINK are NOT proof of a run and do NOT clear this. Clear (exit 0)
# only on a real run result OR an explicit no-run declaration; otherwise nudge.

# 1) A real run result — a screenshot / GIF / recording, inline or as an uploaded
#    asset, that a reviewer can actually OPEN. Evidence is a REMOTE URL: an
#    image/video embed of one, a media-extension URL, or a known upload/share
#    host. A bare local path that happens to end in ".png" is not evidence —
#    2026-08-17, PR #317 cleared the old substring check with
#    "zion:/tmp/gate-recording-run.txt.png", a fleet-local path nobody on GitHub
#    can render, and #329 shipped a gist link while a repo file list full of
#    ".svg" names would also have cleared it.
if printf '%s' "$hay" | grep -Eq '!\[[^]]*\]\(https?://'; then exit 0; fi
if printf '%s' "$hay" | grep -Eqi 'https?://[^[:space:]<>")]+\.(png|jpe?g|gif|webp|mp4|mov|webm|svg)([?#).,">[:space:]]|$)'; then exit 0; fi
if printf '%s' "$hay" | grep -Eqi 'user-attachments/assets|githubusercontent\.com|://share\.'; then exit 0; fi
# 2) An explicit no-run DECLARATION (case-insensitive): the two PR kinds that need no
#    run (a RELEASE or a pure DOC edit), or a no-visible-surface / non-behavioral
#    declaration (refactor / test-only). A Linear ticket or plan link is CONTEXT, not
#    evidence — it does NOT clear the run-result requirement on its own.
#    A declaration only counts in the PR's LEAD — the title plus the body's first
#    8 lines (the repo convention is "lead with a one-line what + type"). Matching
#    the whole body let the word "refactor" inside an unrelated code block or link
#    clear a genuine feature diff — the magic word was a password again, just
#    hidden deeper.
#    The title flag is -t or --title (gh pr create -h), quoted or a bare token;
#    matching only quoted --title false-blocked a legitimate `-t "release v2"`.
#    The flag must follow whitespace so the -t inside "--sort" etc. can't match.
title=$(printf '%s\n' "$cmd" | sed -nE 's/.*[[:space:]](--title|-t)[= ]+"([^"]*)".*/\2/p' | head -1)
[ -n "$title" ] || title=$(printf '%s\n' "$cmd" | sed -nE "s/.*[[:space:]](--title|-t)[= ]+'([^']*)'.*/\2/p" | head -1)
[ -n "$title" ] || title=$(printf '%s\n' "$cmd" | sed -nE 's/.*[[:space:]](--title|-t)[= ]+([^"'"'"'[:space:]-][^[:space:]]*).*/\2/p' | head -1)
lead="$title
$(printf '%s\n' "$body" | head -8)"
lower=$(printf '%s' "$lead" | tr '[:upper:]' '[:lower:]')
case "$lower" in
  *"chore(release)"*|*"release pr"*|*"release:"*|*"release v"*|*"docs:"*|\
  *"no behavior change"*|*"no-behavior-change"*|*"no visible surface"*|*"no user-visible"*|\
  *"refactor"*|*"internal only"*) exit 0 ;;
esac

# Declaration-vs-diff cross-check (2026-08-15, PR #2736): "test-only." on a
# +1,519/-200 fifteen-file fix(browser) diff cleared this check — the magic word
# had become a password. A checkable declaration (test-only / docs-only) is now
# verified against the branch's actual changed files; a contradicted
# declaration BLOCKS instead of clearing. Unverifiable declarations (release /
# refactor / no-behavior-change) keep clearing above — the diff cannot decide
# them. Fail open when the diff is unreadable: a reminder must never block a
# legit PR because git hiccuped.
declared=""
case "$lower" in *"test-only"*|*"test only"*) declared="test-only" ;; esac
if [ -z "$declared" ]; then
  case "$lower" in *"docs-only"*|*"docs only"*) declared="docs-only" ;; esac
fi
if [ -n "$declared" ]; then
  _base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  [ -n "$_base" ] || _base=main
  _files=$(git diff --name-only "origin/$_base...HEAD" 2>/dev/null)
  [ -n "$_files" ] || exit 0
  _bad=""
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    case "$declared" in
      test-only)
        # *test* already covers testdata/ and __tests__ paths (SC2221).
        case "$_f" in
          *test*|*Test*|*.spec.*) ;;
          *) _bad="$_bad  - $_f
" ;;
        esac ;;
      docs-only)
        case "$_f" in
          *.md|*.mdx|*.txt|docs/*|*/docs/*|LICENSE*) ;;
          *) _bad="$_bad  - $_f
" ;;
        esac ;;
    esac
  done <<PRDIFF
$_files
PRDIFF
  if [ -z "$_bad" ]; then exit 0; fi
  {
    echo "PR evidence reminder (truly-agentic-git-workflow): the body declares '$declared' but the branch diff contradicts it."
    echo
    echo "Non-$declared files changed on this branch:"
    printf '%s' "$_bad"
    echo
    echo "A no-run declaration is only for a diff that genuinely matches it — declaring 'test-only' on a behavior change is how an evidence-free PR walks past this check (PR #2736). Either fix the declaration and attach a real run result (screenshot / recording / uploaded output), or split the PR so the declaration is true."
  } >&2
  exit 2
fi

# No run result and not exempt — nudge once. Satisfiable: run it, capture, attach.
{
  echo "PR evidence reminder (truly-agentic-git-workflow): this gh pr body has no proof you RAN what you built."
  echo
  echo "An agentic developer runs its own feature, looks at the result, and attaches THAT — before opening the PR. A code block or table is not proof of a run; a reviewer should not have to read code to see it works."
  echo
  echo "Do this, then retry (it clears as soon as a run result is attached):"
  echo "  * RUN the feature and CAPTURE the result: a SCREENSHOT of the running feature (web UI, app screen), or a RECORDING of the flow — a web app via the browser skill, a terminal flow via 'agents pty'."
  echo "  * For a no-UI change, capture the real run: screenshot the terminal / the passing run, or upload the run's output/log as an asset (not pasted source)."
  echo "  * Attach it: drag into the PR, or reference an on-disk image/recording by full path."
  echo "  * Link the Linear ticket, and the plan file if a plan was shared."
  echo
  echo "Exempt (say so in the body): a RELEASE PR, or a pure DOC edit — those need no run."
  echo "A ticket/plan LINK is context, not run-evidence — it no longer clears this on its own."
  echo "A --body-file body IS inspected now; a --fill / --template / editor body is not."
} >&2
exit 2
