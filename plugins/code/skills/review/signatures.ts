#!/usr/bin/env bun
// D — Behavioral-signature clustering.
// Builds a per-function shape signature (param types, return types, primary
// side-effect class). Functions with matching signatures across 2+ files in
// different modules are flagged as parallel-impl candidates.
//
// The signature ignores names — so `slugify` and `kebabCase` cluster when they
// should; same-name divergent-contract families like `sanitize*` don't all
// cluster (validators returning `error` separate from string-pure transforms).
//
// Usage: bun signatures.ts <run-dir>

import { readFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { join } from "node:path";

const runDir = process.argv[2];
if (!runDir) {
  console.error("usage: signatures.ts <run-dir>");
  process.exit(1);
}

const repoRoot = execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim();
const filesTxt = join(runDir, "files.txt");
const changedFiles = existsSync(filesTxt)
  ? new Set(readFileSync(filesTxt, "utf8").split("\n").filter(Boolean))
  : new Set<string>();

interface Finding {
  category: "patterns";
  severity: "should" | "nice";
  rule: string;
  file: string;
  line_start: number;
  line_end: number;
  snippet: string;
  anchor_file: string;
  anchor_line: number;
  anchor_snippet: string;
  fix_one_line: string;
  tool: "signatures";
}

interface Fn {
  name: string;
  file: string;
  line: number;
  module: string; // top-level surface (e.g. "rush/cli", "harness")
  signature: string;
  bodyHead: string;
}

const SCAN_GLOBS = ["*.go", "*.ts", "*.tsx"];

// Always index across the whole repo — cross-surface parallel implementations
// (e.g. sanitize* in both rush/cli and harness) are the highest-signal pattern
// for AI-era code. Findings are filtered to scope at emit time, not at index time.
const sourceFiles = (): string[] =>
  execSync(`git ls-files -- ${SCAN_GLOBS.map((g) => `'${g}'`).join(" ")}`, {
    cwd: repoRoot, encoding: "utf8",
  }).split("\n").filter(Boolean).filter((p) => {
    // Skip generated, vendored, and corpus dirs that pollute the cluster index.
    if (p.includes("/node_modules/")) return false;
    if (p.includes("/.agents/artifacts/")) return false;
    if (p.includes("/.agents/scratches/")) return false;
    if (p.includes("/vendor/")) return false;
    if (p.includes("/dist/") || p.includes("/build/")) return false;
    if (p.endsWith(".d.ts")) return false;
    // Skip tests — every TestXxx(t *testing.T) trivially clusters.
    if (p.endsWith("_test.go")) return false;
    if (p.endsWith(".test.ts") || p.endsWith(".test.tsx")) return false;
    if (p.endsWith(".spec.ts") || p.endsWith(".spec.tsx")) return false;
    return true;
  });

// A signature is "interesting" enough to flag dupes only if it has both a
// non-trivial input and a non-trivial output. Empty params / `() -> error` is
// just "any function that runs" — way too generic.
const isInterestingSignature = (sig: string): boolean => {
  // Go signature shape: `go(params) -> (returns) [side-effects]`
  const goMatch = sig.match(/^go\(([^)]*)\)\s*->\s*\(([^)]*)\)/);
  if (goMatch) {
    const [, params, returns] = goMatch;
    if (!params.trim()) return false;        // no params = too generic
    if (!returns.trim()) return false;       // no return = procedural side-effect, dupe by name not shape
    // Pure error-returning with single param is also too generic (Run, Execute, etc.)
    if (returns.trim() === "error") {
      const paramCount = params.split(",").filter(Boolean).length;
      if (paramCount <= 1) return false;
    }
    return true;
  }
  // TS signature shape: `ts(params) -> returnType [side-effects]`
  const tsMatch = sig.match(/^ts\(([^)]*)\)\s*->\s*([^[]+)\[/);
  if (tsMatch) {
    const [, params, returns] = tsMatch;
    if (!params.trim()) return false;
    if (!returns.trim() || returns.trim() === "void" || returns.trim() === "Promise<void>") return false;
    return true;
  }
  return false;
};

const moduleOf = (path: string): string => {
  const parts = path.split("/");
  // Two-level for nested products (rush/cli, prix/api, harness/agents).
  if (parts[0] === "rush" || parts[0] === "prix") return parts.slice(0, 2).join("/");
  if (parts[0] === "harness") return "harness";
  return parts[0] || "root";
};

const normaliseGoType = (t: string): string =>
  t.trim().replace(/\s+/g, "").replace(/^\*/, "ptr_");

const classifyBody = (body: string): string => {
  const flags: string[] = [];
  if (/regexp\.|MustCompile\(|\.MatchString\(|\.ReplaceAll/.test(body)) flags.push("regex");
  if (/os\.(Open|Create|ReadFile|WriteFile|Stat)|ioutil\.|filepath\.|fs\./.test(body)) flags.push("io-fs");
  if (/http\.|net\.|fetch\(|\.Get\(|\.Post\(/.test(body)) flags.push("io-net");
  if (/db\.|\.Query\(|\.Exec\(|sqlx\.|sql\.Open/.test(body)) flags.push("db");
  if (/exec\.Command|spawn\(|spawnSync\(/.test(body)) flags.push("subprocess");
  if (flags.length === 0) flags.push("pure");
  return flags.sort().join("+");
};

const parseGo = (path: string, content: string): Fn[] => {
  const out: Fn[] = [];
  const lines = content.split("\n");
  // Match `func Name(params) returnType {` at top level (no leading whitespace).
  const re = /^func\s+(\w+)\s*\(([^)]*)\)\s*([^{]*)\{/;
  lines.forEach((line, i) => {
    const m = line.match(re);
    if (!m) return;
    const [, name, paramsRaw, retRaw] = m;
    const params = paramsRaw
      .split(",")
      .map((p) => p.trim().split(/\s+/).pop() || "")
      .filter(Boolean)
      .map(normaliseGoType);
    const ret = retRaw.trim().replace(/^\(|\)$/g, "");
    const retTypes = ret
      ? ret.split(",").map((t) => t.trim().split(/\s+/).pop() || "").filter(Boolean).map(normaliseGoType)
      : [];
    const bodyHead = lines.slice(i + 1, Math.min(lines.length, i + 12)).join("\n");
    const sideEffect = classifyBody(bodyHead);
    const signature = `go(${params.join(",")}) -> (${retTypes.join(",")}) [${sideEffect}]`;
    out.push({
      name,
      file: path,
      line: i + 1,
      module: moduleOf(path),
      signature,
      bodyHead: lines.slice(Math.max(0, i), Math.min(lines.length, i + 10)).join("\n"),
    });
  });
  return out;
};

const parseTs = (path: string, content: string): Fn[] => {
  const out: Fn[] = [];
  const lines = content.split("\n");
  // Match `export? function Name(...)` and `export const Name = (...) =>` at top level.
  const reFn = /^(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(([^)]*)\)(?:\s*:\s*([^{]+))?\s*\{/;
  const reArrow = /^(?:export\s+)?const\s+(\w+)\s*(?::\s*[^=]+)?=\s*(?:async\s*)?\(([^)]*)\)(?:\s*:\s*([^=]+))?\s*=>/;
  lines.forEach((line, i) => {
    const m = line.match(reFn) || line.match(reArrow);
    if (!m) return;
    const [, name, paramsRaw, retRaw] = m;
    const params = paramsRaw
      .split(",")
      .map((p) => {
        const colon = p.indexOf(":");
        return colon >= 0 ? p.slice(colon + 1).trim() : "any";
      })
      .filter(Boolean);
    const ret = (retRaw || "any").trim();
    const bodyHead = lines.slice(i + 1, Math.min(lines.length, i + 12)).join("\n");
    const sideEffect = classifyBody(bodyHead);
    const signature = `ts(${params.join(",")}) -> ${ret} [${sideEffect}]`;
    out.push({
      name,
      file: path,
      line: i + 1,
      module: moduleOf(path),
      signature,
      bodyHead: lines.slice(Math.max(0, i), Math.min(lines.length, i + 10)).join("\n"),
    });
  });
  return out;
};

const indexFunctions = (): Fn[] => {
  const fns: Fn[] = [];
  for (const f of sourceFiles()) {
    let content: string;
    try {
      content = readFileSync(join(repoRoot, f), "utf8");
    } catch {
      continue;
    }
    if (f.endsWith(".go")) fns.push(...parseGo(f, content));
    else if (f.endsWith(".ts") || f.endsWith(".tsx")) fns.push(...parseTs(f, content));
  }
  return fns;
};

const all = indexFunctions();

// Group by signature.
const bySig = new Map<string, Fn[]>();
for (const fn of all) {
  if (!bySig.has(fn.signature)) bySig.set(fn.signature, []);
  bySig.get(fn.signature)!.push(fn);
}

const findings: Finding[] = [];

// Sub-cluster a signature group by shared name root. Two functions belong to
// the same name-cluster only if they share ≥5 chars of case-insensitive prefix
// (longest common starting substring). This catches families like
// `sanitize*`, `validate*`, `parse*` — the exact AI-era miss the user flagged —
// while dropping the noise of `ResolveAgentPath` clustering with `hashFile`
// just because both happen to be `(string) -> (string, error)`.
const PREFIX_MIN = 5;
const sharedPrefixLen = (a: string, b: string): number => {
  const an = a.toLowerCase(), bn = b.toLowerCase();
  let i = 0;
  while (i < an.length && i < bn.length && an[i] === bn[i]) i++;
  return i;
};

const subClusterByName = (fns: Fn[]): Fn[][] => {
  // Greedy: walk in sorted order, assign each fn to the first existing
  // sub-cluster where shared prefix with any member ≥ PREFIX_MIN.
  const groups: Fn[][] = [];
  for (const fn of fns) {
    let placed = false;
    for (const g of groups) {
      if (g.some((m) => sharedPrefixLen(m.name, fn.name) >= PREFIX_MIN)) {
        g.push(fn);
        placed = true;
        break;
      }
    }
    if (!placed) groups.push([fn]);
  }
  return groups.filter((g) => g.length >= 2);
};

for (const [sig, fns] of bySig) {
  if (fns.length < 2) continue;
  if (!isInterestingSignature(sig)) continue;

  // Subcluster by name family first — drop clusters that only collide on shape.
  const sorted = [...fns].sort((a, b) => a.file.localeCompare(b.file));
  const families = subClusterByName(sorted);

  for (const family of families) {
    const modules = new Set(family.map((f) => f.module));
    if (modules.size < 2) continue;

    // In diff mode, require at least one family member to be in scope.
    if (changedFiles.size > 0 && !family.some((f) => changedFiles.has(f.file))) continue;

    // Anchor = oldest file in the family (alphabetical proxy).
    const anchor = family[0];
    for (const fn of family.slice(1)) {
      if (fn.file === anchor.file) continue;
      findings.push({
        category: "patterns",
        severity: "should",
        rule: `\`${fn.name}\` clusters with \`${anchor.name}\` (shared name root + same shape) — possible parallel implementation`,
        file: fn.file,
        line_start: fn.line,
        line_end: fn.line + 8,
        snippet: fn.bodyHead,
        anchor_file: anchor.file,
        anchor_line: anchor.line,
        anchor_snippet: anchor.bodyHead,
        fix_one_line: `if these are the same operation, drop \`${fn.name}\` and import \`${anchor.name}\` from ${anchor.file}`,
        tool: "signatures",
      });
    }
  }
}

process.stdout.write(JSON.stringify(findings, null, 2) + "\n");
