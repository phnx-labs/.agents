#!/usr/bin/env bun
// Exposure — where agents actually spend their attention.
//
// Joins three per-file signals so cleanup can be ranked by cost rather than taste:
//   churn         commits touching the file in the window          (git log)
//   agent traffic Read/Edit/Write tool calls agents made on it     (sessions.db)
//   size          lines of code, and whether it is past holdable   (wc)
//
// agent_cost = (2*agent_edits + agent_reads + commits) * size_penalty
// size_penalty = clamp(loc / 500, 1, 4)
//
// The formula is deliberately dumb and every input is printed alongside it, so a
// human can disagree with the weighting without re-running anything. Rank order is
// the product; the absolute number means nothing.
//
// The agent-traffic signal comes from the fleet session index at
// ~/.agents/.history/sessions/sessions.db (table `tool_calls`, `input` is JSON).
// Paths are stored both absolute and `[HOME]`-redacted — both forms are matched and
// normalized. When the DB is missing, traffic is zero and `meta.degraded` says so;
// the caller MUST report that rather than present the ranking as complete.
//
// Usage: bun exposure.ts <run-dir> [--days N] [--scope <path>]...

import { existsSync, mkdirSync } from "node:fs";
import { execFileSync, execSync } from "node:child_process";
import { join, resolve } from "node:path";
import { homedir } from "node:os";

const args = process.argv.slice(2);
const runDir = args[0];
if (!runDir || runDir.startsWith("--")) {
  console.error("usage: exposure.ts <run-dir> [--days N] [--scope <path>]...");
  process.exit(1);
}
mkdirSync(runDir, { recursive: true });

let days = 90;
const scopes: string[] = [];
for (let i = 1; i < args.length; i++) {
  if (args[i] === "--days") days = Number(args[++i]) || 90;
  else if (args[i] === "--scope") scopes.push(args[++i]);
}

const repoRoot = execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim();
const HOME = homedir();

// ---------------------------------------------------------------- tracked files
const lsArgs = ["-C", repoRoot, "ls-files", "--"];
lsArgs.push(...(scopes.length ? scopes : ["."]));
const tracked = execFileSync("git", lsArgs, { encoding: "utf8", maxBuffer: 1 << 28 })
  .split("\n")
  .filter(Boolean);

const SOURCE_RE = /\.(ts|tsx|js|jsx|mjs|cjs|go|py|rs|rb|java|kt|swift|cs|c|h|cc|cpp|hpp|sh|bash)$/;
const source = tracked.filter((f) => SOURCE_RE.test(f));

// ---------------------------------------------------------------- size
const loc = new Map<string, number>();
for (const f of source) {
  const abs = join(repoRoot, f);
  if (!existsSync(abs)) continue;
  try {
    const out = execFileSync("wc", ["-l", abs], { encoding: "utf8" });
    loc.set(f, Number(out.trim().split(/\s+/)[0]) || 0);
  } catch {
    /* unreadable file — leave it out of the ranking rather than guess */
  }
}

// ---------------------------------------------------------------- churn
const churn = new Map<string, number>();
try {
  const logArgs = [
    "-C", repoRoot, "log", `--since=${days}.days`,
    "--name-only", "--pretty=format:", "--",
    ...(scopes.length ? scopes : ["."]),
  ];
  for (const line of execFileSync("git", logArgs, { encoding: "utf8", maxBuffer: 1 << 28 }).split("\n")) {
    const f = line.trim();
    if (f) churn.set(f, (churn.get(f) ?? 0) + 1);
  }
} catch {
  /* shallow clone or no history — churn stays empty, reported as degraded below */
}

// ---------------------------------------------------------------- agent traffic
const SESSIONS_DB = join(HOME, ".agents", ".history", "sessions", "sessions.db");
const reads = new Map<string, number>();
const edits = new Map<string, number>();
const degraded: string[] = [];

// Match both the absolute path and the `[HOME]`-redacted form by filtering on the
// portion of the repo path below $HOME. A repo outside $HOME matches on its full path.
const repoNeedle = repoRoot.startsWith(HOME + "/") ? repoRoot.slice(HOME.length + 1) : repoRoot;

if (!existsSync(SESSIONS_DB)) {
  degraded.push(`no session index at ${SESSIONS_DB} — agent traffic is 0 for every file`);
} else {
  const since = new Date(Date.now() - days * 864e5).toISOString().slice(0, 10);
  const sql = `
    select tool, json_extract(input,'$.file_path') as f, count(*) as c
    from tool_calls
    where tool in ('Read','Edit','Write','NotebookEdit')
      and timestamp >= '${since}'
      and input like '%${repoNeedle.replace(/'/g, "''")}%'
      and json_valid(input)
    group by tool, f;`;
  try {
    const out = execFileSync("sqlite3", ["-readonly", SESSIONS_DB, sql], {
      encoding: "utf8",
      maxBuffer: 1 << 28,
    });
    for (const line of out.split("\n")) {
      if (!line) continue;
      const [tool, rawPath, countStr] = line.split("|");
      if (!rawPath) continue;
      const abs = rawPath.replace(/^\[HOME\]/, HOME);
      if (!abs.startsWith(repoRoot + "/")) continue;
      // Most agent EDITS happen in a worktree, not the primary checkout. Fold
      // `.agents/worktrees/<slug>/x` back to `x` or the edit traffic — the strongest
      // signal here — is silently dropped as an untracked path.
      const rel = abs.slice(repoRoot.length + 1).replace(/^\.agents\/worktrees\/[^/]+\//, "");
      const n = Number(countStr) || 0;
      const bucket = tool === "Read" ? reads : edits;
      bucket.set(rel, (bucket.get(rel) ?? 0) + n);
    }
  } catch (e) {
    degraded.push(`session index unreadable (${(e as Error).message.split("\n")[0]}) — agent traffic is 0`);
  }
}

if (churn.size === 0) degraded.push("no git history in the window — churn is 0 for every file");

// ---------------------------------------------------------------- score
const HOLDABLE = 1500; // past this, no agent reliably reads the whole file before editing

interface Row {
  file: string;
  loc: number;
  commits: number;
  agent_reads: number;
  agent_edits: number;
  size_penalty: number;
  agent_cost: number;
  holdable: boolean;
}

const rows: Row[] = source
  .filter((f) => loc.has(f))
  .map((f) => {
    const l = loc.get(f)!;
    const commits = churn.get(f) ?? 0;
    const r = reads.get(f) ?? 0;
    const e = edits.get(f) ?? 0;
    const size_penalty = Math.min(4, Math.max(1, l / 500));
    return {
      file: f,
      loc: l,
      commits,
      agent_reads: r,
      agent_edits: e,
      size_penalty: Number(size_penalty.toFixed(2)),
      agent_cost: Number(((2 * e + r + commits) * size_penalty).toFixed(1)),
      holdable: l <= HOLDABLE,
    };
  })
  .sort((a, b) => b.agent_cost - a.agent_cost || b.loc - a.loc);

const overHoldable = rows.filter((r) => !r.holdable);
const hotAndHuge = rows.filter((r) => !r.holdable && (r.commits >= 10 || r.agent_reads + r.agent_edits >= 5));

console.log(
  JSON.stringify(
    {
      meta: {
        repo: repoRoot,
        scope: scopes.length ? scopes : ["."],
        window_days: days,
        source_files: rows.length,
        total_loc: rows.reduce((s, r) => s + r.loc, 0),
        holdable_threshold_loc: HOLDABLE,
        files_over_threshold: overHoldable.length,
        hot_and_huge: hotAndHuge.length,
        top_file_loc: rows.length ? Math.max(...rows.map((r) => r.loc)) : 0,
        formula: "(2*agent_edits + agent_reads + commits) * clamp(loc/500, 1, 4)",
        degraded,
      },
      files: rows.slice(0, 200),
    },
    null,
    2,
  ),
);
