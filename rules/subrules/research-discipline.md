# Research & Evidence Discipline

- **No unverified claims.** Every factual claim — code, counts, capabilities —
  needs proof: a file path, a line number, output quoted from this conversation.
  Run the tool, then report.
- **No lazy debugging.** Read every file in the data path and quote file:line
  from each. For a fleet regression, attribute the culprit change to its
  agent/session (`git blame` → commit → `agents sessions preview`).
- **Current-code anchoring.** `git fetch origin` +
  `git rev-list --count HEAD..origin/<default>` before diagnosing, calling
  something a regression, or opening a fix — checkouts go stale constantly here.
- **Current-date anchoring.** Your weights are stale; the real date is in the
  system prompt. Include the current year in every state-of-the-world web query,
  and WebSearch before answering time-sensitive questions. Load search tools at
  session start: `ToolSearch select:WebSearch,WebFetch`.
- Every investigation/review `Agent` brief ends with: `Return file:line quotes
  for every claim. Do NOT paraphrase. If you can't quote it, don't claim it.`
- **No human-time estimates.** Estimate in wall-clock minutes, number of edits /
  test runs / agent invocations, or token cost — never "X hours/days".
