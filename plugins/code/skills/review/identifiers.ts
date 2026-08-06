#!/usr/bin/env bun
// C2 — String-table cross-reference.
// Extracts identifier classes from changed code AND docs, cross-references
// against live sources of truth. v1 covers two high-signal classes:
//   1. MCP tool names (`mcp__Provider__Tool`) vs `mcporter list`
//   2. CLI flags in markdown code fences vs the binary's --help output
// SQL identifiers and YAML schema keys are deferred to v2.
//
// Usage: bun identifiers.ts <run-dir>

import { readFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { join } from "node:path";

const runDir = process.argv[2];
if (!runDir) {
  console.error("usage: identifiers.ts <run-dir>");
  process.exit(1);
}
const repoRoot = execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim();
const filesTxt = join(runDir, "files.txt");
const changedFiles = existsSync(filesTxt)
  ? readFileSync(filesTxt, "utf8").split("\n").filter(Boolean)
  : [];

interface Finding {
  category: "context";
  severity: "blocker" | "should" | "nice";
  rule: string;
  file: string;
  line_start: number;
  line_end: number;
  snippet: string;
  anchor_file: string | null;
  anchor_line: number | null;
  anchor_snippet: string | null;
  fix_one_line: string;
  tool: "identifiers";
}

const tryExec = (cmd: string): string | null => {
  try {
    return execSync(cmd, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  } catch {
    return null;
  }
};

const hasTool = (bin: string): boolean => {
  return tryExec(`command -v ${bin}`) !== null;
};

const targetDocs = (): string[] => {
  if (changedFiles.length > 0) {
    return changedFiles.filter((f) => f.endsWith(".md") || f.endsWith(".yaml") || f.endsWith(".yml"));
  }
  return execSync("git ls-files -- '*.md' '*.yaml' '*.yml'", { cwd: repoRoot, encoding: "utf8" })
    .split("\n").filter(Boolean);
};

// ──────────────────────────────────────────────────────────────────────────
// Pass 1: MCP tool name cross-reference
// ──────────────────────────────────────────────────────────────────────────

const findings: Finding[] = [];

const mcpUniverse = (): Set<string> | null => {
  if (!hasTool("mcporter")) return null;
  const out = tryExec("mcporter list 2>/dev/null") || "";
  // Extract `mcp__<provider>__<tool>` patterns from mcporter output.
  const set = new Set<string>();
  for (const m of out.matchAll(/mcp__[A-Za-z0-9_]+__[A-Za-z0-9_]+/g)) {
    set.add(m[0]);
  }
  return set;
};

const checkMcpToolNames = () => {
  const universe = mcpUniverse();
  if (!universe || universe.size === 0) return; // no oracle — skip silently
  for (const doc of targetDocs()) {
    const full = readFileSync(join(repoRoot, doc), "utf8");
    const lines = full.split("\n");
    lines.forEach((line, i) => {
      const matches = line.matchAll(/\bmcp__[A-Za-z0-9_]+__[A-Za-z0-9_]+\b/g);
      for (const m of matches) {
        const ref = m[0];
        if (universe.has(ref)) continue;
        // Skip well-known docs that intentionally show hypothetical or example
        // tool names (the audit/security playbook for instance).
        if (doc.match(/\.agents\/skills\/(audit|security)\//)) continue;
        findings.push({
          category: "context",
          severity: "blocker",
          rule: `MCP tool name \`${ref}\` not in mcporter list`,
          file: doc,
          line_start: i + 1,
          line_end: i + 1,
          snippet: line,
          anchor_file: null,
          anchor_line: null,
          anchor_snippet: null,
          fix_one_line: "verify the tool name; fix the typo or install the missing MCP server",
          tool: "identifiers",
        });
      }
    });
  }
};

// ──────────────────────────────────────────────────────────────────────────
// Pass 2: CLI flag drift — `<binary> <subcmd> --<flag>` in code fences vs --help
// ──────────────────────────────────────────────────────────────────────────

interface FlagRef {
  binary: string;
  subcmd: string;
  flag: string;
  doc: string;
  line: number;
  raw: string;
}

const KNOWN_BINARIES = ["rush", "agents", "linear", "gh", "openclaw", "mcporter"];

const extractFlagRefs = (): FlagRef[] => {
  const refs: FlagRef[] = [];
  for (const doc of targetDocs()) {
    if (!doc.endsWith(".md")) continue;
    const full = readFileSync(join(repoRoot, doc), "utf8");
    const lines = full.split("\n");
    let inFence = false;
    lines.forEach((line, i) => {
      if (/^```/.test(line)) { inFence = !inFence; return; }
      if (!inFence) return;
      for (const binary of KNOWN_BINARIES) {
        // Match: <binary> <subcmd> ... --flag
        const re = new RegExp(`\\b${binary}\\s+([a-z][a-z0-9:-]*)(?:\\s+[^\\n]*?)?\\s(--?[a-zA-Z][a-zA-Z0-9-]+)`, "g");
        let m: RegExpExecArray | null;
        while ((m = re.exec(line)) !== null) {
          refs.push({ binary, subcmd: m[1], flag: m[2], doc, line: i + 1, raw: line.trim() });
        }
      }
    });
  }
  return refs;
};

const helpCache = new Map<string, string | null>();
const getHelp = (binary: string, subcmd: string): string | null => {
  const key = `${binary}::${subcmd}`;
  if (helpCache.has(key)) return helpCache.get(key) ?? null;
  if (!hasTool(binary)) {
    helpCache.set(key, null);
    return null;
  }
  // Try `<binary> <subcmd> --help`. Some binaries use `<binary> help <subcmd>`.
  let help =
    tryExec(`${binary} ${subcmd} --help 2>&1`) ||
    tryExec(`${binary} help ${subcmd} 2>&1`) ||
    null;
  helpCache.set(key, help);
  return help;
};

const checkCliFlags = () => {
  const refs = extractFlagRefs();
  // Skip refs to subcmds that don't render help (avoid false positives from
  // unrecognized subcommands like `rush share` if `share` was removed).
  for (const ref of refs) {
    const help = getHelp(ref.binary, ref.subcmd);
    if (help === null) continue; // binary not on PATH
    // If the binary doesn't recognize the subcommand at all, emit a separate
    // finding for the subcmd itself.
    if (/unknown (sub)?command|no such (sub)?command|invalid command/i.test(help)) {
      findings.push({
        category: "context",
        severity: "blocker",
        rule: `\`${ref.binary} ${ref.subcmd}\` referenced in docs but not in current CLI`,
        file: ref.doc,
        line_start: ref.line,
        line_end: ref.line,
        snippet: ref.raw,
        anchor_file: null,
        anchor_line: null,
        anchor_snippet: null,
        fix_one_line: `update the doc to use a current subcommand of \`${ref.binary}\``,
        tool: "identifiers",
      });
      continue;
    }
    // Check the flag appears in help text. Allow short and long form.
    const flagLong = ref.flag.replace(/^-+/, "");
    const flagPattern = new RegExp(`(^|\\s)--${flagLong}\\b`, "m");
    const shortPattern = new RegExp(`(^|\\s)-${flagLong}\\b`, "m");
    if (flagPattern.test(help) || shortPattern.test(help)) continue;
    findings.push({
      category: "context",
      severity: "should",
      rule: `flag \`${ref.flag}\` for \`${ref.binary} ${ref.subcmd}\` not in --help`,
      file: ref.doc,
      line_start: ref.line,
      line_end: ref.line,
      snippet: ref.raw,
      anchor_file: null,
      anchor_line: null,
      anchor_snippet: null,
      fix_one_line: `verify the flag; remove the reference if it was renamed/removed`,
      tool: "identifiers",
    });
  }
};

checkMcpToolNames();
checkCliFlags();

process.stdout.write(JSON.stringify(findings, null, 2) + "\n");
