#!/usr/bin/env bash
# find-sessions.sh — enumerate the sessions that actually used a given target
# (skill, plugin, command, built-in tool, or free-text workflow) and emit one
# JSON object per matching session, newest first.
#
# Usage:
#   find-sessions.sh <target> [--all] [--since <dur>] [--limit N]
#
#   <target>   skill name ("linear", "rush:design"), plugin prefix ("rush"),
#              command ("/learn"), tool name ("WebSearch"), or any keyword.
#   --all      search every project/repo, not just the current one.
#   --since    only sessions newer than this (e.g. 90d, 30d) — passed to
#              `sessions`. All matches are returned regardless; this
#              only bounds the candidate set for speed.
#   --limit    cap the candidate session count (default 400).
#
# Output (stdout): newline-delimited JSON, one per matched session:
#   {"id","shortId","topic","ts","file","cwd","gitBranch","messageCount",
#    "hits","firstLine","lastLine","kind"}
# where "hits" = number of transcript lines that used the target, "kind" =
# how it matched (skill|command|tool|text), and first/lastLine are 1-based
# JSONL line numbers for the earliest/latest use (the "moment" to quote).
#
# Detection is precise, not a blind substring scan:
#   - skill   : tool_use {name:"Skill", input.skill == target OR starts "target:"}
#   - command : a <command-name> tag naming the target
#   - tool    : tool_use {name == target}  (built-in tools)
#   - text    : literal substring (fallback for workflows / loose keywords)
set -euo pipefail

TARGET="${1:?usage: find-sessions.sh <target> [--all] [--since <dur>] [--limit N]}"
shift || true

ALL=""; SINCE=""; LIMIT="400"; STRUCTURED_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL="--all"; shift ;;
    --since) SINCE="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    # Drop prose mentions; keep only real invocations (skill/command/tool).
    # Use for a named target ("rush:design", "/learn", "WebSearch"); omit for
    # a loose workflow keyword you want to grep for in conversation text.
    --structured-only) STRUCTURED_ONLY="1"; shift ;;
    *) shift ;;
  esac
done

# Strip a leading slash so "/learn" and "learn" both work.
TARGET_BARE="${TARGET#/}"
# Plugin prefix form: "rush" matches any "rush:foo" skill.
PREFIX="${TARGET_BARE%%:*}"

# 1) Candidate session list (metadata + transcript filePath) as JSON.
#    Branch on --since rather than expanding a possibly-empty array, which
#    trips `set -u` on bash 3.2 (the macOS default).
if [ -n "$SINCE" ]; then
  candidates="$(sessions ${ALL} --since "$SINCE" --limit "$LIMIT" --json 2>/dev/null || echo '[]')"
else
  candidates="$(sessions ${ALL} --limit "$LIMIT" --json 2>/dev/null || echo '[]')"
fi

# 2) For each candidate, inspect its transcript for real usage of the target.
#    jq does the precise detection; we stream results newest-first.
echo "$candidates" | jq -rc '.[] | select(.filePath != null) |
  {id, shortId, topic, ts: .timestamp, file: .filePath, cwd, gitBranch, messageCount}' \
| while IFS= read -r meta; do
    file="$(printf '%s' "$meta" | jq -r '.file')"
    [ -f "$file" ] || continue

    # Cheap prefilter: does the literal target appear at all? Skip files that
    # can't possibly match before paying for the jq pass.
    grep -qiF -- "$TARGET_BARE" "$file" 2>/dev/null || \
      grep -qiF -- "$PREFIX" "$file" 2>/dev/null || continue

    # Precise per-line detection. Emit, for each matching JSONL line, its
    # true 1-based line number (jq's input_line_number) and the match kind,
    # tab-separated.
    detail="$(jq -rc --arg t "$TARGET_BARE" --arg p "$PREFIX" '
        # which kind, or empty if no match
        def used:
          if .type=="assistant" then
            ( [ .message.content[]?
                | select(.type=="tool_use")
                | if (.name=="Skill") then
                    ( (.input.skill // "") as $s
                      | if ($s==$t or ($s|startswith($t+":")) or ($s|startswith($p+":")) or $s==$p)
                        then "skill" else empty end )
                  elif (.name==$t) then "tool"
                  else empty end ] | first ) // empty
          elif .type=="user" then
            ( (.message.content // "" | if type=="array" then (map(.text? // "") | join(" ")) else tostring end) as $txt
              | if ($txt | test("<command-name>[^<]*"+$t)) then "command"
                elif ($txt | ascii_downcase | contains($t|ascii_downcase)) then "text"
                else empty end )
          else empty end;
        used as $k | select($k != null) | "\(input_line_number)\t\($k)"
      ' "$file" 2>/dev/null)"

    # In structured-only mode, discard prose mentions before counting.
    if [ -n "$STRUCTURED_ONLY" ]; then
      detail="$(printf '%s' "$detail" | awk -F'\t' '$2 != "text"' || true)"
    fi

    hits="$(printf '%s' "$detail" | grep -c . || true)"
    [ "${hits:-0}" -gt 0 ] || continue

    # Prefer precise structured uses (skill/command/tool) over incidental text
    # mentions when reporting the session's kind and the moment to quote. A
    # passing reference to the word in prose shouldn't outrank a real invocation.
    structured="$(printf '%s' "$detail" | awk -F'\t' '$2 != "text"' || true)"
    ranked="$detail"
    [ -n "$structured" ] && ranked="$structured"

    firstLine="$(printf '%s' "$ranked" | head -1 | cut -f1)"
    lastLine="$(printf '%s' "$ranked" | tail -1 | cut -f1)"
    kind="$(printf '%s' "$ranked" | head -1 | cut -f2)"
    # structuredHits = uses that are a real invocation, not a prose mention.
    structuredHits="$(printf '%s' "$structured" | grep -c . || true)"

    printf '%s' "$meta" | jq -c \
      --argjson hits "${hits:-0}" \
      --argjson structuredHits "${structuredHits:-0}" \
      --argjson firstLine "${firstLine:-0}" \
      --argjson lastLine "${lastLine:-0}" \
      --arg kind "${kind:-text}" \
      '. + {hits:$hits, structuredHits:$structuredHits, firstLine:$firstLine, lastLine:$lastLine, kind:$kind}'
  done | jq -rc -s 'sort_by(.ts) | reverse | .[]'
