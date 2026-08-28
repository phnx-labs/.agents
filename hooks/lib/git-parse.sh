#!/bin/sh
# hooks/lib/git-parse.sh — the shared git-command parser used by every guard
# that inspects a shell command string for a git invocation.
#
# Sourced, never executed. Consumers source it by path (see hooks/AGENTS.md
# §hooks/lib) with a fail-closed check that the parser is defined after the
# source — a guard that cannot parse its input must refuse, not wave the command
# through. This is the same source-then-verify contract the guards already use
# for json-field.sh (#385) and git-facts.sh.
#
# History: this machinery was copy-pasted, near-verbatim, into three guards —
# git-guard.sh (WHAT operation), large-file-add-guard.sh (git add of a blob),
# and main-branch-guard.sh (WHERE: the primary worktree). Each re-implemented
# `sh|bash -c` unwrapping, chain splitting, first-token/`-C` unquoting, env-prefix
# stripping, `git` detection, and global-flag peeling. A parse fix therefore had
# to land in three places; they drifted (large-file grew a redundant sh/bash arm,
# main-branch grew `-C` capture the others lacked). One definition, one fix site.
#
# The parser is policy-free: it identifies git invocations and shell write
# destinations, then hands them to consumer callbacks. WHAT/WHERE policy lives
# in the guard, not here — this file only finds commands and destinations.

# git_extract_sh_c_inner <raw> — detect a `sh|bash -c <inner>` wrapper at the
# raw-string level (BEFORE any token split, so a quoted inner command like
# `sh -c "git reset --hard"` is not shredded). Strips a leading run of
# `VAR=value ` env assignments first. On a match, sets the global _dash_c_inner
# to the (one-layer-unquoted) inner command and returns 0; returns 1 otherwise.
git_extract_sh_c_inner() {
  _raw=$1
  _raw=$(printf '%s' "$_raw" | sed 's/^[[:space:]]*//')
  # Strip leading VAR=value assignments (POSIX env-var prefix).
  while :; do
    _pre=$_raw
    _raw=$(printf '%s' "$_raw" | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]][[:space:]]*//')
    [ "$_raw" = "$_pre" ] && break
  done
  # First word must be sh / bash / absolute path to one.
  case "$_raw" in
    sh\ *|bash\ *|/bin/sh\ *|/bin/bash\ *|/usr/bin/sh\ *|/usr/bin/bash\ *) ;;
    *) return 1 ;;
  esac
  # Find first occurrence of " -c " anywhere after the shell name.
  case "$_raw" in
    *" -c "*) ;;
    *) return 1 ;;
  esac
  _inner=${_raw#* -c }
  _inner=$(printf '%s' "$_inner" | sed 's/^[[:space:]]*//')
  # Strip a single layer of wrapping quotes.
  case "$_inner" in
    \"*\") _inner=${_inner#\"}; _inner=${_inner%\"} ;;
    \'*\') _inner=${_inner#\'}; _inner=${_inner%\'} ;;
  esac
  _dash_c_inner=$_inner
  return 0
}

# git_peel_timeout_wrapper <raw> — detect a leading `timeout` or `gtimeout`
# wrapper (and its options / duration) at the raw-string level. On a match,
# returns the real inner command on stdout. If the first word is not
# timeout/gtimeout, returns the original string unchanged. Preserves leading
# VAR=value assignments and any quoting around the wrapper token.
git_peel_timeout_wrapper() {
  _pt_raw=$1

  # Trim leading whitespace.
  _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')

  # Capture leading VAR=value assignments (no spaces inside the assignment).
  # They belong to the inner command; the guard's existing env-prefix handler
  # will strip them itself.
  _pt_env=""
  while :; do
    _pt_assign=$(printf '%s' "$_pt_raw" | sed -n 's/^\([A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*\)[[:space:]].*/\1/p')
    if [ -z "$_pt_assign" ]; then break; fi
    case "$_pt_raw" in
      "$_pt_assign"*) ;;
      *) break ;;
    esac
    _pt_env="$_pt_env $_pt_assign"
    _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]][[:space:]]*//')
    _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')
  done

  # First word must be timeout/gtimeout (possibly absolute path, possibly quoted).
  _pt_first=${_pt_raw%%[[:space:]]*}
  _pt_first_raw=$_pt_first
  case "$_pt_first" in
    \"*) _pt_first=$(printf '%s' "$_pt_first" | sed 's/^"\(.*\)"$/\1/') ;;
    \'*) _pt_first=$(printf '%s' "$_pt_first" | sed "s/^'\(.*\)'$/\1/") ;;
  esac
  case "$_pt_first" in
    timeout|gtimeout|*/timeout|*/gtimeout) ;;
    *) printf '%s' "$1"; return ;;
  esac

  # Remove the ORIGINAL (possibly quoted) first token.
  _pt_raw=${_pt_raw#"$_pt_first_raw"}
  _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')

  # Skip timeout options. Stop when we consume the required duration argument.
  _pt_done=0
  while [ -n "$_pt_raw" ] && [ "$_pt_done" = 0 ]; do
    _pt_tok=${_pt_raw%%[[:space:]]*}
    _pt_tok_raw=$_pt_tok
    case "$_pt_tok" in
      \"*) _pt_tok=$(printf '%s' "$_pt_tok" | sed 's/^"\(.*\)"$/\1/') ;;
      \'*) _pt_tok=$(printf '%s' "$_pt_tok" | sed "s/^'\(.*\)'$/\1/") ;;
    esac

    case "$_pt_tok" in
      --)
        # End-of-options marker: consume it and continue so the next token is
        # treated as the required duration, then the rest is the command.
        _pt_raw=${_pt_raw#"$_pt_tok_raw"}
        _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')
        ;;
      -k|--kill-after|-s|--signal)
        _pt_raw=${_pt_raw#"$_pt_tok_raw"}
        _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')
        # Skip the option's argument if present.
        if [ -n "$_pt_raw" ]; then
          _pt_arg=${_pt_raw%%[[:space:]]*}
          _pt_raw=${_pt_raw#"$_pt_arg"}
          _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')
        fi
        ;;
      --kill-after=*|--signal=*)
        _pt_raw=${_pt_raw#"$_pt_tok_raw"}
        _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')
        ;;
      --preserve-status|--foreground)
        _pt_raw=${_pt_raw#"$_pt_tok_raw"}
        _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')
        ;;
      -*)
        _pt_raw=${_pt_raw#"$_pt_tok_raw"}
        _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')
        ;;
      *)
        # Required duration argument. Consume it; everything after is the command.
        _pt_raw=${_pt_raw#"$_pt_tok_raw"}
        _pt_raw=$(printf '%s' "$_pt_raw" | sed 's/^[[:space:]]*//')
        _pt_done=1
        ;;
    esac
  done

  # Re-prefix env assignments so the inner command still looks like a normal
  # shell invocation to the guard's existing env-prefix handler.
  if [ -n "$_pt_env" ]; then
    _pt_raw=$(printf '%s %s' "$_pt_env" "$_pt_raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  # If the inner command is still wrapped, recurse to peel nested wrappers.
  _pt_first=${_pt_raw%%[[:space:]]*}
  case "$_pt_first" in
    \"*) _pt_first=$(printf '%s' "$_pt_first" | sed 's/^"\(.*\)"$/\1/') ;;
    \'*) _pt_first=$(printf '%s' "$_pt_first" | sed "s/^'\(.*\)'$/\1/") ;;
  esac
  case "$_pt_first" in
    timeout|gtimeout|*/timeout|*/gtimeout)
      git_peel_timeout_wrapper "$_pt_raw" ;;
    *)
      printf '%s' "$_pt_raw" ;;
  esac
}

# git_extract_remote_inner <raw> — detect `ssh <host> <inner>` and
# `agents|ag ssh <host> <inner>` at the raw-string level, before token splitting
# can shred a quoted inner command. On a match, sets _remote_host and
# _remote_inner (one-layer-unquoted) and returns 0. SSH transport flags before
# the host are skipped; flags whose next token is an argument consume it too.
git_extract_remote_inner() {
  _rr=$1
  _rr=$(printf '%s' "$_rr" | sed 's/^[[:space:]]*//')
  while :; do
    _pre=$_rr
    _rr=$(printf '%s' "$_rr" | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*[[:space:]][[:space:]]*//')
    [ "$_rr" = "$_pre" ] && break
  done
  case "$_rr" in
    agents\ ssh\ *) _rr=${_rr#agents ssh } ;;
    ag\ ssh\ *)     _rr=${_rr#ag ssh } ;;
    ssh\ *)         _rr=${_rr#ssh } ;;
    */ssh\ *)       _rr=${_rr#*/ssh } ;;
    *) return 1 ;;
  esac
  _rr=$(printf '%s' "$_rr" | sed 's/^[[:space:]]*//')
  while [ -n "$_rr" ]; do
    _rw=${_rr%%[[:space:]]*}
    if [ "$_rw" = "$_rr" ]; then _rr=''; else _rr=${_rr#"$_rw"}; fi
    _rr=$(printf '%s' "$_rr" | sed 's/^[[:space:]]*//')
    case "$_rw" in
      -b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-O|-o|-p|-Q|-R|-S|-W|-w)
        [ -n "$_rr" ] || return 1
        _ra=${_rr%%[[:space:]]*}
        if [ "$_ra" = "$_rr" ]; then _rr=''; else _rr=${_rr#"$_ra"}; fi
        _rr=$(printf '%s' "$_rr" | sed 's/^[[:space:]]*//') ;;
      --) ;;
      -*) ;;
      *)
        _remote_host=$(git_unwrap_quotes "$_rw")
        [ -n "$_rr" ] || return 1
        # Split at the MATCHING close quote. `${_rr%\'}` only strips a trailing
        # quote when the string ENDS with one, so anything after the remote
        # command — notably a redirection belonging to the OUTER, local shell —
        # was swallowed into _remote_inner and judged against the remote host.
        # Real case, 2026-08-27:
        #   agents ssh win-mini 'type ...' > /local/scratch/out.yaml
        # was denied as a write to 'win-mini:~/...'. That redirect captures the
        # ssh command's stdout on THIS machine; it is not a remote write at all.
        # _remote_outer_rest carries the remainder back for local scanning.
        _remote_outer_rest=''
        case "$_rr" in
          \"*) _rt=${_rr#\"}; _remote_inner=${_rt%%\"*}
                 case "$_rt" in *\"*) _remote_outer_rest=${_rt#*\"} ;; esac ;;
          \'*) _rt=${_rr#\'}; _remote_inner=${_rt%%\'*}
                 case "$_rt" in *\'*) _remote_outer_rest=${_rt#*\'} ;; esac ;;
          *)     _remote_inner=$_rr ;;
        esac
        return 0 ;;
    esac
  done
  return 1
}

# git_unwrap_quotes <token> — strip ONE layer of matching single or double
# quotes from a token (`"git"` -> git, `'/tmp/x'` -> /tmp/x); prints the token
# unchanged when it is not wholly quote-wrapped. Used for the first token and
# for a quoted `-C <path>` argument.
git_unwrap_quotes() {
  case "$1" in
    \"*\") printf '%s' "$1" | sed 's/^"\(.*\)"$/\1/' ;;
    \'*\') printf '%s' "$1" | sed "s/^'\(.*\)'\$/\1/" ;;
    *) printf '%s' "$1" ;;
  esac
}

# git_split_chains <cmd> — split a command string on chain operators and real
# newlines OUTSIDE quotes. Quoted remote/shell inner commands must stay whole so
# their raw-level extractor sees the complete string before recursion.
git_split_chains() {
  printf '%s\n' "$1" | awk '
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      out = ""; sq = 0; dq = 0; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1); n = substr(s, i + 1, 1)
        if (esc) { out = out c; esc = 0; continue }
        if (c == "\\" && !sq) { out = out c; esc = 1; continue }
        if (c == sprintf("%c", 39) && !dq) { sq = !sq; out = out c; continue }
        if (c == "\"" && !sq) { dq = !dq; out = out c; continue }
        if (!sq && !dq && (c == "\n" || c == ";" || (c == "|" && substr(s, i - 1, 1) != ">") || (c == "&" && n == "&"))) {
          print out; out = ""
          if ((c == "|" && n == "|") || (c == "&" && n == "&")) i++
          continue
        }
        out = out c
      }
      print out
    }
  '
}

# git_scan_segment <segment> — reduce ONE already-split segment to the git
# invocation it runs, then dispatch to the consumer's `git_on_command` callback.
#
# Steps (the machinery every guard shared): skip leading `VAR=value` env
# assignments; unwrap the first token; require it to be `git` or `*/git`
# (non-git segment -> return 0, allow); peel git's global flags, capturing any
# `-C <path>` argument (one-layer-unquoted) into the global GIT_C_PATH; then call
#   git_on_command <subcommand> <remaining-args...>
# and return that callback's rc. Returns 0 (allow) for a non-git or bare-git
# segment. GIT_C_PATH is reset to '' on entry and set before the callback fires,
# so a consumer that resolves a `-C` target reads it; guards that ignore the
# target simply never look at it.
#
# The `sh|bash -c` wrapper is intentionally NOT handled here: the inner-string
# policy (recurse vs. its own recursion path) differs per guard, so the caller
# runs git_extract_sh_c_inner itself BEFORE calling this.
git_scan_segment() {
  GIT_C_PATH=''
  # Restore default IFS so `set -- $1` splits on space/tab/newline. The caller
  # flipped IFS to newline-only to iterate chain segments.
  unset IFS
  # shellcheck disable=SC2086
  set -- $1

  # Skip leading VAR=value assignments.
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && return 0

  # First token may be: git | /path/to/git | "git" | 'git'.
  _first=$(git_unwrap_quotes "$1")
  case "$_first" in
    git|*/git) ;;
    *) return 0 ;;
  esac
  shift

  # Peel git's global flags before the subcommand; capture -C <path>.
  while [ $# -gt 0 ]; do
    case "$1" in
      -C)            shift
                     if [ $# -gt 0 ]; then
                       GIT_C_PATH=$(git_unwrap_quotes "$1"); shift
                     fi ;;
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

  _sub=$1
  shift
  git_on_command "$_sub" "$@"
}

# write_scan_segment <segment> — surface direct filesystem write destinations
# in one already-split shell segment through the consumer callback:
#   write_on_destination <kind> <destination> <remote-host>
# WRITE_REMOTE_HOST is supplied by a recursive remote-command consumer; empty
# means the command runs locally. This scanner deliberately contains no repo,
# branch, allowlist, or deny policy.
_write_extract_redirects() {
  # Character scan keeps `>` inside quoted prose/data from becoming a phantom
  # destination. It also returns every real redirection in the segment rather
  # than only the final one. One-layer shell quotes around a target are removed.
  # Quote and escape state PERSIST ACROSS LINES. Resetting them per record was a
  # false-positive factory: the second line of any multi-line quoted argument — a
  # commit message, a PR body, a ticket description — reopened as "unquoted", so
  # an arrow in ordinary prose read as a redirection and the guard blocked a
  # write that never existed. A guard that blocks a non-existent write gets
  # switched off, which is strictly worse than no guard.
  awk '
    BEGIN { sq = 0; dq = 0; esc = 0 }
    {
      s = $0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (esc) { esc = 0; continue }
        if (c == "\\" && !sq) { esc = 1; continue }
        if (c == sprintf("%c", 39) && !dq) { sq = !sq; continue }
        if (c == "\"" && !sq) { dq = !dq; continue }
        if (c != ">" || sq || dq) continue
        # `<<` is a heredoc (stripped upstream) and a lone `<` is a READ; neither
        # yields a write destination.
        if (i > 1 && substr(s, i - 1, 1) == "<") continue
        if (substr(s, i + 1, 1) == ">") i++
        else if (substr(s, i + 1, 1) == "|") i++
        j = i + 1
        while (j <= length(s) && substr(s, j, 1) ~ /[ \t]/) j++
        out = ""; osq = 0; odq = 0; oesc = 0
        for (; j <= length(s); j++) {
          d = substr(s, j, 1)
          if (oesc) { out = out d; oesc = 0; continue }
          if (d == "\\" && !osq) { oesc = 1; continue }
          if (d == sprintf("%c", 39) && !odq) { osq = !osq; continue }
          if (d == "\"" && !osq) { odq = !odq; continue }
          if (!osq && !odq && d ~ /[ \t|;&]/) break
          out = out d
        }
        if (out != "") print out
        i = j
      }
    }
  '
}

# _write_tokenize <segment> — emit one shell-like argv token per line, retaining
# spaces inside quotes and removing one syntactic quote/backslash layer. This is
# intentionally expansion-free: command substitutions and variables remain
# literal and cannot execute inside a guard.
_write_tokenize() {
  printf '%s\n' "$1" | awk '
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      tok = ""; sq = 0; dq = 0; esc = 0; have = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (esc) { tok = tok c; esc = 0; have = 1; continue }
        if (c == "\\" && !sq) { esc = 1; have = 1; continue }
        if (c == sprintf("%c", 39) && !dq) { sq = !sq; have = 1; continue }
        if (c == "\"" && !sq) { dq = !dq; have = 1; continue }
        if (!sq && !dq && c ~ /[ \t\n]/) {
          if (have) { print tok; tok = ""; have = 0 }
          continue
        }
        tok = tok c; have = 1
      }
      if (have) print tok
    }
  '
}

write_scan_segment() {
  _ws_raw=$1
  _ws_remote=${WRITE_REMOTE_HOST:-}

  # Redirections are syntax, not argv. Heredoc bodies are removed by the
  # consumer before chain splitting.
  _ws_oldifs=${IFS-}
  IFS='
'
  for _ws_redir in $(printf '%s\n' "$_ws_raw" | _write_extract_redirects); do
    IFS=$_ws_oldifs
    write_on_destination redirect "$_ws_redir" "$_ws_remote" || return $?
    IFS='
'
  done
  IFS=$_ws_oldifs

  _ws_oldifs=${IFS-}
  IFS='
'
  # shellcheck disable=SC2046
  set -- $(_write_tokenize "$_ws_raw")
  IFS=$_ws_oldifs
  while [ $# -gt 0 ]; do case "$1" in *=*) shift ;; *) break ;; esac; done
  [ $# -gt 0 ] || return 0
  _ws_cmd=$(git_unwrap_quotes "$1")
  shift
  # Peel ordinary execution wrappers without evaluating any string. These do
  # not change the filesystem destination of the wrapped command.
  while :; do
    case "$_ws_cmd" in
      command)
        while [ $# -gt 0 ]; do case "$1" in --) shift; break ;; -*) shift ;; *) break ;; esac; done ;;
      exec)
        while [ $# -gt 0 ]; do
          case "$1" in
            --) shift; break ;;
            -?*)
              _ws_exec_cluster=${1#-}; _ws_exec_needs_arg=0
              while [ -n "$_ws_exec_cluster" ]; do
                _ws_exec_ch=${_ws_exec_cluster%"${_ws_exec_cluster#?}"}
                _ws_exec_cluster=${_ws_exec_cluster#?}
                case "$_ws_exec_ch" in
                  a) [ -z "$_ws_exec_cluster" ] && _ws_exec_needs_arg=1
                     _ws_exec_cluster='' ;;
                esac
              done
              shift
              if [ "$_ws_exec_needs_arg" -eq 1 ] && [ $# -gt 0 ]; then shift; fi ;;
            *) break ;;
          esac
        done ;;
      nohup|unbuffer)
        while [ $# -gt 0 ]; do case "$1" in --) shift; break ;; -*) shift ;; *) break ;; esac; done ;;
      caffeinate)
        while [ $# -gt 0 ]; do
          case "$1" in --) shift; break ;; -t|-w) shift; [ $# -gt 0 ] && shift ;; -*) shift ;; *) break ;; esac
        done ;;
      time)
        while [ $# -gt 0 ]; do
          case "$1" in --) shift; break ;; -o|-f|--output|--format) shift; [ $# -gt 0 ] && shift ;; -*) shift ;; *) break ;; esac
        done ;;
      env)
        while [ $# -gt 0 ]; do
          case "$1" in
            --) shift; break ;;
            -u|-C|-S|-P|--unset|--chdir|--split-string) shift; [ $# -gt 0 ] && shift ;;
            --unset=*|--chdir=*|--split-string=*|-u?*|-C?*|-S?*|-*|*=*) shift ;;
            *) break ;;
          esac
        done ;;
      *) break ;;
    esac
    [ $# -gt 0 ] || return 0
    _ws_cmd=$(git_unwrap_quotes "$1")
    shift
  done
  case "$_ws_cmd" in
    cd)
      while [ $# -gt 0 ]; do
        case "$1" in --) shift; break ;; -*) shift ;; *) break ;; esac
      done
      [ $# -gt 0 ] || return 0
      _ws_dest=$(git_unwrap_quotes "$1")
      case "$_ws_dest" in
        /*|[A-Za-z]:/*|'~/'*) WRITE_DEST_CWD=$_ws_dest ;;
        *) WRITE_DEST_CWD=${WRITE_DEST_CWD:-.}/$_ws_dest ;;
      esac
      return 0 ;;
    tee|*/tee)
      for _ws_arg in "$@"; do
        case "$_ws_arg" in -*) ;; *)
          write_on_destination tee "$_ws_arg" "$_ws_remote" || return $? ;;
        esac
      done
      ;;
    scp|*/scp|rsync|*/rsync|cp|*/cp|mv|*/mv|install|*/install)
      case "$_ws_cmd" in
        install|*/install)
          _ws_install_dirs=0
          _ws_install_expect=0
          _ws_install_options=1
          _ws_install_operands=''
          for _ws_arg in "$@"; do
            if [ "$_ws_install_expect" -eq 1 ]; then _ws_install_expect=0; continue; fi
            if [ "$_ws_install_options" -eq 0 ]; then
              _ws_install_operands="${_ws_install_operands}
$_ws_arg"
              continue
            fi
            case "$_ws_arg" in
              --) _ws_install_options=0; continue ;;
              --directory) _ws_install_dirs=1; continue ;;
              --group|--mode|--owner|--suffix|--target-directory)
                _ws_install_expect=1; continue ;;
              --group=*|--mode=*|--owner=*|--suffix=*|--target-directory=*|--*) continue ;;
              -?*)
                _ws_cluster=${_ws_arg#-}
                while [ -n "$_ws_cluster" ]; do
                  _ws_ch=${_ws_cluster%"${_ws_cluster#?}"}
                  _ws_cluster=${_ws_cluster#?}
                  case "$_ws_ch" in
                    d) _ws_install_dirs=1 ;;
                    B|f|g|m|M|o|S|t)
                      if [ -z "$_ws_cluster" ]; then _ws_install_expect=1; fi
                      _ws_cluster='' ;;
                  esac
                done
                continue ;;
            esac
            _ws_install_operands="${_ws_install_operands}
$_ws_arg"
          done
          if [ "$_ws_install_dirs" -eq 1 ]; then
            _ws_saved_ifs=${IFS-}; IFS='
'
            for _ws_arg in $_ws_install_operands; do
              IFS=$_ws_saved_ifs
              write_on_destination install "$_ws_arg" "$_ws_remote" || return $?
              IFS='
'
            done
            IFS=$_ws_saved_ifs
            return 0
          fi ;;
      esac
      _ws_dest=''
      _ws_need_target=0
      _ws_target_mode=0
      for _ws_arg in "$@"; do
        if [ "$_ws_need_target" -eq 1 ]; then
          _ws_dest=$_ws_arg; _ws_need_target=0; _ws_target_mode=1; continue
        fi
        case "$_ws_arg" in
          -t|--target-directory) _ws_need_target=1 ;;
          -t?*) _ws_dest=${_ws_arg#-t}; _ws_target_mode=1 ;;
          --target-directory=*) _ws_dest=${_ws_arg#*=}; _ws_target_mode=1 ;;
          -*) ;;
          *) [ "$_ws_target_mode" -eq 1 ] || _ws_dest=$_ws_arg ;;
        esac
      done
      [ -n "$_ws_dest" ] || return 0
      _ws_dest=$(git_unwrap_quotes "$_ws_dest")
      write_on_destination "${_ws_cmd##*/}" "$_ws_dest" "$_ws_remote" || return $?
      ;;
  esac
  return 0
}
