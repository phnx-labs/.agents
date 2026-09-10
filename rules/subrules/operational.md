# Environment and Tools

Credentials live in `agents secrets`; never write them into configuration or
leave them ambient, and prefer existing configuration mechanisms over new
environment variables. Follow the repository's install and release process;
never replace a working tool with a development build. Preserve the user's
running services and desktop: no starting or killing their processes without
authorization, and no background work without a bounded purpose and a verified
completion or cleanup. Reuse authorization already given; ask once before
adding permanent permissions.

Use the owning tool: `tickets` for trackers, `browser` for the web,
`agents computer` for native UI, `agents pty` for interactive terminals,
`agents teams` for parallel coding, and `agents sessions` to recover prior work
and check ownership before taking over a task. Agent homes such as `~/.claude/`
are managed links; shared configuration belongs in `~/.agents/`. Artifacts use
the target product's design tokens and self-contained visuals, no CDN chart
libraries.

Scratch goes under `.agents/scratch/` (or `~/.agents/scratch/` outside a repo);
durable output under `~/.agents/artifacts/yyyy-mm-dd/<slug>/` or, when it ships
with a feature, in that feature's worktree. No unsolicited documents, no emojis
unless asked. For a human-only step, prepare the smallest usable handoff and
verify it (clipboard contents, a script).
