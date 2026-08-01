#!/bin/sh
# truly-agentic-git-workflow/pr-description-reminder.sh — PreToolUse(Bash) reminder.
#
# Nudges once when a `gh pr create` / `gh pr edit` ships an INLINE body that is
# thin — a bare blob with no structure and no change-type marker. The reviewer
# reads the body, not the diff, so a wall-of-prose (or one-liner) PR is one they
# cannot glance. The fix the reminder asks for: lead with a `what + type`
# (docs-only / bugfix / feature / refactor / test-only), highlight the important
# parts (a heading, a table, or bullets), and add a before/after when there is a
# visible or behavioral delta.
#
# SATISFIABLE, not a wall: it clears the moment the body carries any structure or
# a type marker. It fires ONLY on an inline --body/-b; a --body-file / -F / --fill
# / --template / --web / editor body is never inspected and always allowed.
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

# Extract the tool command with a jq -> node -> python fallback so the reminder
# does not misfire when jq is absent (e.g. stock Git Bash on Windows).
_json_field() {
  # $1 = json, $2 = primary dotted key, $3 = optional fallback dotted key
  if command -v jq >/dev/null 2>&1; then
    if [ -n "${3:-}" ]; then
      printf '%s' "$1" | jq -r "((.$2) // (.$3)) // empty" 2>/dev/null
    else
      printf '%s' "$1" | jq -r "(.$2) // empty" 2>/dev/null
    fi
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const dig=(o,p)=>{for(const k of p.split("."))o=(o==null?null:o[k]);return o};try{let o=JSON.parse(s);let v=dig(o,process.argv[1]);if((v==null||v==="")&&process.argv[2])v=dig(o,process.argv[2]);process.stdout.write(v==null?"":String(v))}catch(e){}})' "$2" "${3:-}" 2>/dev/null
    return 0
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

# No JSON parser -> FAIL OPEN (a reminder must never block a legit PR).
cmd=$(_json_field "$input" tool_input.command toolInput.command) || exit 0
[ -n "$cmd" ] || exit 0

# Only the body-bearing subcommands.
case "$cmd" in
  *"gh pr create"*|*"gh pr edit"*) ;;
  *) exit 0 ;;
esac

# Body comes from a file / commits / editor / browser -> not inspectable, allow.
case "$cmd" in
  *"--body-file"*|*" -F "*|*"--fill"*|*"--fill-first"*|*"--fill-verbose"*|*"--template"*|*"--web"*) exit 0 ;;
esac

# No inline body flag at all -> gh opens an editor (create) or it's a non-body
# edit (e.g. --add-label) -> nothing to inspect, allow.
case "$cmd" in
  *"--body"*|*" -b "*) ;;
  *) exit 0 ;;
esac

# RAN-IT-OR-EXEMPT. An agentic developer runs the feature it builds, looks at the
# real result, and attaches THAT — a screenshot/recording of the thing running, or
# the run's output as an uploaded artifact. Source code and hand-authored tables
# are NOT proof of a run and do NOT clear this. Allow (exit 0) if the command
# carries ANY signal below (substring match over the whole command, biased to
# ALLOW to keep false-blocks near zero); otherwise nudge. Exempt: release + docs.

# 1) A real run result — a screenshot / GIF / recording, inline or as an uploaded
#    asset. This is the proof that the agent ran it and observed the outcome.
case "$cmd" in
  *"!["*|*".png"*|*".jpg"*|*".jpeg"*|*".gif"*|*".webp"*|\
  *".mp4"*|*".mov"*|*".webm"*|*".svg"*|\
  *"user-attachments/assets"*|*"githubusercontent.com"*|*"/assets/"*) exit 0 ;;
esac
# 2) An exemption or attached context (case-insensitive):
#    - the two PR kinds that need no run: a RELEASE, or a pure DOC edit
#    - a no-visible-surface / non-behavioral declaration (refactor / test-only)
#    - a Linear ticket link or a shared plan (.html) link
lower=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
case "$lower" in
  *"release"*|*"docs-only"*|*"docs only"*|*"docs:"*|\
  *"no behavior change"*|*"no-behavior-change"*|*"no visible surface"*|*"no user-visible"*|\
  *"refactor"*|*"test-only"*|*"test only"*|*"internal only"*|\
  *"linear.app/"*|*"getrush.ai/"*|*".html"*) exit 0 ;;
esac

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
  echo "A --body-file / --fill body is never nudged."
} >&2
exit 2
