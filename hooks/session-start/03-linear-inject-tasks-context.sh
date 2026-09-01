#!/bin/bash
# SessionStart hook: inject Linear context at start —
#   team/agents · every project (milestones + top open tickets) · active cycle.
#
# Credentials: ONLY the Linear CLI's plaintext config at
#   ~/.linear-cli/config.json  (apiKey + teamId, 0600, written by `linear setup`)
# or LINEAR_API_KEY + LINEAR_TEAM_ID already in the env.
#
# NEVER uses `agents secrets`, the keychain, Touch ID, or any secrets bundle —
# a SessionStart hook must not pop biometry or hang (macOS/Linux/Windows). The
# LINEAR_CLI_CONFIG env var overrides the config path for tests.
#
# Layout of the injection (token-budgeted brief, not a full board dump):
#   1. Team & Agents
#   2. Projects — every non-canceled/completed project, cwd-matched first,
#      each with milestones + top open tickets (priority-sorted)
#   3. Active cycle — Your Tasks first (scoped to the cwd's project when one is
#      matched, with a cross-project pointer for the rest), then open work
#      grouped by project

# Which agent/harness is running this hook (for the "Your Tasks" bucket). The
# script's own path names the agent on every launch path; AGENT_SELF overrides.
self_path=$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
AGENT_SELF="${AGENT_SELF:-$(printf '%s' "$self_path" | sed -n 's#.*/versions/\([^/]*\)/.*#\1#p')}"
export AGENT_SELF="${AGENT_SELF:-claude}"
# The name is interpolated into a GraphQL string literal below AND printed into
# every session's injected context. It comes from a path segment or the
# environment, so strip anything that isn't a plain agent name — otherwise a
# hostile value injects either query syntax or arbitrary text (newlines included)
# into the prompt. Everything downstream reads the sanitized value.
AGENT_SELF_SAFE=$(printf '%s' "$AGENT_SELF" | tr -cd 'A-Za-z0-9_-')
export AGENT_SELF_SAFE="${AGENT_SELF_SAFE:-claude}"

# Portable timeout. macOS ships neither `timeout` nor `gtimeout`, and the old
# fallback here ran the command BARE — so on every Mac on this fleet nothing was
# bounded at all, and a hung call took the whole hook past its manifest timeout,
# which delivers zero bytes rather than a degraded brief. Emulate it instead:
# run the command in the background with a watchdog that kills it.
#
# The watchdog's own output is discarded so a command substitution around this
# closes when the command does, not when the watchdog does.
# Emulation runs through python3, which this hook already hard-depends on, not
# through bash job control. Two things the obvious bash version gets wrong:
# killing the child's pid leaves ITS children holding the pipe (a `$(...)` then
# still blocks for the full duration), and a backgrounded job silently loses
# stdin. `start_new_session` + `killpg` kills the whole subtree, and the
# std streams are inherited.
_to() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  command -v python3 >/dev/null 2>&1 || { "$@"; return $?; }
  python3 -c '
import os, signal, subprocess, sys
secs = float(sys.argv[1])
try:
    p = subprocess.Popen(sys.argv[2:], start_new_session=True)
except (FileNotFoundError, PermissionError):
    sys.exit(127)
try:
    sys.exit(p.wait(timeout=secs))
except subprocess.TimeoutExpired:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(os.getpgid(p.pid), sig)
        except Exception:
            pass
        try:
            p.wait(timeout=1)
            break
        except Exception:
            continue
    sys.exit(124)
' "$secs" "$@"
}

# Which Linear project is this cwd? `agents projects` owns that mapping — a def
# under ~/.agents/projects/<name>.yaml binds a root, its repos[].path entries,
# and a `linear.projectId`/`linear.name`. Ask the CLI rather than re-deriving it:
# `projects view <dir>` does longest-match over every bound root and monorepo
# subpath, so a worktree, a subdir, and two projects sharing one monorepo root
# all resolve correctly — none of which a basename comparison can do.
#
# Cost: one CLI call, measured 0.28-0.31s on an idle box. The brief below
# already budgets 8s of curl and the lane sweep up to 3s against a `timeout: 15`
# manifest cap, so ~0.3s here stays inside the remaining headroom. It is
# bounded and fails open — no `agents` on PATH, no def for this cwd, or a slow
# call just leaves the fields empty and the basename fallback takes over.
CWD_PROJECT_NAME=""
OTHER_PROJECT_NAMES=""
if command -v agents >/dev/null 2>&1; then
  # One call: `projects view . --json` longest-matches the cwd to a def and
  # returns {name, linear:{name, projectId}, root}. We want linear.name — the
  # board label ("AGI"), what the project rows below match on. Several defs may
  # point at one Linear project, so the board name is the right key.
  CWD_PROJECT_NAME=$(_to 3 agents projects view . --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin) or {}
    print(((d.get("linear") or {}).get("name")) or "")
except Exception:
    pass
' 2>/dev/null || true)
fi
export CWD_PROJECT_NAME

# The basename fuzz stays armed even when the def resolved. It is the fallback
# for two cases, and disabling it on a merely-PRESENT linear.name failed closed:
# a def whose recorded name no longer matches any live project (the CLI only
# started refreshing it in 1.22.40, so every older def carries a stale label)
# expanded NOTHING and claimed no def existed. Python prefers the exact match
# and only falls back when it finds no project by that name.
# Git repo name first (stable across subdirs), then the raw cwd basename; python
# normalizes both ("agents-cli" and "Agents CLI" -> "agentscli").
git_root=$(git rev-parse --show-toplevel 2>/dev/null)
export CWD_PROJECT_HINTS="$(basename "$git_root" 2>/dev/null),$(basename "$PWD" 2>/dev/null)"

# Resolve credentials: env first, then ~/.linear-cli/config.json. No secrets
# broker, no keychain — so this can never pop Touch ID or hang.
if [ -z "$LINEAR_API_KEY" ] || [ -z "$LINEAR_TEAM_ID" ]; then
  cfg="${LINEAR_CLI_CONFIG:-$HOME/.linear-cli/config.json}"
  if [ -f "$cfg" ]; then
    eval "$(python3 -c '
import json, os, shlex, sys
try:
    c = json.load(open(os.path.expanduser(sys.argv[1])))
except Exception:
    sys.exit(0)
if not os.environ.get("LINEAR_API_KEY") and c.get("apiKey"):
    print("LINEAR_API_KEY=" + shlex.quote(c["apiKey"]))
if not os.environ.get("LINEAR_TEAM_ID") and c.get("teamId"):
    print("LINEAR_TEAM_ID=" + shlex.quote(c["teamId"]))
' "$cfg" 2>/dev/null)"
  fi
  if [ -z "$LINEAR_API_KEY" ] || [ -z "$LINEAR_TEAM_ID" ]; then
    echo "Linear context skipped (no credentials): run 'linear setup' once (writes ~/.linear-cli/config.json), or export LINEAR_API_KEY + LINEAR_TEAM_ID."
    exit 0
  fi
fi
export LINEAR_API_KEY LINEAR_TEAM_ID

# One round trip: users, every team project (milestones + top open issues),
# and the active-cycle board with project on each issue. Build the JSON body
# in Python to sidestep GraphQL-in-bash quoting.
QUERY='{
  users(first: 250) { nodes { displayName name email active app guest } }
  team(id: "'"$LINEAR_TEAM_ID"'") {
    projects(first: 50) {
      nodes {
        name state progress
        projectMilestones(first: 20) { nodes { name targetDate progress sortOrder } }
        issues(first: 8, filter: { state: { type: { nin: ["completed", "canceled"] } } }) {
          nodes { identifier title priority state { name type } assignee { displayName } }
        }
      }
    }
    myOpenIssues: issues(first: 100, filter: {
      state: { type: { nin: ["completed", "canceled"] } }
      cycle: { isActive: { eq: true } }
      delegate: { name: { eqIgnoreCase: "'"$AGENT_SELF_SAFE"'" } }
    }) {
      nodes {
        identifier title description state { name type } priority
        assignee { name }
        delegate { name }
        labels { nodes { name } }
        project { name }
        updatedAt
      }
      pageInfo { hasNextPage }
    }
    activeCycle {
      name startsAt endsAt
      issues(first: 250, filter: { state: { type: { nin: ["completed", "canceled"] } } }) {
        pageInfo { hasNextPage }
        nodes {
          identifier title description state { name type } priority
          assignee { name }
          delegate { name }
          labels { nodes { name } }
          project { name }
          updatedAt
        }
      }
    }
  }
}'
BODY=$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$QUERY")

# Self-bounded: without --max-time the only limit is the harness's own hook timeout,
# so a reachable-but-slow Linear API would stall every SessionStart on every harness.
result=$(curl -s --connect-timeout 3 --max-time 8 -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  -d "$BODY" 2>/dev/null)

# The "other agent lanes" counts need the WHOLE active cycle, and Linear caps a
# page at 250 — this workspace already has more open than that, so counting from
# the page above understated every lane and dropped some entirely. This second
# request asks only for delegate names, so it is small and fast (~0.5s against
# the 8s budget). Strictly additive: any failure leaves LANES empty and the
# python block falls back to counting the page, saying so.
# Budget: this hook is registered with `timeout: 15` in agents.yaml, and the
# brief above already claims 8 of those seconds. The sweep gets 3 pages at 1s —
# 11s of network worst case, leaving ~4s for the script's own work.
#
# That headroom is not slack. The timeout covers wall-clock, not just curl, and
# this script spawns up to nine python3 interpreters: ~0.85s on an idle box and
# ~1.2s under contention, which is exactly when SessionStart runs. A budget that
# merely fits inside 15s on paper gets killed in practice.
#
# And a kill is not a degraded brief — the sweep runs BEFORE anything prints, so
# overrunning delivers zero bytes. A slow or oversized workspace instead falls
# back to counting the cycle page, which says so. Live sweep pages measure
# 0.23-0.26s, so 1s is still ~4x headroom.
LANES=""
lanes_cursor="null"
for _ in 1 2 3; do
  lq='{ team(id: "'"$LINEAR_TEAM_ID"'") { activeCycle { issues(first: 250, after: '"$lanes_cursor"', filter: { state: { type: { nin: ["completed", "canceled"] } } }) { nodes { delegate { name } } pageInfo { hasNextPage endCursor } } } } }'
  lbody=$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$lq" 2>/dev/null) || break
  lpage=$(curl -s --connect-timeout 1 --max-time 1 -X POST https://api.linear.app/graphql \
    -H "Content-Type: application/json" -H "Authorization: $LINEAR_API_KEY" \
    -d "$lbody" 2>/dev/null) || break
  read -r lnames lnext < <(printf '%s' "$lpage" | python3 -c "
import json, sys
try:
    conn = json.load(sys.stdin)['data']['team']['activeCycle']['issues']
except Exception:
    print('! !'); raise SystemExit
names = [((n.get('delegate') or {}).get('name') or '') for n in conn.get('nodes', [])]
info = conn.get('pageInfo') or {}
cur = info.get('endCursor') if info.get('hasNextPage') else ''
print('|'.join(x for x in names if x) or '-', cur or '-')
" 2>/dev/null) || break
  [ "$lnames" = "!" ] && { LANES=""; break; }
  [ "$lnames" != "-" ] && LANES="$LANES|$lnames"
  [ "$lnext" = "-" ] && { LANES="${LANES}|COMPLETE"; break; }
  lanes_cursor="\"$lnext\""
done
export LANES

echo "$result" | python3 -c "
import json, sys, os, re

# Sanitized upstream: this is printed into the injected context, so it must not
# be able to carry newlines or markup.
SELF = os.environ.get('AGENT_SELF_SAFE') or 'claude'
HINTS = [h for h in os.environ.get('CWD_PROJECT_HINTS', '').split(',') if h.strip()]
# Set when \`agents projects\` resolved this cwd to a def carrying a linear.name.
# Authoritative when present: HINTS is then empty and the fuzz never runs.
CWD_PROJECT = (os.environ.get('CWD_PROJECT_NAME') or '').strip()

def norm(s):
    return re.sub(r'[^a-z0-9]', '', (s or '').lower())

PRIORITY = {0: 'None', 1: 'Urgent', 2: 'High', 3: 'Medium', 4: 'Low'}

def pri_rank(n):
    # Linear priority: 1=Urgent .. 4=Low, and 0 means 'no priority set'. Sorting
    # on the raw value put unprioritized issues ABOVE Urgent ones; Your Tasks is
    # capped, so that hid real work. 0 and null both rank last, matching
    # linear-cli's issue_sort_key.
    p = n.get('priority')
    return p if p else 4

def pct_str(prog):
    # Linear project progress is 0..1; some milestone fields arrive already as percent.
    if not isinstance(prog, (int, float)):
        return None
    if prog > 1.0:
        return f'{round(prog)}%'
    return f'{round(prog * 100)}%'

def capped(rendered, cap):
    if len(rendered) <= cap:
        return ', '.join(rendered)
    return ', '.join(rendered[:cap]) + f', +{len(rendered) - cap} more'

def fmt_issue_line(n, with_desc=False, with_project=False):
    ident = n.get('identifier') or '?'
    title = n.get('title') or ''
    state = (n.get('state') or {}).get('name', '')
    pri = PRIORITY.get(n.get('priority', 0), 'None')
    labels = n.get('_other_labels') or []
    assignee = n.get('assignee') or {}
    who = assignee.get('displayName') or assignee.get('name') or ''
    parts = [f'**{ident}**', f'({pri}, {state})']
    if with_project:
        pname = (n.get('project') or {}).get('name')
        if pname:
            parts.append(f'{{{pname}}}')
    if labels:
        parts.append('[' + ', '.join(labels) + ']')
    if who:
        parts.append(f'@{who}')
    parts.append(f': {title}')
    line = '- ' + ' '.join(parts)
    if with_desc:
        desc = n.get('description') or ''
        if desc:
            short = desc[:160].replace(chr(10), ' ')
            if len(desc) > 160:
                short += '...'
            line += f'\n  > {short}'
    return line

try:
    data = json.load(sys.stdin)
    # GraphQL error / empty payload
    if not data.get('data'):
        err = data.get('errors')
        if err:
            print(f'Linear query failed: {err[0].get(\"message\", err)}')
        else:
            print('Linear query failed: empty response')
        sys.exit(0)

    team = data.get('data', {}).get('team') or {}

    # -- Team & Agents ----------------------------------------------------
    users = (data.get('data', {}).get('users') or {}).get('nodes', [])
    humans, agents = [], []
    for u in users:
        if not u.get('active', True):
            continue
        email = u.get('email') or ''
        name = u.get('displayName') or u.get('name') or 'unknown'
        if u.get('app'):
            if email.endswith('@linear.linear.app') or name == 'linear':
                continue
            agents.append(name)
        elif not u.get('guest'):
            humans.append((name, email))

    if humans or agents:
        print('## Team & Agents')
        if humans:
            rows = [f'{n} ({e})' if e else n for n, e in sorted(humans, key=lambda x: x[0].lower())]
            print(f'**Humans ({len(humans)}):** {capped(rows, 15)}')
        if agents:
            names = sorted(set(agents), key=str.lower)
            print(f'**Agent members ({len(names)}, assignable):** {capped(names, 20)}')
        print()

    # -- Projects (all) + milestones + top open tickets -------------------
    projects = (team.get('projects') or {}).get('nodes', [])
    # Drop finished projects; keep backlog/started/planned.
    live_projects = [
        p for p in projects
        if (p.get('state') or '').lower() not in ('completed', 'canceled', 'cancelled')
    ]
    hint_norms = [norm(h) for h in HINTS if norm(h)]

    def exact_match(p):
        # The recorded link. Exact only: this is not a guess, so widening it
        # could only add false matches.
        return bool(CWD_PROJECT) and norm(p.get('name')) == norm(CWD_PROJECT)

    def fuzzy_match(p):
        pn = norm(p.get('name'))
        if pn in hint_norms:
            return True
        for hn in hint_norms:
            if len(hn) >= 4 and (hn in pn or pn in hn):
                return True
        return False

    # Prefer the recorded link, but only when it actually names a live project.
    # A def carrying a name the board no longer uses must degrade to the guess,
    # not to nothing — that was the fail-closed bug.
    _matcher = exact_match if any(exact_match(p) for p in live_projects) else fuzzy_match

    def is_cwd_match(p):
        return _matcher(p)

    # cwd-matched project first, then the rest alphabetically.
    focus = [p for p in live_projects if is_cwd_match(p)]
    rest = sorted(
        [p for p in live_projects if not is_cwd_match(p)],
        key=lambda p: (p.get('name') or '').lower(),
    )
    ordered = focus + rest

    if ordered:
        print(f'## Projects ({len(ordered)})')
        # Depth goes to the project this cwd belongs to; the rest are one line
        # each. Printing every project in full was ~13.8KB of injected context
        # per session, most of it about work this session cannot touch.
        if focus:
            print(f'_Depth on **{focus[0].get(\"name\")}** (this working directory). Others are one line — \`linear tasks --project <name> --by-milestone\` for detail._')
        else:
            # Nothing claims this directory: fail OPEN to the old full listing.
            # Collapsing every project here would leave a session with no board
            # context at all, which is strictly worse than the pre-scoping brief.
            print('_Each project: milestones, then top open tickets by priority. Full board: linear tasks --project <name> --by-milestone._')
        print()
        for p in ordered:
            name = p.get('name') or 'unnamed'
            pct = pct_str(p.get('progress')) or '?'
            state = p.get('state') or ''
            # \`focus and\` keeps the no-focus case on the full listing, matching
            # the cycle section below — one rule, both sections.
            if focus and not is_cwd_match(p):
                # One-line roll-up: enough to know the project exists and roughly
                # where it stands, without its milestones or ticket list.
                n_open = len((p.get('issues') or {}).get('nodes', []))
                open_s = f' · {n_open}+ open' if n_open else ''
                print(f'- **{name}** — {pct} · {state}{open_s}')
                continue
            star = ' ★ this directory' if is_cwd_match(p) else ''
            print(f'### {name}{star} — {pct} · {state}')

            ms = (p.get('projectMilestones') or {}).get('nodes', [])
            if ms:
                # sortOrder ascending when present; else targetDate then name
                def ms_key(m):
                    so = m.get('sortOrder')
                    if isinstance(so, (int, float)):
                        return (0, so)
                    td = m.get('targetDate') or '9999'
                    return (1, td, m.get('name') or '')
                ms_sorted = sorted(ms, key=ms_key)
                print('**Milestones:**')
                for m in ms_sorted:
                    mpct = pct_str(m.get('progress'))
                    mpct_s = f' · {mpct}' if mpct else ''
                    td = f' by {m[\"targetDate\"]}' if m.get('targetDate') else ''
                    print(f'- {m.get(\"name\", \"?\")}{td}{mpct_s}')
            else:
                print('**Milestones:** _(none)_')

            issues = (p.get('issues') or {}).get('nodes', [])
            if issues:
                issues = sorted(issues, key=pri_rank)
                print(f'**Top open ({len(issues)}):**')
                for n in issues:
                    print(fmt_issue_line(n, with_desc=False))
            else:
                print('**Top open:** _(none)_')
            print()
    elif projects:
        names = ', '.join(p.get('name', '?') for p in projects)
        print(f'_No live projects to show (team projects: {names})._')
        print()
    else:
        print('_No projects on this Linear team._')
        print()

    # -- Active-sprint board (Your Tasks, then by project) ----------------
    cycle = team.get('activeCycle')
    if not cycle:
        print('No active sprint in Linear.')
        sys.exit(0)

    cycle_issues = cycle.get('issues') or {}
    nodes = cycle_issues.get('nodes', [])
    cycle_truncated = (cycle_issues.get('pageInfo') or {}).get('hasNextPage')
    cycle_name = cycle.get('name') or 'Current Sprint'

    if not nodes:
        print(f'No open tasks in {cycle_name}.')
        sys.exit(0)

    # Group by Linear's native delegate — the only thing that owns an issue.
    # SELF is a harness name ('claude'); Linear returns the roster spelling
    # ('Claude'), so the match is case-insensitive. Labels confer no ownership,
    # so every label an issue carries is shown as-is.
    groups = {}
    for n in nodes:
        n['_other_labels'] = [l['name'] for l in (n.get('labels') or {}).get('nodes', [])]
        dg = (n.get('delegate') or {}).get('name')
        if dg:
            groups.setdefault(dg, []).append(n)

    for g in groups.values():
        g.sort(key=pri_rank)

    # Drop EVERY case-variant of your own name, not just the first. This map is
    # only ever read as everyone else's lanes, so a straggler variant would show
    # up there as a foreign agent.
    for k in [k for k in groups if k.lower() == SELF.lower()]:
        groups.pop(k)

    cycle_count = f'{len(nodes)}+' if cycle_truncated else str(len(nodes))
    print(f'## {cycle_name} — {cycle_count} open tasks')
    print()

    # Your Tasks comes from its own delegate-filtered query, not from the cycle
    # page above: Linear caps that page, so picking your queue out of it showed
    # whichever of your issues happened to land in the first page.
    my_conn = team.get('myOpenIssues') or {}
    mine = sorted(my_conn.get('nodes', []), key=pri_rank)
    for n in mine:
        n['_other_labels'] = [l['name'] for l in (n.get('labels') or {}).get('nodes', [])]
    my_truncated = (my_conn.get('pageInfo') or {}).get('hasNextPage')

    # When this cwd belongs to a project, promote that project's delegated work
    # to \"Your Tasks\" and demote the rest to a one-line cross-project hint. The
    # bug this fixes: an agent launched in one project's folder saw OTHER
    # projects' tasks in its own queue and picked them up. No focus (cwd matched
    # no live project) keeps the full cross-project queue, so nothing is hidden
    # from a session that isn't in a project directory.
    focus_norms = {norm(p.get('name')) for p in focus}
    if focus_norms:
        here_ids = set()
        mine_here = []
        for n in mine:
            if norm((n.get('project') or {}).get('name')) in focus_norms:
                mine_here.append(n)
                here_ids.add(n.get('identifier'))
        mine_elsewhere = [n for n in mine if n.get('identifier') not in here_ids]
    else:
        mine_here = mine
        mine_elsewhere = []

    # The '+' truncation marker tracks whether the SOURCE query was truncated
    # (my_truncated), not the client-side project filter: a filtered page can
    # still have focus-project issues on later pages, so keep '+' when the query
    # was capped rather than claim a false-exact count.
    scoped = bool(focus_norms)
    where = f' in {focus[0].get(\"name\")}' if scoped else ''
    elsewhere_hint = (f'- _+{len(mine_elsewhere)} more delegated to you in other '
                      f'projects (see: linear tasks --all --agent {SELF})_') if mine_elsewhere else None

    MY_CAP = 10
    printed_ids = set()
    if mine_here:
        owner = (mine_here[0].get('delegate') or {}).get('name') or SELF
        total = f'{len(mine_here)}+' if my_truncated else str(len(mine_here))
        print(f'### Your Tasks (delegated to {owner}{where}) — {total}')
        for n in mine_here[:MY_CAP]:
            printed_ids.add(n.get('identifier'))
            # In-project view: project name is redundant on every row. Unscoped:
            # keep it, since the rows span projects.
            print(fmt_issue_line(n, with_desc=True, with_project=not scoped))
        # Remainder past the display cap. clamp to 0: once mine_here is the
        # page filtered client-side to one project, it can be far below MY_CAP
        # even while the SOURCE query was truncated (an agent with 100+ open
        # issues team-wide, few in this project) — an unclamped subtraction then
        # injected a garbled '_+-6+ more_'. When there is no real remainder the
        # header's own '+' already signals the truncation, so drop the line.
        more = max(0, len(mine_here) - MY_CAP)
        if more:
            suffix = f'{more}+' if my_truncated else str(more)
            print(f'- _+{suffix} more delegated to you (see: linear tasks --agent {SELF})_')
        if elsewhere_hint:
            print(elsewhere_hint)
        print()
    elif mine_elsewhere:
        # Nothing in this project, but you do own work elsewhere — say so, rather
        # than \"none assigned\", which reads as an empty queue.
        print(f'### Your Tasks (delegated to {SELF}{where}) — none here')
        print(elsewhere_hint)
        print()
    else:
        print(f'### Your Tasks (delegated to {SELF}) — none assigned')
        print()

    # Remaining cycle issues grouped by project (not by agent) — titles only
    # so the project spine above stays the source of truth for open work.
    by_project = {}
    for n in nodes:
        # Skip only what Your Tasks actually PRINTED. Skipping everything
        # delegated to you would drop your own issues out of the brief entirely
        # whenever they fell past the cap above — the two lists come from
        # different queries, so their overlap is not guaranteed.
        if n.get('identifier') in printed_ids:
            continue
        pname = (n.get('project') or {}).get('name') or 'No project'
        by_project.setdefault(pname, []).append(n)

    if by_project:
        print('### Cycle by project')
        focus_names = {(p.get('name') or '') for p in focus}

        # Focus project first if present, then alpha
        def proj_sort_key(name):
            return (0, name.lower()) if name in focus_names else (1, name.lower())

        # Same scoping rule as the Projects section above: the cwd's project is
        # listed ticket by ticket, every other project collapses to a count.
        # Measured before this: 5865 bytes, 54% of the whole injection, and most
        # of it was cycle tickets for projects this session cannot act on.
        rolled = []
        for pname in sorted(by_project.keys(), key=proj_sort_key):
            issues = sorted(by_project[pname], key=pri_rank)
            if focus_names and pname not in focus_names:
                rolled.append(f'{pname} {len(issues)}')
                continue
            # Cap per project in the cycle section to protect context
            CAP = 12
            shown = issues[:CAP]
            more = len(issues) - len(shown)
            print(f'**{pname}** — {len(issues)} open')
            for n in shown:
                print(fmt_issue_line(n, with_desc=False))
            if more > 0:
                print(f'- _+{more} more in cycle (see project section / linear tasks --project {pname})_')
            print()
        if rolled:
            print('**Elsewhere in the cycle:** ' + ' · '.join(rolled) + ' open — \`linear tasks --project <name>\`')
            print()

    # Other-agent counts only (not full dump — agents already have project view).
    # Your own bucket was popped out of the groups map above, so what is left is
    # everyone else's delegated work. These counts are over the cycle page: say
    # so when it was truncated rather than print a number that reads exact.
    # Prefer the exact counts from the delegate-only sweep. It is marked COMPLETE
    # only when every page came back, so a partial sweep falls back rather than
    # printing a number that looks exact.
    lanes_raw = [x for x in os.environ.get('LANES', '').split('|') if x]
    note = ''
    if lanes_raw and lanes_raw[-1] == 'COMPLETE':
        tally = {}
        for name in lanes_raw[:-1]:
            if name.lower() != SELF.lower():
                tally[name] = tally.get(name, 0) + 1
    else:
        tally = {name: len(v) for name, v in groups.items()}
        if cycle_truncated:
            note = f' (of the first {len(nodes)} cycle issues)'
    other_agent_counts = [f'{name}={tally[name]}' for name in sorted(tally)]
    if other_agent_counts:
        print(f'### Other agent lanes{note}: {\", \".join(other_agent_counts)}')
        print()

    print('---')
    if mine:
        print('Pick your highest-priority task. Projects above carry milestones + open work; cycle section is this sprint only.')
    else:
        print('Nothing is delegated to you. Use the Projects section (milestones + top open) to pick work, or claim from the cycle-by-project list.')

except Exception as e:
    print(f'Linear query failed: {e}')
" 2>&1
