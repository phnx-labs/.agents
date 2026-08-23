#!/bin/sh
# gh-merge-guard/merge-guard.sh — PreToolUse(Bash) guard.
#
# Blocks an actual `gh pr merge ... --admin` invocation. Admin bypass merges
# past branch protection and required reviews; in the retro it was used to
# self-merge an agent's own PR. A normal authorized merge is fine — only the
# --admin bypass is blocked, so branch protections still decide.
#
# SCOPE / THREAT MODEL. This is a best-effort speed-bump against a cooperative
# agent carelessly running an admin-bypass merge (the retro incident was a plain
# `gh pr merge N --admin`). It is NOT an adversarial security boundary: a shell
# command string cannot be fully analysed with text rules, so a determined
# obfuscation (variable indirection like `X=--admin; gh pr merge $X`, splitting
# the literal word `merge`, etc.) can still get through. The REAL enforcement is
# server-side GitHub branch protection with required reviews — enable that.
#
# What this DOES reliably do: block direct and chained bypass merges, catch
# simple quote/backslash obfuscation of `--admin` (`--ad""min`, `--ad\min`,
# `--ad'min'`), and NOT false-block a `gh pr create` / `git commit` whose body
# or message merely *documents* the guard (that false-positive fired on PR #40).
#
# Deciding shell dataflow with a regex is a losing game, so this is
# BLOCK-BY-DEFAULT: blank only regions we can PROVE are inert, then match;
# anything else stays visible and blocks. Provably inert:
#   * a documentation-flag value (--body/-b/--title/-t/-m/--message/...) that is
#     a PLAIN quoted string — no command substitution ($( or backtick);
#   * a heredoc body whose sink is cat/gh/git at top level and that is NOT routed
#     onward into execution (no pipe/;/&/backtick/redirect after the tag, no
#     process substitution or interpreter around the sink).
# Over-blocks exotic constructs (safe direction); does not fail open on the
# realistic bypass forms. If perl is unavailable we fall back to a raw
# (unblanked) match, which only over-blocks.
#
# Reads the hook JSON from stdin, extracts .tool_input.command via jq.
# Exits 0 (allow) or 2 (deny, message on stderr).
input=$(cat)

# Portable timeout: macOS ships neither `timeout` nor `gtimeout` by default.
_to() {
  if command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  else shift; "$@"
  fi
}

# --- portable JSON field extractor (jq -> node -> python) -------------------
# jq is absent on Windows git-bash; the old `… | jq …` extraction then returned
# empty and this guard fail-OPEN'd (waved `gh pr merge --admin` through). Prefer
# jq (fast, present on mac/Linux), fall back to node (always shipped with
# agents-cli) then python. Returns 1 ONLY when NO parser exists -> fail CLOSED.
#
# Harness portability: Claude Code sends snake_case (tool_input.command); Grok
# CLI sends camelCase (toolInput.command). A call passes the snake_case path as
# $2 and its camelCase equivalent as an optional $3 — the first path that
# resolves non-empty wins. Keeping the fallback in the extractor keeps all three
# parser branches uniform.
_json_field() {  # $1=json  $2=dotted.path  [$3=alternate.dotted.path]
  if command -v jq >/dev/null 2>&1; then
    if [ -n "${3:-}" ]; then
      printf '%s' "$1" | jq -r "((.$2) // (.$3)) // empty" 2>/dev/null
    else
      printf '%s' "$1" | jq -r "(.$2) // empty" 2>/dev/null
    fi
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const dig=(o,p)=>{for(const k of p.split("."))o=(o==null?null:o[k]);return o};try{let o=JSON.parse(s);let v=dig(o,process.argv[1]);if((v==null||v==="")&&process.argv[2])v=dig(o,process.argv[2]);process.stdout.write(v==null?"":String(v))}catch(e){}})' "$2" "${3:-}" 2>/dev/null; return 0
  fi
  for _py in python3 python; do
    command -v "$_py" >/dev/null 2>&1 && "$_py" -c '' >/dev/null 2>&1 || continue
    printf '%s' "$1" | "$_py" -c 'import json,sys
try: o=json.load(sys.stdin)
except Exception: o=None
def dig(o,p):
    for k in p.split("."):
        o=o.get(k) if isinstance(o,dict) else None
    return o
v=dig(o,sys.argv[1])
if (v is None or v=="") and len(sys.argv)>2 and sys.argv[2]:
    v=dig(o,sys.argv[2])
sys.stdout.write("" if v is None else str(v))' "$2" "${3:-}" 2>/dev/null
    return 0
  done
  return 1
}

# Fast path: a command that never mentions "merge" can't be a bypass merge.
case "$input" in
  *merge*) ;;
  *) exit 0 ;;
esac

# Fail CLOSED if no JSON parser is available — a guard that cannot read the
# command must not wave a possible admin-bypass merge through.
if ! cmd=$(_json_field "$input" tool_input.command toolInput.command); then
  printf 'merge-guard: no JSON parser (jq/node/python) available — cannot verify the merge command; refusing (fail-closed).\n' >&2
  exit 2
fi
[ -n "$cmd" ] || exit 0

blanked=no
if command -v perl >/dev/null 2>&1; then
  blanked=yes
  scan=$(printf '%s' "$cmd" | perl -0777 -pe '
    # 0. Join backslash-newline line continuations so routing on the next
    #    physical line (e.g. `cat <<EOF \` <newline> `| sh`) is seen inline.
    s/\\\n//g;

    # 1. Heredoc body -> blank ONLY when provably inert: sink is cat/gh/git at a
    #    top-level command position ($(, start, ; & | backtick, newline — NOT a
    #    bare "(" so "<(cat" / subshells stay visible), nothing between sink and
    #    "<<" that redirects/routes, no interpreter/process-subst in the prefix,
    #    and nothing after the tag on the opener line that pipes/redirects the
    #    body onward. Otherwise keep the body visible.
    s{
      (^|[\n;&|`]|\$\()([^\n]*?)<<[-~]?[ \t]*(["\x27]?)([A-Za-z_]\w*)\3
      ([^\n]*)\n(.*?)\n[ \t]*\4[ \t]*(?=\n|$)
    }{
      my ($b,$pre,$tag,$rest,$body)=($1,$2,$4,$5,$6);
      my $inert =
        $pre  =~ m{(?:^|[;&|`]|\$\()[ \t]*(?:cat|gh|git)\b[^;&|`<>]*$}
        && $pre  !~ m{(?:^|[;&|`])[ \t]*(?:eval|exec|sh|bash|zsh|ksh|dash|source|xargs|\.)\b}
        && $pre  !~ m{[<>]\(}
        && $rest !~ m{[|&;`<>]};
      $inert ? "$b$pre$rest" : "$b$pre<<$tag$rest\n$body\n$tag";
    }gemsx;

    # 2. Documentation-flag value -> blank ONLY plain quoted text; keep any value
    #    containing a command substitution ($( or backtick) visible. The short
    #    forms allow a combined single-dash cluster ending in the value flag, so
    #    `git commit -am/-asm "msg"` is handled like `-m "msg"`.
    s{
      (^|[ \t;&|`(])
      ((?:--body|--title|--message|--notes|--subject|--body-text|-[A-Za-z]*[btm])(?:=|[ \t]+))
      ("(?:\\.|[^"\\])*"|\x27[^\x27]*\x27)
    }{
      my ($bnd,$flag,$val)=($1,$2,$3);
      $val =~ /[\$`]/ ? "$bnd$flag$val" : "$bnd$flag ";
    }gex;
  ') || scan=$cmd
else
  scan=$cmd
fi

# Normalize away quote/backslash obfuscation for the token check. `scan` has had
# its inert regions blanked already, so stripping quotes here cannot resurrect
# documentation tokens — it only collapses forms like `--ad""min` -> `--admin`.
norm=$(printf '%s' "$scan" | tr -d '\047\042\134')   # remove ' " \

case "$norm" in
  *"gh pr merge"*)
    case "$norm" in
      *"--admin"*)
        printf '%s\n' "Blocked: 'gh pr merge --admin' bypasses branch protection (used in the retro to self-merge an own PR). Get explicit user authorization, then merge WITHOUT --admin so required reviews and checks still apply." >&2
        exit 2
        ;;
    esac

    # With perl absent nothing was blanked, so body/title TEXT mentioning a
    # merge (e.g. a PR body documenting "gh pr merge 42") could reach the API
    # probe below on a non-merge command. Require the command to actually START
    # with a merge invocation (allowing a leading env/command position) in that
    # case — the admin check above stays as-is (over-blocking is its safe
    # direction; a network probe on the wrong command is not).
    if [ "$blanked" = "no" ]; then
      case "$cmd" in
        "gh pr merge"*|*";gh pr merge"*|*"; gh pr merge"*|*"&& gh pr merge"*|*"| gh pr merge"*) ;;
        *) exit 0 ;;
      esac
    fi

    # Review-on-THIS-PR check (2026-08-15, PR #2736): a merge satisfied the
    # non-author-review convention with "Non-author APPROVE on #2731" — an
    # approval carried from a DIFFERENT PR. A verdict only counts on the PR it
    # was posted on. Accept either a real GitHub APPROVED review, or the fleet
    # convention of an APPROVE verdict comment on this PR that is not a
    # carried-from citation. Fail OPEN on anything the guard cannot resolve
    # (no number, no repo, API error, rate limit) — a review guard must never
    # block a legit merge because GitHub hiccuped; --admin blocking above never
    # fails open.
    _pr_num=""; _pr_repo=""
    _pr_url=$(printf '%s' "$cmd" | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | head -1)
    if [ -n "$_pr_url" ]; then
      _pr_num=${_pr_url##*/}
      _pr_repo=$(printf '%s' "$_pr_url" | sed -E 's#https://github\.com/([^/]+/[^/]+)/pull/.*#\1#')
    else
      _pr_num=$(printf '%s' "$cmd" | grep -oE 'pr merge[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1)
      # Both spellings gh accepts: --repo and -R. Missing -R sent the verdict
      # probe to the CWD repo's origin and blocked a legitimate merge whose
      # APPROVE lived on the -R repo's PR (RUSH-3032; hit live 2026-08-22).
      _pr_repo=$(printf '%s' "$cmd" | grep -oE '(\-\-repo|-R)[= ][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | sed -E 's/(--repo|-R)[= ]//' | head -1)
      if [ -z "$_pr_repo" ]; then
        _pr_repo=$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github\.com:|https://github\.com/)([^/]+/[^/.]+)(\.git)?#\2#' | head -1)
      fi
    fi
    if [ -n "$_pr_num" ] && [ -n "$_pr_repo" ]; then
      # 3s per call: two sequential probes must fit the hook's registered
      # timeout. On stock macOS (no timeout/gtimeout) _to runs gh unbounded —
      # the harness then kills the hook at its registered timeout, which FAILS
      # OPEN at the harness layer; acceptable for a review probe, never relied
      # on for the admin block (which needs no network).
      _reviews=$(_to 3 gh api "repos/$_pr_repo/pulls/$_pr_num/reviews" --cache 60s 2>/dev/null) || _reviews="__API_ERR__"
      _comments=$(_to 3 gh api "repos/$_pr_repo/issues/$_pr_num/comments" --cache 60s 2>/dev/null) || _comments="__API_ERR__"
      if [ "$_reviews" != "__API_ERR__" ] && [ "$_comments" != "__API_ERR__" ]; then
        # Same verdict as pr-merge-on-green: reuse pr-verdict.py, do not re-inline.
        _GUARD_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
        _verdict=$(printf '%s\n---AGENTS-SPLIT---\n%s' "$_reviews" "$_comments" | python3 "$_GUARD_DIR/pr-verdict.py" 2>/dev/null) || _verdict="ok"
        if [ "$_verdict" = "missing" ]; then
          printf '%s\n' "Blocked: no non-author review verdict found ON this PR ($_pr_repo#$_pr_num). A GitHub APPROVED review or an APPROVE verdict comment must be posted on the PR being merged — a verdict 'carried from' another PR satisfies nothing (the #2736 laundering pattern). Get the automated reviewer's verdict or spawn a non-author subagent review on THIS PR, then retry." >&2
          exit 2
        fi
      fi
    fi
    ;;
esac
exit 0
