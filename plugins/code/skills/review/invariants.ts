#!/usr/bin/env bun
// C1 — Doc-asserted invariants.
// Scans CLAUDE.md / AGENTS.md / README.md for negative assertions about
// backtick-quoted tokens, then re-greps the codebase. Any reappearance of an
// asserted-absent token is a BLOCKER.
//
// Usage: bun invariants.ts <run-dir>

import { readFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { join } from "node:path";

const runDir = process.argv[2];
if (!runDir) {
  console.error("usage: invariants.ts <run-dir>");
  process.exit(1);
}

const repoRoot = execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim();
const filesTxt = join(runDir, "files.txt");
const changedFiles = existsSync(filesTxt)
  ? readFileSync(filesTxt, "utf8").split("\n").filter(Boolean)
  : [];

// Patterns that extract X from absolute-removal assertions only.
// Deliberately exclude contextual phrases like "there is no `X` on the box" or
// "never use `X` with Y" — those describe a situation, not a global ban.
// We only flag claims that the token is GLOBALLY GONE from the codebase.
const PATTERNS: { regex: RegExp; label: string }[] = [
  // "`X` is gone", "`X` CLI is gone", "`X` was removed", "`X` has been removed"
  { regex: /`([^`\n]{1,80})`\s+(?:CLI\s+)?(?:is\s+gone|was\s+gone|has\s+been\s+(?:removed|deleted)|was\s+(?:removed|deleted))/gi, label: "removed" },
  // "`X` is deprecated" (only flag if it implies removal, not "soft deprecation")
  { regex: /`([^`\n]{1,80})`\s+(?:is|has\s+been)\s+deprecated\s+(?:and\s+removed|—\s+use|--?\s+use)/gi, label: "deprecated + removed" },
  // "`X` no longer exists / works / supported"
  { regex: /`([^`\n]{1,80})`\s+no\s+longer\s+(?:exists?|works?|supported)/gi, label: "no longer exists" },
];

// Skip tokens that are too generic to enforce as code-level invariants.
const isLowSignal = (tok: string): boolean => {
  if (tok.length < 3) return true;
  // Single-word lowercase, no hyphens/dots — too generic (e.g. "default", "main")
  if (/^[a-z]+$/.test(tok)) return true;
  // Pure file extensions or version strings
  if (/^\.[a-z]+$/.test(tok)) return true;
  return false;
};

// Find the docs to scan. Prefer docs near changed files in diff mode;
// in corpus mode (no diff context) scan the whole repo.
const findDocs = (): string[] => {
  const allDocs = execSync(
    "git ls-files -- '*CLAUDE.md' '*AGENTS.md' '*README.md'",
    { cwd: repoRoot, encoding: "utf8" }
  ).split("\n").filter(Boolean);

  if (changedFiles.length === 0) return allDocs;

  // Scope: any doc that's either changed itself OR sits at or above a changed
  // file's directory (so CLAUDE.md at any ancestor dir applies).
  const changedDirs = new Set<string>();
  for (const f of changedFiles) {
    let d = f;
    while (d && d !== "." && d !== "/") {
      const parts = d.split("/");
      parts.pop();
      d = parts.join("/");
      changedDirs.add(d || ".");
    }
  }

  return allDocs.filter((doc) => {
    if (changedFiles.includes(doc)) return true;
    const parts = doc.split("/");
    parts.pop();
    const docDir = parts.join("/") || ".";
    return changedDirs.has(docDir);
  });
};

interface Assertion {
  doc: string;
  doc_line: number;
  token: string;
  label: string;
}

const extractAssertions = (): Assertion[] => {
  const out: Assertion[] = [];
  for (const doc of findDocs()) {
    const full = readFileSync(join(repoRoot, doc), "utf8");
    const lines = full.split("\n");
    lines.forEach((line, i) => {
      for (const { regex, label } of PATTERNS) {
        regex.lastIndex = 0;
        let m: RegExpExecArray | null;
        while ((m = regex.exec(line)) !== null) {
          const token = m[1].trim();
          // Filter noise: tokens that are just a single word common in prose,
          // or contain only whitespace/punctuation.
          if (!token || token.length < 2) continue;
          if (/^[a-z]+$/.test(token) && token.length < 4) continue; // e.g. "we", "the"
          out.push({ doc, doc_line: i + 1, token, label });
        }
      }
    });
  }
  return out;
};

interface Finding {
  category: "context";
  severity: "blocker" | "should" | "nice";
  rule: string;
  file: string;
  line_start: number;
  line_end: number;
  snippet: string;
  anchor_file: string;
  anchor_line: number;
  anchor_snippet: string;
  fix_one_line: string;
  tool: "invariants";
}

// Cache: build the searchable file list ONCE. In diff mode, search only changed
// non-markdown source files. In corpus mode, search every tracked non-markdown
// source file in the repo (excluding lockfiles, generated bundles).
const searchFiles = (() => {
  const base = changedFiles.length > 0
    ? changedFiles
    : execSync("git ls-files", { cwd: repoRoot, encoding: "utf8" }).split("\n").filter(Boolean);
  return base.filter((p) => {
    if (p.endsWith(".md")) return false;
    if (p.includes(".agents/artifacts/")) return false;
    if (p.includes(".agents/plugins/code/skills/review/")) return false;
    // Skip generated / archival corpora that legitimately mention historical tokens.
    if (p.includes("/e2e/") && p.endsWith(".jsonl")) return false;
    if (p.includes("docs/archive/")) return false;
    if (p.endsWith(".lock") || p.endsWith("bun.lock") || p.endsWith("go.sum")) return false;
    return true;
  });
})();

// Cache file contents so multi-pattern searches don't re-read.
const fileCache = new Map<string, string[]>();
const readLines = (path: string): string[] => {
  if (fileCache.has(path)) return fileCache.get(path)!;
  let lines: string[] = [];
  try { lines = readFileSync(join(repoRoot, path), "utf8").split("\n"); } catch {}
  fileCache.set(path, lines);
  return lines;
};

const findReappearances = (assertion: Assertion): Finding[] => {
  const findings: Finding[] = [];
  const token = assertion.token;
  // Strip surrounding whitespace for safer matching; the prose match would have
  // had it stripped already.
  for (const path of searchFiles) {
    // Don't flag the doc that contains the assertion itself.
    if (path === assertion.doc) continue;
    const lines = readLines(path);
    for (let i = 0; i < lines.length; i++) {
      if (!lines[i].includes(token)) continue;
      findings.push({
        category: "context",
        severity: "blocker",
        rule: `\`${token}\` asserted "${assertion.label}" in ${assertion.doc}:${assertion.doc_line}, still present here`,
        file: path,
        line_start: i + 1,
        line_end: i + 1,
        snippet: lines[i],
        anchor_file: assertion.doc,
        anchor_line: assertion.doc_line,
        anchor_snippet: readLines(assertion.doc)
          .slice(Math.max(0, assertion.doc_line - 2), assertion.doc_line + 1)
          .join("\n"),
        fix_one_line: `Remove \`${token}\` from this file, or update ${assertion.doc}:${assertion.doc_line} if the assertion is wrong.`,
        tool: "invariants",
      });
    }
  }
  return findings;
};

const assertions = extractAssertions();
const allFindings: Finding[] = [];
for (const a of assertions) allFindings.push(...findReappearances(a));

// Dedupe by (file, line, token) — when the same invariant is asserted in both
// CLAUDE.md and AGENTS.md (a common mirror pattern), the violation is one bug,
// not two. Keep the first anchor encountered.
const seen = new Set<string>();
const deduped: Finding[] = [];
for (const f of allFindings) {
  const tokenMatch = f.rule.match(/^`([^`]+)`/);
  const token = tokenMatch ? tokenMatch[1] : f.rule;
  const key = `${f.file}|${f.line_start}|${token}`;
  if (seen.has(key)) continue;
  seen.add(key);
  deduped.push(f);
}

process.stdout.write(JSON.stringify(deduped, null, 2) + "\n");
