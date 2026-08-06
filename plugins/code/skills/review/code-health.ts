#!/usr/bin/env bun
// B — Code Health.
// Runs classic lint per surface using ONLY tools already on PATH.
// Tools missing from PATH are logged to <run-dir>/skipped.json for the HTML
// footer. Severity comes from the tool's own output level — error=BLOCKER,
// warning=SHOULD, info/note=NICE.
//
// Usage: bun code-health.ts <run-dir>

import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { join } from "node:path";

const runDir = process.argv[2];
if (!runDir) {
  console.error("usage: code-health.ts <run-dir>");
  process.exit(1);
}
const repoRoot = execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim();
const filesTxt = join(runDir, "files.txt");
const changedFiles = existsSync(filesTxt)
  ? readFileSync(filesTxt, "utf8").split("\n").filter(Boolean)
  : [];

interface Finding {
  category: "code-health";
  severity: "blocker" | "should" | "nice";
  rule: string;
  file: string;
  line_start: number;
  line_end?: number;
  snippet: string;
  anchor_file: null;
  anchor_line: null;
  anchor_snippet: null;
  fix_one_line: string;
  tool: string;
}

const findings: Finding[] = [];
const skipped: string[] = [];

const has = (bin: string): boolean => {
  try { execSync(`command -v ${bin}`, { stdio: "ignore" }); return true; } catch { return false; }
};

const run = (cmd: string, cwd: string): string => {
  try {
    return execSync(cmd, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (e: any) {
    // Most lint tools exit non-zero when they find issues — that's expected.
    return (e.stdout || "") + (e.stderr || "");
  }
};

const surfacesTouched = (): string[] => {
  if (changedFiles.length === 0) {
    // corpus mode: caller passes paths via files.txt = git ls-files <paths>;
    // infer surfaces from those.
    return [];
  }
  const set = new Set<string>();
  for (const f of changedFiles) {
    const parts = f.split("/");
    if (parts[0] === "rush" || parts[0] === "prix") set.add(parts.slice(0, 2).join("/"));
    else if (parts[0] === "harness") set.add("harness");
  }
  return [...set];
};

// ──────────────────────────────────────────────────────────────────────────
// Go: go vet
// ──────────────────────────────────────────────────────────────────────────
const runGoVet = (surface: string) => {
  if (!existsSync(join(repoRoot, surface, "go.mod"))) return;
  if (!has("go")) { skipped.push("go"); return; }
  const out = run("go vet ./...", join(repoRoot, surface));
  // Output lines: `<file>:<line>:<col>: <message>`
  for (const line of out.split("\n")) {
    const m = line.match(/^(.+?\.go):(\d+):(\d+)?:?\s+(.+)$/);
    if (!m) continue;
    const [, fileAbs, lnStr, , msg] = m;
    const rel = fileAbs.startsWith(repoRoot) ? fileAbs.slice(repoRoot.length + 1) : `${surface}/${fileAbs}`;
    findings.push({
      category: "code-health",
      severity: "blocker",
      rule: msg.trim(),
      file: rel,
      line_start: Number(lnStr),
      snippet: line.trim(),
      anchor_file: null, anchor_line: null, anchor_snippet: null,
      fix_one_line: "address the vet warning",
      tool: "go-vet",
    });
  }
};

// ──────────────────────────────────────────────────────────────────────────
// Go: staticcheck (if on PATH)
// ──────────────────────────────────────────────────────────────────────────
const runStaticcheck = (surface: string) => {
  if (!existsSync(join(repoRoot, surface, "go.mod"))) return;
  if (!has("staticcheck")) { if (!skipped.includes("staticcheck")) skipped.push("staticcheck"); return; }
  const out = run("staticcheck ./...", join(repoRoot, surface));
  for (const line of out.split("\n")) {
    const m = line.match(/^(.+?\.go):(\d+):(\d+)?:?\s+(.+)$/);
    if (!m) continue;
    const [, fileAbs, lnStr, , msg] = m;
    const rel = fileAbs.startsWith(repoRoot) ? fileAbs.slice(repoRoot.length + 1) : `${surface}/${fileAbs}`;
    findings.push({
      category: "code-health",
      severity: "should",
      rule: msg.trim(),
      file: rel,
      line_start: Number(lnStr),
      snippet: line.trim(),
      anchor_file: null, anchor_line: null, anchor_snippet: null,
      fix_one_line: "address the staticcheck finding",
      tool: "staticcheck",
    });
  }
};

// ──────────────────────────────────────────────────────────────────────────
// TS: tsc --noEmit  (only where package.json has a `typecheck` script)
// ──────────────────────────────────────────────────────────────────────────
const runTsc = (surface: string) => {
  const pkgPath = join(repoRoot, surface, "package.json");
  if (!existsSync(pkgPath)) return;
  let pkg: any;
  try { pkg = JSON.parse(readFileSync(pkgPath, "utf8")); } catch { return; }
  if (!pkg?.scripts?.typecheck) return;
  if (!has("bun")) { skipped.push("bun"); return; }
  const out = run("bun run typecheck", join(repoRoot, surface));
  // tsc lines: `<file>(<line>,<col>): error TSnnnn: <message>`
  for (const line of out.split("\n")) {
    const m = line.match(/^(.+?\.tsx?)\((\d+),(\d+)\):\s+(error|warning)\s+TS\d+:\s+(.+)$/);
    if (!m) continue;
    const [, fileAbs, lnStr, , level, msg] = m;
    const rel = fileAbs.startsWith(repoRoot) ? fileAbs.slice(repoRoot.length + 1) : `${surface}/${fileAbs}`;
    findings.push({
      category: "code-health",
      severity: level === "error" ? "blocker" : "should",
      rule: msg.trim(),
      file: rel,
      line_start: Number(lnStr),
      snippet: line.trim(),
      anchor_file: null, anchor_line: null, anchor_snippet: null,
      fix_one_line: "fix the type error",
      tool: "tsc",
    });
  }
};

// ──────────────────────────────────────────────────────────────────────────
// Shell: shellcheck on changed *.sh files (if on PATH)
// ──────────────────────────────────────────────────────────────────────────
const runShellcheck = () => {
  if (!has("shellcheck")) { if (!skipped.includes("shellcheck")) skipped.push("shellcheck"); return; }
  const shFiles = changedFiles.filter((f) => f.endsWith(".sh"));
  if (shFiles.length === 0) return;
  for (const f of shFiles) {
    const out = run(`shellcheck -f gcc ${JSON.stringify(f)}`, repoRoot);
    for (const line of out.split("\n")) {
      const m = line.match(/^(.+?):(\d+):(\d+):\s+(error|warning|note|info):\s+(.+)\s+\[(SC\d+)\]$/);
      if (!m) continue;
      const [, file, lnStr, , level, msg, code] = m;
      const sev = level === "error" ? "blocker" : level === "warning" ? "should" : "nice";
      findings.push({
        category: "code-health",
        severity: sev,
        rule: `${code}: ${msg}`,
        file,
        line_start: Number(lnStr),
        snippet: line.trim(),
        anchor_file: null, anchor_line: null, anchor_snippet: null,
        fix_one_line: "address shellcheck finding",
        tool: "shellcheck",
      });
    }
  }
};

const surfaces = surfacesTouched();
for (const s of surfaces) {
  runGoVet(s);
  runStaticcheck(s);
  runTsc(s);
}
runShellcheck();

// Write skipped tools to a sibling file the orchestrator picks up for meta.json.
writeFileSync(join(runDir, "skipped-tools.json"), JSON.stringify(skipped, null, 2));

process.stdout.write(JSON.stringify(findings, null, 2) + "\n");
